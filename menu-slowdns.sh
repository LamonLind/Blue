#!/bin/bash
# =========================================
# SlowDNS Menu Script
# Based on LamonLind/autodns
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
green() { echo -e "\\033[32;1m${*}\\033[0m"; }
red() { echo -e "\\033[31;1m${*}\\033[0m"; }

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

# // Root Checking
if [ "${EUID}" -ne 0 ]; then
    echo -e "${EROR} Please Run This Script As Root User !"
    exit 1
fi

# Configuration paths
CONFIG_FILE="/etc/dnstt/config"
INSTALL_DIR="/opt/dnstt"

# Function to check if SlowDNS is installed
check_installed() {
    if [ -f "$CONFIG_FILE" ] && [ -d "$INSTALL_DIR/dnstt" ]; then
        return 0
    else
        return 1
    fi
}

# Function to check if SlowDNS is running
check_running() {
    if systemctl is-active --quiet dnstt.service 2>/dev/null; then
        return 0
    elif screen -list | grep -q "dnstt"; then
        return 0
    else
        return 1
    fi
}

# Function to display SlowDNS status
show_status() {
    clear
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\E[0;41;36m            SLOWDNS STATUS               \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    
    if ! check_installed; then
        echo -e "${RED}SlowDNS is not installed${NC}"
        echo -e ""
        echo -e "Use option [1] to install SlowDNS"
        echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        read -n 1 -s -r -p "Press any key to back on menu"
        menu-slowdns
        return
    fi
    
    # Load configuration
    source "$CONFIG_FILE"
    
    if check_running; then
        STATUS="${GREEN}● RUNNING${NC}"
    else
        STATUS="${RED}● STOPPED${NC}"
    fi
    
    echo -e ""
    echo -e " ${YELLOW}Public Key  :${NC} ${GREEN}$PUBKEY${NC}"
    echo -e " ${YELLOW}Name Server :${NC} ${GREEN}$NAMESERVER${NC}"
    echo -e " ${YELLOW}DNSTT Port  :${NC} ${GREEN}$PORT${NC}"
    echo -e " ${YELLOW}Status      :${NC} $STATUS"
    echo -e ""
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    read -n 1 -s -r -p "Press any key to back on menu"
    menu-slowdns
}

# Function to install SlowDNS
install_slowdns() {
    clear
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\E[0;41;36m          INSTALL SLOWDNS                \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    
    if check_installed; then
        echo -e "${YELLOW}SlowDNS is already installed${NC}"
        echo -e ""
        read -n 1 -s -r -p "Press any key to back on menu"
        menu-slowdns
        return
    fi
    
    echo -e ""
    read -p "Enter Name Server (e.g., ns.example.com): " NAMESERVER
    
    if [ -z "$NAMESERVER" ]; then
        echo -e "${RED}Error: Nameserver cannot be empty${NC}"
        read -n 1 -s -r -p "Press any key to back on menu"
        menu-slowdns
        return
    fi
    
    echo -e ""
    echo -e "${YELLOW}[*] Installing dependencies...${NC}"
    apt-get update -qq
    apt-get install -y git screen iptables iptables-persistent wget > /dev/null 2>&1
    
    # Install golang
    echo -e "${YELLOW}[*] Installing golang...${NC}"
    GO_V="1.22.5"
    wget -q https://dl.google.com/go/go${GO_V}.linux-amd64.tar.gz
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to download golang${NC}"
        read -n 1 -s -r -p "Press any key to back on menu"
        menu-slowdns
        return
    fi
    
    rm -rf /usr/local/go
    tar -C /usr/local -xzf go${GO_V}.linux-amd64.tar.gz
    rm go${GO_V}.linux-amd64.tar.gz
    
    # Add Go to PATH
    if ! grep -q "/usr/local/go/bin" ~/.profile 2>/dev/null; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
    fi
    export PATH=$PATH:/usr/local/go/bin
    
    echo -e "${GREEN}✓ Go ${GO_V} Installed${NC}"
    
    # Create directories
    echo -e "${YELLOW}[*] Creating installation directories...${NC}"
    mkdir -p "$INSTALL_DIR"
    mkdir -p "/etc/dnstt"
    
    # Clone and build dnstt
    if [ ! -d "$INSTALL_DIR/dnstt" ]; then
        echo -e "${YELLOW}[*] Cloning dnstt from source...${NC}"
        cd "$INSTALL_DIR"
        git clone https://www.bamsoftware.com/git/dnstt.git > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error: Failed to clone dnstt repository${NC}"
            read -n 1 -s -r -p "Press any key to back on menu"
            menu-slowdns
            return
        fi
    fi
    
    # Build dnstt-server
    echo -e "${YELLOW}[*] Building dnstt-server...${NC}"
    cd "$INSTALL_DIR/dnstt/dnstt-server"
    /usr/local/go/bin/go build > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to build dnstt-server${NC}"
        read -n 1 -s -r -p "Press any key to back on menu"
        menu-slowdns
        return
    fi
    
    # Generate server keys
    echo -e "${YELLOW}[*] Generating server keys...${NC}"
    ./dnstt-server -gen-key -privkey-file "$INSTALL_DIR/server.key" -pubkey-file "$INSTALL_DIR/server.pub" > /dev/null 2>&1
    
    # Read the public key
    PUBKEY=$(cat "$INSTALL_DIR/server.pub")
    echo -e "${GREEN}✓ Public key generated${NC}"
    
    # Default port
    PORT=22
    
    # Save configuration
    echo -e "${YELLOW}[*] Saving configuration...${NC}"
    cat > "$CONFIG_FILE" <<EOF
# DNSTT Configuration
NAMESERVER=$NAMESERVER
PORT=$PORT
INSTALL_DIR=$INSTALL_DIR
PUBKEY=$PUBKEY
EOF

    # Set up iptables rules
    echo -e "${YELLOW}[*] Setting up iptables rules...${NC}"
    
    # Detect primary network interface
    PRIMARY_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -z "$PRIMARY_IFACE" ]; then
        PRIMARY_IFACE="eth0"
    fi
    
    iptables -I INPUT -p udp --dport 5300 -j ACCEPT
    iptables -t nat -I PREROUTING -i "$PRIMARY_IFACE" -p udp --dport 53 -j REDIRECT --to-ports 5300
    
    # Save iptables rules
    if command -v netfilter-persistent > /dev/null; then
        netfilter-persistent save > /dev/null 2>&1
    elif command -v iptables-save > /dev/null; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    
    # Create systemd service
    echo -e "${YELLOW}[*] Creating systemd service...${NC}"
    cat > /etc/systemd/system/dnstt.service <<SERVICEEOF
[Unit]
Description=DNSTT DNS Tunnel Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/dnstt/dnstt-server
EnvironmentFile=$CONFIG_FILE
ExecStart=/usr/bin/screen -DmS dnstt $INSTALL_DIR/dnstt/dnstt-server/dnstt-server -udp :5300 -privkey-file $INSTALL_DIR/server.key \${NAMESERVER} 127.0.0.1:\${PORT}
ExecStop=/usr/bin/screen -S dnstt -X quit
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICEEOF

    systemctl daemon-reload
    systemctl enable dnstt.service > /dev/null 2>&1
    
    # Start dnstt service
    echo -e "${YELLOW}[*] Starting DNSTT server...${NC}"
    systemctl start dnstt.service
    
    sleep 2
    
    if check_running; then
        echo -e "${GREEN}✓ DNSTT server started successfully${NC}"
    else
        echo -e "${RED}✗ Failed to start DNSTT server${NC}"
    fi
    
    echo -e ""
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "${GREEN}Installation Complete!${NC}"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e " ${YELLOW}Public Key  :${NC} ${GREEN}$PUBKEY${NC}"
    echo -e " ${YELLOW}Name Server :${NC} ${GREEN}$NAMESERVER${NC}"
    echo -e " ${YELLOW}Port        :${NC} ${GREEN}$PORT${NC}"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    read -n 1 -s -r -p "Press any key to back on menu"
    menu-slowdns
}

# Function to restart SlowDNS
restart_slowdns() {
    clear
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\E[0;41;36m          RESTART SLOWDNS                \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    
    if ! check_installed; then
        echo -e "${RED}SlowDNS is not installed${NC}"
        read -n 1 -s -r -p "Press any key to back on menu"
        menu-slowdns
        return
    fi
    
    echo -e "${YELLOW}Restarting DNSTT...${NC}"
    systemctl restart dnstt.service
    sleep 1
    
    if check_running; then
        echo -e "${GREEN}✓ DNSTT restarted successfully${NC}"
    else
        echo -e "${RED}✗ Failed to restart DNSTT${NC}"
    fi
    
    read -n 1 -s -r -p "Press any key to back on menu"
    menu-slowdns
}

# Function to stop SlowDNS
stop_slowdns() {
    clear
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\E[0;41;36m           STOP SLOWDNS                  \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    
    if ! check_installed; then
        echo -e "${RED}SlowDNS is not installed${NC}"
        read -n 1 -s -r -p "Press any key to back on menu"
        menu-slowdns
        return
    fi
    
    if ! check_running; then
        echo -e "${YELLOW}DNSTT is not running${NC}"
        read -n 1 -s -r -p "Press any key to back on menu"
        menu-slowdns
        return
    fi
    
    systemctl stop dnstt.service
    echo -e "${GREEN}✓ DNSTT stopped${NC}"
    
    read -n 1 -s -r -p "Press any key to back on menu"
    menu-slowdns
}

# Function to change port
change_port() {
    clear
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\E[0;41;36m          CHANGE SLOWDNS PORT            \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    
    if ! check_installed; then
        echo -e "${RED}SlowDNS is not installed${NC}"
        read -n 1 -s -r -p "Press any key to back on menu"
        menu-slowdns
        return
    fi
    
    source "$CONFIG_FILE"
    
    echo -e ""
    echo -e " Current Port: ${GREEN}$PORT${NC}"
    echo -e ""
    echo -e " ${CYAN}Select new port:${NC}"
    echo -e "  ${YELLOW}1.${NC} Port 22 (SSH)"
    echo -e "  ${YELLOW}2.${NC} Port 80 (HTTP)"
    echo -e "  ${YELLOW}3.${NC} Port 443 (HTTPS)"
    echo -e ""
    read -p "Enter choice [1-3]: " choice
    
    case $choice in
        1) NEW_PORT=22 ;;
        2) NEW_PORT=80 ;;
        3) NEW_PORT=443 ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            read -n 1 -s -r -p "Press any key to back on menu"
            menu-slowdns
            return
            ;;
    esac
    
    # Update config file
    sed -i "s/PORT=.*/PORT=$NEW_PORT/" "$CONFIG_FILE"
    
    echo -e "${GREEN}✓ Port changed to $NEW_PORT${NC}"
    
    # Restart service
    systemctl daemon-reload
    systemctl restart dnstt.service
    sleep 1
    
    if check_running; then
        echo -e "${GREEN}✓ DNSTT restarted with new port${NC}"
    else
        echo -e "${RED}✗ Failed to restart DNSTT${NC}"
    fi
    
    read -n 1 -s -r -p "Press any key to back on menu"
    menu-slowdns
}

# Function to uninstall SlowDNS
uninstall_slowdns() {
    clear
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\E[0;41;36m         UNINSTALL SLOWDNS               \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    
    if ! check_installed; then
        echo -e "${RED}SlowDNS is not installed${NC}"
        read -n 1 -s -r -p "Press any key to back on menu"
        menu-slowdns
        return
    fi
    
    echo -e ""
    read -p "Are you sure you want to uninstall SlowDNS? [y/N]: " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo -e "${YELLOW}Uninstall cancelled${NC}"
        read -n 1 -s -r -p "Press any key to back on menu"
        menu-slowdns
        return
    fi
    
    echo -e "${YELLOW}[*] Stopping DNSTT service...${NC}"
    systemctl stop dnstt.service 2>/dev/null
    systemctl disable dnstt.service 2>/dev/null
    
    echo -e "${YELLOW}[*] Removing systemd service...${NC}"
    rm -f /etc/systemd/system/dnstt.service
    systemctl daemon-reload
    
    echo -e "${YELLOW}[*] Removing installation directory...${NC}"
    rm -rf "$INSTALL_DIR"
    
    echo -e "${YELLOW}[*] Removing configuration...${NC}"
    rm -rf /etc/dnstt
    
    echo -e "${GREEN}✓ SlowDNS uninstalled successfully${NC}"
    
    read -n 1 -s -r -p "Press any key to back on menu"
    menu-slowdns
}

# Main menu
clear

# Check status for display
if check_installed && check_running; then
    SDNS_STATUS="${GREEN}ON${NC}"
else
    SDNS_STATUS="${RED}OFF${NC}"
fi

echo -e "${BICyan} ┌─────────────────────────────────────────────────────┐${NC}"
echo -e "       ${BIWhite}${UWhite}SLOWDNS MENU ${NC}     Status: $SDNS_STATUS"
echo -e ""
echo -e "     ${BICyan}[${BIWhite}1${BICyan}] Install SlowDNS      "
echo -e "     ${BICyan}[${BIWhite}2${BICyan}] SlowDNS Status      "
echo -e "     ${BICyan}[${BIWhite}3${BICyan}] Restart SlowDNS      "
echo -e "     ${BICyan}[${BIWhite}4${BICyan}] Stop SlowDNS     "
echo -e "     ${BICyan}[${BIWhite}5${BICyan}] Change Port (22/80/443)     "
echo -e "     ${BICyan}[${BIWhite}6${BICyan}] Uninstall SlowDNS     "
echo -e " ${BICyan}└─────────────────────────────────────────────────────┘${NC}"
echo -e "     ${BIYellow}Press x or [ Ctrl+C ] • To-${BIWhite}Exit${NC}"
echo ""
read -p " Select menu : " opt
echo -e ""
case $opt in
1) clear ; install_slowdns ;;
2) clear ; show_status ;;
3) clear ; restart_slowdns ;;
4) clear ; stop_slowdns ;;
5) clear ; change_port ;;
6) clear ; uninstall_slowdns ;;
0) clear ; menu ;;
x) exit ;;
*) echo -e "" ; echo "Press any key to back on menu" ; sleep 1 ; menu ;;
esac
