#!/bin/bash
# =========================================
# Comprehensive Bandwidth Limiter Installer
# Installs both Xray and SSH bandwidth limiting
# =========================================
# Version: 1.0.0
# Author: LamonLind
# =========================================

# Color definitions
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export NC='\033[0m'

# Root check
if [ "${EUID}" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

clear
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Comprehensive Bandwidth Limiter Installation      ║${NC}"
echo -e "${BLUE}║                                                        ║${NC}"
echo -e "${BLUE}║  • Xray per-client data limits (3x-ui style)          ║${NC}"
echo -e "${BLUE}║  • SSH cgroups v2 bandwidth limiting                  ║${NC}"
echo -e "${BLUE}║                                                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# =========================================
# DEPENDENCY INSTALLATION
# =========================================

install_dependencies() {
    echo -e "${YELLOW}[1/5]${NC} Installing system dependencies..."
    
    # Detect OS and package manager
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt-get"
        apt-get update -qq
        apt-get install -y iptables iproute2 coreutils procps jq bc curl wget net-tools >/dev/null 2>&1
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        yum install -y iptables iproute coreutils procps-ng jq bc curl wget net-tools >/dev/null 2>&1
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        dnf install -y iptables iproute coreutils procps-ng jq bc curl wget net-tools >/dev/null 2>&1
    else
        echo -e "${RED}Error: Unsupported package manager${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓${NC} Dependencies installed"
}

# =========================================
# GOLANG INSTALLATION (for Xray tools)
# =========================================

install_golang() {
    echo -e "${YELLOW}[2/5]${NC} Checking Golang installation..."
    
    # Check if Go is already installed
    if command -v go &>/dev/null; then
        local current_version=$(go version | grep -oP 'go\K[0-9.]+')
        echo -e "${GREEN}✓${NC} Golang already installed (version $current_version)"
        export PATH=$PATH:/usr/local/go/bin
        return 0
    fi
    
    echo -e "${CYAN}Installing Golang...${NC}"
    
    # Based on slowdns script pattern
    # Note: Update this version periodically or use GO_VERSION env variable
    local GO_VERSION="${GO_VERSION:-1.21.5}"
    
    # Download Go
    wget -q "https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to download Golang${NC}"
        return 1
    fi
    
    # Remove old Go installation
    rm -rf /usr/local/go
    
    # Extract new Go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm -f /tmp/go.tar.gz
    
    # Add to PATH
    if ! grep -q "/usr/local/go/bin" ~/.profile 2>/dev/null; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
    fi
    
    export PATH=$PATH:/usr/local/go/bin
    
    # Verify installation
    if /usr/local/go/bin/go version &>/dev/null; then
        echo -e "${GREEN}✓${NC} Golang ${GO_VERSION} installed successfully"
        return 0
    else
        echo -e "${RED}Error: Golang installation failed${NC}"
        return 1
    fi
}

# =========================================
# XRAY BANDWIDTH LIMITER SETUP
# =========================================

setup_xray_limiter() {
    echo -e "${YELLOW}[3/5]${NC} Setting up Xray bandwidth limiter..."
    
    # Check if Xray is installed
    if [ ! -f "/usr/local/bin/xray" ]; then
        echo -e "${YELLOW}Warning: Xray not found. Xray bandwidth limiting will not be available.${NC}"
        echo -e "${YELLOW}Install Xray first, then re-run this installer.${NC}"
        return 0
    fi
    
    # Copy script to system location
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    if [ -f "${script_dir}/xray-bandwidth-limit.sh" ]; then
        cp "${script_dir}/xray-bandwidth-limit.sh" /usr/local/bin/xray-bw-limit
        chmod +x /usr/local/bin/xray-bw-limit
        echo -e "${GREEN}✓${NC} Xray bandwidth limiter installed at /usr/local/bin/xray-bw-limit"
    else
        echo -e "${RED}Error: xray-bandwidth-limit.sh not found${NC}"
        return 1
    fi
    
    # Create systemd service for monitoring
    cat > /etc/systemd/system/xray-bw-monitor.service <<EOF
[Unit]
Description=Xray Bandwidth Monitoring Daemon
After=network.target xray.service
Requires=xray.service

[Service]
Type=simple
ExecStart=/usr/local/bin/xray-bw-limit monitor
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    
    echo -e "${GREEN}✓${NC} Xray bandwidth monitor service created"
    echo -e "${CYAN}    Start with: systemctl start xray-bw-monitor${NC}"
    echo -e "${CYAN}    Enable on boot: systemctl enable xray-bw-monitor${NC}"
}

# =========================================
# SSH LIMITER SETUP
# =========================================

setup_ssh_limiter() {
    echo -e "${YELLOW}[4/5]${NC} Setting up SSH bandwidth limiter with cgroups v2..."
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    if [ -f "${script_dir}/ssh-limiter.sh" ]; then
        # Install SSH limiter
        bash "${script_dir}/ssh-limiter.sh" install
        
        echo -e "${GREEN}✓${NC} SSH bandwidth limiter installed"
        echo -e "${CYAN}    Configure at: /etc/ssh-limiter.conf${NC}"
    else
        echo -e "${RED}Error: ssh-limiter.sh not found${NC}"
        return 1
    fi
}

# =========================================
# MENU INTEGRATION
# =========================================

create_menu_integration() {
    echo -e "${YELLOW}[5/5]${NC} Creating menu integration..."
    
    # Create a unified menu script
    cat > /usr/local/bin/bandwidth-manager <<'EOF'
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           Bandwidth Management System                 ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo -e ""
    echo -e "${CYAN}[1]${NC} Xray Client Bandwidth Management"
    echo -e "${CYAN}[2]${NC} SSH User Bandwidth Management"
    echo -e "${CYAN}[3]${NC} View Xray Client Status"
    echo -e "${CYAN}[4]${NC} View SSH User Status"
    echo -e "${CYAN}[5]${NC} Start/Stop Monitoring Services"
    echo -e "${CYAN}[0]${NC} Exit"
    echo -e ""
    read -p "Select option: " choice
    
    case $choice in
        1) xray_menu ;;
        2) ssh_menu ;;
        3) /usr/local/bin/xray-bw-limit status; read -p "Press enter to continue..."; show_menu ;;
        4) /usr/local/bin/ssh-limiter.sh status; read -p "Press enter to continue..."; show_menu ;;
        5) services_menu ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; show_menu ;;
    esac
}

