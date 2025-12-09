#!/bin/bash
# =========================================
# Bandwidth Quota Management Menu
# View and manage bandwidth quotas for all users
# Author: LamonLind
# (C) Copyright 2024
# =========================================

BIBlack='\033[1;90m'
BIRed='\033[1;91m'
BIGreen='\033[1;92m'
BIYellow='\033[1;93m'
BIBlue='\033[1;94m'
BIPurple='\033[1;95m'
BICyan='\033[1;96m'
BIWhite='\033[1;97m'
UWhite='\033[4;37m'
NC='\e[0m'

# Export Color & Information
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export LIGHT='\033[0;37m'
export NC='\033[0m'

# Export Banner Status Information
export EROR="[${RED} EROR ${NC}]"
export INFO="[${YELLOW} INFO ${NC}]"
export OKEY="[${GREEN} OKEY ${NC}]"

# Root Checking
if [ "${EUID}" -ne 0 ]; then
    echo -e "${EROR} Please Run This Script As Root User !"
    exit 1
fi

# Configuration
QUOTA_CONF="/etc/xray/client-quotas.conf"

# Convert bytes to human readable
bytes_to_human() {
    local bytes="$1"
    if [ "$bytes" -ge 1099511627776 ]; then
        echo "$(awk "BEGIN {printf \"%.2f TB\", $bytes/1099511627776}")"
    elif [ "$bytes" -ge 1073741824 ]; then
        echo "$(awk "BEGIN {printf \"%.2f GB\", $bytes/1073741824}")"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.2f MB\", $bytes/1048576}")"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(awk "BEGIN {printf \"%.2f KB\", $bytes/1024}")"
    else
        echo "${bytes} Bytes"
    fi
}

# Get user traffic from xray stats API
# NOTE: Tracking ONLY downlink (client download) divided by 3 to fix overcounting bug.
# Upload traffic is not measured properly, so we only track download.
# The 3x bug occurs because users exist in multiple inbound configurations
# (ws/grpc/xhttp) and Xray aggregates stats across all of them.
# We divide by 3 to get accurate single-protocol traffic.
# Note: Integer division truncates values < 3 bytes to 0, which is acceptable
# since bandwidth is measured in KB/MB/GB, not individual bytes.
get_user_traffic() {
    local email="$1"
    local downlink=0
    local _Xray="/usr/local/bin/xray"
    
    # Check if xray exists and is executable
    if [ -x "$_Xray" ]; then
        # Query downlink (download) - handle both "value":"123" and "value": 123 formats
        downlink=$($_Xray api statsquery --server=127.0.0.1:10085 -pattern "user>>>$email>>>traffic>>>downlink" 2>/dev/null | sed -n 's/.*"value"[[:space:]]*:[[:space:]]*"\?\([0-9]\+\)"\?.*/\1/p' | head -1)
        [ -z "$downlink" ] && downlink=0
    fi
    
    # Return downlink divided by 3 (fixes 3x overcounting bug)
    # Integer division: downlink / 3
    echo $(( downlink / 3 ))
}

# Function to view all bandwidth quotas
view_all_quotas() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "\E[44;1;39m                          BANDWIDTH QUOTA STATUS - ALL USERS                             \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ ! -f "$QUOTA_CONF" ] || [ ! -s "$QUOTA_CONF" ]; then
        echo -e " ${BIYellow}No bandwidth quotas configured.${NC}"
        echo -e " ${BICyan}Set quotas during account creation or use 'xray-quota-manager' command.${NC}"
        echo ""
    else
        printf " ${BIWhite}%-30s %-15s %-15s %-12s %-12s %-10s${NC}\n" "USERNAME/EMAIL" "QUOTA LIMIT" "USED" "REMAINING" "PERCENT" "STATUS"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        local count=0
        while IFS='|' read -r email total_bytes enabled; do
            [ -z "$email" ] && continue
            ((count++))
            
            local total_human=$(bytes_to_human $total_bytes)
            local current_usage=$(get_user_traffic "$email")
            local usage_human=$(bytes_to_human $current_usage)
            
            local remaining=0
            local remaining_human="N/A"
            local usage_percent="0.0"
            local percent_color="${GREEN}"
            
            if [ "$total_bytes" -gt 0 ]; then
                usage_percent=$(awk "BEGIN {printf \"%.1f\", ($current_usage * 100.0) / $total_bytes}")
                
                # Color code based on percentage using awk for portability
                if [ $(awk "BEGIN {print ($usage_percent >= 90)}") -eq 1 ]; then
                    percent_color="${RED}"
                elif [ $(awk "BEGIN {print ($usage_percent >= 75)}") -eq 1 ]; then
                    percent_color="${YELLOW}"
                fi
                
                if [ "$current_usage" -lt "$total_bytes" ]; then
                    remaining=$((total_bytes - current_usage))
                    remaining_human=$(bytes_to_human $remaining)
                else
                    remaining_human="0 B"
                fi
            fi
            
            local status_text="${GREEN}Active${NC}"
            if [ "$enabled" != "true" ]; then
                status_text="${RED}Disabled${NC}"
            elif [ "$current_usage" -ge "$total_bytes" ]; then
                status_text="${RED}Over Limit${NC}"
            fi
            
            printf " ${BICyan}%-30s${NC} ${BIWhite}%-15s${NC} ${BIYellow}%-15s${NC} ${BIGreen}%-12s${NC} ${percent_color}%-12s${NC} %b\n" \
                "$email" "$total_human" "$usage_human" "$remaining_human" "${usage_percent}%" "$status_text"
        done < "$QUOTA_CONF"
        
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e " ${BICyan}Total Users with Quotas:${NC} ${BIWhite}$count${NC}"
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to view specific user quota
view_user_quota() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "\E[44;1;39m                  VIEW USER BANDWIDTH QUOTA                     \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    read -p " Enter username/email: " user_email
    
    if [ -z "$user_email" ]; then
        echo -e ""
        echo -e " ${EROR} Username cannot be empty."
    else
        echo ""
        /usr/bin/xray-quota-manager usage "$user_email"
    fi
    echo ""
}

