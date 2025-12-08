#!/bin/bash
# =========================================
# Xray Bandwidth/Data Limit Manager
# Implements 3x-ui style per-client bandwidth limiting
# =========================================
# Version: 1.0.0
# Based on: https://github.com/MHSanaei/3x-ui
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

# Configuration
XRAY_CONFIG="/etc/xray/config.json"
XRAY_API="127.0.0.1:10085"
CLIENT_LIMITS_DB="/etc/xray/client-limits.db"
LOG_FILE="/var/log/xray-bandwidth.log"

# Root check
if [ "${EUID}" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# =========================================
# UTILITY FUNCTIONS
# =========================================

log_msg() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    if [ "$LOG_LEVEL" != "QUIET" ]; then
        case "$level" in
            ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
            WARN)  echo -e "${YELLOW}[WARN]${NC} $message" ;;
            INFO)  echo -e "${GREEN}[INFO]${NC} $message" ;;
            *)     echo -e "[${level}] $message" ;;
        esac
    fi
}

bytes_to_gb() {
    echo "scale=2; $1 / 1024 / 1024 / 1024" | bc
}

gb_to_bytes() {
    echo "scale=0; $1 * 1024 * 1024 * 1024" | bc
}

bytes_to_mb() {
    echo $(( $1 / 1024 / 1024 ))
}

mb_to_bytes() {
    echo $(( $1 * 1024 * 1024 ))
}

# Convert limit with unit to bytes
# Supports: 100MB, 10GB, 1000M, 5G
limit_to_bytes() {
    local limit=$1
    
    # Extract number and unit
    local number=$(echo "$limit" | grep -oP '^\d+(\.\d+)?')
    local unit=$(echo "$limit" | grep -oP '[A-Za-z]+$' | tr '[:lower:]' '[:upper:]')
    
    # If no unit specified, assume MB for backward compatibility
    if [ -z "$unit" ]; then
        unit="MB"
    fi
    
    # Convert based on unit
    case "$unit" in
        GB|G)
            gb_to_bytes "$number"
            ;;
        MB|M)
            mb_to_bytes "$number"
            ;;
        *)
            echo "0"
            return 1
            ;;
    esac
}

# Format bytes to human readable with appropriate unit
bytes_to_human() {
    local bytes=$1
    
    if [ "$bytes" -ge 1073741824 ]; then
        # >= 1GB, show in GB
        echo "$(bytes_to_gb $bytes)GB"
    else
        # < 1GB, show in MB
        echo "$(bytes_to_mb $bytes)MB"
    fi
}

# =========================================
# XRAY API FUNCTIONS
# =========================================

get_client_stats() {
    local email=$1
    local protocol=$2
    
    # Query Xray stats API for client traffic
    local stats_query=$(cat <<EOF
{
    "command": "QueryStats",
    "pattern": "user>>>$email>>>"
}
EOF
)
    
    # Use xray API command (log errors for debugging)
    local result=$(/usr/local/bin/xray api statsquery --server="$XRAY_API" <<< "$stats_query" 2>> "$LOG_FILE")
    
    # Parse uplink and downlink
    local uplink=$(echo "$result" | grep -oP '(?<="value":)\d+' | head -1)
    local downlink=$(echo "$result" | grep -oP '(?<="value":)\d+' | tail -1)
    
    uplink=${uplink:-0}
    downlink=${downlink:-0}
    
    local total=$((uplink + downlink))
    echo "$total"
}

