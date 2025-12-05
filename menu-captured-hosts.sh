#!/bin/bash
# =========================================
# View Captured Hosts Menu
# Displays all captured request hosts excluding VPS main domain
# =========================================

BIBlack='\033[1;90m'      # Black
BIRed='\033[1;91m'        # Red
BIGreen='\033[1;92m'      # Green
BIYellow='\033[1;93m'     # Yellow
BIBlue='\033[1;94m'       # Blue
BIPurple='\033[1;95m'     # Purple
BICyan='\033[1;96m'       # Cyan
BIWhite='\033[1;97m'      # White
UWhite='\033[4;37m'       # White
On_IPurple='\033[0;105m'  #
On_IRed='\033[0;101m'
IBlack='\033[0;90m'       # Black
IRed='\033[0;91m'         # Red
IGreen='\033[0;92m'       # Green
IYellow='\033[0;93m'      # Yellow
IBlue='\033[0;94m'        # Blue
IPurple='\033[0;95m'      # Purple
ICyan='\033[0;96m'        # Cyan
IWhite='\033[0;97m'       # White
NC='\e[0m'

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
export PENDING="[${YELLOW} PENDING ${NC}]"
export SEND="[${YELLOW} SEND ${NC}]"
export RECEIVE="[${YELLOW} RECEIVE ${NC}]"

# // Export Align
export BOLD="\e[1m"
export WARNING="${RED}\e[5m"
export UNDERLINE="\e[4m"

# // Exporting URL Host
export Server_URL="raw.githubusercontent.com/LamonLind/Blue/main/test"
export Server1_URL="raw.githubusercontent.com/LamonLind/Blue/main/limit"
export Server_Port="443"
export Server_IP="underfined"
export Script_Mode="Stable"
export Auther=".geovpn"

# // Root Checking
if [ "${EUID}" -ne 0 ]; then
    echo -e "${EROR} Please Run This Script As Root User !"
    exit 1
fi

# // Exporting IP Address
export IP=$( curl -s https://ipinfo.io/ip/ )

# // Exporting Network Interface
export NETWORK_IFACE="$(ip route show to default | awk '{print $5}')"

# File containing captured hosts
HOSTS_FILE="/etc/xray/captured-hosts.txt"

# Get main domain
get_main_domain() {
    if [ -f /etc/xray/domain ]; then
        cat /etc/xray/domain
    else
        echo ""
    fi
}

# Get VPS IP
get_vps_ip() {
    curl -s ipinfo.io/ip 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo ""
}

# Function to display captured hosts
display_hosts() {
    clear
    MAIN_DOMAIN=$(get_main_domain)
    VPS_IP=$(get_vps_ip)
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m                  ⇱ CAPTURED REQUEST HOSTS ⇲                  \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    echo -e " ${BICyan}VPS Main Domain:${NC} ${BIYellow}$MAIN_DOMAIN${NC}"
    echo -e " ${BICyan}VPS IP Address:${NC}  ${BIYellow}$VPS_IP${NC}"
    echo -e ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    
    if [ ! -f "$HOSTS_FILE" ] || [ ! -s "$HOSTS_FILE" ]; then
        echo -e ""
        echo -e " ${BIYellow}No captured hosts found.${NC}"
        echo -e " ${BICyan}Hosts will be captured when users connect through custom hosts.${NC}"
        echo -e ""
    else
        echo -e ""
        echo -e " ${BIWhite}HOST                          SERVICE       CAPTURED DATE${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
        
        # Read and display hosts, excluding main domain and VPS IP
        count=0
        while IFS='|' read -r host service timestamp; do
            # Skip main domain and VPS IP
            if [ "$host" = "$MAIN_DOMAIN" ] || [ "$host" = "$VPS_IP" ]; then
                continue
            fi
            
            # Format output with padding
            printf " ${BIGreen}%-28s${NC}  ${BICyan}%-12s${NC}  ${BIYellow}%s${NC}\n" "$host" "$service" "$timestamp"
            ((count++))
        done < "$HOSTS_FILE"
        
        echo -e ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
        echo -e " ${BICyan}Total Captured Hosts:${NC} ${BIWhite}$count${NC}"
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
}

# Function to scan for new hosts
scan_hosts() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m                    ⇱ SCANNING FOR HOSTS ⇲                    \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    /usr/bin/capture-host
    echo -e ""
}

# Function to clear captured hosts
clear_hosts() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m                   ⇱ CLEAR CAPTURED HOSTS ⇲                   \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    read -p " Are you sure you want to clear all captured hosts? (y/n): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        > "$HOSTS_FILE"
        echo -e ""
        echo -e " ${OKEY} All captured hosts have been cleared."
    else
        echo -e ""
        echo -e " ${INFO} Operation cancelled."
    fi
    echo -e ""
}

# Function to normalize hostname (lowercase, remove trailing dots, ports)
normalize_host() {
    local host="$1"
    # Convert to lowercase, remove port if present, then remove trailing dots
    echo "$host" | tr '[:upper:]' '[:lower:]' | sed 's/:.*$//; s/\.$//'
}

