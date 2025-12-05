#!/bin/bash
# =========================================
# Bandwidth Usage Limit Checker
# Checks user bandwidth usage and deletes
# accounts that exceed their limit
# Edition : Stable Edition V1.0
# Author  : LamonLind
# (C) Copyright 2024
# =========================================

# // Export Color & Information
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# // Root Checking
if [ "${EUID}" -ne 0 ]; then
    echo -e "[${RED} EROR ${NC}] Please Run This Script As Root User !"
    exit 1
fi

# // Bandwidth limit file location
BW_LIMIT_FILE="/etc/xray/bw-limit.conf"
BW_USAGE_FILE="/etc/xray/bw-usage.conf"

# // Create files if they don't exist
touch "$BW_LIMIT_FILE" 2>/dev/null
touch "$BW_USAGE_FILE" 2>/dev/null

# // Xray API configuration
_APISERVER=127.0.0.1:10085
_Xray=/usr/local/bin/xray

# // Function to get user bandwidth usage from xray API
get_user_bandwidth() {
    local username=$1
    local total_bytes=0
    
    # Get bandwidth stats from xray API
    if [ -f "$_Xray" ]; then
        local stats=$($_Xray api statsquery --server=$_APISERVER 2>/dev/null)
        if [ -n "$stats" ]; then
            # Get upload bytes
            local up_bytes=$(echo "$stats" | grep -A1 "\"name\": \"user>>>$username>>>traffic>>>uplink\"" | grep "value" | grep -oP '\d+' | head -1)
            # Get download bytes  
            local down_bytes=$(echo "$stats" | grep -A1 "\"name\": \"user>>>$username>>>traffic>>>downlink\"" | grep "value" | grep -oP '\d+' | head -1)
            
            up_bytes=${up_bytes:-0}
            down_bytes=${down_bytes:-0}
            total_bytes=$((up_bytes + down_bytes))
        fi
    fi
    
    # Add stored usage from file (for persistent tracking)
    local stored_usage=$(grep "^$username " "$BW_USAGE_FILE" 2>/dev/null | awk '{print $2}')
    stored_usage=${stored_usage:-0}
    
    echo $((total_bytes + stored_usage))
}

# // Function to convert MB to bytes
mb_to_bytes() {
    local mb=$1
    echo $((mb * 1024 * 1024))
}

# // Function to convert bytes to MB
bytes_to_mb() {
    local bytes=$1
    echo $((bytes / 1024 / 1024))
}

# // Function to delete vmess user
delete_vmess_user() {
    local user=$1
    local exp=$(grep -wE "^#vmsg $user" "/etc/xray/config.json" 2>/dev/null | cut -d ' ' -f 3 | sort | uniq | head -1)
    if [ -n "$exp" ]; then
        sed -i "/^#vms $user $exp/,/^},{/d" /etc/xray/config.json
        sed -i "/^#vmsg $user $exp/,/^},{/d" /etc/xray/config.json
        rm -f /etc/xray/$user-tls.json /etc/xray/$user-none.json
        rm -f /home/vps/public_html/vmess-$user.txt
        echo -e "[${GREEN} OKEY ${NC}] VMess user $user deleted (bandwidth limit exceeded)"
    fi
}

# // Function to delete vless user
delete_vless_user() {
    local user=$1
    local exp=$(grep -wE "^#vlsg $user" "/etc/xray/config.json" 2>/dev/null | cut -d ' ' -f 3 | sort | uniq | head -1)
    if [ -n "$exp" ]; then
        sed -i "/^#vls $user $exp/,/^},{/d" /etc/xray/config.json
        sed -i "/^#vlsg $user $exp/,/^},{/d" /etc/xray/config.json
        sed -i "/^#vlsx $user $exp/,/^},{/d" /etc/xray/config.json
        rm -f /home/vps/public_html/vless-$user.txt
        echo -e "[${GREEN} OKEY ${NC}] Vless user $user deleted (bandwidth limit exceeded)"
    fi
}

# // Function to delete trojan user
delete_trojan_user() {
    local user=$1
    local exp=$(grep -wE "^#trg $user" "/etc/xray/config.json" 2>/dev/null | cut -d ' ' -f 3 | sort | uniq | head -1)
    if [ -n "$exp" ]; then
        sed -i "/^#tr $user $exp/,/^},{/d" /etc/xray/config.json
        sed -i "/^#trg $user $exp/,/^},{/d" /etc/xray/config.json
        rm -f /home/vps/public_html/trojan-$user.txt
        echo -e "[${GREEN} OKEY ${NC}] Trojan user $user deleted (bandwidth limit exceeded)"
    fi
}