disable_client_in_config() {
    local email=$1
    local protocol=$2
    
    log_msg "INFO" "Disabling client $email in Xray config"
    
    # Create backup
    cp "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.$(date +%s)"
    
    # Use jq to set enable=false for the client
    # This is protocol-specific, so we need to handle each protocol
    case "$protocol" in
        vmess|vless|trojan)
            # For most protocols, clients are in settings.clients array
            jq --arg email "$email" '
                .inbounds[] |= (
                    if .protocol == "vmess" or .protocol == "vless" or .protocol == "trojan" then
                        .settings.clients |= map(
                            if .email == $email then
                                .enable = false
                            else
                                .
                            end
                        )
                    else
                        .
                    end
                )
            ' "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp" && mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
            ;;
        *)
            log_msg "WARN" "Protocol $protocol not supported for client disabling"
            return 1
            ;;
    esac
    
    # Reload Xray
    systemctl reload xray 2>/dev/null || systemctl restart xray
    
    log_msg "INFO" "Client $email disabled and Xray reloaded"
}

enable_client_in_config() {
    local email=$1
    local protocol=$2
    
    log_msg "INFO" "Enabling client $email in Xray config"
    
    # Create backup
    cp "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.$(date +%s)"
    
    case "$protocol" in
        vmess|vless|trojan)
            jq --arg email "$email" '
                .inbounds[] |= (
                    if .protocol == "vmess" or .protocol == "vless" or .protocol == "trojan" then
                        .settings.clients |= map(
                            if .email == $email then
                                .enable = true
                            else
                                .
                            end
                        )
                    else
                        .
                    end
                )
            ' "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp" && mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
            ;;
    esac
    
    # Reload Xray
    systemctl reload xray 2>/dev/null || systemctl restart xray
    
    log_msg "INFO" "Client $email enabled and Xray reloaded"
}

# =========================================
# DATABASE OPERATIONS
# =========================================

init_database() {
    touch "$CLIENT_LIMITS_DB"
    # Database format: email|protocol|limit_bytes|baseline_bytes|state|last_check
    # States: UNLIMITED, LIMITED (disabled due to quota exceeded)
    # limit_bytes: 0 = unlimited, or total bytes allowed
}

add_client_limit() {
    local email=$1
    local protocol=$2
    local limit=${3:-0}  # 0 = unlimited, or "100MB", "10GB", etc.
    
    # Convert limit to bytes
    local limit_bytes=0
    if [ "$limit" != "0" ] && [ -n "$limit" ]; then
        limit_bytes=$(limit_to_bytes "$limit")
        if [ $? -ne 0 ] || [ "$limit_bytes" = "0" ]; then
            echo -e "${RED}Error: Invalid limit format. Use: 100MB, 10GB, 500M, 5G${NC}"
            return 1
        fi
    fi
    
    # Remove existing entry
    sed -i "/^${email}|/d" "$CLIENT_LIMITS_DB" 2>/dev/null
    
    # Add new entry
    local timestamp=$(date +%s)
    echo "${email}|${protocol}|${limit_bytes}|0|UNLIMITED|${timestamp}" >> "$CLIENT_LIMITS_DB"
    
    local limit_display
    if [ "$limit_bytes" = "0" ]; then
        limit_display="UNLIMITED"
    else
        limit_display=$(bytes_to_human $limit_bytes)
    fi
    
    log_msg "INFO" "Added bandwidth limit for $email ($protocol): ${limit_display}"
}

remove_client_limit() {
    local email=$1
    
    sed -i "/^${email}|/d" "$CLIENT_LIMITS_DB" 2>/dev/null
    log_msg "INFO" "Removed bandwidth limit for $email"
}

get_client_limit_bytes() {
    local email=$1
    local limit=$(grep "^${email}|" "$CLIENT_LIMITS_DB" 2>/dev/null | cut -d'|' -f3)
    echo "${limit:-0}"
}

get_client_state() {
    local email=$1
    grep "^${email}|" "$CLIENT_LIMITS_DB" 2>/dev/null | cut -d'|' -f5
}

