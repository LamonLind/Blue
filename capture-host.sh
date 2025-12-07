#!/bin/bash
# =========================================
# Host Capture Script
# Captures request hosts from SSH, VLESS, VMESS, and Trojan connections
# Saves unique hosts to /etc/myvpn/hosts.log
# Enhanced with real-time monitoring and IP capture
# 
# Features:
# - Runs every 2 seconds via systemd service for real-time capture (safe frequency: 1-5 seconds)
# - Captures host headers, SNI (Server Name Indication), domain names, and source IPs
# - Prevents duplicate hosts from being stored repeatedly
# - Stores unique hosts with timestamp and service type
# - Excludes VPS main domain and IP from capture list
# 
# Storage Format: host|service|source_ip|timestamp
# Example: example.com|SSH|192.168.1.100|2024-12-07 10:30:45
# 
# Author: LamonLind
# (C) Copyright 2024
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

# File to store captured hosts (new location as per requirements)
HOSTS_FILE="/etc/myvpn/hosts.log"
# Create directory if it doesn't exist
mkdir -p /etc/myvpn 2>/dev/null

# Backward compatibility: also maintain old location
HOSTS_FILE_OLD="/etc/xray/captured-hosts.txt"

# Hostname regex pattern for valid domain names
# Matches: example.com, sub.example.com, etc.
HOSTNAME_PATTERN='[a-zA-Z0-9][-a-zA-Z0-9.]*[a-zA-Z0-9]'

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
# Also maintain old file for backward compatibility
if [ ! -f "$HOSTS_FILE_OLD" ]; then
    touch "$HOSTS_FILE_OLD"
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
# This function prevents duplicate entries and filters out internal hosts
# Parameters:
#   $1 - host/domain name to add
#   $2 - service type (SSH, VMESS, VLESS, Trojan, SNI, Header-Host, Proxy-Host, etc.)
#   $3 - source IP address of the connection
add_host() {
    local host="$1"
    local service="$2"
    local ip="$3"
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
    # This prevents capturing our own VPS domain/IP
    local main_domain_lower
    main_domain_lower=$(echo "$MAIN_DOMAIN" | tr '[:upper:]' '[:lower:]')
    if [ "$host" = "$main_domain_lower" ] || [ "$host" = "$VPS_IP" ]; then
        return
    fi
    
    # Skip localhost and common internal addresses
    # These are never useful for tracking user connections
    if [ "$host" = "localhost" ] || [ "$host" = "127.0.0.1" ] || [ "$host" = "::1" ]; then
        return
    fi
    
    # Check if host already exists in the file (case-insensitive check)
    # This prevents duplicate entries and keeps the log file clean
    if ! grep -qi "^${host}|" "$HOSTS_FILE" 2>/dev/null; then
        # Format: host|service|ip|timestamp
        echo "$host|$service|${ip:-N/A}|$timestamp" >> "$HOSTS_FILE"
        # Also add to old location for backward compatibility
        echo "$host|$service|$timestamp" >> "$HOSTS_FILE_OLD"
        echo -e "${OKEY} Captured new host: $host ($service) from IP: ${ip:-N/A}"
    fi
}

# Capture hosts from SSH auth log
# Extracts hostnames and IPs from SSH connection attempts
# This helps identify custom domains used for SSH connections
capture_ssh_hosts() {
    local LOG="/var/log/auth.log"
    if [ -f "/var/log/secure" ]; then
        LOG="/var/log/secure"
    fi
    
    if [ -f "$LOG" ]; then
        # Extract hosts and IPs from SSH connections
        # Pattern: "from <host/ip> port <port>" or "from <host/ip>"
        # Use tail first for efficiency on large log files, then filter
        tail -n 1000 "$LOG" 2>/dev/null | grep -i "sshd.*from" | while read -r line; do
            # Extract the connecting IP/host
            local from_part=$(echo "$line" | grep -oP 'from \K[^\s:]+')
            # Extract actual source IP from the line if available
            local source_ip=$(echo "$line" | grep -oP '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' | head -1)
            
            # Check if it looks like a hostname (contains letters)
            # Only capture if it's a domain name, not just an IP
            if echo "$from_part" | grep -q '[a-zA-Z]'; then
                add_host "$from_part" "SSH" "$source_ip"
            fi
        done
    fi
}