# // Function to delete SSH user (non-main accounts only)
delete_ssh_user() {
    local user=$1
    # Skip main/root accounts
    local uid=$(id -u "$user" 2>/dev/null)
    if [ -n "$uid" ] && [ "$uid" -ge 1000 ]; then
        userdel "$user" 2>/dev/null
        rm -f /home/vps/public_html/ssh-$user.txt
        echo -e "[${GREEN} OKEY ${NC}] SSH user $user deleted (bandwidth limit exceeded)"
    fi
}

# // Main function to check bandwidth limits
check_bandwidth_limits() {
    local deleted_count=0
    
    # Read bandwidth limits file
    while IFS=' ' read -r username limit_mb account_type; do
        # Skip empty lines and comments
        [[ -z "$username" || "$username" =~ ^# ]] && continue
        
        # Skip if limit is 0 (unlimited)
        if [ "$limit_mb" -eq 0 ] 2>/dev/null; then
            continue
        fi
        
        # Get current bandwidth usage
        local current_usage=$(get_user_bandwidth "$username")
        local limit_bytes=$(mb_to_bytes "$limit_mb")
        
        # Check if limit exceeded
        if [ "$current_usage" -ge "$limit_bytes" ]; then
            echo -e "[${YELLOW} INFO ${NC}] User $username exceeded bandwidth limit ($(bytes_to_mb $current_usage) MB / $limit_mb MB)"
            
            # Delete user based on account type
            case "$account_type" in
                vmess)
                    delete_vmess_user "$username"
                    ;;
                vless)
                    delete_vless_user "$username"
                    ;;
                trojan)
                    delete_trojan_user "$username"
                    ;;
                ssh)
                    delete_ssh_user "$username"
                    ;;
            esac
            
            # Remove from bandwidth limit file
            sed -i "/^$username /d" "$BW_LIMIT_FILE"
            sed -i "/^$username /d" "$BW_USAGE_FILE"
            
            ((deleted_count++))
        fi
    done < "$BW_LIMIT_FILE"
    
    # Restart xray if any user was deleted
    if [ "$deleted_count" -gt 0 ]; then
        systemctl restart xray >/dev/null 2>&1
        echo -e "[${GREEN} OKEY ${NC}] Deleted $deleted_count user(s) for exceeding bandwidth limit"
    fi
}

# // Function to display bandwidth usage
display_bandwidth_usage() {
    clear
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\\E[0;41;36m                    BANDWIDTH USAGE MONITOR                    \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    printf "%-15s %-12s %-12s %-10s %-10s\n" "USERNAME" "USED (MB)" "LIMIT (MB)" "TYPE" "STATUS"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    
    while IFS=' ' read -r username limit_mb account_type; do
        [[ -z "$username" || "$username" =~ ^# ]] && continue
        
        local current_usage=$(get_user_bandwidth "$username")
        local current_mb=$(bytes_to_mb "$current_usage")
        
        local status="OK"
        local color="${GREEN}"
        
        if [ "$limit_mb" -eq 0 ] 2>/dev/null; then
            status="UNLIMITED"
        elif [ "$current_usage" -ge $(mb_to_bytes "$limit_mb") ]; then
            status="EXCEEDED"
            color="${RED}"
        elif [ "$current_usage" -ge $(mb_to_bytes $((limit_mb * 80 / 100))) ]; then
            status="WARNING"
            color="${YELLOW}"
        fi
        
        printf "%-15s %-12s %-12s %-10s ${color}%-10s${NC}\n" "$username" "$current_mb" "$limit_mb" "$account_type" "$status"
    done < "$BW_LIMIT_FILE"
    
    echo ""
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
}

# // Function to add bandwidth limit for user
add_bandwidth_limit() {
    local username=$1
    local limit_mb=$2
    local account_type=$3
    
    # Remove existing entry
    sed -i "/^$username /d" "$BW_LIMIT_FILE"
    
    # Add new entry
    echo "$username $limit_mb $account_type" >> "$BW_LIMIT_FILE"
    echo -e "[${GREEN} OKEY ${NC}] Bandwidth limit set: $username = $limit_mb MB ($account_type)"
}

# // Run mode
case "$1" in
    check)
        check_bandwidth_limits
        ;;
    show)
        display_bandwidth_usage
        read -n 1 -s -r -p "Press any key to continue"
        ;;
    add)
        if [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ]; then
            add_bandwidth_limit "$2" "$3" "$4"
        else
            echo "Usage: $0 add <username> <limit_mb> <account_type>"
        fi
        ;;
    *)
        # Default: run check
        check_bandwidth_limits
        ;;
esac
