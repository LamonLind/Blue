#!/bin/bash
# =========================================
# Update Script - Blue VPN Script
# Edition : Stable Edition V1.0
# Author  : LamonLind
# (C) Copyright 2024
# =========================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Root checking
if [ "${EUID}" -ne 0 ]; then
    echo -e "${RED}ERROR: Please run this script as root user!${NC}"
    exit 1
fi

# Export GitHub repository URL
REPO_URL="raw.githubusercontent.com/LamonLind/Blue/main"

# Function to show header
show_header() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}           Blue VPN Script - Update Tool${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Function to update all scripts
update_all_scripts() {
    echo -e "${YELLOW}[INFO]${NC} Updating all scripts..."
    
    # List of all scripts to update
    local scripts=(
        "add-ws" "add-ssws" "add-socks" "add-vless" "add-tr" "add-trgo"
        "autoreboot" "restart" "tendang" "clearlog" "running"
        "cek-trafik" "cek-speed" "cek-ram" "limit-speed"
        "realtime-hosts"
        "menu-vless" "menu-vmess" "menu-socks" "menu-ss" "menu-trojan"
        "menu-trgo" "menu-ssh" "menu-slowdns" "menu-captured-hosts"
        "capture-host" "menu-bckp" "usernew" "menu" "wbm" "xp"
        "dns" "netf" "bbr" "backup" "restore"
        "xray-quota-manager" "xray-traffic-monitor"
    )
    
    local success_count=0
    local fail_count=0
    
    for script in "${scripts[@]}"; do
        echo -ne "${CYAN}Updating ${script}...${NC}"
        
        # Determine the correct filename with extension
        local filename="${script}.sh"
        if [ "$script" == "menu" ]; then
            filename="menu4.sh"
        elif [ "$script" == "cek-speed" ]; then
            filename="speedtest_cli.py"
        elif [ "$script" == "xray-quota-manager" ] || [ "$script" == "xray-traffic-monitor" ]; then
            filename="${script}"
        fi
        
        if wget -q -O "/usr/bin/${script}" "https://${REPO_URL}/${filename}"; then
            chmod +x "/usr/bin/${script}"
            echo -e " ${GREEN}✓${NC}"
            ((success_count++))
        else
            echo -e " ${RED}✗${NC}"
            ((fail_count++))
        fi
    done
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Update Summary:${NC}"
    echo -e "  ${GREEN}Success: ${success_count}${NC}"
    echo -e "  ${RED}Failed: ${fail_count}${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to update specific component
update_component() {
    echo ""
    echo -e "${CYAN}Select component to update:${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} SSH/WS Scripts"
    echo -e "  ${CYAN}[2]${NC} XRAY Scripts (VMESS, VLESS, Trojan, Shadowsocks)"
    echo -e "  ${CYAN}[3]${NC} Menu Scripts"
    echo -e "  ${CYAN}[4]${NC} System Utilities"
    echo -e "  ${CYAN}[5]${NC} Update ALL Components"
    echo -e "  ${CYAN}[0]${NC} Back to Menu"
    echo ""
    read -p "Select option: " component_choice
    
    case $component_choice in
        1)
            echo -e "${YELLOW}[INFO]${NC} Updating SSH/WS scripts..."
            wget -q -O /usr/bin/usernew "https://${REPO_URL}/usernew.sh" && chmod +x /usr/bin/usernew
            wget -q -O /usr/bin/menu-ssh "https://${REPO_URL}/menu-ssh.sh" && chmod +x /usr/bin/menu-ssh
            wget -q -O /usr/bin/tendang "https://${REPO_URL}/tendang.sh" && chmod +x /usr/bin/tendang
            echo -e "${GREEN}[DONE]${NC} SSH/WS scripts updated!"
            ;;
        2)
            echo -e "${YELLOW}[INFO]${NC} Updating XRAY scripts..."
            wget -q -O /usr/bin/add-ws "https://${REPO_URL}/add-ws.sh" && chmod +x /usr/bin/add-ws
            wget -q -O /usr/bin/add-vless "https://${REPO_URL}/add-vless.sh" && chmod +x /usr/bin/add-vless
            wget -q -O /usr/bin/add-tr "https://${REPO_URL}/add-tr.sh" && chmod +x /usr/bin/add-tr
            wget -q -O /usr/bin/add-ssws "https://${REPO_URL}/add-ssws.sh" && chmod +x /usr/bin/add-ssws
            wget -q -O /usr/bin/menu-vmess "https://${REPO_URL}/menu-vmess.sh" && chmod +x /usr/bin/menu-vmess
            wget -q -O /usr/bin/menu-vless "https://${REPO_URL}/menu-vless.sh" && chmod +x /usr/bin/menu-vless
            wget -q -O /usr/bin/menu-trojan "https://${REPO_URL}/menu-trojan.sh" && chmod +x /usr/bin/menu-trojan
            wget -q -O /usr/bin/menu-ss "https://${REPO_URL}/menu-ss.sh" && chmod +x /usr/bin/menu-ss
            echo -e "${GREEN}[DONE]${NC} XRAY scripts updated!"
            ;;
        3)
            echo -e "${YELLOW}[INFO]${NC} Updating menu scripts..."
            wget -q -O /usr/bin/menu "https://${REPO_URL}/menu4.sh" && chmod +x /usr/bin/menu
            echo -e "${GREEN}[DONE]${NC} Menu scripts updated!"
            ;;
        4)
            echo -e "${YELLOW}[INFO]${NC} Updating system utilities..."
            wget -q -O /usr/bin/restart "https://${REPO_URL}/restart.sh" && chmod +x /usr/bin/restart
            wget -q -O /usr/bin/autoreboot "https://${REPO_URL}/autoreboot.sh" && chmod +x /usr/bin/autoreboot
            wget -q -O /usr/bin/clearlog "https://${REPO_URL}/clearlog.sh" && chmod +x /usr/bin/clearlog
            wget -q -O /usr/bin/running "https://${REPO_URL}/running.sh" && chmod +x /usr/bin/running
            wget -q -O /usr/bin/cek-trafik "https://${REPO_URL}/cek-trafik.sh" && chmod +x /usr/bin/cek-trafik
            wget -q -O /usr/bin/xp "https://${REPO_URL}/xp.sh" && chmod +x /usr/bin/xp
            wget -q -O /usr/bin/backup "https://${REPO_URL}/backup.sh" && chmod +x /usr/bin/backup
            wget -q -O /usr/bin/restore "https://${REPO_URL}/restore.sh" && chmod +x /usr/bin/restore
            wget -q -O /usr/bin/xray-quota-manager "https://${REPO_URL}/xray-quota-manager" && chmod +x /usr/bin/xray-quota-manager
            wget -q -O /usr/bin/xray-traffic-monitor "https://${REPO_URL}/xray-traffic-monitor" && chmod +x /usr/bin/xray-traffic-monitor
            wget -q -O /usr/bin/capture-host "https://${REPO_URL}/capture-host.sh" && chmod +x /usr/bin/capture-host
            wget -q -O /usr/bin/realtime-hosts "https://${REPO_URL}/realtime-hosts.sh" && chmod +x /usr/bin/realtime-hosts
            wget -q -O /usr/bin/menu-captured-hosts "https://${REPO_URL}/menu-captured-hosts.sh" && chmod +x /usr/bin/menu-captured-hosts
            # Restart services to apply updates
            systemctl daemon-reload
            systemctl restart host-capture 2>/dev/null
            systemctl restart xray-quota-monitor 2>/dev/null
            echo -e "${GREEN}[DONE]${NC} System utilities updated!"
            ;;
        5)
            update_all_scripts
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Invalid option!"
            ;;
    esac
    
    if [ "$component_choice" != "0" ] && [ "$component_choice" != "5" ]; then
        echo ""
        echo -e "${GREEN}Component update completed!${NC}"
    fi
}