# Capture hosts from Xray access log (VLESS, VMESS, Trojan)
# Captures: HTTP Host header, SNI (Server Name Indication), Proxy Host
# These are the most common ways users specify custom domains in Xray protocols
# Also captures source IP addresses for each connection
# Enhanced with better regex patterns and more header types
capture_xray_hosts() {
    local XRAY_LOG="/var/log/xray/access.log"
    local XRAY_LOG2="/var/log/xray/access2.log"
    
    # Process main xray log
    if [ -f "$XRAY_LOG" ]; then
        # Extract HTTP Host headers with source IPs (various formats: host=, Host:, host:)
        # The Host header is used by HTTP-based protocols to specify the target domain
        # Parse each line to extract both host and source IP
        tail -n 1000 "$XRAY_LOG" 2>/dev/null | while read -r line; do
            # Extract source IP from line (typically at start or after "from")
            local source_ip=$(echo "$line" | grep -oP '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' | head -1)
            
            # Extract Host header (multiple patterns for various log formats)
            local host=$(echo "$line" | grep -oiP "(host[=:\s]+|Host:\s*|\"host\":\s*\"?)\K${HOSTNAME_PATTERN}" | head -1)
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "Header-Host" "$source_ip"
            fi
            
            # Extract SNI (Server Name Indication) - multiple patterns
            local sni=$(echo "$line" | grep -oiP "(sni[=:\s]+|serverName[=:\s]+|server_name[=:\s]+|\"sni\":\s*\"?)\K${HOSTNAME_PATTERN}" | head -1)
            if [ -n "$sni" ] && echo "$sni" | grep -q '[a-zA-Z]'; then
                add_host "$sni" "SNI" "$source_ip"
            fi
            
            # Extract Proxy Host and X-Forwarded-Host
            local proxy_host=$(echo "$line" | grep -oiP "(proxy[_-]?[Hh]ost[=:\s]+|X-Forwarded-Host:\s*|\"proxyHost\":\s*\"?)\K${HOSTNAME_PATTERN}" | head -1)
            if [ -n "$proxy_host" ] && echo "$proxy_host" | grep -q '[a-zA-Z]'; then
                add_host "$proxy_host" "Proxy-Host" "$source_ip"
            fi
            
            # Extract ws-host, grpc-service-name, and other custom headers from VPN configs
            local ws_host=$(echo "$line" | grep -oiP "(ws[_-]?[Hh]ost[=:\s]+|\"wsHost\":\s*\"?)\K${HOSTNAME_PATTERN}" | head -1)
            if [ -n "$ws_host" ] && echo "$ws_host" | grep -q '[a-zA-Z]'; then
                add_host "$ws_host" "WS-Host" "$source_ip"
            fi
            
            # Extract grpc service name (often contains domain)
            local grpc_service=$(echo "$line" | grep -oiP "(serviceName[=:\s]+|\"serviceName\":\s*\"?)\K${HOSTNAME_PATTERN}" | head -1)
            if [ -n "$grpc_service" ] && echo "$grpc_service" | grep -q '[a-zA-Z]'; then
                add_host "$grpc_service" "gRPC-Service" "$source_ip"
            fi
            
            # Extract address/serverAddress from custom configs
            local server_addr=$(echo "$line" | grep -oiP "(address[=:\s]+|serverAddress[=:\s]+|\"address\":\s*\"?)\K${HOSTNAME_PATTERN}" | head -1)
            if [ -n "$server_addr" ] && echo "$server_addr" | grep -q '[a-zA-Z]'; then
                add_host "$server_addr" "Server-Address" "$source_ip"
            fi
            
            # Extract destination domains (format: -> domain:port or accepted domain:port)
            local dest_host=$(echo "$line" | grep -oP "(->|accepted|to)\s*\K${HOSTNAME_PATTERN}\.[a-zA-Z]{2,}" | head -1)
            if [ -n "$dest_host" ] && echo "$dest_host" | grep -q '[a-zA-Z]'; then
                # Determine protocol from log line
                local protocol="XRAY"
                if echo "$line" | grep -qi "vless"; then
                    protocol="VLESS"
                elif echo "$line" | grep -qi "vmess"; then
                    protocol="VMESS"
                elif echo "$line" | grep -qi "trojan"; then
                    protocol="Trojan"
                elif echo "$line" | grep -qi "shadowsocks\|ss"; then
                    protocol="Shadowsocks"
                fi
                add_host "$dest_host" "$protocol" "$source_ip"
            fi
            
            # Extract path-based hosts (e.g., /path?host=example.com)
            local path_host=$(echo "$line" | grep -oiP "[\?&]host=\K${HOSTNAME_PATTERN}" | head -1)
            if [ -n "$path_host" ] && echo "$path_host" | grep -q '[a-zA-Z]'; then
                add_host "$path_host" "Query-Host" "$source_ip"
            fi
        done
    fi
    
    # Process second xray log (same enhanced logic as above)
    if [ -f "$XRAY_LOG2" ]; then
        tail -n 1000 "$XRAY_LOG2" 2>/dev/null | while read -r line; do
            # Extract source IP from line
            local source_ip=$(echo "$line" | grep -oP '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' | head -1)
            
            # Extract Host header (multiple patterns)
            local host=$(echo "$line" | grep -oiP "(host[=:\s]+|Host:\s*|\"host\":\s*\"?)\K${HOSTNAME_PATTERN}" | head -1)
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "Header-Host" "$source_ip"
            fi
            
            # Extract SNI
            local sni=$(echo "$line" | grep -oiP "(sni[=:\s]+|serverName[=:\s]+|server_name[=:\s]+|\"sni\":\s*\"?)\K${HOSTNAME_PATTERN}" | head -1)
            if [ -n "$sni" ] && echo "$sni" | grep -q '[a-zA-Z]'; then
                add_host "$sni" "SNI" "$source_ip"
            fi
            
            # Extract Proxy Host
            local proxy_host=$(echo "$line" | grep -oiP "(proxy[_-]?[Hh]ost[=:\s]+|X-Forwarded-Host:\s*|\"proxyHost\":\s*\"?)\K${HOSTNAME_PATTERN}" | head -1)
            if [ -n "$proxy_host" ] && echo "$proxy_host" | grep -q '[a-zA-Z]'; then
                add_host "$proxy_host" "Proxy-Host" "$source_ip"
            fi
            
            # Extract ws-host
            local ws_host=$(echo "$line" | grep -oiP "(ws[_-]?[Hh]ost[=:\s]+|\"wsHost\":\s*\"?)\K${HOSTNAME_PATTERN}" | head -1)
            if [ -n "$ws_host" ] && echo "$ws_host" | grep -q '[a-zA-Z]'; then
                add_host "$ws_host" "WS-Host" "$source_ip"
            fi
            
            # Extract grpc service name
            local grpc_service=$(echo "$line" | grep -oiP "(serviceName[=:\s]+|\"serviceName\":\s*\"?)\K${HOSTNAME_PATTERN}" | head -1)
            if [ -n "$grpc_service" ] && echo "$grpc_service" | grep -q '[a-zA-Z]'; then
                add_host "$grpc_service" "gRPC-Service" "$source_ip"
            fi
            
            # Extract server address
            local server_addr=$(echo "$line" | grep -oiP "(address[=:\s]+|serverAddress[=:\s]+|\"address\":\s*\"?)\K${HOSTNAME_PATTERN}" | head -1)
            if [ -n "$server_addr" ] && echo "$server_addr" | grep -q '[a-zA-Z]'; then
                add_host "$server_addr" "Server-Address" "$source_ip"
            fi
            
            # Extract destination domains
            local dest_host=$(echo "$line" | grep -oP "(->|accepted|to)\s*\K${HOSTNAME_PATTERN}\.[a-zA-Z]{2,}" | head -1)
            if [ -n "$dest_host" ] && echo "$dest_host" | grep -q '[a-zA-Z]'; then
                # Determine protocol from log line
                local protocol="XRAY"
                if echo "$line" | grep -qi "vless"; then
                    protocol="VLESS"
                elif echo "$line" | grep -qi "vmess"; then
                    protocol="VMESS"
                elif echo "$line" | grep -qi "trojan"; then
                    protocol="Trojan"
                elif echo "$line" | grep -qi "shadowsocks\|ss"; then
                    protocol="Shadowsocks"
                fi
                add_host "$dest_host" "$protocol" "$source_ip"
            fi
            
            # Extract path-based hosts
            local path_host=$(echo "$line" | grep -oiP "[\?&]host=\K${HOSTNAME_PATTERN}" | head -1)
            if [ -n "$path_host" ] && echo "$path_host" | grep -q '[a-zA-Z]'; then
                add_host "$path_host" "Query-Host" "$source_ip"
            fi
        done
    fi
}

