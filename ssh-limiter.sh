#!/bin/bash
# =========================================
# SSH Bandwidth Limiter with cgroups v2
# Production-ready bandwidth limiting for SSH users
# =========================================
# Version: 1.0.0
# Author: LamonLind
# License: MIT
# =========================================

# Color definitions
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export NC='\033[0m'

# Configuration paths
CONFIG_FILE="/etc/ssh-limiter.conf"
DATA_DIR="/var/lib/ssh-limiter"
USAGE_DB="${DATA_DIR}/usage.db"
LOG_FILE="/var/log/ssh-limiter.log"
PID_FILE="/var/run/ssh-limiter.pid"
CGROUP_ROOT="/sys/fs/cgroup/ssh-limited"

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

bytes_to_mb() {
    echo $(( $1 / 1024 / 1024 ))
}

mb_to_bytes() {
    echo $(( $1 * 1024 * 1024 ))
}

# =========================================
# CONFIGURATION MANAGEMENT
# =========================================

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        # Default configuration
        DEFAULT_QUOTA_MB=500
        DEFAULT_LIMIT_KBPS=30
        MONITOR_INTERVAL=30
        LOG_LEVEL="INFO"
        ALERT_EMAIL="admin@example.com"
        PERSIST_USAGE=true
        AUTO_CLEANUP_DAYS=30
    fi
}

create_default_config() {
    cat > "$CONFIG_FILE" <<EOF
# SSH Bandwidth Limiter Configuration
# Generated: $(date)

# Default quota in MB (users start unlimited, limited when exceeded)
DEFAULT_QUOTA_MB=500

# Default bandwidth limit in kbps when quota exceeded
DEFAULT_LIMIT_KBPS=30

# Monitoring interval in seconds
MONITOR_INTERVAL=30

# Log level: DEBUG, INFO, WARN, ERROR, QUIET
LOG_LEVEL=INFO

# Alert email for notifications
ALERT_EMAIL=admin@example.com

# Persist usage data across reboots
PERSIST_USAGE=true

# Auto cleanup old data (days)
AUTO_CLEANUP_DAYS=30

# Enable web dashboard
WEB_DASHBOARD_ENABLED=false
WEB_DASHBOARD_PORT=8080
EOF
    log_msg "INFO" "Created default configuration at $CONFIG_FILE"
}

# =========================================
# CGROUPS V2 SETUP
# =========================================

setup_cgroups() {
    log_msg "INFO" "Setting up cgroups v2..."
    
    # Check if cgroup v2 is available
    if [ ! -d "/sys/fs/cgroup" ]; then
        log_msg "ERROR" "cgroup filesystem not found"
        return 1
    fi
    
    # Create root cgroup directory for SSH limiting
    mkdir -p "$CGROUP_ROOT" 2>/dev/null
    
    # Enable controllers
    if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
        # Enable cpu and memory controllers if available
        echo "+cpu +memory +io" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
        echo "+cpu +memory +io" > "${CGROUP_ROOT%/*}/cgroup.subtree_control" 2>/dev/null || true
    fi
    
    log_msg "INFO" "cgroups v2 setup complete"
    return 0
}

create_user_cgroup() {
    local username=$1
    local limit_kbps=$2
    local cgroup_path="${CGROUP_ROOT}/${username}"
    
    mkdir -p "$cgroup_path" 2>/dev/null
    
    # Set bandwidth limit using tc (traffic control) via cgroup
    # Note: cgroups v2 doesn't directly support network bandwidth limiting
    # We use iptables for actual bandwidth control and cgroups for process management
    
    log_msg "INFO" "Created cgroup for user $username at $cgroup_path"
    return 0
}

assign_process_to_cgroup() {
    local pid=$1
    local username=$2
    local cgroup_path="${CGROUP_ROOT}/${username}"
    
    if [ -d "$cgroup_path" ]; then
        echo "$pid" > "${cgroup_path}/cgroup.procs" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_msg "DEBUG" "Assigned PID $pid to cgroup $username"
            return 0
        fi
    fi
    return 1
}

