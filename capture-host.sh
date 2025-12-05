#!/bin/bash
# =========================================
# Host Capture Script
# Captures request hosts from SSH, VLESS, VMESS, and Trojan connections
# Saves unique hosts to /etc/xray/captured-hosts.txt
# =========================================

# // Export Color & Information
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export LIGHT='\033[0;37m'
export NC='\033[0m'

# // Export Banner Status Information
export EROR="[${RED} EROR ${NC}]"
export INFO="[${YELLOW} INFO ${NC}]"
export OKEY="[${GREEN} OKEY ${NC}]"

# // Root Checking
if [ "${EUID}" -ne 0 ]; then
    echo -e "${EROR} Please Run This Script As Root User !"
    exit 1
fi

# File to store captured hosts
HOSTS_FILE="/etc/xray/captured-hosts.txt"

# Get the main domain of the VPS
get_main_domain() {
    if [ -f /etc/xray/domain ]; then
        cat /etc/xray/domain
    else
        echo ""
    fi
}

# Get the VPS IP using local interface detection first, then fallback to external
get_vps_ip() {
    # Try to get external IP from local file first (faster)
    if [ -f /etc/myipvps ]; then
        cat /etc/myipvps
        return
    fi
    # Fallback to external service with timeout
    timeout 5 curl -s ipinfo.io/ip 2>/dev/null || timeout 5 curl -s ifconfig.me 2>/dev/null || echo ""
}

# Initialize hosts file if not exists
if [ ! -f "$HOSTS_FILE" ]; then
    touch "$HOSTS_FILE"
fi

# Get main domain and IP to exclude
MAIN_DOMAIN=$(get_main_domain)
VPS_IP=$(get_vps_ip)

# Function to normalize hostname (lowercase, remove trailing dots, ports)
normalize_host() {
    local host="$1"
    # Convert to lowercase, remove port if present, then remove trailing dots
    echo "$host" | tr '[:upper:]' '[:lower:]' | sed 's/:.*$//; s/\.$//'
}

# Function to add host if not already in list and not main domain/IP
add_host() {
    local host="$1"
    local service="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Skip if empty
    if [ -z "$host" ]; then
        return
    fi
    
    # Normalize the host (lowercase, remove port, remove trailing dot)
    host=$(normalize_host "$host")
    
    # Skip if empty after normalization
    if [ -z "$host" ]; then
        return
    fi
    
    # Skip if it's the main domain or VPS IP (case-insensitive)
    local main_domain_lower
    main_domain_lower=$(echo "$MAIN_DOMAIN" | tr '[:upper:]' '[:lower:]')
    if [ "$host" = "$main_domain_lower" ] || [ "$host" = "$VPS_IP" ]; then
        return
    fi
    
    # Skip localhost and common internal addresses
    if [ "$host" = "localhost" ] || [ "$host" = "127.0.0.1" ] || [ "$host" = "::1" ]; then
        return
    fi
    
    # Check if host already exists in the file (case-insensitive check)
    if ! grep -qi "^${host}|" "$HOSTS_FILE" 2>/dev/null; then
        echo "$host|$service|$timestamp" >> "$HOSTS_FILE"
        echo -e "${OKEY} Captured new host: $host ($service)"
    fi
}

# Capture hosts from SSH auth log
capture_ssh_hosts() {
    local LOG="/var/log/auth.log"
    if [ -f "/var/log/secure" ]; then
        LOG="/var/log/secure"
    fi
    
    if [ -f "$LOG" ]; then
        # Extract hosts from SSH connections (look for any non-IP connection attempts)
        # Store results in array to avoid subshell issues
        local hosts
        hosts=$(grep -i "sshd" "$LOG" 2>/dev/null | grep -oP 'from \K[^\s:]+' | sort -u)
        for host in $hosts; do
            # Check if it looks like a hostname (contains letters)
            if echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "SSH"
            fi
        done
    fi
}

