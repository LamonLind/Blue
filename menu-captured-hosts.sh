#!/bin/bash
# =========================================
# Universal Host Capture Menu
# Extracts and displays all hosts configured
# in the client config files:
#   - Target Host (connection address)
#   - SNI (Server Name Indication)
#   - Host Header (HTTP Host override)
# =========================================

BICyan='\033[1;96m'
BIGreen='\033[1;92m'
BIYellow='\033[1;93m'
BIWhite='\033[1;97m'
BIRed='\033[1;91m'
UWhite='\033[4;37m'
NC='\e[0m'

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export CYAN='\033[0;36m'
export NC='\033[0m'

export EROR="[${RED} EROR ${NC}]"
export INFO="[${YELLOW} INFO ${NC}]"
export OKEY="[${GREEN} OKEY ${NC}]"

# Root check
if [ "${EUID}" -ne 0 ]; then
    echo -e "${EROR} Please Run This Script As Root User !"
    exit 1
fi

HOSTS_FILE="/etc/myvpn/hosts.log"
DOMAIN_FILE="/etc/xray/domain"

get_main_domain() {
    [ -f "$DOMAIN_FILE" ] && cat "$DOMAIN_FILE" || echo "N/A"
}

get_vps_ip() {
    [ -f /etc/myipvps ] && cat /etc/myipvps && return
    timeout 5 curl -s ipinfo.io/ip 2>/dev/null || echo "N/A"
}

# ================================================================
# Display extracted hosts
# ================================================================
display_hosts() {
    clear
    local MAIN_DOMAIN VPS_IP
    MAIN_DOMAIN=$(get_main_domain)
    VPS_IP=$(get_vps_ip)

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m                      ⇱ UNIVERSAL HOST CAPTURE ⇲                             \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    echo -e " ${BICyan}Server Domain : ${NC}${BIYellow}${MAIN_DOMAIN}${NC}"
    echo -e " ${BICyan}Server IP     : ${NC}${BIYellow}${VPS_IP}${NC}"
    echo -e ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"

    if [ ! -f "$HOSTS_FILE" ] || [ ! -s "$HOSTS_FILE" ]; then
        echo -e ""
        echo -e " ${BIYellow}No hosts found. Run option [1] to extract hosts from config.${NC}"
        echo -e ""
    else
        echo -e ""
        echo -e " ${BIWhite}HOST                          TYPE          SOURCE FILE           EXTRACTED${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"

        local count=0
        while IFS='|' read -r host type source timestamp; do
            # Color by type
            local color="$BIGreen"
            case "$type" in
                SNI)          color="$BICyan"   ;;
                Host-Header)  color="$BIYellow" ;;
                Target-Host)  color="$BIGreen"  ;;
            esac
            printf " ${color}%-28s${NC}  ${BIWhite}%-12s${NC}  ${NC}%-20s${NC}  ${BICyan}%s${NC}\n" \
                "$host" "$type" "${source:0:20}" "$timestamp"
            ((count++))
        done < "$HOSTS_FILE"

        echo -e ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
        echo -e " ${BICyan}Total:${NC} ${BIWhite}${count}${NC} host entries  ${BICyan}|${NC}  ${BIGreen}Target-Host${NC} = connection address  ${BICyan}|${NC}  ${BICyan}SNI${NC} = TLS server name  ${BICyan}|${NC}  ${BIYellow}Host-Header${NC} = HTTP host"
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
}

# ================================================================
# Extract hosts from config files
# ================================================================
extract_hosts() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m            ⇱ EXTRACTING HOSTS FROM CONFIG ⇲               \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    echo -e " ${INFO} Scanning config files for hosts..."
    echo -e " ${INFO} Sources: /etc/xray/config.json, /home/vps/public_html/*.txt"
    echo -e ""

    if command -v capture-host &>/dev/null; then
        capture-host
    elif [ -f /usr/bin/capture-host ]; then
        /usr/bin/capture-host
    else
        echo -e " ${EROR} capture-host script not found!"
    fi

    echo -e ""
    echo -e " ${INFO} Done. Use option [2] to view the results."
}

# ================================================================
# Clear saved hosts
# ================================================================
clear_hosts() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m                   ⇱ CLEAR HOST LIST ⇲                     \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    read -p " Are you sure you want to clear the host list? (y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        > "$HOSTS_FILE"
        echo -e ""
        echo -e " ${OKEY} Host list cleared."
    else
        echo -e ""
        echo -e " ${INFO} Operation cancelled."
    fi
    echo -e ""
}

# ================================================================
# Main Menu
# ================================================================
show_menu() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m              ⇱ UNIVERSAL HOST CAPTURE MENU ⇲               \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    echo -e " ${BICyan}Extracts all hosts used in client configs:${NC}"
    echo -e " ${BIGreen} Target Host${NC} = address clients connect to"
    echo -e " ${BICyan} SNI${NC}         = TLS Server Name Indication"
    echo -e " ${BIYellow} Host Header${NC} = HTTP Host header override"
    echo -e ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    echo -e "     ${BICyan}[${BIWhite}1${BICyan}]${NC} Extract Hosts from Config Files"
    echo -e "     ${BICyan}[${BIWhite}2${BICyan}]${NC} View Extracted Hosts"
    echo -e "     ${BICyan}[${BIWhite}3${BICyan}]${NC} Extract & View (run both)"
    echo -e "     ${BICyan}[${BIWhite}4${BICyan}]${NC} Clear Host List"
    echo -e "     ${BICyan}[${BIWhite}0${BICyan}]${NC} Back to Main Menu"
    echo -e "     ${BIYellow}Press x to Exit${NC}"
    echo -e ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo ""
    read -p " Select menu : " opt
    echo -e ""
    case $opt in
        1)
            extract_hosts
            echo ""
            read -n 1 -s -r -p " Press any key to return..."
            show_menu
            ;;
        2)
            display_hosts
            echo ""
            read -n 1 -s -r -p " Press any key to return..."
            show_menu
            ;;
        3)
            extract_hosts
            echo ""
            display_hosts
            echo ""
            read -n 1 -s -r -p " Press any key to return..."
            show_menu
            ;;
        4)
            clear_hosts
            read -n 1 -s -r -p " Press any key to return..."
            show_menu
            ;;
        0)
            clear
            menu
            ;;
        x|X)
            exit 0
            ;;
        *)
            echo -e " ${INFO} Invalid option. Press any key to try again."
            read -n 1 -s -r
            show_menu
            ;;
    esac
}

show_menu
