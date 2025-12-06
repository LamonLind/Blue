#!/bin/bash
# =========================================
# Professional Data Usage Limit Manager
# Universal bandwidth/data limit system for:
# - SSH users
# - VLESS users (UUID based)
# - VMESS users (UUID based)
# - Trojan users
# - Shadowsocks users
# Edition : Stable Edition V2.0
# Author  : LamonLind
# (C) Copyright 2024
# =========================================

# // Export Color & Information
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export NC='\033[0m'

# // Color Variables for Menu
BIBlack='\033[1;90m'
BIRed='\033[1;91m'
BIGreen='\033[1;92m'
BIYellow='\033[1;93m'
BIBlue='\033[1;94m'
BIPurple='\033[1;95m'
BICyan='\033[1;96m'
BIWhite='\033[1;97m'
UWhite='\033[4;37m'

# // Configuration
WARNING_THRESHOLD=80  # Percentage at which to show warning (0-100)
# Note: Check interval is configured in systemd service (/etc/systemd/system/bw-limit-check.service)

# // Root Checking
if [ "${EUID}" -ne 0 ]; then
    echo -e "[${RED} EROR ${NC}] Please Run This Script As Root User !"
    exit 1
fi

# // Bandwidth limit file location (persistent storage)
BW_LIMIT_FILE="/etc/xray/bw-limit.conf"
BW_USAGE_FILE="/etc/xray/bw-usage.conf"
BW_DISABLED_FILE="/etc/xray/bw-disabled.conf"
BW_LAST_STATS_FILE="/etc/xray/bw-last-stats.conf"

# // Create files if they don't exist
touch "$BW_LIMIT_FILE" 2>/dev/null
touch "$BW_USAGE_FILE" 2>/dev/null
touch "$BW_DISABLED_FILE" 2>/dev/null
touch "$BW_LAST_STATS_FILE" 2>/dev/null

# // Xray API configuration
_APISERVER=127.0.0.1:10085
_Xray=/usr/local/bin/xray