update_client_state() {
    local email=$1
    local new_state=$2
    local timestamp=$(date +%s)
    
    # Read current record
    local record=$(grep "^${email}|" "$CLIENT_LIMITS_DB" 2>/dev/null)
    if [ -z "$record" ]; then
        return 1
    fi
    
    local protocol=$(echo "$record" | cut -d'|' -f2)
    local limit_bytes=$(echo "$record" | cut -d'|' -f3)
    local baseline=$(echo "$record" | cut -d'|' -f4)
    
    # Remove old record
    sed -i "/^${email}|/d" "$CLIENT_LIMITS_DB"
    
    # Add updated record
    echo "${email}|${protocol}|${limit_bytes}|${baseline}|${new_state}|${timestamp}" >> "$CLIENT_LIMITS_DB"
}

# =========================================
# MONITORING AND ENFORCEMENT
# =========================================

check_client_limits() {
    [ ! -f "$CLIENT_LIMITS_DB" ] && return
    
    while IFS='|' read -r email protocol limit_bytes baseline state last_check; do
        [ -z "$email" ] && continue
        [ "$limit_bytes" = "0" ] && continue  # 0 means unlimited
        
        # Get current traffic from Xray API
        local current_bytes=$(get_client_stats "$email" "$protocol")
        local total_usage=$((baseline + current_bytes))
        
        # Format for display
        local usage_display=$(bytes_to_human $total_usage)
        local limit_display=$(bytes_to_human $limit_bytes)
        
        # Check if limit exceeded (using bash integer comparison)
        if [ "$total_usage" -ge "$limit_bytes" ] && [ "$state" = "UNLIMITED" ]; then
            log_msg "WARN" "Client $email exceeded quota: ${usage_display} / ${limit_display}"
            
            # Disable client
            disable_client_in_config "$email" "$protocol"
            
            # Update state
            update_client_state "$email" "LIMITED"
            
            echo -e "${RED}[LIMIT EXCEEDED]${NC} Client $email disabled (${usage_display} / ${limit_display})"
        fi
        
    done < "$CLIENT_LIMITS_DB"
}

reset_client_usage() {
    local email=$1
    
    # Check if client exists in database
    if ! grep -q "^${email}|" "$CLIENT_LIMITS_DB" 2>/dev/null; then
        echo -e "${RED}Error: Client $email not found in limits database${NC}"
        return 1
    fi
    
    # Read current record
    local record=$(grep "^${email}|" "$CLIENT_LIMITS_DB" 2>/dev/null)
    local protocol=$(echo "$record" | cut -d'|' -f2)
    local limit_bytes=$(echo "$record" | cut -d'|' -f3)
    
    # Re-enable client
    enable_client_in_config "$email" "$protocol"
    
    # Reset in database (set baseline to 0, state to UNLIMITED)
    local timestamp=$(date +%s)
    sed -i "/^${email}|/d" "$CLIENT_LIMITS_DB"
    echo "${email}|${protocol}|${limit_bytes}|0|UNLIMITED|${timestamp}" >> "$CLIENT_LIMITS_DB"
    
    local limit_display
    if [ "$limit_bytes" = "0" ]; then
        limit_display="UNLIMITED"
    else
        limit_display=$(bytes_to_human $limit_bytes)
    fi
    
    log_msg "INFO" "Reset usage for client $email"
    echo -e "${GREEN}✓${NC} Usage reset for $email (quota: ${limit_display})"
}

# =========================================
# MONITORING DAEMON
# =========================================

start_monitoring_daemon() {
    log_msg "INFO" "Starting Xray bandwidth monitoring daemon"
    
    while true; do
        check_client_limits
        sleep 30  # Check every 30 seconds
    done
}

# =========================================
# MENU FUNCTIONS
# =========================================