xray_menu() {
    clear
    echo -e "${BLUE}=== Xray Client Bandwidth Management ===${NC}\n"
    echo -e "${CYAN}[1]${NC} Add bandwidth limit to client"
    echo -e "${CYAN}[2]${NC} Remove bandwidth limit from client"
    echo -e "${CYAN}[3]${NC} Reset client usage"
    echo -e "${CYAN}[4]${NC} Check limits now"
    echo -e "${CYAN}[0]${NC} Back"
    echo -e ""
    read -p "Select option: " choice
    
    case $choice in
        1)
            read -p "Client email: " email
            read -p "Protocol (vmess/vless/trojan): " protocol
            read -p "Limit (e.g., 100MB, 10GB, 0 for unlimited): " limit
            /usr/local/bin/xray-bw-limit add-limit "$email" "$protocol" "$limit"
            read -p "Press enter to continue..."
            xray_menu
            ;;
        2)
            read -p "Client email: " email
            /usr/local/bin/xray-bw-limit remove-limit "$email"
            read -p "Press enter to continue..."
            xray_menu
            ;;
        3)
            read -p "Client email: " email
            /usr/local/bin/xray-bw-limit reset-usage "$email"
            read -p "Press enter to continue..."
            xray_menu
            ;;
        4)
            /usr/local/bin/xray-bw-limit check
            read -p "Press enter to continue..."
            xray_menu
            ;;
        0) show_menu ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; xray_menu ;;
    esac
}

ssh_menu() {
    clear
    echo -e "${BLUE}=== SSH User Bandwidth Management ===${NC}\n"
    echo -e "${CYAN}[1]${NC} Add user to monitoring"
    echo -e "${CYAN}[2]${NC} Remove user from monitoring"
    echo -e "${CYAN}[3]${NC} Reset user usage"
    echo -e "${CYAN}[4]${NC} Set custom limit for user"
    echo -e "${CYAN}[5]${NC} Set custom quota for user"
    echo -e "${CYAN}[0]${NC} Back"
    echo -e ""
    read -p "Select option: " choice
    
    case $choice in
        1)
            read -p "Username: " username
            /usr/local/bin/ssh-limiter.sh add-user "$username"
            read -p "Press enter to continue..."
            ssh_menu
            ;;
        2)
            read -p "Username: " username
            /usr/local/bin/ssh-limiter.sh remove-user "$username"
            read -p "Press enter to continue..."
            ssh_menu
            ;;
        3)
            read -p "Username: " username
            /usr/local/bin/ssh-limiter.sh reset-user "$username"
            read -p "Press enter to continue..."
            ssh_menu
            ;;
        4)
            read -p "Username: " username
            read -p "Limit (kbps): " limit
            /usr/local/bin/ssh-limiter.sh set-limit "$username" "$limit"
            read -p "Press enter to continue..."
            ssh_menu
            ;;
        5)
            read -p "Username: " username
            read -p "Quota (MB): " quota
            /usr/local/bin/ssh-limiter.sh set-quota "$username" "$quota"
            read -p "Press enter to continue..."
            ssh_menu
            ;;
        0) show_menu ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; ssh_menu ;;
    esac
}