# Function to set quota for user
set_user_quota() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "\E[44;1;39m                   SET BANDWIDTH QUOTA                          \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    read -p " Enter username/email: " user_email
    read -p " Enter quota (e.g., 10GB, 500MB, 1TB): " quota_limit
    
    if [ -z "$user_email" ] || [ -z "$quota_limit" ]; then
        echo -e ""
        echo -e " ${EROR} Username and quota cannot be empty."
    else
        echo ""
        /usr/bin/xray-quota-manager set "$user_email" "$quota_limit"
    fi
    echo ""
}

# Function to remove quota for user
remove_user_quota() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "\E[44;1;39m                  REMOVE BANDWIDTH QUOTA                        \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    read -p " Enter username/email: " user_email
    
    if [ -z "$user_email" ]; then
        echo -e ""
        echo -e " ${EROR} Username cannot be empty."
    else
        echo ""
        read -p " Are you sure you want to remove quota for $user_email? (y/n): " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            /usr/bin/xray-quota-manager remove "$user_email"
        else
            echo -e " ${INFO} Operation cancelled."
        fi
    fi
    echo ""
}

# Function to check monitor service status
check_monitor_status() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "\E[44;1;39m              BANDWIDTH QUOTA MONITOR STATUS                    \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if systemctl is-active --quiet xray-quota-monitor; then
        echo -e " ${OKEY} Quota Monitor Service: ${GREEN}Running${NC}"
    else
        echo -e " ${EROR} Quota Monitor Service: ${RED}Not Running${NC}"
    fi
    
    if systemctl is-enabled --quiet xray-quota-monitor 2>/dev/null; then
        echo -e " ${OKEY} Auto-start on Boot: ${GREEN}Enabled${NC}"
    else
        echo -e " ${INFO} Auto-start on Boot: ${YELLOW}Disabled${NC}"
    fi
    
    echo ""
    echo -e " ${BICyan}Recent Monitor Logs:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    tail -n 10 /var/log/xray-quota-monitor.log 2>/dev/null || echo " No logs found"
    echo ""
}

# Function to restart monitor service
restart_monitor() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "\E[44;1;39m             RESTART BANDWIDTH QUOTA MONITOR                    \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${INFO} Restarting quota monitor service..."
    systemctl restart xray-quota-monitor
    sleep 2
    
    if systemctl is-active --quiet xray-quota-monitor; then
        echo -e " ${OKEY} Service restarted successfully."
    else
        echo -e " ${EROR} Failed to restart service."
    fi
    echo ""
}

# Main menu
clear
echo -e "${BICyan} ┌─────────────────────────────────────────────────────┐${NC}"
echo -e "       ${BIWhite}${UWhite}BANDWIDTH QUOTA MANAGEMENT MENU ${NC}"
echo -e ""
echo -e "     ${BICyan}[${BIWhite}1${BICyan}] View All User Quotas & Usage      "
echo -e "     ${BICyan}[${BIWhite}2${BICyan}] View Specific User Quota      "
echo -e "     ${BICyan}[${BIWhite}3${BICyan}] Set/Update User Quota      "
echo -e "     ${BICyan}[${BIWhite}4${BICyan}] Remove User Quota     "
echo -e "     ${BICyan}[${BIWhite}5${BICyan}] Check Monitor Status     "
echo -e "     ${BICyan}[${BIWhite}6${BICyan}] Restart Monitor Service     "
echo -e " ${BICyan}└─────────────────────────────────────────────────────┘${NC}"
echo -e "     ${BIYellow}Press x or [ Ctrl+C ] • To-${BIWhite}Exit${NC}"
echo ""
read -p " Select menu : " opt
echo -e ""
case $opt in
1) view_all_quotas ;;
2) view_user_quota ;;
3) set_user_quota ;;
4) remove_user_quota ;;
5) check_monitor_status ;;
6) restart_monitor ;;
0) clear ; menu ;;
x) exit ;;
*) echo -e "" ; echo "Press any key to back on menu" ; sleep 1 ; menu ;;
esac

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
menu