# Capture hosts from Xray access log (VLESS, VMESS, Trojan)
# Captures: HTTP Host header, SNI (Server Name Indication), Proxy Host
capture_xray_hosts() {
    local XRAY_LOG="/var/log/xray/access.log"
    local XRAY_LOG2="/var/log/xray/access2.log"
    
    # Process main xray log
    if [ -f "$XRAY_LOG" ]; then
        # Extract HTTP Host headers (various formats: host=, Host:, host:)
        local header_hosts
        header_hosts=$(grep -oiP '(host[=:]\s*|Host:\s*)\K[a-zA-Z0-9][-a-zA-Z0-9.]*[a-zA-Z0-9]' "$XRAY_LOG" 2>/dev/null | sort -u)
        for host in $header_hosts; do
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "Header-Host"
            fi
        done
        
        # Extract SNI (Server Name Indication) - common log formats: sni=, serverName=, SNI:
        local sni_hosts
        sni_hosts=$(grep -oiP '(sni[=:]\s*|serverName[=:]\s*|server_name[=:]\s*)\K[a-zA-Z0-9][-a-zA-Z0-9.]*[a-zA-Z0-9]' "$XRAY_LOG" 2>/dev/null | sort -u)
        for host in $sni_hosts; do
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "SNI"
            fi
        done
        
        # Extract Proxy Host - common log formats: proxy_host=, proxyHost=, X-Forwarded-Host:
        local proxy_hosts
        proxy_hosts=$(grep -oiP '(proxy[_-]?host[=:]\s*|X-Forwarded-Host:\s*|x-forwarded-host:\s*)\K[a-zA-Z0-9][-a-zA-Z0-9.]*[a-zA-Z0-9]' "$XRAY_LOG" 2>/dev/null | sort -u)
        for host in $proxy_hosts; do
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "Proxy-Host"
            fi
        done
        
        # Extract destination domains from xray log (format: -> domain:port or accepted domain:port)
        local dest_hosts
        dest_hosts=$(grep -oP '(->|accepted)\s*\K[a-zA-Z0-9][-a-zA-Z0-9.]*\.[a-zA-Z]{2,}' "$XRAY_LOG" 2>/dev/null | sort -u)
        for host in $dest_hosts; do
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "XRAY"
            fi
        done
    fi
    
    # Process second xray log
    if [ -f "$XRAY_LOG2" ]; then
        # Extract HTTP Host headers
        local header_hosts2
        header_hosts2=$(grep -oiP '(host[=:]\s*|Host:\s*)\K[a-zA-Z0-9][-a-zA-Z0-9.]*[a-zA-Z0-9]' "$XRAY_LOG2" 2>/dev/null | sort -u)
        for host in $header_hosts2; do
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "Header-Host"
            fi
        done
        
        # Extract SNI
        local sni_hosts2
        sni_hosts2=$(grep -oiP '(sni[=:]\s*|serverName[=:]\s*|server_name[=:]\s*)\K[a-zA-Z0-9][-a-zA-Z0-9.]*[a-zA-Z0-9]' "$XRAY_LOG2" 2>/dev/null | sort -u)
        for host in $sni_hosts2; do
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "SNI"
            fi
        done
        
        # Extract Proxy Host
        local proxy_hosts2
        proxy_hosts2=$(grep -oiP '(proxy[_-]?host[=:]\s*|X-Forwarded-Host:\s*|x-forwarded-host:\s*)\K[a-zA-Z0-9][-a-zA-Z0-9.]*[a-zA-Z0-9]' "$XRAY_LOG2" 2>/dev/null | sort -u)
        for host in $proxy_hosts2; do
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "Proxy-Host"
            fi
        done
        
        # Extract destination domains
        local dest_hosts2
        dest_hosts2=$(grep -oP '(->|accepted)\s*\K[a-zA-Z0-9][-a-zA-Z0-9.]*\.[a-zA-Z]{2,}' "$XRAY_LOG2" 2>/dev/null | sort -u)
        for host in $dest_hosts2; do
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "XRAY"
            fi
        done
    fi
}

# Capture hosts from nginx access log
# Captures: Host header, X-Forwarded-Host, SNI from SSL logs
capture_nginx_hosts() {
    local NGINX_LOG="/var/log/nginx/access.log"
    local NGINX_ERROR_LOG="/var/log/nginx/error.log"
    
    if [ -f "$NGINX_LOG" ]; then
        # Extract Host header from nginx logs
        local hosts
        hosts=$(awk -F'"' '{for(i=1;i<=NF;i++) if($i ~ /Host:/) print $i}' "$NGINX_LOG" 2>/dev/null | \
                grep -oP 'Host:\s*\K[^\s]+' | sort -u)
        for host in $hosts; do
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "Header-Host"
            fi
        done
        
        # Extract X-Forwarded-Host from nginx logs (proxy host)
        local proxy_hosts
        proxy_hosts=$(grep -oiP 'X-Forwarded-Host:\s*\K[a-zA-Z0-9][-a-zA-Z0-9.]*[a-zA-Z0-9]' "$NGINX_LOG" 2>/dev/null | sort -u)
        for host in $proxy_hosts; do
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "Proxy-Host"
            fi
        done
    fi
    
    # Extract SNI from nginx error log (SSL handshake info)
    if [ -f "$NGINX_ERROR_LOG" ]; then
        local sni_hosts
        sni_hosts=$(grep -oiP '(SSL_do_handshake.*|server name[=:]\s*|SNI[=:]\s*)\K[a-zA-Z0-9][-a-zA-Z0-9.]*[a-zA-Z0-9]' "$NGINX_ERROR_LOG" 2>/dev/null | sort -u)
        for host in $sni_hosts; do
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "SNI"
            fi
        done
    fi
}

# Capture hosts from Dropbear
capture_dropbear_hosts() {
    local LOG="/var/log/auth.log"
    if [ -f "/var/log/secure" ]; then
        LOG="/var/log/secure"
    fi
    
    if [ -f "$LOG" ]; then
        local hosts
        hosts=$(grep -i "dropbear" "$LOG" 2>/dev/null | grep -oP 'from \K[^\s:]+' | sort -u)
        for host in $hosts; do
            if echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "Dropbear"
            fi
        done
    fi
}

# Main execution
echo -e "${INFO} Scanning for request hosts..."
echo -e "${INFO} Main Domain: $MAIN_DOMAIN"
echo -e "${INFO} VPS IP: $VPS_IP"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"

capture_ssh_hosts
capture_xray_hosts
capture_nginx_hosts
capture_dropbear_hosts

echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "${OKEY} Host capture complete!"

exit 0