show_status() {
    echo -e "\n${BLUE}=== Xray Client Bandwidth Status ===${NC}\n"
    
    if [ ! -s "$CLIENT_LIMITS_DB" ]; then
        echo -e "${YELLOW}No clients being monitored${NC}"
        return
    fi
    
    printf "%-25s %-12s %-15s %-15s %-15s\n" "EMAIL" "PROTOCOL" "LIMIT" "USAGE" "STATE"
    printf "%-25s %-12s %-15s %-15s %-15s\n" "-----" "--------" "-----" "-----" "-----"
    
    while IFS='|' read -r email protocol limit_bytes baseline state last_check; do
        [ -z "$email" ] && continue
        
        local current_bytes=$(get_client_stats "$email" "$protocol")
        local total_usage=$((baseline + current_bytes))
        
        # Color code state
        local state_color=""
        case "$state" in
            UNLIMITED) state_color="${GREEN}" ;;
            LIMITED)   state_color="${RED}" ;;
            *)         state_color="${NC}" ;;
        esac
        
        local limit_display
        local usage_display=$(bytes_to_human $total_usage)
        
        if [ "$limit_bytes" = "0" ]; then
            limit_display="UNLIMITED"
        else
            limit_display=$(bytes_to_human $limit_bytes)
        fi
        
        printf "%-25s %-12s %-15s %-15s ${state_color}%-15s${NC}\n" \
            "$email" \
            "$protocol" \
            "$limit_display" \
            "$usage_display" \
            "$state"
            
    done < "$CLIENT_LIMITS_DB"
    
    echo ""
}

show_help() {
    cat <<EOF
${BLUE}Xray Bandwidth Limiter${NC}
3x-ui style per-client bandwidth/data limiting for Xray

${YELLOW}Usage:${NC}
    $0 <command> [arguments]

${YELLOW}Commands:${NC}
    ${GREEN}add-limit <email> <protocol> <limit>${NC}
        Add bandwidth limit for client
        Limit formats: 100MB, 500M, 10GB, 5G, 0 (unlimited)
        Protocols: vmess, vless, trojan, shadowsocks

    ${GREEN}remove-limit <email>${NC}
        Remove bandwidth limit for client

    ${GREEN}reset-usage <email>${NC}
        Reset client usage to 0 and re-enable

    ${GREEN}status${NC}
        Show all clients with usage and limit status

    ${GREEN}check${NC}
        Manually check and enforce limits now

    ${GREEN}monitor${NC}
        Start monitoring daemon (background)

${YELLOW}Examples:${NC}
    $0 add-limit user@example.com vmess 100MB    # 100 megabytes
    $0 add-limit user@example.com vless 500M     # 500 megabytes
    $0 add-limit premium@example.com trojan 10GB # 10 gigabytes
    $0 add-limit unlimited@example.com vmess 0   # unlimited
    $0 status
    $0 reset-usage user@example.com
    $0 check

EOF
}

# =========================================
# MAIN
# =========================================

# Ensure jq is installed
if ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}Installing jq...${NC}"
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y jq bc >/dev/null 2>&1
    elif command -v yum &>/dev/null; then
        yum install -y jq bc >/dev/null 2>&1
    fi
fi

# Initialize database
init_database

case "${1:-}" in
    add-limit)
        if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
            echo -e "${RED}Error: email, protocol, and limit required${NC}"
            echo "Usage: $0 add-limit <email> <protocol> <limit>"
            echo "Limit formats: 100MB, 500M, 10GB, 5G, 0 (unlimited)"
            exit 1
        fi
        if add_client_limit "$2" "$3" "$4"; then
            echo -e "${GREEN}✓${NC} Bandwidth limit set for $2: $4"
        fi
        ;;
    remove-limit)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: email required${NC}"
            echo "Usage: $0 remove-limit <email>"
            exit 1
        fi
        remove_client_limit "$2"
        echo -e "${GREEN}✓${NC} Bandwidth limit removed for $2"
        ;;
    reset-usage)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: email required${NC}"
            echo "Usage: $0 reset-usage <email>"
            exit 1
        fi
        reset_client_usage "$2"
        ;;
    status)
        show_status
        ;;
    check)
        echo -e "${BLUE}Checking client limits...${NC}"
        check_client_limits
        echo -e "${GREEN}✓${NC} Check complete"
        ;;
    monitor)
        echo -e "${BLUE}Starting monitoring daemon...${NC}"
        start_monitoring_daemon
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac

exit 0
