#!/bin/bash
# =========================================
# Reset User Quota & Re-enable Script
# Resets bandwidth usage and re-enables disabled users
# Automatically restarts Xray service
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
XRAY_CONFIG="/etc/xray/config.json"

# Function to list users with quotas
list_users_with_quotas() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "\E[44;1;39m                  USERS WITH BANDWIDTH QUOTAS                   \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ ! -f "$QUOTA_CONF" ] || [ ! -s "$QUOTA_CONF" ]; then
        echo -e " ${BIYellow}No users with quotas found.${NC}"
        echo ""
        return 1
    fi
    
    local count=0
    echo -e " ${BIWhite}No.  Username/Email                      Status${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    while IFS='|' read -r email total_bytes enabled; do
        [ -z "$email" ] && continue
        ((count++))
        
        local status_text="${GREEN}Active${NC}"
        if [ "$enabled" != "true" ]; then
            status_text="${RED}Disabled${NC}"
        fi
        
        printf " ${BICyan}%-4s${NC} ${BIWhite}%-40s${NC} %b\n" "$count)" "$email" "$status_text"
    done < "$QUOTA_CONF"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    return 0
}

# Interactive mode
clear
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "\E[44;1;39m             RESET USER QUOTA & RE-ENABLE USER                  \E[0m"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e " ${BICyan}This script will:${NC}"
echo -e "  ${YELLOW}•${NC} Reset bandwidth usage statistics to zero"
echo -e "  ${YELLOW}•${NC} Re-enable user if they were disabled due to quota"
echo -e "  ${YELLOW}•${NC} Keep the existing quota limit unchanged"
echo -e "  ${YELLOW}•${NC} Restart Xray service to apply changes"
echo ""

# List users with quotas
if ! list_users_with_quotas; then
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -n 1 -s -r -p "Press any key to exit"
    echo ""
    exit 1
fi

# Get user input
read -p " Enter username/email to reset: " user_email

if [ -z "$user_email" ]; then
    echo -e ""
    echo -e " ${EROR} Username cannot be empty."
    echo ""
    read -n 1 -s -r -p "Press any key to exit"
    echo ""
    exit 1
fi

# Confirm action
echo ""
read -p " Are you sure you want to reset quota for '$user_email'? (y/n): " confirm

if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo -e ""
    echo -e " ${INFO} Operation cancelled."
    echo ""
    read -n 1 -s -r -p "Press any key to exit"
    echo ""
    exit 0
fi

# Execute reset via xray-quota-manager
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
/usr/bin/xray-quota-manager reset "$user_email"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
echo ""

# Return to menu if available
if command -v menu &> /dev/null; then
    menu
fi