services_menu() {
    clear
    echo -e "${BLUE}=== Monitoring Services ===${NC}\n"
    
    # Check service status
    echo -e "Xray Monitor: $(systemctl is-active xray-bw-monitor 2>/dev/null || echo 'inactive')"
    echo -e "SSH Monitor: $(systemctl is-active ssh-limiter 2>/dev/null || echo 'inactive')"
    echo -e ""
    
    echo -e "${CYAN}[1]${NC} Start Xray monitoring"
    echo -e "${CYAN}[2]${NC} Stop Xray monitoring"
    echo -e "${CYAN}[3]${NC} Start SSH monitoring"
    echo -e "${CYAN}[4]${NC} Stop SSH monitoring"
    echo -e "${CYAN}[5]${NC} Enable Xray monitor on boot"
    echo -e "${CYAN}[6]${NC} Enable SSH monitor on boot"
    echo -e "${CYAN}[0]${NC} Back"
    echo -e ""
    read -p "Select option: " choice
    
    case $choice in
        1) systemctl start xray-bw-monitor; echo "Started"; sleep 1; services_menu ;;
        2) systemctl stop xray-bw-monitor; echo "Stopped"; sleep 1; services_menu ;;
        3) systemctl start ssh-limiter; echo "Started"; sleep 1; services_menu ;;
        4) systemctl stop ssh-limiter; echo "Stopped"; sleep 1; services_menu ;;
        5) systemctl enable xray-bw-monitor; echo "Enabled"; sleep 1; services_menu ;;
        6) systemctl enable ssh-limiter; echo "Enabled"; sleep 1; services_menu ;;
        0) show_menu ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; services_menu ;;
    esac
}

show_menu
EOF
    
    chmod +x /usr/local/bin/bandwidth-manager
    
    echo -e "${GREEN}✓${NC} Menu integration created"
    echo -e "${CYAN}    Access menu: bandwidth-manager${NC}"
}

# =========================================
# MAIN INSTALLATION
# =========================================

main() {
    echo -e "${CYAN}Starting installation...${NC}\n"
    
    install_dependencies
    install_golang
    setup_xray_limiter
    setup_ssh_limiter
    create_menu_integration
    
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              Installation Complete!                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo -e ""
    echo -e "${GREEN}Commands available:${NC}"
    echo -e "  ${CYAN}bandwidth-manager${NC}     - Interactive menu"
    echo -e "  ${CYAN}xray-bw-limit${NC}         - Xray bandwidth management"
    echo -e "  ${CYAN}ssh-limiter.sh${NC}        - SSH bandwidth management"
    echo -e ""
    echo -e "${GREEN}Quick Start:${NC}"
    echo -e "  1. Add SSH users to monitoring:"
    echo -e "     ${CYAN}ssh-limiter.sh add-user vpnuser1${NC}"
    echo -e ""
    echo -e "  2. Add Xray client limits:"
    echo -e "     ${CYAN}xray-bw-limit add-limit user@example.com vmess 10${NC}"
    echo -e ""
    echo -e "  3. Start monitoring services:"
    echo -e "     ${CYAN}systemctl start ssh-limiter${NC}"
    echo -e "     ${CYAN}systemctl start xray-bw-monitor${NC}"
    echo -e ""
    echo -e "  4. Enable on boot:"
    echo -e "     ${CYAN}systemctl enable ssh-limiter${NC}"
    echo -e "     ${CYAN}systemctl enable xray-bw-monitor${NC}"
    echo -e ""
    echo -e "${YELLOW}Configuration files:${NC}"
    echo -e "  SSH: ${CYAN}/etc/ssh-limiter.conf${NC}"
    echo -e "  Xray: ${CYAN}/etc/xray/client-limits.db${NC}"
    echo -e ""
    echo -e "${YELLOW}Log files:${NC}"
    echo -e "  SSH: ${CYAN}/var/log/ssh-limiter.log${NC}"
    echo -e "  Xray: ${CYAN}/var/log/xray-bandwidth.log${NC}"
    echo -e ""
}

main
