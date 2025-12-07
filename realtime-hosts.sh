#!/bin/bash
# =========================================
# Real-time Host Capture Monitor Display
# Shows live captured hosts from all connections
# Updates every 1 second to show new captured hosts
# Author: LamonLind
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

BIBlack='\033[1;90m'
BIRed='\033[1;91m'
BIGreen='\033[1;92m'
BIYellow='\033[1;93m'
BIBlue='\033[1;94m'
BIPurple='\033[1;95m'
BICyan='\033[1;96m'
BIWhite='\033[1;97m'
UWhite='\033[4;37m'

# // Root Checking
if [ "${EUID}" -ne 0 ]; then
    echo -e "[${RED} EROR ${NC}] Please Run This Script As Root User !"
    exit 1
fi

# File containing captured hosts
HOSTS_FILE="/etc/myvpn/hosts.log"

# Get main domain to exclude
get_main_domain() {
    if [ -f /etc/xray/domain ]; then
        cat /etc/xray/domain
    else
        echo ""
    fi
}

# Get VPS IP to exclude
get_vps_ip() {
    # Try to get from local file first (faster)
    if [ -f /etc/myipvps ]; then
        cat /etc/myipvps
        return
    fi
    # Fallback to external service with timeout
    timeout 3 curl -s ipinfo.io/ip 2>/dev/null || echo ""
}

# Track last display count to show only new entries
LAST_COUNT=0

# Function to display captured hosts in real-time
display_realtime_hosts() {
    local main_domain=$(get_main_domain)
    local vps_ip=$(get_vps_ip)
    
    # Clear screen and show header
    clear
    
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\\E[0;41;36m                   REAL-TIME HOST CAPTURE MONITOR (10ms UPDATE)                      \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "  Main Domain: ${BIWhite}$main_domain${NC} | VPS IP: ${BIWhite}$vps_ip${NC}"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    
    # Check if hosts file exists and has content
    if [ ! -f "$HOSTS_FILE" ] || [ ! -s "$HOSTS_FILE" ]; then
        echo -e "  ${YELLOW}No hosts captured yet. Waiting for connections...${NC}"
        echo ""
        echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "  ${BIWhite}Press Ctrl+C to exit real-time monitoring${NC}"
        echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        return
    fi
    
    # Display header for host list
    printf "%-4s %-40s %-15s %-15s %-20s\n" "NO" "HOST/DOMAIN" "SERVICE" "SOURCE IP" "CAPTURED TIME"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    
    # Read and display hosts from file
    local count=0
    local new_count=0
    
    while IFS='|' read -r host service ip timestamp; do
        # Skip empty lines
        [ -z "$host" ] && continue
        
        ((count++))
        
        # Highlight new entries (entries added since last display)
        local color="${NC}"
        if [ $count -gt $LAST_COUNT ]; then
            color="${GREEN}"
            ((new_count++))
        fi
        
        # Format and display
        printf "${color}%-4s %-40s %-15s %-15s %-20s${NC}\n" \
            "$count" "$host" "$service" "${ip:-N/A}" "${timestamp:-N/A}"
    done < "$HOSTS_FILE"
    
    # Update last count
    LAST_COUNT=$count
    
    echo ""
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "  Total Unique Hosts: ${BIWhite}$count${NC} | New This Update: ${BIGreen}$new_count${NC}"
    echo -e "  ${BIWhite}Press Ctrl+C to exit real-time monitoring${NC}"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
}

# // Main loop - update display every 10 milliseconds (0.01 seconds)
echo -e "${GREEN}Starting Real-time Host Capture Monitor...${NC}"
echo -e "${YELLOW}Updating every 10 milliseconds (100 updates/second). Press Ctrl+C to stop.${NC}"
sleep 2

while true; do
    display_realtime_hosts
    sleep 0.01  # 10 milliseconds = 0.01 seconds
done