# Capture hosts from nginx access log
# Captures: Host header, X-Forwarded-Host, SNI from SSL logs
# Also captures source IP addresses for each connection
capture_nginx_hosts() {
    local NGINX_LOG="/var/log/nginx/access.log"
    local NGINX_ERROR_LOG="/var/log/nginx/error.log"
    
    if [ -f "$NGINX_LOG" ]; then
        # Parse nginx access log line by line to extract both host and source IP
        # Nginx log format typically: IP - - [timestamp] "request" status size "referer" "user-agent"
        tail -n 1000 "$NGINX_LOG" 2>/dev/null | while read -r line; do
            # Extract source IP (first field in nginx access log)
            local source_ip=$(echo "$line" | awk '{print $1}')
            
            # Extract Host header from request headers in log
            local host=$(echo "$line" | grep -oiP 'Host:\s*\K[^\s"]+' | head -1)
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "Header-Host" "$source_ip"
            fi
            
            # Extract X-Forwarded-Host from log (proxy host)
            local proxy_host=$(echo "$line" | grep -oiP "X-Forwarded-Host:\s*\K${HOSTNAME_PATTERN}")
            if [ -n "$proxy_host" ] && echo "$proxy_host" | grep -q '[a-zA-Z]'; then
                add_host "$proxy_host" "Proxy-Host" "$source_ip"
            fi
        done
    fi
    
    # Extract SNI from nginx error log (SSL handshake info)
    # Common nginx error log formats: "server name: example.com", "SNI=example.com", "for server name example.com"
    if [ -f "$NGINX_ERROR_LOG" ]; then
        tail -n 1000 "$NGINX_ERROR_LOG" 2>/dev/null | while read -r line; do
            # Extract source IP from error log line
            local source_ip=$(echo "$line" | grep -oP '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' | head -1)
            
            # Extract SNI hostname
            local sni_host=$(echo "$line" | grep -oiP "(server\s*name[=:\s]+|SNI[=:\s]+|for\s+server\s+name\s+)\K${HOSTNAME_PATTERN}" | head -1)
            if [ -n "$sni_host" ] && echo "$sni_host" | grep -q '[a-zA-Z]'; then
                add_host "$sni_host" "SNI" "$source_ip"
            fi
        done
    fi
}

# Capture hosts from Dropbear SSH connections
# Extracts hostnames and source IPs from Dropbear connection attempts
capture_dropbear_hosts() {
    local LOG="/var/log/auth.log"
    if [ -f "/var/log/secure" ]; then
        LOG="/var/log/secure"
    fi
    
    if [ -f "$LOG" ]; then
        tail -n 1000 "$LOG" 2>/dev/null | grep -i "dropbear" | while read -r line; do
            # Extract the connecting host/IP
            local from_part=$(echo "$line" | grep -oP 'from \K[^\s:]+')
            # Extract actual source IP from the line if available
            local source_ip=$(echo "$line" | grep -oP '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' | head -1)
            
            # Check if it looks like a hostname (contains letters)
            # Only capture if it's a domain name, not just an IP
            if echo "$from_part" | grep -q '[a-zA-Z]'; then
                add_host "$from_part" "Dropbear" "$source_ip"
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