# // Function to get user bandwidth usage from xray API (for xray protocols)
get_xray_user_bandwidth() {
    local username=$1
    local total_bytes=0
    
    # Get bandwidth stats from xray API
    if [ -f "$_Xray" ]; then
        local stats=$($_Xray api statsquery --server=$_APISERVER 2>/dev/null)
        if [ -n "$stats" ]; then
            # Parse upload and download bytes using awk
            # This approach handles both multi-line and single-line/compact JSON formats
            local traffic=$(echo "$stats" | awk -v user="$username" '
                BEGIN { up=0; down=0; current_name="" }
                {
                    line = $0
                    
                    # Check if line contains multiple JSON objects (compact format)
                    # This handles lines like: {"name":"...","value":"..."},{"name":"...","value":"..."}
                    # Use match() to avoid side effects from gsub()
                    is_compact = (match(line, /},{/) > 0) || (match(line, /"name"[[:space:]]*:/) && match(line, /"value"[[:space:]]*:/))
                    if (is_compact) {
                        # Compact JSON - split entries and process each
                        n = split($0, entries, /},{/)
                        for (i = 1; i <= n; i++) {
                            entry = entries[i]
                            
                            # Check if this entry contains our user pattern
                            pattern = "user>>>" user ">>>traffic>>>"
                            if (index(entry, pattern) > 0) {
                                # Extract name
                                temp = entry
                                gsub(/.*"name"[[:space:]]*:[[:space:]]*"/, "", temp)
                                name = temp
                                gsub(/".*/, "", name)
                                
                                # Extract value
                                temp2 = entry
                                gsub(/.*"value"[[:space:]]*:[[:space:]]*"?/, "", temp2)
                                gsub(/"?[,}\]].*/, "", temp2)
                                gsub(/[^0-9]/, "", temp2)
                                val = temp2
                                if (val == "") val = 0
                                
                                if (name == "user>>>" user ">>>traffic>>>uplink") {
                                    up = val
                                }
                                if (name == "user>>>" user ">>>traffic>>>downlink") {
                                    down = val
                                }
                            }
                        }
                    }
                    else {
                        # Multi-line JSON format - handle name and value on separate lines
                        if (match(line, /"name":/)) {
                            temp = line
                            gsub(/.*"name"[[:space:]]*:[[:space:]]*"/, "", temp)
                            gsub(/".*/, "", temp)
                            current_name = temp
                        }
                        if (match(line, /"value":/) && current_name != "") {
                            val = line
                            gsub(/.*"value"[[:space:]]*:[[:space:]]*"?/, "", val)
                            gsub(/"?[,}].*/, "", val)
                            gsub(/[^0-9]/, "", val)
                            if (val == "") val = 0
                            
                            if (current_name == "user>>>" user ">>>traffic>>>uplink") {
                                up = val
                            }
                            if (current_name == "user>>>" user ">>>traffic>>>downlink") {
                                down = val
                            }
                            current_name = ""
                        }
                    }
                }
                END { print up " " down }
            ')
            local up_bytes=$(echo "$traffic" | awk '{print $1}')
            local down_bytes=$(echo "$traffic" | awk '{print $2}')
            
            up_bytes=${up_bytes:-0}
            down_bytes=${down_bytes:-0}
            total_bytes=$((up_bytes + down_bytes))
        fi
    fi
    
    echo $total_bytes
}

# // Function to get SSH user bandwidth usage via iptables accounting
get_ssh_user_bandwidth() {
    local username=$1
    local total_bytes=0
    
    # Get user UID
    local uid=$(id -u "$username" 2>/dev/null)
    if [ -z "$uid" ]; then
        echo 0
        return
    fi
    
    # Create unique chain name for this user to track bandwidth
    local chain_name="BW_${uid}"
    
    # Check if user chain exists, if not create it with rules for both directions
    if ! iptables -L "$chain_name" -n 2>/dev/null | grep -q "Chain"; then
        # Create a custom chain for this user
        iptables -N "$chain_name" 2>/dev/null
        # Add rule to OUTPUT to track outgoing traffic by user
        iptables -I OUTPUT -m owner --uid-owner "$uid" -j "$chain_name" 2>/dev/null
        # Add RETURN rule to continue processing
        iptables -A "$chain_name" -j RETURN 2>/dev/null
    fi
    
    # Get bytes from the custom chain (tracks both directions via owner match in OUTPUT)
    # For SSH, most traffic is bidirectional so we estimate total by doubling outgoing
    local out_bytes=$(iptables -L "$chain_name" -v -n -x 2>/dev/null | grep -v "^Chain\|^$\|pkts" | awk '{sum+=$2} END {print sum+0}')
    out_bytes=${out_bytes:-0}
    
    # SSH traffic is roughly symmetric, so estimate total as output * 2 to account for both directions
    # This provides a more accurate bandwidth measurement for SSH users
    total_bytes=$((out_bytes * 2))
    echo $total_bytes
}

# // Function to get user bandwidth usage based on account type
# // This handles xray stats reset by tracking last known stats and baseline
get_user_bandwidth() {
    local username=$1
    local account_type=$2
    local current_stats=0
    
    if [ "$account_type" = "ssh" ]; then
        current_stats=$(get_ssh_user_bandwidth "$username")
    else
        current_stats=$(get_xray_user_bandwidth "$username")
    fi
    
    # Get last known xray stats (before any reset)
    local last_stats=$(grep "^$username " "$BW_LAST_STATS_FILE" 2>/dev/null | awk '{print $2}')
    last_stats=${last_stats:-0}
    
    # Get stored baseline usage (accumulated from previous xray sessions)
    local baseline=$(grep "^$username " "$BW_USAGE_FILE" 2>/dev/null | awk '{print $2}')
    baseline=${baseline:-0}
    
    # Detect xray stats reset: current stats < last known stats indicates xray was restarted
    # This includes the case when current_stats is 0 (xray just restarted)
    if [ "$last_stats" -gt 0 ] && [ "$current_stats" -lt "$last_stats" ]; then
        # Xray stats were reset, add last known stats to baseline
        baseline=$((baseline + last_stats))
        # Update baseline file
        sed -i "/^$username /d" "$BW_USAGE_FILE"
        echo "$username $baseline" >> "$BW_USAGE_FILE"
    fi
    
    # Update last known stats
    sed -i "/^$username /d" "$BW_LAST_STATS_FILE"
    echo "$username $current_stats" >> "$BW_LAST_STATS_FILE"
    
    # Total usage = baseline + current xray stats
    echo $((baseline + current_stats))
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
    local deleted=0
    
    # Get exp from any vmess-related tag (try multiple patterns)
    local exp=$(grep -E "^#(vms|vmsg|vmsx) $user " "/etc/xray/config.json" 2>/dev/null | head -1 | cut -d ' ' -f 3)
    
    if [ -n "$exp" ]; then
        # Delete all vmess-related entries for this user
        sed -i "/^#vms $user $exp/,/^},{/d" /etc/xray/config.json
        sed -i "/^#vmsg $user $exp/,/^},{/d" /etc/xray/config.json
        sed -i "/^#vmsx $user $exp/,/^},{/d" /etc/xray/config.json
        # Also delete ### entries (used for vmess quota/worryfree)
        sed -i "/^### $user $exp/,/^},{/d" /etc/xray/config.json
        deleted=1
    fi
    
    # Cleanup user files regardless of config entry
    rm -f "/etc/xray/vmess-${user}-tls.json" "/etc/xray/vmess-${user}-nontls.json"
    rm -f "/home/vps/public_html/vmess-${user}.txt"
    
    if [ "$deleted" -eq 1 ]; then
        echo -e "[${GREEN} OKEY ${NC}] VMess user $user deleted (bandwidth limit exceeded)"
        return 0
    else
        echo -e "[${YELLOW} WARN ${NC}] VMess user $user not found in config"
        return 1
    fi
}

# // Function to delete vless user
delete_vless_user() {
    local user=$1
    local deleted=0
    
    # Get exp from any vless-related tag (try multiple patterns)
    local exp=$(grep -E "^#(vls|vlsg|vlsx) $user " "/etc/xray/config.json" 2>/dev/null | head -1 | cut -d ' ' -f 3)
    
    if [ -n "$exp" ]; then
        # Delete all vless-related entries for this user
        sed -i "/^#vls $user $exp/,/^},{/d" /etc/xray/config.json
        sed -i "/^#vlsg $user $exp/,/^},{/d" /etc/xray/config.json
        sed -i "/^#vlsx $user $exp/,/^},{/d" /etc/xray/config.json
        deleted=1
    fi
    
    # Cleanup user files regardless of config entry
    rm -f "/home/vps/public_html/vless-${user}.txt"
    
    if [ "$deleted" -eq 1 ]; then
        echo -e "[${GREEN} OKEY ${NC}] Vless user $user deleted (bandwidth limit exceeded)"
        return 0
    else
        echo -e "[${YELLOW} WARN ${NC}] Vless user $user not found in config"
        return 1
    fi
}

# // Function to delete trojan user
delete_trojan_user() {
    local user=$1
    local deleted=0
    
    # Get exp from any trojan-related tag (try multiple patterns)
    local exp=$(grep -E "^#(tr|trg) $user " "/etc/xray/config.json" 2>/dev/null | head -1 | cut -d ' ' -f 3)
    
    if [ -n "$exp" ]; then
        # Delete all trojan-related entries for this user
        sed -i "/^#tr $user $exp/,/^},{/d" /etc/xray/config.json
        sed -i "/^#trg $user $exp/,/^},{/d" /etc/xray/config.json
        deleted=1
    fi
    
    # Cleanup user files regardless of config entry
    rm -f "/home/vps/public_html/trojan-${user}.txt"
    
    if [ "$deleted" -eq 1 ]; then
        echo -e "[${GREEN} OKEY ${NC}] Trojan user $user deleted (bandwidth limit exceeded)"
        return 0
    else
        echo -e "[${YELLOW} WARN ${NC}] Trojan user $user not found in config"
        return 1
    fi
}

# // Function to delete shadowsocks user
delete_ssws_user() {
    local user=$1
    local deleted=0
    
    # Get exp from any shadowsocks-related tag (try multiple patterns)
    local exp=$(grep -E "^#(ssw|sswg) $user " "/etc/xray/config.json" 2>/dev/null | head -1 | cut -d ' ' -f 3)
    
    if [ -n "$exp" ]; then
        # Delete all shadowsocks-related entries for this user
        sed -i "/^#ssw $user $exp/,/^},{/d" /etc/xray/config.json
        sed -i "/^#sswg $user $exp/,/^},{/d" /etc/xray/config.json
        deleted=1
    fi
    
    # Cleanup user files regardless of config entry
    rm -f "/home/vps/public_html/sodosokws-${user}.txt"
    rm -f "/home/vps/public_html/sodosokgrpc-${user}.txt"
    
    if [ "$deleted" -eq 1 ]; then
        echo -e "[${GREEN} OKEY ${NC}] Shadowsocks user $user deleted (bandwidth limit exceeded)"
        return 0
    else
        echo -e "[${YELLOW} WARN ${NC}] Shadowsocks user $user not found in config"
        return 1
    fi
}

# // Function to cleanup SSH user iptables rules
cleanup_ssh_iptables() {
    local uid=$1
    local chain_name="BW_${uid}"
    
    # Remove reference from OUTPUT chain
    iptables -D OUTPUT -m owner --uid-owner "$uid" -j "$chain_name" 2>/dev/null
    # Flush and delete the custom chain
    iptables -F "$chain_name" 2>/dev/null
    iptables -X "$chain_name" 2>/dev/null
}

# // Function to delete SSH user (non-main accounts only)
delete_ssh_user() {
    local user=$1
    # Check if user exists and get UID using getent (consistent with menu-ssh.sh)
    local passwd_entry=$(getent passwd "$user" 2>/dev/null)
    if [ -n "$passwd_entry" ]; then
        # Get UID from passwd entry to ensure we don't delete system users
        local uid_min=$(grep "^UID_MIN" /etc/login.defs 2>/dev/null | awk '{print $2}')
        uid_min=${uid_min:-1000}
        local uid=$(echo "$passwd_entry" | cut -d: -f3)
        if [ -n "$uid" ] && [ "$uid" -ge "$uid_min" ]; then
            # Cleanup iptables rules for this user before deletion
            cleanup_ssh_iptables "$uid"
            userdel "$user" > /dev/null 2>&1
            rm -f /home/vps/public_html/ssh-"$user".txt
            echo -e "[${GREEN} OKEY ${NC}] SSH user $user deleted (bandwidth limit exceeded)"
            return 0
        fi
    fi
    echo -e "[${YELLOW} WARN ${NC}] SSH user $user not found or is a system user"
    return 1
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
        
        # Get current bandwidth usage (includes baseline + current xray stats)
        # Note: get_user_bandwidth handles xray stats reset detection internally
        local current_usage=$(get_user_bandwidth "$username" "$account_type")
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
                ssws)
                    delete_ssws_user "$username"
                    ;;
                ssh)
                    delete_ssh_user "$username"
                    ;;
            esac
            
            # Remove from bandwidth limit file and tracking files
            sed -i "/^$username /d" "$BW_LIMIT_FILE"
            sed -i "/^$username /d" "$BW_USAGE_FILE"
            sed -i "/^$username /d" "$BW_LAST_STATS_FILE"
            
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
        
        local current_usage=$(get_user_bandwidth "$username" "$account_type")
        local current_mb=$(bytes_to_mb "$current_usage")
        
        local status="OK"
        local color="${GREEN}"
        
        if [ "$limit_mb" -eq 0 ] 2>/dev/null; then
            status="UNLIMITED"
        elif [ "$current_usage" -ge $(mb_to_bytes "$limit_mb") ]; then
            status="EXCEEDED"
            color="${RED}"
        elif [ "$current_usage" -ge $(mb_to_bytes $((limit_mb * WARNING_THRESHOLD / 100))) ]; then
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

# // Function to save current usage to persistent storage
# // This updates the stored baseline when xray stats are higher than stored value
save_usage_to_file() {
    local username=$1
    local account_type=$2
    local current_xray_usage=0
    
    if [ "$account_type" = "ssh" ]; then
        current_xray_usage=$(get_ssh_user_bandwidth "$username")
    else
        current_xray_usage=$(get_xray_user_bandwidth "$username")
    fi
    
    # Read stored usage
    local stored_usage=$(grep "^$username " "$BW_USAGE_FILE" 2>/dev/null | awk '{print $2}')
    stored_usage=${stored_usage:-0}
    
    # Calculate total usage (stored baseline + current xray stats)
    local total=$((stored_usage + current_xray_usage))
    
    # Only update if we have xray stats (to avoid resetting on API failures)
    if [ "$current_xray_usage" -gt 0 ]; then
        sed -i "/^$username /d" "$BW_USAGE_FILE"
        echo "$username $total" >> "$BW_USAGE_FILE"
    fi
}

# // Function to reset user usage (renew)
reset_user_usage() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "[${RED} EROR ${NC}] Username required!"
        return 1
    fi
    
    # Check if user has a limit set
    if ! grep -q "^$username " "$BW_LIMIT_FILE" 2>/dev/null; then
        echo -e "[${YELLOW} WARN ${NC}] User $username not found in bandwidth limit list"
        return 1
    fi
    
    # Get account type
    local account_type=$(grep "^$username " "$BW_LIMIT_FILE" | awk '{print $3}')
    
    # Remove from usage file and last stats file
    sed -i "/^$username /d" "$BW_USAGE_FILE"
    sed -i "/^$username /d" "$BW_LAST_STATS_FILE"
    
    # Reset iptables counters for SSH users
    if [ "$account_type" = "ssh" ]; then
        local uid=$(id -u "$username" 2>/dev/null)
        if [ -n "$uid" ]; then
            local chain_name="BW_${uid}"
            iptables -Z "$chain_name" 2>/dev/null
        fi
    fi
    
    echo -e "[${GREEN} OKEY ${NC}] Usage reset for user: $username"
}

# // Function to reset all users usage
reset_all_usage() {
    echo -e "[${YELLOW} INFO ${NC}] Resetting usage for all users..."
    
    while IFS=' ' read -r username limit_mb account_type; do
        [[ -z "$username" || "$username" =~ ^# ]] && continue
        reset_user_usage "$username"
    done < "$BW_LIMIT_FILE"
    
    # Clear usage and last stats files
    > "$BW_USAGE_FILE"
    > "$BW_LAST_STATS_FILE"
    
    echo -e "[${GREEN} OKEY ${NC}] All user usage has been reset"
}

# // Function to disable a user manually
disable_user() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "[${RED} EROR ${NC}] Username required!"
        return 1
    fi
    
    # Get account type from limit file
    local account_type=$(grep "^$username " "$BW_LIMIT_FILE" 2>/dev/null | awk '{print $3}')
    
    if [ -z "$account_type" ]; then
        # Try to detect account type
        if getent passwd "$username" >/dev/null 2>&1; then
            account_type="ssh"
        elif grep -qE "^#(vms|vmsg) $username " /etc/xray/config.json 2>/dev/null; then
            account_type="vmess"
        elif grep -qE "^#(vls|vlsg) $username " /etc/xray/config.json 2>/dev/null; then
            account_type="vless"
        elif grep -qE "^#(tr|trg) $username " /etc/xray/config.json 2>/dev/null; then
            account_type="trojan"
        elif grep -qE "^#(ssw|sswg) $username " /etc/xray/config.json 2>/dev/null; then
            account_type="ssws"
        else
            echo -e "[${RED} EROR ${NC}] Cannot detect account type for $username"
            return 1
        fi
    fi
    
    case "$account_type" in
        ssh)
            passwd -l "$username" >/dev/null 2>&1
            echo -e "[${GREEN} OKEY ${NC}] SSH user $username has been locked"
            ;;
        vmess|vless|trojan|ssws)
            # Add to disabled list
            if ! grep -q "^$username " "$BW_DISABLED_FILE"; then
                echo "$username $account_type $(date +%Y-%m-%d)" >> "$BW_DISABLED_FILE"
            fi
            echo -e "[${GREEN} OKEY ${NC}] Xray user $username has been disabled"
            ;;
    esac
    return 0
}

# // Function to enable a user
enable_user() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "[${RED} EROR ${NC}] Username required!"
        return 1
    fi
    
    # Get account type
    local account_type=$(grep "^$username " "$BW_LIMIT_FILE" 2>/dev/null | awk '{print $3}')
    
    if [ -z "$account_type" ]; then
        account_type=$(grep "^$username " "$BW_DISABLED_FILE" 2>/dev/null | awk '{print $2}')
    fi
    
    if [ -z "$account_type" ]; then
        if getent passwd "$username" >/dev/null 2>&1; then
            account_type="ssh"
        fi
    fi
    
    case "$account_type" in
        ssh)
            passwd -u "$username" >/dev/null 2>&1
            echo -e "[${GREEN} OKEY ${NC}] SSH user $username has been unlocked"
            ;;
        vmess|vless|trojan|ssws)
            # Remove from disabled list
            sed -i "/^$username /d" "$BW_DISABLED_FILE"
            echo -e "[${GREEN} OKEY ${NC}] Xray user $username has been enabled"
            ;;
        *)
            echo -e "[${YELLOW} WARN ${NC}] Cannot determine account type for $username"
            return 1
            ;;
    esac
    return 0
}

# // Function to set/update user limit
set_user_limit() {
    local username=$1
    local limit_mb=$2
    
    if [ -z "$username" ] || [ -z "$limit_mb" ]; then
        echo -e "[${RED} EROR ${NC}] Username and limit required!"
        return 1
    fi
    
    # Get existing account type or detect it
    local account_type=$(grep "^$username " "$BW_LIMIT_FILE" 2>/dev/null | awk '{print $3}')
    
    if [ -z "$account_type" ]; then
        # Try to detect account type
        if getent passwd "$username" >/dev/null 2>&1; then
            account_type="ssh"
        elif grep -qE "^#(vms|vmsg) $username " /etc/xray/config.json 2>/dev/null; then
            account_type="vmess"
        elif grep -qE "^#(vls|vlsg) $username " /etc/xray/config.json 2>/dev/null; then
            account_type="vless"
        elif grep -qE "^#(tr|trg) $username " /etc/xray/config.json 2>/dev/null; then
            account_type="trojan"
        elif grep -qE "^#(ssw|sswg) $username " /etc/xray/config.json 2>/dev/null; then
            account_type="ssws"
        else
            echo -e "[${RED} EROR ${NC}] Cannot detect account type for $username"
            return 1
        fi
    fi
    
    add_bandwidth_limit "$username" "$limit_mb" "$account_type"
}

# // Function to remove user limit
remove_user_limit() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "[${RED} EROR ${NC}] Username required!"
        return 1
    fi
    
    sed -i "/^$username /d" "$BW_LIMIT_FILE"
    sed -i "/^$username /d" "$BW_USAGE_FILE"
    sed -i "/^$username /d" "$BW_LAST_STATS_FILE"
    echo -e "[${GREEN} OKEY ${NC}] Limit removed for user: $username"
}

# // Function to check single user usage
check_user_usage() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "[${RED} EROR ${NC}] Username required!"
        return 1
    fi
    
    local entry=$(grep "^$username " "$BW_LIMIT_FILE" 2>/dev/null)
    
    if [ -z "$entry" ]; then
        echo -e "[${YELLOW} WARN ${NC}] User $username not found in bandwidth limit list"
        return 1
    fi
    
    local limit_mb=$(echo "$entry" | awk '{print $2}')
    local account_type=$(echo "$entry" | awk '{print $3}')
    
    local current_usage=$(get_user_bandwidth "$username" "$account_type")
    local current_mb=$(bytes_to_mb "$current_usage")
    local limit_bytes=$(mb_to_bytes "$limit_mb")
    
    local status="OK"
    local color="${GREEN}"
    local percentage=0
    
    if [ "$limit_mb" -eq 0 ] 2>/dev/null; then
        status="UNLIMITED"
    else
        percentage=$((current_usage * 100 / limit_bytes))
        if [ "$current_usage" -ge "$limit_bytes" ]; then
            status="EXCEEDED"
            color="${RED}"
        elif [ "$percentage" -ge "$WARNING_THRESHOLD" ]; then
            status="WARNING"
            color="${YELLOW}"
        fi
    fi
    
    clear
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\\E[0;41;36m       USER USAGE DETAILS         \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e ""
    echo -e " Username     : ${BIWhite}$username${NC}"
    echo -e " Account Type : ${BIWhite}$account_type${NC}"
    echo -e " Used         : ${BIWhite}$current_mb MB${NC}"
    echo -e " Limit        : ${BIWhite}$limit_mb MB${NC}"
    echo -e " Percentage   : ${color}$percentage%${NC}"
    echo -e " Status       : ${color}$status${NC}"
    echo -e ""
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
}

# // Function to list all users with limits
list_all_users() {
    clear
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\\E[0;41;36m                         ALL USERS WITH DATA LIMITS                        \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    printf "%-4s %-15s %-10s %-12s %-10s %-8s %-10s\n" "NO" "USERNAME" "USED(MB)" "LIMIT(MB)" "TYPE" "PERCENT" "STATUS"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    
    local count=0
    while IFS=' ' read -r username limit_mb account_type; do
        [[ -z "$username" || "$username" =~ ^# ]] && continue
        
        ((count++))
        
        local current_usage=$(get_user_bandwidth "$username" "$account_type")
        local current_mb=$(bytes_to_mb "$current_usage")
        
        local status="OK"
        local color="${GREEN}"
        local percentage=0
        
        if [ "$limit_mb" -eq 0 ] 2>/dev/null; then
            status="UNLIM"
            percentage=0
        else
            local limit_bytes=$(mb_to_bytes "$limit_mb")
            if [ "$limit_bytes" -gt 0 ]; then
                percentage=$((current_usage * 100 / limit_bytes))
            fi
            if [ "$current_usage" -ge "$limit_bytes" ]; then
                status="EXCEED"
                color="${RED}"
            elif [ "$percentage" -ge "$WARNING_THRESHOLD" ]; then
                status="WARN"
                color="${YELLOW}"
            fi
        fi
        
        printf "%-4s %-15s %-10s %-12s %-10s %-8s ${color}%-10s${NC}\n" "$count" "$username" "$current_mb" "$limit_mb" "$account_type" "${percentage}%" "$status"
    done < "$BW_LIMIT_FILE"
    
    if [ "$count" -eq 0 ]; then
        echo -e "  ${YELLOW}No users with data limits found${NC}"
    fi
    
    echo ""
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "  Total Users: ${BIWhite}$count${NC}"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
}

# // Interactive menu for data limit management
data_limit_menu() {
    clear
    echo -e "${BICyan} ┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "       ${BIWhite}${UWhite}DATA USAGE LIMIT MENU${NC}"
    echo -e ""
    echo -e "     ${BICyan}[${BIWhite}1${BICyan}] Show All Users + Usage + Limits"
    echo -e "     ${BICyan}[${BIWhite}2${BICyan}] Check Single User Usage"
    echo -e "     ${BICyan}[${BIWhite}3${BICyan}] Set User Data Limit"
    echo -e "     ${BICyan}[${BIWhite}4${BICyan}] Remove User Limit"
    echo -e "     ${BICyan}[${BIWhite}5${BICyan}] Reset User Usage (Renew)"
    echo -e "     ${BICyan}[${BIWhite}6${BICyan}] Reset All Users Usage"
    echo -e "     ${BICyan}[${BIWhite}7${BICyan}] Disable User"
    echo -e "     ${BICyan}[${BIWhite}8${BICyan}] Enable User"
    echo -e " ${BICyan}└─────────────────────────────────────────────────────┘${NC}"
    echo -e "     ${BIYellow}Press x or [ Ctrl+C ] • To-${BIWhite}Exit${NC}"
    echo ""
    read -p " Select menu : " opt
    echo -e ""
    
    case $opt in
        1)
            list_all_users
            echo ""
            read -n 1 -s -r -p "Press any key to continue"
            data_limit_menu
            ;;
        2)
            echo ""
            read -p "Enter username: " uname
            check_user_usage "$uname"
            echo ""
            read -n 1 -s -r -p "Press any key to continue"
            data_limit_menu
            ;;
        3)
            echo ""
            read -p "Enter username: " uname
            read -p "Enter limit in MB (0 for unlimited): " limit
            set_user_limit "$uname" "$limit"
            echo ""
            read -n 1 -s -r -p "Press any key to continue"
            data_limit_menu
            ;;
        4)
            echo ""
            read -p "Enter username: " uname
            remove_user_limit "$uname"
            echo ""
            read -n 1 -s -r -p "Press any key to continue"
            data_limit_menu
            ;;
        5)
            echo ""
            read -p "Enter username to reset: " uname
            reset_user_usage "$uname"
            echo ""
            read -n 1 -s -r -p "Press any key to continue"
            data_limit_menu
            ;;
        6)
            echo ""
            read -p "Are you sure you want to reset ALL users? (y/n): " confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                reset_all_usage
            else
                echo -e "[${YELLOW} INFO ${NC}] Operation cancelled"
            fi
            echo ""
            read -n 1 -s -r -p "Press any key to continue"
            data_limit_menu
            ;;
        7)
            echo ""
            read -p "Enter username to disable: " uname
            disable_user "$uname"
            echo ""
            read -n 1 -s -r -p "Press any key to continue"
            data_limit_menu
            ;;
        8)
            echo ""
            read -p "Enter username to enable: " uname
            enable_user "$uname"
            echo ""
            read -n 1 -s -r -p "Press any key to continue"
            data_limit_menu
            ;;
        x|X)
            # Exit to main menu (menu command is available when script is installed)
            if command -v menu &>/dev/null; then
                menu
            else
                exit 0
            fi
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            sleep 1
            data_limit_menu
            ;;
    esac
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
    reset)
        if [ -n "$2" ]; then
            reset_user_usage "$2"
        else
            echo "Usage: $0 reset <username>"
        fi
        ;;
    reset-all)
        reset_all_usage
        ;;
    set)
        if [ -n "$2" ] && [ -n "$3" ]; then
            set_user_limit "$2" "$3"
        else
            echo "Usage: $0 set <username> <limit_mb>"
        fi
        ;;
    remove)
        if [ -n "$2" ]; then
            remove_user_limit "$2"
        else
            echo "Usage: $0 remove <username>"
        fi
        ;;
    disable)
        if [ -n "$2" ]; then
            disable_user "$2"
        else
            echo "Usage: $0 disable <username>"
        fi
        ;;
    enable)
        if [ -n "$2" ]; then
            enable_user "$2"
        else
            echo "Usage: $0 enable <username>"
        fi
        ;;
    usage)
        if [ -n "$2" ]; then
            check_user_usage "$2"
        else
            echo "Usage: $0 usage <username>"
        fi
        ;;
    list)
        list_all_users
        ;;
    menu)
        data_limit_menu
        ;;
    *)
        # Default: run check
        check_bandwidth_limits
        ;;
esac
