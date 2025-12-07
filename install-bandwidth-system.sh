#!/bin/bash
# =========================================
# Bandwidth & Host Capture System Installer
# Installs all components needed for the bandwidth monitoring and host capture system
# Author: LamonLind
# (C) Copyright 2024
# =========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

EROR="[${RED} EROR ${NC}]"
INFO="[${YELLOW} INFO ${NC}]"
OKEY="[${GREEN} OKEY ${NC}]"

# Root check
if [ "${EUID}" -ne 0 ]; then
    echo -e "${EROR} Please run this script as root!"
    exit 1
fi

echo -e "${INFO} Installing Bandwidth & Host Capture System..."
echo ""

# Step 1: Install main scripts
echo -e "${INFO} Installing main scripts..."
cp cek-bw-limit.sh /usr/bin/cek-bw-limit
chmod +x /usr/bin/cek-bw-limit
echo -e "${OKEY} Installed cek-bw-limit to /usr/bin/cek-bw-limit"

cp capture-host.sh /usr/bin/capture-host
chmod +x /usr/bin/capture-host
echo -e "${OKEY} Installed capture-host to /usr/bin/capture-host"

# Install bandwidth tracking library if exists
if [ -f "bw-tracking-lib.sh" ]; then
    cp bw-tracking-lib.sh /usr/bin/bw-tracking-lib
    chmod +x /usr/bin/bw-tracking-lib
    echo -e "${OKEY} Installed bw-tracking-lib to /usr/bin/bw-tracking-lib"
fi

# Install real-time bandwidth monitor if exists
if [ -f "realtime-bandwidth.sh" ]; then
    cp realtime-bandwidth.sh /usr/bin/realtime-bandwidth
    chmod +x /usr/bin/realtime-bandwidth
    echo -e "${OKEY} Installed realtime-bandwidth to /usr/bin/realtime-bandwidth"
fi

# Install real-time host capture monitor if exists
if [ -f "realtime-hosts.sh" ]; then
    cp realtime-hosts.sh /usr/bin/realtime-hosts
    chmod +x /usr/bin/realtime-hosts
    echo -e "${OKEY} Installed realtime-hosts to /usr/bin/realtime-hosts"
fi

echo ""

# Step 2: Create directory structure
echo -e "${INFO} Creating directory structure..."
mkdir -p /etc/xray
mkdir -p /etc/myvpn/usage
mkdir -p /etc/myvpn/blocked_users
echo -e "${OKEY} Created directories"

# Step 3: Create configuration files
echo -e "${INFO} Creating configuration files..."
touch /etc/xray/bw-limit.conf
touch /etc/xray/bw-usage.conf
touch /etc/xray/bw-disabled.conf
touch /etc/xray/bw-last-stats.conf
chmod 644 /etc/xray/bw-*.conf
echo -e "${OKEY} Created bandwidth configuration files"

# Step 4: Create log files
echo -e "${INFO} Creating log files..."
touch /etc/myvpn/blocked.log
touch /etc/myvpn/deleted.log
touch /etc/myvpn/hosts.log
chmod 644 /etc/myvpn/*.log
echo -e "${OKEY} Created log files"

# Step 5: Set directory permissions
chmod 755 /etc/myvpn/usage
chmod 755 /etc/myvpn/blocked_users
echo -e "${OKEY} Set directory permissions"

echo ""

# Step 6: Create systemd services
echo -e "${INFO} Creating systemd services..."

# Bandwidth monitoring service (2-second interval)
cat > /etc/systemd/system/bw-limit-check.service <<'END'
[Unit]
Description=Bandwidth Limit Monitoring and Blocking Service (2s interval)
After=network.target xray.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do /usr/bin/cek-bw-limit check >/dev/null 2>&1; sleep 2; done'
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
END
echo -e "${OKEY} Created bw-limit-check.service"

# Host capture service (2-second interval)
cat > /etc/systemd/system/host-capture.service <<'END'
[Unit]
Description=Real-time Host Capture Service (2s interval)
After=network.target xray.service nginx.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do /usr/bin/capture-host >/dev/null 2>&1; sleep 2; done'
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
END
echo -e "${OKEY} Created host-capture.service"

echo ""

# Step 7: Reload systemd and enable services
echo -e "${INFO} Enabling and starting services..."
systemctl daemon-reload
systemctl enable bw-limit-check >/dev/null 2>&1
systemctl enable host-capture >/dev/null 2>&1

# Start services
systemctl start bw-limit-check
if systemctl is-active --quiet bw-limit-check; then
    echo -e "${OKEY} Started bw-limit-check service"
else
    echo -e "${EROR} Failed to start bw-limit-check service"
fi

systemctl start host-capture
if systemctl is-active --quiet host-capture; then
    echo -e "${OKEY} Started host-capture service"
else
    echo -e "${EROR} Failed to start host-capture service"
fi

echo ""

# Step 8: Add cron job for host capture (backup)
echo -e "${INFO} Adding cron job for host capture (backup)..."
if ! crontab -l 2>/dev/null | grep -q "/usr/bin/capture-host"; then
    (crontab -l 2>/dev/null; echo "* * * * * root /usr/bin/capture-host >/dev/null 2>&1") | crontab -
    echo -e "${OKEY} Added cron job"
else
    echo -e "${INFO} Cron job already exists"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${INFO} Services installed:"
echo -e "  - bw-limit-check.service (Bandwidth monitoring)"
echo -e "  - host-capture.service (Host capture)"
echo ""
echo -e "${INFO} Scripts installed:"
echo -e "  - /usr/bin/cek-bw-limit"
echo -e "  - /usr/bin/capture-host"
echo ""
echo -e "${INFO} You can now use:"
echo -e "  - cek-bw-limit menu  # Interactive menu"
echo -e "  - systemctl status bw-limit-check"
echo -e "  - systemctl status host-capture"
echo ""

exit 0
