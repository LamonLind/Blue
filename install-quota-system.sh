#!/bin/bash
# install-quota-system.sh
# Installs xray-quota-manager, xray-traffic-monitor, menu-bandwidth.sh,
# and the systemd service for the bandwidth quota system.
# Author: LamonLind

set -euo pipefail

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' NC='\033[0m'

[ "${EUID}" -ne 0 ] && { echo -e "${RED}Run as root.${NC}"; exit 1; }

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BIN_DIR="/usr/local/bin"
readonly SERVICE_DIR="/etc/systemd/system"
readonly MENU_DIR="/usr/local/bin"
readonly LOG_DIR="/var/log"
readonly DB_DIR="/etc/xray"

# ---------------------------------------------------------------------------
# Step 1 — Dependencies
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[1/5] Checking dependencies…${NC}"
MISSING=()
for pkg in jq bc curl; do
    command -v "$pkg" &>/dev/null || MISSING+=("$pkg")
done
if [ "${#MISSING[@]}" -gt 0 ]; then
    echo "Installing: ${MISSING[*]}"
    apt-get install -y "${MISSING[@]}" 2>/dev/null \
        || yum install -y "${MISSING[@]}" 2>/dev/null \
        || { echo -e "${RED}Could not install ${MISSING[*]}. Install manually.${NC}"; exit 1; }
fi
echo -e "${GREEN}  Dependencies OK.${NC}"

# ---------------------------------------------------------------------------
# Step 2 — Copy binaries
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[2/5] Installing binaries…${NC}"
install -m 755 "$SCRIPT_DIR/xray-quota-manager"  "$BIN_DIR/xray-quota-manager"
install -m 755 "$SCRIPT_DIR/xray-traffic-monitor" "$BIN_DIR/xray-traffic-monitor"
install -m 755 "$SCRIPT_DIR/menu-bandwidth.sh"    "$MENU_DIR/menu-bandwidth.sh"
echo -e "${GREEN}  Installed to $BIN_DIR.${NC}"

# ---------------------------------------------------------------------------
# Step 3 — Initialise DB
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[3/5] Initialising quota database…${NC}"
[ -d "$DB_DIR" ] || mkdir -p "$DB_DIR"
[ -f "$DB_DIR/quota-db.json" ] || { printf '{"users":[]}\n' > "$DB_DIR/quota-db.json"; chmod 600 "$DB_DIR/quota-db.json"; }
touch "$LOG_DIR/xray-quota.log"
echo -e "${GREEN}  DB ready at $DB_DIR/quota-db.json.${NC}"

# ---------------------------------------------------------------------------
# Step 4 — Systemd service
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[4/5] Installing systemd service…${NC}"
install -m 644 "$SCRIPT_DIR/xray-quota-monitor.service" "$SERVICE_DIR/xray-quota-monitor.service"
systemctl daemon-reload
systemctl enable  xray-quota-monitor
systemctl restart xray-quota-monitor
echo -e "${GREEN}  Service xray-quota-monitor enabled and started.${NC}"

# ---------------------------------------------------------------------------
# Step 5 — Verify
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[5/5] Verifying…${NC}"
if systemctl is-active --quiet xray-quota-monitor; then
    echo -e "${GREEN}  xray-quota-monitor is running.${NC}"
else
    echo -e "${RED}  Service did not start — check: journalctl -u xray-quota-monitor${NC}"
fi

echo ""
echo -e "${GREEN}Installation complete.${NC}"
echo -e "  Run quota manager : ${YELLOW}xray-quota-manager${NC}"
echo -e "  Bandwidth menu    : ${YELLOW}bash /usr/local/bin/menu-bandwidth.sh${NC}"
echo -e "  Monitor logs      : ${YELLOW}tail -f /var/log/xray-quota.log${NC}"
