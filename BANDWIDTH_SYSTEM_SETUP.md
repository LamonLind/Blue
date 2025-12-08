# Bandwidth Manager - Complete Setup Guide

## Overview
The bandwidth management system is now fully integrated into the VPN setup script. This document explains how the system works and how to use it.

## Features

### ✅ Integrated Installation
- **No separate installation required** - All bandwidth components are installed during main setup
- Downloads all required files from GitHub automatically
- Sets up systemd service for continuous monitoring
- Creates necessary directories and configuration files

### ✅ Account Creation Integration
- **Bandwidth limits set during account creation** - No need to set limits separately
- All account types support bandwidth limits:
  - SSH accounts (usernew.sh)
  - VLESS accounts (add-vless.sh)
  - VMESS accounts (add-ws.sh)
  - Trojan accounts (add-tr.sh)
  - Shadowsocks accounts (add-ssws.sh)

### ✅ Menu Integration
The main menu (menu4.sh) provides easy access to bandwidth features:
- **Option 15**: USER BANDWIDTH - View user traffic statistics
- **Option 17**: CHECK BANDWIDTH - Check current bandwidth usage
- **Option 28**: DATA LIMIT MENU - Full bandwidth management menu

## How It Works

### During Account Creation
When you create a new account using any of the account creation scripts, you'll be prompted:

```
Bandwidth Limit (MB, 0 for unlimited): 
```

**Examples:**
- Enter `1000` for 1GB (1000 MB) limit
- Enter `5000` for 5GB (5000 MB) limit
- Enter `0` for unlimited bandwidth

The system will:
1. Create the user account
2. Automatically set the bandwidth limit
3. Start monitoring the user's bandwidth usage
4. Block the user when limit is exceeded (user stays in system but network access is blocked)

### Bandwidth Monitoring Service
The system runs a background service (`bw-limit-check.service`) that:
- Checks bandwidth usage every 2 seconds
- Tracks upload and download traffic
- Automatically blocks users when they exceed their limit
- Maintains persistent usage data across reboots

### Network Blocking (Not Deletion)
When a user exceeds their bandwidth limit:
- **User account remains in the system**
- Network access is completely blocked
- User appears as "BLOCKED" in bandwidth manager
- Can be unblocked manually or usage can be reset

## Using the Bandwidth Manager Menu

Access the full bandwidth manager by selecting option 28 from the main menu:

```bash
menu
# Select option 28
```

### Menu Options

1. **Show All Users + Usage + Limits + Status**
   - View all users with bandwidth limits
   - See current usage, limit, and percentage
   - See status (ACTIVE, BLOCKED, UNLIMITED)

2. **Check Single User Usage**
   - Check detailed bandwidth usage for one user
   - Shows upload, download, and total usage
   - Shows remaining bandwidth

3. **Set User Data Limit**
   - Set or update bandwidth limit for existing user
   - Enter limit in MB (0 for unlimited)

4. **Remove User Limit**
   - Remove bandwidth limit from user
   - User becomes unlimited

5. **Reset User Usage (Renew)**
   - Reset user's bandwidth usage counter to zero
   - Unblocks user if they were blocked
   - Useful for monthly renewals

6. **Reset All Users Usage**
   - Reset bandwidth usage for ALL users
   - Useful for monthly billing cycle reset

7. **Disable User**
   - Manually disable a user account
   - User is blocked even if within bandwidth limit

8. **Enable User**
   - Re-enable a disabled user account

9. **Check Bandwidth Service Status**
   - View status of bandwidth monitoring service
   - See if service is running correctly

10. **Real-time Bandwidth Monitor**
    - Live monitoring of all users' bandwidth
    - Updates every 2 seconds
    - Shows current upload/download speeds

11. **Unblock User (Manual Unblock)**
    - Manually unblock a blocked user
    - Usage counter is NOT reset
    - User will be re-blocked if still over limit

12. **View Blocked Users**
    - List all currently blocked users
    - Shows when they were blocked

13. **Debug Diagnostics & Logging**
    - View detailed debug information
    - Check for any system issues
    - View debug logs

## Installation Details

All bandwidth components are installed by `setup.sh`:

