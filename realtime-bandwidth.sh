#!/bin/bash
# =========================================
# Real-time Bandwidth Monitor Display
# Shows live bandwidth usage updates every 1 second
# Displays daily, total, and remaining bandwidth for all users
# Author: LamonLind
# =========================================

# // Export Color & Information
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export LIGHT='\033[0;37m'
export NC='\033[0m'

BIBlack='\033[1;90m'
BIRed='\033[1;91m'
BIGreen='\033[1;92m'
BIYellow='\033[1;93m'
BIBlue='\033[1;94m'
BIPurple='\033[1;95m'
BICyan='\033[1;96m'
BIWhite='\033[1;97m'
UWhite='\033[4;37m'

# // Root Checking
if [ "${EUID}" -ne 0 ]; then
    echo -e "[${RED} EROR ${NC}] Please Run This Script As Root User !"
    exit 1
fi

# // Load bandwidth tracking library for JSON-based storage
if [ -f "/usr/bin/bw-tracking-lib" ]; then
    source /usr/bin/bw-tracking-lib
fi

# // Configuration files
BW_LIMIT_FILE="/etc/xray/bw-limit.conf"
BW_USAGE_FILE="/etc/xray/bw-usage.conf"
BW_LAST_STATS_FILE="/etc/xray/bw-last-stats.conf"

# // Xray API configuration
_APISERVER=127.0.0.1:10085
_Xray=/usr/local/bin/xray

# // Warning threshold percentage
WARNING_THRESHOLD=80

# // Function to convert bytes to MB
bytes_to_mb() {
    local bytes=$1
    echo $((bytes / 1024 / 1024))
}

# // Function to convert MB to bytes
mb_to_bytes() {
    local mb=$1
    echo $((mb * 1024 * 1024))
}

# // Function to get SSH user bandwidth usage via iptables accounting
# // Tracks both upload (OUTPUT) and download (INPUT) traffic for accurate total bandwidth
get_ssh_user_bandwidth() {
    local username=$1
    local total_bytes=0
    
    # Get user UID for iptables owner matching
    local uid=$(id -u "$username" 2>/dev/null)
    if [ -z "$uid" ]; then
        echo 0
        return
    fi
    
    # Create unique chain names for this user to track both directions
    local chain_out="BW_OUT_${uid}"  # Upload/outbound traffic
    local chain_in="BW_IN_${uid}"    # Download/inbound traffic
    
    # Setup OUTPUT chain for upload tracking (outbound from VPS)
    if ! iptables -L "$chain_out" -n 2>/dev/null | grep -q "Chain"; then
        # Create custom chain for outbound traffic
        iptables -N "$chain_out" 2>/dev/null
        # Track outgoing traffic by user UID (upload)
        iptables -I OUTPUT -m owner --uid-owner "$uid" -j "$chain_out" 2>/dev/null
        # Add RETURN rule to continue processing
        iptables -A "$chain_out" -j RETURN 2>/dev/null
    fi
    
    # Setup INPUT chain for download tracking (inbound to VPS)
    if ! iptables -L "$chain_in" -n 2>/dev/null | grep -q "Chain"; then
        # Create custom chain for inbound traffic
        iptables -N "$chain_in" 2>/dev/null
        # Track established connections that were initiated by this user
        iptables -I INPUT -m conntrack --ctstate ESTABLISHED -m owner --uid-owner "$uid" -j "$chain_in" 2>/dev/null
        # Add RETURN rule to continue processing
        iptables -A "$chain_in" -j RETURN 2>/dev/null
    fi
    
    # Get upload bytes from OUTPUT chain
    local upload_bytes=$(iptables -L "$chain_out" -v -n -x 2>/dev/null | grep -v "^Chain\|^$\|pkts" | awk '{sum+=$2} END {print sum+0}')
    upload_bytes=${upload_bytes:-0}
    
    # Get download bytes from INPUT chain
    local download_bytes=$(iptables -L "$chain_in" -v -n -x 2>/dev/null | grep -v "^Chain\|^$\|pkts" | awk '{sum+=$2} END {print sum+0}')
    download_bytes=${download_bytes:-0}
    
    # Total bandwidth = upload + download
    total_bytes=$((upload_bytes + download_bytes))
    echo $total_bytes
}

# // Function to get xray user bandwidth usage from xray API
get_xray_user_bandwidth() {
    local username=$1
    local total_bytes=0
    
    # Get bandwidth stats from xray API
    if [ -f "$_Xray" ]; then
        local stats=$($_Xray api statsquery --server=$_APISERVER 2>/dev/null)
        if [ -n "$stats" ]; then
            # Flatten multi-line JSON to single line for reliable parsing
            local flat_stats=$(echo "$stats" | tr -d '\n\t')
            
            # Parse upload bytes using awk (only uplink as per requirements)
            # This approach handles both multi-line and single-line/compact JSON formats
            # We track BOTH uplink (upload) and downlink (download) for accurate total bandwidth
            local traffic=$(echo "$flat_stats" | awk -v user="$username" '
                BEGIN { up=0; down=0; }
                {
                    line = $0
                    
                    # Check if line contains multiple JSON objects (compact format)
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
                                
                                # Track both uplink (upload) and downlink (download)
                                if (name == "user>>>" user ">>>traffic>>>uplink") {
                                    up = val
                                }
                                if (name == "user>>>" user ">>>traffic>>>downlink") {
                                    down = val
                                }
                            }
                        }
                    }
                }
                END { print up " " down }
            ')
            local up_bytes=$(echo "$traffic" | awk '{print $1}')
            local down_bytes=$(echo "$traffic" | awk '{print $2}')
            
            up_bytes=${up_bytes:-0}
            down_bytes=${down_bytes:-0}
            # Track BOTH upload (uplink) and download (downlink) traffic
            # Total bandwidth = upload + download
            total_bytes=$((up_bytes + down_bytes))
        fi
    fi
    
    echo $total_bytes
}