# Main menu
main_menu() {
    show_header
    echo -e "${CYAN}Select update mode:${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} Update All Scripts (Recommended)"
    echo -e "  ${CYAN}[2]${NC} Update Specific Component"
    echo -e "  ${CYAN}[3]${NC} Check for Updates"
    echo -e "  ${CYAN}[0]${NC} Exit"
    echo ""
    read -p "Select option: " choice
    
    case $choice in
        1)
            show_header
            update_all_scripts
            ;;
        2)
            show_header
            update_component
            ;;
        3)
            show_header
            echo -e "${YELLOW}[INFO]${NC} Checking for updates..."
            local_ver=$(cat /home/.ver 2>/dev/null || echo "Unknown")
            remote_ver=$(curl -s https://${REPO_URL}/test/versions || echo "Unknown")
            echo ""
            echo -e "  Current Version : ${CYAN}${local_ver}${NC}"
            echo -e "  Latest Version  : ${GREEN}${remote_ver}${NC}"
            echo ""
            if [ "$local_ver" != "$remote_ver" ] && [ "$remote_ver" != "Unknown" ]; then
                echo -e "${YELLOW}[INFO]${NC} New version available!"
                echo ""
                read -p "Do you want to update now? (y/n): " update_now
                if [ "$update_now" == "y" ] || [ "$update_now" == "Y" ]; then
                    update_all_scripts
                    echo "$remote_ver" > /home/.ver
                fi
            else
                echo -e "${GREEN}[INFO]${NC} You are running the latest version!"
            fi
            ;;
        0)
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Invalid option!"
            sleep 2
            main_menu
            ;;
    esac
    
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    main_menu
}

# Start the script
main_menu