remove_user_cgroup() {
    local username=$1
    local cgroup_path="${CGROUP_ROOT}/${username}"
    
    if [ -d "$cgroup_path" ]; then
        # Move processes back to parent cgroup
        if [ -f "${cgroup_path}/cgroup.procs" ]; then
            while read -r pid; do
                [ -n "$pid" ] && echo "$pid" > "${CGROUP_ROOT}/cgroup.procs" 2>/dev/null || true
            done < "${cgroup_path}/cgroup.procs"
        fi
        rmdir "$cgroup_path" 2>/dev/null
        log_msg "INFO" "Removed cgroup for user $username"
    fi
}

# =========================================
# IPTABLES TRAFFIC TRACKING
# =========================================

initialize_iptables_tracking() {
    local username=$1
    local uid=$(id -u "$username" 2>/dev/null)
    
    if [ -z "$uid" ]; then
        log_msg "ERROR" "User $username not found"
        return 1
    fi
    
    local chain_name="SSH_TRACK_${uid}"
    
    # Create custom chain for tracking
    if ! iptables -L "$chain_name" -n &>/dev/null; then
        iptables -N "$chain_name" 2>/dev/null
        
        # Track outgoing traffic (upload)
        iptables -I OUTPUT -m owner --uid-owner "$uid" -j "$chain_name" 2>/dev/null
        
        # Mark connections for this user
        iptables -I OUTPUT -m owner --uid-owner "$uid" -j CONNMARK --set-mark "$uid" 2>/dev/null
        
        # Track incoming traffic (download) using connection marks
        iptables -I INPUT -m connmark --mark "$uid" -j "$chain_name" 2>/dev/null
        
        # Return rule
        iptables -A "$chain_name" -j RETURN 2>/dev/null
        
        log_msg "INFO" "Initialized iptables tracking for $username (UID: $uid)"
    fi
}

get_user_traffic_bytes() {
    local username=$1
    local uid=$(id -u "$username" 2>/dev/null)
    
    if [ -z "$uid" ]; then
        echo 0
        return
    fi
    
    local chain_name="SSH_TRACK_${uid}"
    
    # Get total bytes from chain (upload + download)
    local total=$(iptables -L "$chain_name" -v -n -x 2>/dev/null | \
                  grep -v "^Chain\|^$\|pkts" | \
                  awk '{sum+=$2} END {print sum+0}')
    
    echo "${total:-0}"
}

cleanup_iptables_tracking() {
    local username=$1
    local uid=$(id -u "$username" 2>/dev/null)
    
    if [ -z "$uid" ]; then
        return 1
    fi
    
    local chain_name="SSH_TRACK_${uid}"
    
    # Remove jump rules
    iptables -D OUTPUT -m owner --uid-owner "$uid" -j "$chain_name" 2>/dev/null
    iptables -D OUTPUT -m owner --uid-owner "$uid" -j CONNMARK --set-mark "$uid" 2>/dev/null
    iptables -D INPUT -m connmark --mark "$uid" -j "$chain_name" 2>/dev/null
    
    # Flush and delete chain
    iptables -F "$chain_name" 2>/dev/null
    iptables -X "$chain_name" 2>/dev/null
    
    log_msg "INFO" "Cleaned up iptables tracking for $username"
}

# =========================================
# BANDWIDTH LIMITING WITH TC
# =========================================