# // Function to get user bandwidth usage based on account type
get_user_bandwidth() {
    local username=$1
    local account_type=$2
    local current_stats=0
    
    if [ "$account_type" = "ssh" ]; then
        current_stats=$(get_ssh_user_bandwidth "$username")
        # For SSH, iptables counters persist until manually reset
        echo $current_stats
        return
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

# // Function to display real-time bandwidth usage
display_realtime_bandwidth() {
    # Clear screen and show header
    clear
    
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\\E[0;41;36m                    REAL-TIME BANDWIDTH USAGE MONITOR (100ms Display)                \E[0m"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    printf "%-12s %-10s %-10s %-10s %-10s %-8s %-10s\n" "USERNAME" "DAILY(MB)" "TOTAL(MB)" "LIMIT(MB)" "REMAIN(MB)" "TYPE" "STATUS"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    
    # Check if limit file exists
    if [ ! -f "$BW_LIMIT_FILE" ] || [ ! -s "$BW_LIMIT_FILE" ]; then
        echo -e "  ${YELLOW}No users with bandwidth limits configured${NC}"
        echo ""
        echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        return
    fi
    
    # Read and display each user
    while IFS=' ' read -r username limit_mb account_type; do
        # Skip empty lines and comments
        [[ -z "$username" || "$username" =~ ^# ]] && continue
        
        # Get current usage (total bytes)
        local current_usage=$(get_user_bandwidth "$username" "$account_type")
        local current_mb=$(bytes_to_mb "$current_usage")
        
        # Try to get JSON-based tracking data for daily/remaining info
        local daily_mb=0
        local remaining_mb=0
        
        if [ -f "/usr/bin/bw-tracking-lib" ] && [ -f "/etc/myvpn/usage/${username}.json" ]; then
            # Check for daily reset
            check_daily_reset "$username"
            
            # Get daily usage
            local daily_bytes=$(get_user_bw_value "$username" "daily_usage")
            daily_mb=$(bytes_to_mb "$daily_bytes")
            
            # Calculate remaining
            if [ "$limit_mb" -gt 0 ]; then
                local limit_bytes=$(mb_to_bytes "$limit_mb")
                # Both current_usage and limit_bytes are in bytes, subtraction is safe
                local remaining_bytes=$((limit_bytes - current_usage))
                [ $remaining_bytes -lt 0 ] && remaining_bytes=0
                remaining_mb=$(bytes_to_mb "$remaining_bytes")
            else
                remaining_mb="∞"
            fi
        else
            # Fallback: use current usage as daily (backward compatibility)
            daily_mb=$current_mb
            if [ "$limit_mb" -gt 0 ]; then
                remaining_mb=$((limit_mb - current_mb))
                [ $remaining_mb -lt 0 ] && remaining_mb=0
            else
                remaining_mb="∞"
            fi
        fi
        
        # Determine status and color
        local status="OK"
        local color="${GREEN}"
        
        if [ "$limit_mb" -eq 0 ] 2>/dev/null; then
            status="UNLIMITED"
            color="${CYAN}"
        elif [ "$current_usage" -ge $(mb_to_bytes "$limit_mb") ]; then
            status="EXCEEDED"
            color="${RED}"
        elif [ "$current_usage" -ge $(mb_to_bytes $((limit_mb * WARNING_THRESHOLD / 100))) ]; then
            status="WARNING"
            color="${YELLOW}"
        fi
        
        # Display user row
        printf "%-12s %-10s %-10s %-10s %-10s %-8s ${color}%-10s${NC}\n" \
            "$username" "$daily_mb" "$current_mb" "$limit_mb" "$remaining_mb" "$account_type" "$status"
    done < "$BW_LIMIT_FILE"
    
    echo ""
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "  ${BIWhite}Press Ctrl+C to exit real-time monitoring${NC}"
    echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
}

# // Main loop - update display every 100 milliseconds (0.1 seconds)
# // Note: Background service checks at 10ms, but display updates at 100ms
# // This provides smooth viewing without screen flickering (10 updates/second)
echo -e "${GREEN}Starting Real-time Bandwidth Monitor...${NC}"
echo -e "${YELLOW}Display updating every 100ms (10 updates/second). Press Ctrl+C to stop.${NC}"
sleep 2

while true; do
    display_realtime_bandwidth
    sleep 0.1  # 100 milliseconds = 0.1 seconds - smooth display refresh
done
