#!/bin/bash
# =========================================
# Universal Host Capture
# Extracts all hosts from the client config files:
#   - Target Host (address clients connect to)
#   - SNI (Server Name Indication for TLS)
#   - Host Header (HTTP Host header override)
#
# Sources parsed:
#   1. /etc/xray/config.json  - serverName, address, Host header fields
#   2. /home/vps/public_html/ - vless://, vmess://, trojan:// client links
#
# Author: LamonLind
# =========================================

# Export Color
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m'
BICyan='\033[1;96m'
BIGreen='\033[1;92m'
BIYellow='\033[1;93m'
BIWhite='\033[1;97m'
BIRed='\033[1;91m'

export EROR="[${RED} EROR ${NC}]"
export INFO="[${YELLOW} INFO ${NC}]"
export OKEY="[${GREEN} OKEY ${NC}]"

# Root check
if [ "${EUID}" -ne 0 ]; then
    echo -e "${EROR} Please Run This Script As Root User !"
    exit 1
fi

# Config paths
XRAY_CONFIG="/etc/xray/config.json"
CLIENT_DIR="/home/vps/public_html"
DOMAIN_FILE="/etc/xray/domain"

# Output
HOSTS_FILE="/etc/myvpn/hosts.log"
mkdir -p /etc/myvpn 2>/dev/null

# Get main domain/IP to label (not exclude)
get_main_domain() {
    [ -f "$DOMAIN_FILE" ] && cat "$DOMAIN_FILE" || echo ""
}

get_vps_ip() {
    [ -f /etc/myipvps ] && cat /etc/myipvps && return
    timeout 5 curl -s ipinfo.io/ip 2>/dev/null || echo ""
}

# Normalize: lowercase, strip port, strip trailing dot
normalize_host() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/:[0-9]*$//; s/\.$//'
}

# Validate: must look like a hostname or IP (not empty, not a path, not a number only)
is_valid_host() {
    local h="$1"
    [ -z "$h" ] && return 1
    # Must match a valid hostname pattern (allows single-char labels per RFC 1123)
    echo "$h" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9._-]*)?$' || return 1
    # Must not be pure numeric (IPs are fine, but bare integers are not hostnames)
    echo "$h" | grep -qE '^[0-9]+$' && return 1
    # Skip loopback / localhost
    [[ "$h" == "127.0.0.1" || "$h" == "localhost" || "$h" == "0.0.0.0" ]] && return 1
    return 0
}

# ---- Temporary file for collecting raw results ----
TMP_RESULTS=$(mktemp /tmp/host-extract-XXXXXX)

add_result() {
    local host="$1"
    local type="$2"
    local source="$3"
    host=$(normalize_host "$host")
    is_valid_host "$host" || return
    echo "${host}|${type}|${source}" >> "$TMP_RESULTS"
}

# ================================================================
# 1. Parse /etc/xray/config.json
# ================================================================
parse_xray_config() {
    [ -f "$XRAY_CONFIG" ] || return

    local src="xray-config.json"

    # serverName -> SNI
    grep -oE '"serverName"[[:space:]]*:[[:space:]]*"[^"]+"' "$XRAY_CONFIG" | \
        grep -oE '"[^"]+"\s*$' | tr -d '"' | while read -r val; do
        add_result "$val" "SNI" "$src"
    done

    # "host" in headers -> Host Header
    # Covers wsSettings.headers.Host and similar
    grep -oE '"[Hh]ost"[[:space:]]*:[[:space:]]*"[^"]+"' "$XRAY_CONFIG" | \
        grep -oE '"[^"]+"\s*$' | tr -d '"' | while read -r val; do
        add_result "$val" "Host-Header" "$src"
    done

    # "address" fields -> Target Host (skip 127.x and IPs if they equal VPS IP)
    grep -oE '"address"[[:space:]]*:[[:space:]]*"[^"]+"' "$XRAY_CONFIG" | \
        grep -oE '"[^"]+"\s*$' | tr -d '"' | while read -r val; do
        add_result "$val" "Target-Host" "$src"
    done
}