apply_bandwidth_limit() {
    local username=$1
    local limit_kbps=$2
    local uid=$(id -u "$username" 2>/dev/null)
    
    if [ -z "$uid" ]; then
        log_msg "ERROR" "User $username not found"
        return 1
    fi
    
    # Use tc (traffic control) with HTB (Hierarchical Token Bucket) for bandwidth shaping
    # This provides kernel-level bandwidth limiting
    
    # Get default interface
    local iface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -z "$iface" ]; then
        iface="eth0"
    fi
    
    # Convert kbps to kbit for tc
    local limit_kbit="${limit_kbps}"
    
    # Create tc qdisc if not exists
    if ! tc qdisc show dev "$iface" | grep -q "htb"; then
        tc qdisc add dev "$iface" root handle 1: htb default 9999 2>/dev/null || true
    fi
    
    # Add class for this user with bandwidth limit
    local classid="1:${uid}"
    tc class add dev "$iface" parent 1: classid "$classid" htb rate "${limit_kbit}kbit" ceil "${limit_kbit}kbit" 2>/dev/null || \
    tc class change dev "$iface" parent 1: classid "$classid" htb rate "${limit_kbit}kbit" ceil "${limit_kbit}kbit" 2>/dev/null
    
    # Add filter to match user traffic
    tc filter add dev "$iface" parent 1: protocol ip prio 1 handle "${uid}" fw flowid "$classid" 2>/dev/null || true
    
    # Mark packets from this user using iptables (for tc to catch)
    iptables -t mangle -I OUTPUT -m owner --uid-owner "$uid" -j MARK --set-mark "$uid" 2>/dev/null || true
    iptables -t mangle -I POSTROUTING -m connmark --mark "$uid" -j MARK --set-mark "$uid" 2>/dev/null || true
    
    log_msg "INFO" "Applied ${limit_kbps}kbps bandwidth limit to $username on interface $iface"
    return 0
}

remove_bandwidth_limit() {
    local username=$1
    local uid=$(id -u "$username" 2>/dev/null)
    
    if [ -z "$uid" ]; then
        return 1
    fi
    
    local iface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -z "$iface" ]; then
        iface="eth0"
    fi
    
    # Remove tc rules
    local classid="1:${uid}"
    tc filter del dev "$iface" parent 1: prio 1 handle "${uid}" fw 2>/dev/null || true
    tc class del dev "$iface" classid "$classid" 2>/dev/null || true
    
    # Remove iptables marks
    iptables -t mangle -D OUTPUT -m owner --uid-owner "$uid" -j MARK --set-mark "$uid" 2>/dev/null || true
    iptables -t mangle -D POSTROUTING -m connmark --mark "$uid" -j MARK --set-mark "$uid" 2>/dev/null || true
    
    log_msg "INFO" "Removed bandwidth limit from $username"
}

# =========================================
# DATABASE OPERATIONS
# =========================================

init_database() {
    mkdir -p "$DATA_DIR"
    touch "$USAGE_DB"
    
    # Database format: username|quota_mb|limit_kbps|current_usage_bytes|state|last_updated
    # States: UNLIMITED, LIMITED, RESET
}

get_user_state() {
    local username=$1
    grep "^${username}|" "$USAGE_DB" 2>/dev/null | cut -d'|' -f5
}

get_user_quota() {
    local username=$1
    local quota=$(grep "^${username}|" "$USAGE_DB" 2>/dev/null | cut -d'|' -f2)
    echo "${quota:-$DEFAULT_QUOTA_MB}"
}

get_user_limit() {
    local username=$1
    local limit=$(grep "^${username}|" "$USAGE_DB" 2>/dev/null | cut -d'|' -f3)
    echo "${limit:-$DEFAULT_LIMIT_KBPS}"
}

get_stored_usage() {
    local username=$1
    local usage=$(grep "^${username}|" "$USAGE_DB" 2>/dev/null | cut -d'|' -f4)
    echo "${usage:-0}"
}

update_user_record() {
    local username=$1
    local quota_mb=$2
    local limit_kbps=$3
    local usage_bytes=$4
    local state=$5
    local timestamp=$(date +%s)
    
    # Remove old record
    sed -i "/^${username}|/d" "$USAGE_DB"
    
    # Add new record
    echo "${username}|${quota_mb}|${limit_kbps}|${usage_bytes}|${state}|${timestamp}" >> "$USAGE_DB"
}

# =========================================
# USER MANAGEMENT
# =========================================

add_user_monitoring() {
    local username=$1
    
    # Verify user exists
    if ! id "$username" &>/dev/null; then
        log_msg "ERROR" "User $username does not exist in the system"
        return 1
    fi
    
    # Check if already monitored
    if grep -q "^${username}|" "$USAGE_DB" 2>/dev/null; then
        log_msg "WARN" "User $username is already being monitored"
        return 0
    fi
    
    # Initialize tracking
    initialize_iptables_tracking "$username"
    
    # Add to database with UNLIMITED state
    update_user_record "$username" "$DEFAULT_QUOTA_MB" "$DEFAULT_LIMIT_KBPS" "0" "UNLIMITED"
    
    log_msg "INFO" "Added $username to monitoring (quota: ${DEFAULT_QUOTA_MB}MB, unlimited until threshold)"
    echo -e "${GREEN}✓${NC} User $username added to bandwidth monitoring"
    echo -e "  Quota: ${DEFAULT_QUOTA_MB}MB (unlimited until exceeded)"
    echo -e "  Limit when exceeded: ${DEFAULT_LIMIT_KBPS}kbps"
}

