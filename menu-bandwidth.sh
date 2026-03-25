#!/bin/bash
# menu-bandwidth.sh
# Bandwidth quota menu — integrates xray-quota-manager into the existing
# menu system used by add-vless.sh, menu-vless.sh, etc.
# Author: LamonLind

readonly MANAGER="/usr/local/bin/xray-quota-manager"

# ---------------------------------------------------------------------------
# Colours (same palette used across the repo)
# ---------------------------------------------------------------------------
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
BLUE='\033[0;34m' CYAN='\033[0;36m' NC='\033[0m' BOLD='\e[1m'

EROR="[${RED} EROR ${NC}]"
INFO="[${YELLOW} INFO ${NC}]"
OKEY="[${GREEN} OKEY ${NC}]"

# ---------------------------------------------------------------------------
# Root guard
# ---------------------------------------------------------------------------
[ "${EUID}" -ne 0 ] && { echo -e "${EROR} Run as root."; exit 1; }

# ---------------------------------------------------------------------------
# Verify manager is installed
# ---------------------------------------------------------------------------
_require_manager() {
    [ -x "$MANAGER" ] && return 0
    echo -e "${EROR} xray-quota-manager not found at $MANAGER"
    echo -e "${INFO} Run install-quota-system.sh to install."
    return 1
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
_header() {
    clear
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}          XRAY BANDWIDTH QUOTA MENU${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------
bandwidth_menu() {
    _require_manager || { read -n1 -s -r -p "Press any key…"; return; }

    while true; do
        _header
        echo -e "  [1]  Open user dashboard"
        echo -e "  [2]  Register account with quota"
        echo -e "  [3]  View user usage"
        echo -e "  [4]  Reset user bandwidth"
        echo -e "  [5]  Set quota limit"
        echo -e "  [6]  Enable user"
        echo -e "  [7]  Disable user"
        echo -e "  [8]  Enforce quotas now"
        echo -e "  [0]  Back to main menu"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        read -rp "Option: " opt

        case "$opt" in
            1) "$MANAGER" dashboard ;;
            2) "$MANAGER" menu ;;
            3) read -rp "Username: " u; "$MANAGER" usage "$u" ;;
            4) read -rp "Username: " u; "$MANAGER" reset "$u" ;;
            5) read -rp "Username: " u; read -rp "Quota GB (0=unlimited): " g
               "$MANAGER" quota "$u" "$g" ;;
            6) read -rp "Username: " u; "$MANAGER" enable "$u" ;;
            7) read -rp "Username: " u; "$MANAGER" disable "$u" ;;
            8) "$MANAGER" enforce ;;
            0) return ;;
            *) echo -e "${EROR} Invalid option."; sleep 1; continue ;;
        esac

        read -n1 -s -r -p "Press any key to continue…"
    done
}

bandwidth_menu
