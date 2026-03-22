#!/bin/bash
# =========================================
# Standalone Host Capture Installer
# Installs the Universal Host Capture feature
# WITHOUT requiring the full VPN script setup.
#
# Requirements:
#   - Debian/Ubuntu Linux
#   - Root access
#   - Existing xray/v2ray installation
#
# Usage:
#   wget -qO install-host-capture.sh https://raw.githubusercontent.com/LamonLind/Blue/main/install-host-capture.sh
#   chmod +x install-host-capture.sh && ./install-host-capture.sh
# =========================================

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export CYAN='\033[0;36m'
export NC='\033[0m'

export EROR="[${RED} EROR ${NC}]"
export INFO="[${YELLOW} INFO ${NC}]"
export OKEY="[${GREEN} OKEY ${NC}]"

REPO_URL="raw.githubusercontent.com/LamonLind/Blue/main"

# Root check
if [ "${EUID}" -ne 0 ]; then
    echo -e "${EROR} Please Run This Script As Root User !"
    exit 1
fi

clear
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo -e "\E[44;1;39m          ⇱ UNIVERSAL HOST CAPTURE - INSTALLER ⇲            \E[0m"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo -e ""
echo -e " ${INFO} This installer adds the Universal Host Capture feature"
echo -e " ${INFO} to an existing xray/v2ray VPN server."
echo -e ""
echo -e " ${INFO} It extracts hosts from:"
echo -e "        • /etc/xray/config.json  (Target Host, SNI, Host Headers)"
echo -e "        • /home/vps/public_html/ (client link files)"
echo -e ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo ""
read -p " Proceed with installation? (y/n): " confirm
[[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo -e "\n ${INFO} Installation cancelled."; exit 0; }

echo ""

# Create required directories
echo -ne " ${INFO} Creating directories..."
mkdir -p /etc/myvpn 2>/dev/null
echo -e " ${OKEY}"

# Download capture-host
echo -ne " ${INFO} Installing capture-host..."
if wget -q -O /usr/bin/capture-host "https://${REPO_URL}/capture-host.sh"; then
    chmod +x /usr/bin/capture-host
    echo -e " ${OKEY}"
else
    echo -e " ${EROR} Failed to download capture-host"
    exit 1
fi

# Download menu-captured-hosts
echo -ne " ${INFO} Installing menu-captured-hosts..."
if wget -q -O /usr/bin/menu-captured-hosts "https://${REPO_URL}/menu-captured-hosts.sh"; then
    chmod +x /usr/bin/menu-captured-hosts
    echo -e " ${OKEY}"
else
    echo -e " ${EROR} Failed to download menu-captured-hosts"
    exit 1
fi

# Stop and disable old host-capture service if running
if systemctl is-active --quiet host-capture 2>/dev/null; then
    echo -ne " ${INFO} Stopping old host-capture service..."
    systemctl stop host-capture 2>/dev/null
    systemctl disable host-capture 2>/dev/null
    echo -e " ${OKEY}"
fi

# Remove old cron entry if present
if [ -f /etc/cron.d/capture_host ]; then
    echo -ne " ${INFO} Removing old capture_host cron..."
    rm -f /etc/cron.d/capture_host
    echo -e " ${OKEY}"
fi

# Initialize hosts file
[ ! -f /etc/myvpn/hosts.log ] && touch /etc/myvpn/hosts.log

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo -e " ${OKEY} Universal Host Capture installed successfully!"
echo -e ""
echo -e " ${INFO} Usage:"
echo -e "        Run  ${CYAN}menu-captured-hosts${NC}  to open the host capture menu"
echo -e "        Run  ${CYAN}capture-host${NC}         to extract hosts from config files"
echo -e ""
echo -e " ${INFO} Results saved to: /etc/myvpn/hosts.log"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
echo ""

read -p " Run host extraction now? (y/n): " run_now
if [[ "$run_now" == "y" || "$run_now" == "Y" ]]; then
    echo ""
    /usr/bin/capture-host
    echo ""
    echo -e " ${INFO} Open menu with: ${CYAN}menu-captured-hosts${NC}"
fi