remove_user_monitoring() {
    local username=$1
    
    if ! grep -q "^${username}|" "$USAGE_DB" 2>/dev/null; then
        log_msg "WARN" "User $username is not being monitored"
        return 1
    fi
    
    # Remove bandwidth limit if applied
    remove_bandwidth_limit "$username"
    
    # Remove cgroup
    remove_user_cgroup "$username"
    
    # Cleanup iptables
    cleanup_iptables_tracking "$username"
    
    # Remove from database
    sed -i "/^${username}|/d" "$USAGE_DB"
    
    log_msg "INFO" "Removed $username from monitoring"
    echo -e "${GREEN}✓${NC} User $username removed from monitoring"
}

reset_user_usage() {
    local username=$1
    
    if ! grep -q "^${username}|" "$USAGE_DB" 2>/dev/null; then
        log_msg "ERROR" "User $username is not being monitored"
        return 1
    fi
    
    # Get current settings
    local quota=$(get_user_quota "$username")
    local limit=$(get_user_limit "$username")
    
    # Remove bandwidth limit
    remove_bandwidth_limit "$username"
    
    # Reset iptables counters by recreating the chain
    cleanup_iptables_tracking "$username"
    initialize_iptables_tracking "$username"
    
    # Update state to UNLIMITED with 0 usage
    update_user_record "$username" "$quota" "$limit" "0" "UNLIMITED"
    
    log_msg "INFO" "Reset usage for $username to 0MB (state: UNLIMITED)"
    echo -e "${GREEN}✓${NC} Usage reset for $username"
    echo -e "  New state: UNLIMITED (0MB used)"
    echo -e "  Quota: ${quota}MB"
}

set_user_limit() {
    local username=$1
    local limit_kbps=$2
    
    if ! grep -q "^${username}|" "$USAGE_DB" 2>/dev/null; then
        log_msg "ERROR" "User $username is not being monitored"
        return 1
    fi
    
    # Get current settings
    local quota=$(get_user_quota "$username")
    local usage=$(get_stored_usage "$username")
    local state=$(get_user_state "$username")
    
    # Update limit
    update_user_record "$username" "$quota" "$limit_kbps" "$usage" "$state"
    
    # If currently limited, update the limit
    if [ "$state" = "LIMITED" ]; then
        remove_bandwidth_limit "$username"
        apply_bandwidth_limit "$username" "$limit_kbps"
    fi
    
    log_msg "INFO" "Set bandwidth limit for $username to ${limit_kbps}kbps"
    echo -e "${GREEN}✓${NC} Bandwidth limit updated for $username: ${limit_kbps}kbps"
}

set_user_quota() {
    local username=$1
    local quota_mb=$2
    
    if ! grep -q "^${username}|" "$USAGE_DB" 2>/dev/null; then
        log_msg "ERROR" "User $username is not being monitored"
        return 1
    fi
    
    # Get current settings
    local limit=$(get_user_limit "$username")
    local usage=$(get_stored_usage "$username")
    local state=$(get_user_state "$username")
    
    # Update quota
    update_user_record "$username" "$quota_mb" "$limit" "$usage" "$state"
    
    log_msg "INFO" "Set quota for $username to ${quota_mb}MB"
    echo -e "${GREEN}✓${NC} Quota updated for $username: ${quota_mb}MB"
}

# =========================================
# MONITORING DAEMON
# =========================================