# Function to add host manually
add_host_manual() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m                    ⇱ ADD HOST MANUALLY ⇲                     \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    read -p " Enter host/domain: " new_host
    read -p " Enter service type (SSH/VMESS/VLESS/Trojan/SNI/Header-Host/Proxy-Host): " service
    
    if [ -z "$new_host" ]; then
        echo -e ""
        echo -e " ${EROR} Host cannot be empty."
    else
        # Normalize the host (lowercase, remove port, remove trailing dot)
        new_host=$(normalize_host "$new_host")
        
        if [ -z "$new_host" ]; then
            echo -e ""
            echo -e " ${EROR} Invalid host format."
        else
            local timestamp
            timestamp=$(date "+%Y-%m-%d %H:%M:%S")
            
            # Check if host already exists (case-insensitive)
            if grep -qi "^${new_host}|" "$HOSTS_FILE" 2>/dev/null; then
                echo -e ""
                echo -e " ${INFO} Host already exists in the list."
            else
                echo "$new_host|${service:-Manual}|$timestamp" >> "$HOSTS_FILE"
                echo -e ""
                echo -e " ${OKEY} Host '$new_host' has been added."
            fi
        fi
    fi
    echo -e ""
}

# Function to remove a specific host
remove_host() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m                    ⇱ REMOVE HOST ⇲                           \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    
    if [ ! -f "$HOSTS_FILE" ] || [ ! -s "$HOSTS_FILE" ]; then
        echo -e " ${INFO} No captured hosts to remove."
        echo -e ""
        return
    fi
    
    echo -e " ${BIWhite}Current captured hosts:${NC}"
    echo -e ""
    local count=0
    while IFS='|' read -r host service timestamp; do
        ((count++))
        echo -e " $count. $host ($service)"
    done < "$HOSTS_FILE"
    echo -e ""
    read -p " Enter the host to remove: " host_to_remove
    
    if [ -z "$host_to_remove" ]; then
        echo -e ""
        echo -e " ${EROR} Host cannot be empty."
    elif grep -q "^$host_to_remove|" "$HOSTS_FILE" 2>/dev/null; then
        sed -i "/^$host_to_remove|/d" "$HOSTS_FILE"
        echo -e ""
        echo -e " ${OKEY} Host '$host_to_remove' has been removed."
    else
        echo -e ""
        echo -e " ${INFO} Host not found in the list."
    fi
    echo -e ""
}

# Function to check if auto capture is enabled
is_auto_capture_enabled() {
    if [ -f "/etc/cron.d/capture_host" ]; then
        return 0
    else
        return 1
    fi
}

# Function to enable auto capture
enable_auto_capture() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m                  ⇱ ENABLE AUTO CAPTURE ⇲                    \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    
    if is_auto_capture_enabled; then
        echo -e " ${INFO} Auto capture is already enabled."
    else
        cat > /etc/cron.d/capture_host <<-END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/30 * * * * root /usr/bin/capture-host >/dev/null 2>&1
END
        chmod 644 /etc/cron.d/capture_host
        service cron restart >/dev/null 2>&1
        echo -e " ${OKEY} Auto capture has been enabled."
        echo -e " ${INFO} Hosts will be captured automatically every 30 minutes."
    fi
    echo -e ""
}

# Function to disable auto capture
disable_auto_capture() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "\E[44;1;39m                  ⇱ DISABLE AUTO CAPTURE ⇲                   \E[0m"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e ""
    
    if is_auto_capture_enabled; then
        rm -f /etc/cron.d/capture_host
        service cron restart >/dev/null 2>&1
        echo -e " ${OKEY} Auto capture has been disabled."
    else
        echo -e " ${INFO} Auto capture is already disabled."
    fi
    echo -e ""
}

# Get auto capture status for display
get_auto_capture_status() {
    if is_auto_capture_enabled; then
        echo -e "${BIGreen}ON${NC}"
    else
        echo -e "${BIRed}OFF${NC}"
    fi
}

# Main menu
clear
AUTO_STATUS=$(get_auto_capture_status)
echo -e "${BICyan} ┌─────────────────────────────────────────────────────┐${NC}"
echo -e "       ${BIWhite}${UWhite}CAPTURED HOSTS MENU ${NC}"
echo -e ""
echo -e "     ${BICyan}Auto Capture Status: ${AUTO_STATUS}"
echo -e ""
echo -e "     ${BICyan}[${BIWhite}1${BICyan}] View Captured Hosts      "
echo -e "     ${BICyan}[${BIWhite}2${BICyan}] Scan for New Hosts      "
echo -e "     ${BICyan}[${BIWhite}3${BICyan}] Add Host Manually      "
echo -e "     ${BICyan}[${BIWhite}4${BICyan}] Remove Host     "
echo -e "     ${BICyan}[${BIWhite}5${BICyan}] Clear All Hosts     "
echo -e "     ${BICyan}[${BIWhite}6${BICyan}] Turn ON Auto Capture     "
echo -e "     ${BICyan}[${BIWhite}7${BICyan}] Turn OFF Auto Capture     "
echo -e " ${BICyan}└─────────────────────────────────────────────────────┘${NC}"
echo -e "     ${BIYellow}Press x or [ Ctrl+C ] • To-${BIWhite}Exit${NC}"
echo ""
read -p " Select menu : " opt
echo -e ""
case $opt in
1) display_hosts ;;
2) scan_hosts ;;
3) add_host_manual ;;
4) remove_host ;;
5) clear_hosts ;;
6) enable_auto_capture ;;
7) disable_auto_capture ;;
0) clear ; menu ;;
x) exit ;;
*) echo -e "" ; echo "Press any key to back on menu" ; sleep 1 ; menu ;;
esac

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
menu
