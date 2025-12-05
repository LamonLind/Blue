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
TEMP_FILE="/tmp/captured-hosts-temp.txt"

# Get the main domain of the VPS
get_main_domain() {
    if [ -f /etc/xray/domain ]; then
        cat /etc/xray/domain
    else
        echo ""
    fi
}

# Get the VPS IP
get_vps_ip() {
    curl -s ipinfo.io/ip 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo ""
}

# Initialize hosts file if not exists
if [ ! -f "$HOSTS_FILE" ]; then
    touch "$HOSTS_FILE"
fi

# Get main domain and IP to exclude
MAIN_DOMAIN=$(get_main_domain)
VPS_IP=$(get_vps_ip)

# Create temp file
touch "$TEMP_FILE"

# Function to add host if not already in list and not main domain/IP
add_host() {
    local host="$1"
    local service="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Skip if empty
    if [ -z "$host" ]; then
        return
    fi
    
    # Skip if it's the main domain or VPS IP
    if [ "$host" = "$MAIN_DOMAIN" ] || [ "$host" = "$VPS_IP" ]; then
        return
    fi
    
    # Skip localhost and common internal addresses
    if [ "$host" = "localhost" ] || [ "$host" = "127.0.0.1" ] || [ "$host" = "::1" ]; then
        return
    fi
    
    # Check if host already exists in the file
    if ! grep -q "^$host|" "$HOSTS_FILE" 2>/dev/null; then
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
        grep -i "sshd" "$LOG" 2>/dev/null | grep -oP 'from \K[^\s:]+' | sort -u | while read host; do
            # Check if it looks like a hostname (contains letters)
            if echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "SSH"
            fi
        done
    fi
}

# Capture hosts from Xray access log (VLESS, VMESS, Trojan)
capture_xray_hosts() {
    local XRAY_LOG="/var/log/xray/access.log"
    local XRAY_LOG2="/var/log/xray/access2.log"
    
    # Process main xray log
    if [ -f "$XRAY_LOG" ]; then
        # Extract hosts from xray access log - look for host headers
        grep -oP 'host[=:]\s*\K[^\s,"\]]+' "$XRAY_LOG" 2>/dev/null | sort -u | while read host; do
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                # Try to determine the service type from the log
                if grep -q "vmess.*$host" "$XRAY_LOG" 2>/dev/null; then
                    add_host "$host" "VMESS"
                elif grep -q "vless.*$host" "$XRAY_LOG" 2>/dev/null; then
                    add_host "$host" "VLESS"
                elif grep -q "trojan.*$host" "$XRAY_LOG" 2>/dev/null; then
                    add_host "$host" "Trojan"
                else
                    add_host "$host" "XRAY"
                fi
            fi
        done
    fi
    
    # Process second xray log
    if [ -f "$XRAY_LOG2" ]; then
        grep -oP 'host[=:]\s*\K[^\s,"\]]+' "$XRAY_LOG2" 2>/dev/null | sort -u | while read host; do
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "XRAY"
            fi
        done
    fi
}

# Capture hosts from nginx access log
capture_nginx_hosts() {
    local NGINX_LOG="/var/log/nginx/access.log"
    
    if [ -f "$NGINX_LOG" ]; then
        # Extract Host header from nginx logs
        awk -F'"' '{for(i=1;i<=NF;i++) if($i ~ /Host:/) print $i}' "$NGINX_LOG" 2>/dev/null | \
        grep -oP 'Host:\s*\K[^\s]+' | sort -u | while read host; do
            if [ -n "$host" ] && echo "$host" | grep -q '[a-zA-Z]'; then
                add_host "$host" "WebSocket"
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
        grep -i "dropbear" "$LOG" 2>/dev/null | grep -oP 'from \K[^\s:]+' | sort -u | while read host; do
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

# Cleanup temp file
rm -f "$TEMP_FILE"

exit 0