check_and_enforce_limits() {
    while IFS='|' read -r username quota_mb limit_kbps stored_usage state last_updated; do
        [ -z "$username" ] && continue
        
        # Get current traffic from iptables
        local current_traffic=$(get_user_traffic_bytes "$username")
        
        # Total usage = stored baseline + current traffic
        local total_usage=$((stored_usage + current_traffic))
        local total_mb=$(bytes_to_mb $total_usage)
        local quota_bytes=$(mb_to_bytes $quota_mb)
        
        # Check if quota exceeded
        if [ "$total_usage" -ge "$quota_bytes" ] && [ "$state" = "UNLIMITED" ]; then
            # Quota exceeded, apply limit
            log_msg "INFO" "User $username exceeded quota (${total_mb}MB / ${quota_mb}MB) - applying ${limit_kbps}kbps limit"
            
            apply_bandwidth_limit "$username" "$limit_kbps"
            create_user_cgroup "$username" "$limit_kbps"
            
            # Assign all current user processes to cgroup
            pgrep -u "$username" | while read -r pid; do
                assign_process_to_cgroup "$pid" "$username"
            done
            
            # Update state
            update_user_record "$username" "$quota_mb" "$limit_kbps" "$total_usage" "LIMITED"
            
            # Send alert if configured
            if [ -n "$ALERT_EMAIL" ] && command -v mail &>/dev/null; then
                echo "User $username has exceeded bandwidth quota (${total_mb}MB / ${quota_mb}MB). Bandwidth limited to ${limit_kbps}kbps." | \
                    mail -s "SSH Bandwidth Limit Alert: $username" "$ALERT_EMAIL" 2>/dev/null || true
            fi
        elif [ "$state" = "LIMITED" ]; then
            # Already limited, update usage
            update_user_record "$username" "$quota_mb" "$limit_kbps" "$total_usage" "LIMITED"
            
            # Ensure processes are in cgroup
            pgrep -u "$username" | while read -r pid; do
                assign_process_to_cgroup "$pid" "$username"
            done
        fi
        
    done < "$USAGE_DB"
}

monitor_daemon() {
    log_msg "INFO" "Starting SSH bandwidth monitoring daemon (interval: ${MONITOR_INTERVAL}s)"
    
    # Write PID file
    echo $$ > "$PID_FILE"
    
    while true; do
        check_and_enforce_limits
        sleep "$MONITOR_INTERVAL"
    done
}

start_monitoring() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}Monitoring daemon is already running (PID: $pid)${NC}"
            return 0
        fi
    fi
    
    # Start daemon in background
    nohup bash -c "$(declare -f monitor_daemon check_and_enforce_limits get_user_traffic_bytes bytes_to_mb mb_to_bytes get_user_quota get_user_limit get_stored_usage get_user_state update_user_record apply_bandwidth_limit create_user_cgroup assign_process_to_cgroup log_msg); monitor_daemon" > /dev/null 2>&1 &
    
    local daemon_pid=$!
    echo "$daemon_pid" > "$PID_FILE"
    
    log_msg "INFO" "Monitoring daemon started (PID: $daemon_pid)"
    echo -e "${GREEN}✓${NC} Monitoring daemon started (PID: $daemon_pid)"
}

stop_monitoring() {
    if [ ! -f "$PID_FILE" ]; then
        echo -e "${YELLOW}Monitoring daemon is not running${NC}"
        return 0
    fi
    
    local pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        rm -f "$PID_FILE"
        log_msg "INFO" "Monitoring daemon stopped (PID: $pid)"
        echo -e "${GREEN}✓${NC} Monitoring daemon stopped"
    else
        rm -f "$PID_FILE"
        echo -e "${YELLOW}Daemon PID file exists but process not running${NC}"
    fi
}

# =========================================
# STATUS AND REPORTING
# =========================================

