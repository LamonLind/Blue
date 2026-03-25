#!/usr/bin/env bash

red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[0;34m'
NC='\e[0m'

if [ "${EUID}" -ne 0 ]; then
    echo -e "${red}Please run this script as root.${NC}"
    exit 1
fi

QUOTA_MANAGER="/usr/bin/xray-quota-manager"
DB_PATH="/etc/xray/user-quotas.json"
if [ ! -x "$QUOTA_MANAGER" ]; then
    echo -e "${red}Quota manager not found at ${QUOTA_MANAGER}.${NC}"
    exit 1
fi

status_filter="all"

read_user_list() {
    local prompt="$1"
    local input
    read -rp "$prompt" input
    if [ -z "$input" ]; then
        echo ""
        return
    fi
    echo "$input" | tr ',' ' '
}

resolve_users() {
    local input="$1"
    if [ "$input" = "all" ]; then
        if [ -f "$DB_PATH" ]; then
            jq -r '.users[]?.username' "$DB_PATH"
        fi
    else
        echo "$input"
    fi
}

while true; do
    clear
    "$QUOTA_MANAGER" dashboard "$status_filter"
    echo ""
    echo "Options:"
    echo "[1] View user details"
    echo "[2] Reset user bandwidth"
    echo "[3] Extend bandwidth quota"
    echo "[4] Enable/Disable user"
    echo "[5] Delete user"
    echo "[6] Filter users (all/active/disabled/expired)"
    echo "[7] Back to main menu"
    echo ""
    read -rp "Select option: " option
    case "$option" in
        1)
            read -rp "Username: " username
            if [ -n "$username" ]; then
                clear
                "$QUOTA_MANAGER" show "$username"
            fi
            read -n 1 -s -r -p "Press any key to return"
            ;;
        2)
            users=$(read_user_list "Username(s) (comma-separated or 'all'): ")
            for user in $(resolve_users "$users"); do
                "$QUOTA_MANAGER" reset "$user"
            done
            read -n 1 -s -r -p "Bandwidth reset completed. Press any key to return"
            ;;
        3)
            users=$(read_user_list "Username(s) to extend: ")
            if [ -z "$users" ]; then
                continue
            fi
            read -rp "Add bandwidth (GB): " extra_gb
            for user in $(resolve_users "$users"); do
                "$QUOTA_MANAGER" extend-limit "$user" "$extra_gb"
            done
            read -n 1 -s -r -p "Quota update completed. Press any key to return"
            ;;
        4)
            users=$(read_user_list "Username(s): ")
            if [ -z "$users" ]; then
                continue
            fi
            read -rp "Action (enable/disable): " action
            for user in $(resolve_users "$users"); do
                if [ "$action" = "enable" ]; then
                    "$QUOTA_MANAGER" enable "$user"
                elif [ "$action" = "disable" ]; then
                    "$QUOTA_MANAGER" disable "$user" "manual"
                fi
            done
            read -n 1 -s -r -p "Action completed. Press any key to return"
            ;;
        5)
            users=$(read_user_list "Username(s) to delete: ")
            if [ -z "$users" ]; then
                continue
            fi
            for user in $(resolve_users "$users"); do
                "$QUOTA_MANAGER" delete "$user"
            done
            read -n 1 -s -r -p "Delete completed. Press any key to return"
            ;;
        6)
            read -rp "Filter (all/active/disabled/expired): " filter_input
            case "$filter_input" in
                all|active|disabled|expired)
                    status_filter="$filter_input"
                    ;;
                *)
                    echo -e "${yellow}Invalid filter. Using current filter.${NC}"
                    sleep 1
                    ;;
            esac
            ;;
        7)
            if [ -x /usr/bin/menu ]; then
                /usr/bin/menu
            else
                menu
            fi
            exit 0
            ;;
        *)
            ;;
    esac
done
