#!/bin/bash
# =========================================
# Host Capture Service Daemon
# Runs host capture in continuous loop
# Designed for systemd service with full root access
# Author: LamonLind
# (C) Copyright 2024
# =========================================

# Export Color & Information
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
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
CAPTURE_SCRIPT="/usr/local/bin/capture-host.sh"
LOG_FILE="/var/log/host-capture-service.log"

# Function to log messages
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if capture script exists
if [ ! -f "$CAPTURE_SCRIPT" ]; then
    log_msg "ERROR: Capture script not found at $CAPTURE_SCRIPT"
    exit 1
fi

if [ ! -x "$CAPTURE_SCRIPT" ]; then
    log_msg "WARNING: Capture script not executable, attempting to fix..."
    chmod +x "$CAPTURE_SCRIPT"
fi

log_msg "Host Capture Service starting..."

# Main loop - run capture every 2 seconds (safe frequency)
# 2 seconds provides real-time capture without overloading the system
while true; do
    # Run the capture script, filtering output to prevent log spam
    # Only capture errors and important messages
    "$CAPTURE_SCRIPT" 2>&1 | grep -E "(EROR|OKEY|new host)" >> "$LOG_FILE"
    
    # Wait 2 seconds before next capture (optimal frequency: 1-5 seconds)
    # - 1 second: very aggressive, high CPU usage
    # - 2 seconds: RECOMMENDED - excellent real-time capture, low overhead
    # - 5 seconds: conservative, may miss some short-lived connections
    sleep 2
done