show_status() {
    echo -e "\n${BLUE}=== SSH Bandwidth Limiter Status ===${NC}\n"
    
    # Check daemon status
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "Daemon: ${GREEN}Running${NC} (PID: $pid)"
        else
            echo -e "Daemon: ${RED}Not Running${NC} (stale PID file)"
        fi
    else
        echo -e "Daemon: ${RED}Not Running${NC}"
    fi
    
    echo -e "\n${BLUE}Monitored Users:${NC}\n"
    printf "%-15s %-10s %-10s %-15s %-10s\n" "USERNAME" "QUOTA" "USAGE" "STATE" "LIMIT"
    printf "%-15s %-10s %-10s %-15s %-10s\n" "--------" "-----" "-----" "-----" "-----"
    
    if [ ! -s "$USAGE_DB" ]; then
        echo -e "${YELLOW}No users being monitored${NC}"
        return
    fi
    
    while IFS='|' read -r username quota_mb limit_kbps stored_usage state last_updated; do
        [ -z "$username" ] && continue
        
        local current_traffic=$(get_user_traffic_bytes "$username")
        local total_usage=$((stored_usage + current_traffic))
        local total_mb=$(bytes_to_mb $total_usage)
        
        # Color code state
        local state_color=""
        case "$state" in
            UNLIMITED) state_color="${GREEN}" ;;
            LIMITED)   state_color="${RED}" ;;
            *)         state_color="${NC}" ;;
        esac
        
        printf "%-15s %-10s %-10s ${state_color}%-15s${NC} %-10s\n" \
            "$username" \
            "${quota_mb}MB" \
            "${total_mb}MB" \
            "$state" \
            "${limit_kbps}kbps"
    done < "$USAGE_DB"
    
    echo ""
}

view_logs() {
    local lines=${1:-50}
    
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}No log file found${NC}"
        return
    fi
    
    echo -e "\n${BLUE}=== Recent Log Entries (last $lines lines) ===${NC}\n"
    tail -n "$lines" "$LOG_FILE"
}

# =========================================
# INSTALLATION
# =========================================

install_dependencies() {
    log_msg "INFO" "Installing dependencies..."
    
    # Detect package manager
    if command -v apt-get &>/dev/null; then
        apt-get update -qq
        apt-get install -y iptables iproute2 coreutils procps > /dev/null 2>&1
    elif command -v yum &>/dev/null; then
        yum install -y iptables iproute coreutils procps-ng > /dev/null 2>&1
    elif command -v dnf &>/dev/null; then
        dnf install -y iptables iproute coreutils procps-ng > /dev/null 2>&1
    fi
    
    log_msg "INFO" "Dependencies installed"
}

install_system() {
    echo -e "${BLUE}=== Installing SSH Bandwidth Limiter ===${NC}\n"
    
    # Install dependencies
    install_dependencies
    
    # Create directories
    mkdir -p "$DATA_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Initialize database
    init_database
    
    # Create configuration
    if [ ! -f "$CONFIG_FILE" ]; then
        create_default_config
    fi
    
    # Load configuration
    load_config
    
    # Setup cgroups
    setup_cgroups
    
    # Create systemd service
    cat > /etc/systemd/system/ssh-limiter.service <<EOF
[Unit]
Description=SSH Bandwidth Limiter Monitoring Daemon
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/bin/ssh-limiter.sh start-monitor
ExecStop=/usr/local/bin/ssh-limiter.sh stop-monitor
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    # Copy script to system location
    cp "$0" /usr/local/bin/ssh-limiter.sh
    chmod +x /usr/local/bin/ssh-limiter.sh
    
    # Reload systemd
    systemctl daemon-reload
    
    # Add default monitoring users if specified
    if [ -n "$1" ]; then
        IFS=',' read -ra USERS <<< "$1"
        for user in "${USERS[@]}"; do
            user=$(echo "$user" | xargs) # trim whitespace
            if [ -n "$user" ]; then
                add_user_monitoring "$user"
            fi
        done
    fi
    
    echo -e "\n${GREEN}✓ Installation complete!${NC}"
    echo -e "\nConfiguration file: $CONFIG_FILE"
    echo -e "Usage database: $USAGE_DB"
    echo -e "Log file: $LOG_FILE"
    echo -e "\nTo start monitoring: systemctl start ssh-limiter"
    echo -e "To enable on boot: systemctl enable ssh-limiter"
}