### Downloaded Files
```bash
/usr/bin/cek-bw-limit          # Main bandwidth manager script
/usr/bin/bw-tracking-lib       # Bandwidth tracking library
/usr/bin/realtime-bandwidth    # Real-time bandwidth monitor
/usr/bin/realtime-hosts        # Real-time host capture
```

### Created Directories
```bash
/etc/myvpn/                    # Main configuration directory
/etc/myvpn/usage/              # JSON-based user tracking
/etc/myvpn/blocked_users/      # Blocked user markers
```

### Configuration Files
```bash
/etc/xray/bw-limit.conf        # User bandwidth limits
/etc/xray/bw-usage.conf        # Stored baseline usage
/etc/xray/bw-disabled.conf     # Disabled users list
/etc/xray/bw-last-stats.conf   # Last stats for reset detection
```

### Systemd Service
```bash
/etc/systemd/system/bw-limit-check.service
```
- Runs continuously in background
- Checks limits every 2 seconds
- Auto-restarts if it crashes

## Command Line Usage

You can also manage bandwidth limits from command line:

### Add/Update Limit
```bash
cek-bw-limit add <username> <limit_mb> <account_type>

# Examples:
cek-bw-limit add john 5000 ssh          # 5GB limit for SSH user
cek-bw-limit add user@test.com 10000 vless  # 10GB for VLESS user
```

### Check User Usage
```bash
cek-bw-limit usage <username>
```

### Reset User Usage
```bash
cek-bw-limit reset <username>
```

### List All Users
```bash
cek-bw-limit list
```

### Remove Limit
```bash
cek-bw-limit remove <username>
```

### Launch Menu
```bash
cek-bw-limit menu
```

## Bandwidth Tracking Details

### For Xray Protocols (VLESS, VMESS, Trojan, Shadowsocks)
- Uses Xray Stats API for accurate tracking
- Tracks both upload and download
- Handles Xray service restarts (reset detection)
- Total bandwidth = upload + download

### For SSH Accounts
- Uses iptables counters for tracking
- Tracks upload (outbound) traffic only
- Counters persist across reboots
- Per-user UID-based tracking

## Troubleshooting

### Service Not Running
Check service status:
```bash
systemctl status bw-limit-check
```

Restart service:
```bash
systemctl restart bw-limit-check
```

### View Debug Logs
Enable debug mode:
```bash
export DEBUG_MODE=1
systemctl restart bw-limit-check
```

View debug log:
```bash
tail -f /var/log/bw-limit-debug.log
```

Or use the menu (option 28 → option 13)

### User Not Being Blocked
1. Check if limit is set: `cek-bw-limit list`
2. Check service status: `systemctl status bw-limit-check`
3. Check debug logs for errors
4. Verify user exists in system

### Reset Not Working
1. Make sure service is running
2. Check if user is in disabled list: `cat /etc/xray/bw-disabled.conf`
3. Try manual unblock: Use menu option 11

## Important Notes

1. **Bandwidth limits are set in MB (Megabytes)**
   - 1 GB = 1000 MB (not 1024)
   - For GB, multiply by 1000 (e.g., 5GB = 5000 MB)

2. **Blocking does not delete users**
   - Blocked users remain in the system
   - They just cannot access the network
   - Can be unblocked or reset at any time

3. **Service runs automatically**
   - Starts on boot
   - Runs continuously
   - No manual intervention needed

4. **Per-user tracking**
   - Each user has their own limit
   - Usage is tracked separately
   - Limits can be different for each user

## Best Practices

1. **Set limits during account creation** - Easier than setting them later
2. **Use menu option 28** - Most user-friendly way to manage bandwidth
3. **Reset usage monthly** - Use option 6 for monthly billing cycles
4. **Monitor regularly** - Check option 1 to see all users' status
5. **Enable debug only when troubleshooting** - Adds overhead to logging

## Summary

✅ **Installation**: Automatic during setup.sh - no separate steps needed  
✅ **Account Creation**: Prompts for bandwidth limit - no need to set separately  
✅ **Menu Access**: Option 28 for full management, options 15 & 17 for monitoring  
✅ **Monitoring**: Automatic background service checks every 2 seconds  
✅ **Blocking**: Automatic when limit exceeded - user stays in system  
✅ **Management**: Easy menu-driven interface for all operations  

The bandwidth management system is fully integrated and working. No additional setup or configuration is required beyond running the main setup.sh script!
