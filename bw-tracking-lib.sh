#!/bin/bash
# =========================================
# Bandwidth Tracking Library
# Provides functions for managing per-user bandwidth tracking
# with daily/total/remaining usage in JSON format
# =========================================

# Storage directory for per-user tracking data
BW_STORAGE_DIR="/etc/myvpn/usage"

# Initialize storage directory
init_bw_storage() {
    mkdir -p "$BW_STORAGE_DIR" 2>/dev/null
    chmod 755 "$BW_STORAGE_DIR"
}

# Get current date in YYYY-MM-DD format for daily tracking
get_current_date() {
    date +%Y-%m-%d
}

# Get timestamp for last update
get_timestamp() {
    date +%s
}

# Initialize or load user bandwidth data from JSON file
# Returns JSON structure with daily_usage, total_usage, daily_limit, total_limit, last_reset, last_update
get_user_bw_data() {
    local username=$1
    local user_file="$BW_STORAGE_DIR/${username}.json"
    
    # If file doesn't exist, create default structure
    if [ ! -f "$user_file" ]; then
        local current_date=$(get_current_date)
        local timestamp=$(get_timestamp)
        cat > "$user_file" <<EOF
{
  "username": "$username",
  "daily_usage": 0,
  "total_usage": 0,
  "daily_limit": 0,
  "total_limit": 0,
  "last_reset": "$current_date",
  "last_update": $timestamp,
  "baseline_usage": 0,
  "last_stats": 0
}
EOF
    fi
    
    cat "$user_file"
}

# Update user bandwidth data with new values
# Usage: update_user_bw_data username key value
update_user_bw_data() {
    local username=$1
    local key=$2
    local value=$3
    local user_file="$BW_STORAGE_DIR/${username}.json"
    
    # Ensure file exists
    get_user_bw_data "$username" > /dev/null
    
    # Update the specific key using sed (simple JSON update)
    # For numeric values
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        sed -i "s/\"$key\": [0-9]*/\"$key\": $value/" "$user_file"
    else
        # For string values
        sed -i "s/\"$key\": \"[^\"]*\"/\"$key\": \"$value\"/" "$user_file"
    fi
    
    # Update timestamp
    local timestamp=$(get_timestamp)
    sed -i "s/\"last_update\": [0-9]*/\"last_update\": $timestamp/" "$user_file"
}

# Get specific value from user bandwidth data
# Usage: get_user_bw_value username key
get_user_bw_value() {
    local username=$1
    local key=$2
    local user_file="$BW_STORAGE_DIR/${username}.json"
    
    if [ ! -f "$user_file" ]; then
        echo "0"
        return
    fi
    
    # Extract value using grep and sed
    local value=$(grep "\"$key\"" "$user_file" | sed 's/.*: \(.*\),*/\1/' | tr -d ' "')
    echo "${value:-0}"
}

# Reset daily usage for a user
reset_daily_usage() {
    local username=$1
    local current_date=$(get_current_date)
    
    update_user_bw_data "$username" "daily_usage" 0
    update_user_bw_data "$username" "last_reset" "$current_date"
}

# Check if daily reset is needed (date changed)
check_daily_reset() {
    local username=$1
    local current_date=$(get_current_date)
    local last_reset=$(get_user_bw_value "$username" "last_reset")
    
    if [ "$last_reset" != "$current_date" ]; then
        reset_daily_usage "$username"
        return 0
    fi
    return 1
}

# Update user bandwidth usage (both daily and total)
# Usage: update_bandwidth_usage username bytes_used
update_bandwidth_usage() {
    local username=$1
    local new_bytes=$2
    
    # Check if daily reset needed
    check_daily_reset "$username"
    
    # This function should be called with the absolute current usage, not incremental
    # The get_user_bandwidth function returns the current total, we store it directly
    update_user_bw_data "$username" "daily_usage" "$new_bytes"
    update_user_bw_data "$username" "total_usage" "$new_bytes"
}

# Set user bandwidth limits
# Usage: set_user_limits username daily_limit_mb total_limit_mb
set_user_limits() {
    local username=$1
    local daily_limit_mb=$2
    local total_limit_mb=$3
    
    # Convert MB to bytes
    local daily_limit_bytes=$((daily_limit_mb * 1024 * 1024))
    local total_limit_bytes=$((total_limit_mb * 1024 * 1024))
    
    update_user_bw_data "$username" "daily_limit" "$daily_limit_bytes"
    update_user_bw_data "$username" "total_limit" "$total_limit_bytes"
}

# Get remaining bandwidth (daily and total)
# Usage: get_remaining_bandwidth username
# Returns: "daily_remaining total_remaining" in bytes
get_remaining_bandwidth() {
    local username=$1
    
    local daily_usage=$(get_user_bw_value "$username" "daily_usage")
    local total_usage=$(get_user_bw_value "$username" "total_usage")
    local daily_limit=$(get_user_bw_value "$username" "daily_limit")
    local total_limit=$(get_user_bw_value "$username" "total_limit")
    
    local daily_remaining=$((daily_limit - daily_usage))
    local total_remaining=$((total_limit - total_usage))
    
    # Ensure non-negative
    [ $daily_remaining -lt 0 ] && daily_remaining=0
    [ $total_remaining -lt 0 ] && total_remaining=0
    
    echo "$daily_remaining $total_remaining"
}

# Delete user bandwidth data
delete_user_bw_data() {
    local username=$1
    local user_file="$BW_STORAGE_DIR/${username}.json"
    
    rm -f "$user_file" 2>/dev/null
}

# Convert bytes to human-readable format
bytes_to_human() {
    local bytes=$1
    
    if [ $bytes -ge 1073741824 ]; then
        # GB
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}") GB"
    elif [ $bytes -ge 1048576 ]; then
        # MB
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}") MB"
    elif [ $bytes -ge 1024 ]; then
        # KB
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1024}") KB"
    else
        echo "$bytes B"
    fi
}

# Convert bytes to MB
bytes_to_mb() {
    local bytes=$1
    echo $((bytes / 1024 / 1024))
}

# Convert MB to bytes
mb_to_bytes() {
    local mb=$1
    echo $((mb * 1024 * 1024))
}

# Initialize storage on first load
init_bw_storage