uninstall_system() {
    echo -e "${YELLOW}Uninstalling SSH Bandwidth Limiter...${NC}\n"
    
    # Stop service
    systemctl stop ssh-limiter 2>/dev/null || true
    systemctl disable ssh-limiter 2>/dev/null || true
    
    # Stop daemon
    stop_monitoring
    
    # Remove limits from all users
    if [ -f "$USAGE_DB" ]; then
        while IFS='|' read -r username _; do
            [ -n "$username" ] && remove_user_monitoring "$username"
        done < "$USAGE_DB"
    fi
    
    # Remove files
    rm -f /etc/systemd/system/ssh-limiter.service
    rm -f /usr/local/bin/ssh-limiter.sh
    rm -rf "$DATA_DIR"
    rm -f "$PID_FILE"
    
    # Optionally keep config and logs
    read -p "Remove configuration and logs? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$CONFIG_FILE"
        rm -f "$LOG_FILE"
    fi
    
    systemctl daemon-reload
    
    echo -e "${GREEN}✓ Uninstallation complete${NC}"
}

# =========================================
# MAIN COMMAND HANDLER
# =========================================

show_help() {
    cat <<EOF
${BLUE}SSH Bandwidth Limiter${NC}
Production-ready bandwidth limiting for SSH users using cgroups v2

${YELLOW}Usage:${NC}
    $0 <command> [arguments]

${YELLOW}Commands:${NC}
    ${GREEN}install [user1,user2,...]${NC}
        Full installation with dependencies
        Optional: Comma-separated list of users to monitor

    ${GREEN}uninstall${NC}
        Complete cleanup and removal

    ${GREEN}status${NC}
        Show all users with usage and limit status

    ${GREEN}add-user <username>${NC}
        Add new user to monitoring (starts UNLIMITED)

    ${GREEN}remove-user <username>${NC}
        Stop monitoring user and remove limits

    ${GREEN}reset-user <username>${NC}
        Reset user's usage to 0, remove limits

    ${GREEN}set-limit <username> <kbps>${NC}
        Manually set custom bandwidth limit

    ${GREEN}set-quota <username> <MB>${NC}
        Change quota threshold for user

    ${GREEN}start-monitor${NC}
        Start background monitoring daemon

    ${GREEN}stop-monitor${NC}
        Stop monitoring daemon

    ${GREEN}view-logs [lines]${NC}
        Show recent logs (default: 50 lines)

${YELLOW}Configuration:${NC}
    Edit $CONFIG_FILE to change defaults

${YELLOW}States:${NC}
    ${GREEN}UNLIMITED${NC} - User has not exceeded quota (no restrictions)
    ${RED}LIMITED${NC}   - User exceeded quota (bandwidth limited)
    ${BLUE}RESET${NC}     - Usage reset by admin (back to UNLIMITED)

${YELLOW}Examples:${NC}
    $0 install vpnuser1,vpnuser2,vpnuser3
    $0 add-user newuser
    $0 status
    $0 reset-user vpnuser1
    $0 set-limit vpnuser2 50
    $0 set-quota vpnuser3 1000

EOF
}

# =========================================
# MAIN
# =========================================

# Load configuration if exists
load_config

case "${1:-}" in
    install)
        install_system "$2"
        ;;
    uninstall)
        uninstall_system
        ;;
    status)
        show_status
        ;;
    add-user)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Username required${NC}"
            echo "Usage: $0 add-user <username>"
            exit 1
        fi
        add_user_monitoring "$2"
        ;;
    remove-user)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Username required${NC}"
            echo "Usage: $0 remove-user <username>"
            exit 1
        fi
        remove_user_monitoring "$2"
        ;;
    reset-user)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Username required${NC}"
            echo "Usage: $0 reset-user <username>"
            exit 1
        fi
        reset_user_usage "$2"
        ;;
    set-limit)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo -e "${RED}Error: Username and limit required${NC}"
            echo "Usage: $0 set-limit <username> <kbps>"
            exit 1
        fi
        set_user_limit "$2" "$3"
        ;;
    set-quota)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo -e "${RED}Error: Username and quota required${NC}"
            echo "Usage: $0 set-quota <username> <MB>"
            exit 1
        fi
        set_user_quota "$2" "$3"
        ;;
    start-monitor)
        start_monitoring
        ;;
    stop-monitor)
        stop_monitoring
        ;;
    view-logs)
        view_logs "${2:-50}"
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