# ================================================================
# 2. Parse vless:// and trojan:// URL links in client files
# ================================================================
parse_url_link() {
    local link="$1"
    local proto="$2"
    local src="$3"

    # Target host: between @ and : (port)
    local addr
    addr=$(echo "$link" | sed -n 's|.*://[^@]*@\([^:/?#]*\).*|\1|p')
    add_result "$addr" "Target-Host" "$src"

    # Query params: host= and sni=
    local query
    query=$(echo "$link" | grep -oE '\?[^#]*' | tr -d '?')

    local host_param sni_param
    host_param=$(echo "$query" | tr '&' '\n' | grep -i '^host=' | cut -d= -f2- | head -1)
    sni_param=$(echo "$query" | tr '&' '\n' | grep -i '^sni=' | cut -d= -f2- | head -1)

    # URL-decode percent-encoded characters safely using printf (no shell injection risk)
    if [ -n "$host_param" ]; then
        local decoded_host
        decoded_host=$(printf '%b' "$(echo "$host_param" | sed 's/%/\\x/g')" 2>/dev/null || echo "$host_param")
        add_result "$decoded_host" "Host-Header" "$src"
    fi
    [ -n "$sni_param" ] && add_result "$sni_param" "SNI" "$src"
}

# ================================================================
# 3. Parse vmess:// base64-encoded JSON links
# ================================================================
parse_vmess_link() {
    local link="$1"
    local src="$2"

    local b64
    b64=$(echo "$link" | sed 's|vmess://||')
    local json
    json=$(echo "$b64" | base64 -d 2>/dev/null) || return

    # "add" -> Target Host
    local add_val
    add_val=$(echo "$json" | grep -oE '"add"[[:space:]]*:[[:space:]]*"[^"]+"' | grep -oE '"[^"]+"$' | tr -d '"')
    add_result "$add_val" "Target-Host" "$src"

    # "host" -> Host Header
    local host_val
    host_val=$(echo "$json" | grep -oE '"host"[[:space:]]*:[[:space:]]*"[^"]+"' | grep -oE '"[^"]+"$' | tr -d '"')
    add_result "$host_val" "Host-Header" "$src"

    # "sni" -> SNI (some clients include this)
    local sni_val
    sni_val=$(echo "$json" | grep -oE '"sni"[[:space:]]*:[[:space:]]*"[^"]+"' | grep -oE '"[^"]+"$' | tr -d '"')
    [ -n "$sni_val" ] && add_result "$sni_val" "SNI" "$src"
}

# ================================================================
# 4. Scan client link files
# ================================================================
parse_client_files() {
    [ -d "$CLIENT_DIR" ] || return

    find "$CLIENT_DIR" -name "*.txt" -type f 2>/dev/null | while read -r file; do
        local src
        src=$(basename "$file")

        # Extract all links from file
        while read -r line; do
            # Strip leading/trailing spaces
            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            case "$line" in
                vless://*)
                    parse_url_link "$line" "vless" "$src"
                    ;;
                trojan://*)
                    parse_url_link "$line" "trojan" "$src"
                    ;;
                vmess://*)
                    parse_vmess_link "$line" "$src"
                    ;;
            esac
        done < <(grep -oE '(vless|vmess|trojan)://[^[:space:]"'"'"']+' "$file")
    done
}

# ================================================================
# Run extraction
# ================================================================
parse_xray_config
parse_client_files

# ================================================================
# Deduplicate and save
# ================================================================
# Sort and unique by host+type combination
sort -u "$TMP_RESULTS" > "${TMP_RESULTS}.sorted"

# Save to hosts file (unique hosts only - all types)
# Format: host|type|source|timestamp
> "$HOSTS_FILE"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
while IFS='|' read -r host type source; do
    echo "${host}|${type}|${source}|${TIMESTAMP}" >> "$HOSTS_FILE"
done < "${TMP_RESULTS}.sorted"

rm -f "$TMP_RESULTS" "${TMP_RESULTS}.sorted"

echo -e "${OKEY} Host extraction complete. Found $(wc -l < "$HOSTS_FILE") host entries."
