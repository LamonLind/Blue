# Bandwidth Monitoring System

## Overview

This system provides comprehensive bandwidth/data limit management for all VPN account types:
- **SSH** accounts
- **VMess** (Xray) accounts  
- **VLess** (Xray) accounts
- **Trojan** (Xray) accounts
- **Shadowsocks** (Xray) accounts

## Features

- Set bandwidth limits per user (in MB)
- Automatic user deletion when limit exceeded
- Real-time bandwidth usage monitoring
- Persistent tracking across Xray service restarts
- Manual user limit management
- Usage reset/renewal capabilities

## How It Works

### 1. User Creation with Bandwidth Limit

When creating a new user with any of the add scripts (add-ws.sh, add-vless.sh, add-tr.sh, add-ssws.sh, usernew.sh), you'll be prompted:

```
Bandwidth Limit (MB, 0 for unlimited):
```

Enter a value in MB (e.g., 1024 for 1 GB, 10240 for 10 GB).

### 2. Bandwidth Tracking

The system tracks bandwidth using:
- **Xray API** for Xray-based protocols (vmess, vless, trojan, shadowsocks)
- **iptables** for SSH users

Tracking data is stored in:
- `/etc/xray/bw-limit.conf` - User limits
- `/etc/xray/bw-usage.conf` - Baseline usage (accumulated)
- `/etc/xray/bw-last-stats.conf` - Last known stats (for reset detection)
- `/etc/xray/bw-disabled.conf` - Disabled users

### 3. Automatic Limit Enforcement

A background service (`bw-limit-check.service`) runs every 2 seconds and:
1. Checks each user's current bandwidth usage
2. Compares against their limit
3. Automatically deletes users who exceed their limit
4. Restarts Xray service after deletions

### 4. Persistent Tracking

The system handles Xray service restarts correctly by:
- Tracking baseline usage in `bw-usage.conf`
- Detecting when Xray stats reset (service restart)
- Adding previous stats to baseline before reset
- Continuing to accumulate total usage accurately

## Usage Guide

### Access Bandwidth Menu

From the main menu, select the data limit management option, or run:

```bash
cek-bw-limit menu
```

### Menu Options

1. **Show All Users + Usage + Limits** - View all users with their current usage and limits
2. **Check Single User Usage** - Detailed view of a specific user
3. **Set User Data Limit** - Add or update bandwidth limit for a user
4. **Remove User Limit** - Remove bandwidth limit (makes user unlimited)
5. **Reset User Usage (Renew)** - Reset usage counter to 0 for a user
6. **Reset All Users Usage** - Reset usage for all users
7. **Disable User** - Temporarily disable a user without deleting
8. **Enable User** - Re-enable a disabled user
9. **Check Bandwidth Service Status** - Diagnostic tool to check if system is working

### Command Line Usage

You can also use cek-bw-limit.sh from command line:

```bash
# Set user limit
cek-bw-limit set username 10240  # 10 GB limit

# Remove user limit
cek-bw-limit remove username

# Reset user usage
cek-bw-limit reset username

# Check single user
cek-bw-limit usage username

# List all users
cek-bw-limit list

# Show usage display
cek-bw-limit show

# Manually run limit check
cek-bw-limit check
```

## Troubleshooting

### Bandwidth Not Working / Not Tracking

If bandwidth is showing as 0 or not updating, use menu option 9 "Check Bandwidth Service Status" to diagnose.

**Common Issues:**

#### 1. Service Not Running

**Symptom:** Service Status shows "NOT RUNNING"

**Fix:**
```bash
systemctl start bw-limit-check
systemctl enable bw-limit-check
```

#### 2. Service Not Installed

**Symptom:** Service File shows "NOT FOUND"

**Fix:** The service should be created during initial setup. To create manually:

```bash
cat > /etc/systemd/system/bw-limit-check.service <<-END
[Unit]
Description=Professional Data Usage Limit Checker Service
After=network.target xray.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do /usr/bin/cek-bw-limit check >/dev/null 2>&1; sleep 2; done'
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
END

systemctl daemon-reload
systemctl enable bw-limit-check
systemctl start bw-limit-check
```

#### 3. Xray API Not Accessible

**Symptom:** Xray API shows "NOT ACCESSIBLE"

**Fixes:**
- Verify Xray is running: `systemctl status xray`
- Check Xray API config in `/etc/xray/config.json` has:
  ```json
  "api": {
    "tag": "api",
    "services": ["StatsService"]
  }
  ```
- Verify API inbound in config.json:
  ```json
  {
    "tag": "api",
    "port": 10085,
    "listen": "127.0.0.1",
    "protocol": "dokodemo-door",
    "settings": {
      "address": "127.0.0.1"
    }
  }
  ```
- Restart xray: `systemctl restart xray`

#### 4. Configuration Files Missing

**Symptom:** Config files show "MISSING"

**Fix:**
```bash
mkdir -p /etc/xray
touch /etc/xray/bw-limit.conf
touch /etc/xray/bw-usage.conf
touch /etc/xray/bw-last-stats.conf
touch /etc/xray/bw-disabled.conf
```

### Bandwidth Showing Incorrect Value

If bandwidth shows incorrect values (e.g., "20 MB showing as 1 MB"):

1. **Check if service is running** - Use menu option 9
2. **Reset user usage** - Use menu option 5 to reset and start fresh
3. **Check Xray stats directly**:
   ```bash
   /usr/local/bin/xray api statsquery --server=127.0.0.1:10085
   ```
4. **Verify baseline files** - Check `/etc/xray/bw-usage.conf` and `/etc/xray/bw-last-stats.conf`

### Users Not Being Deleted When Limit Exceeded

1. **Verify service is running**:
   ```bash
   systemctl status bw-limit-check
   ```

2. **Check service logs**:
   ```bash
   journalctl -u bw-limit-check -f
   ```

3. **Manually trigger check**:
   ```bash
   /usr/bin/cek-bw-limit check
   ```

4. **Verify user has limit set**:
   ```bash
   grep username /etc/xray/bw-limit.conf
   ```

## Technical Details

### Bandwidth Calculation Formula

```
Total Usage = Baseline Usage + Current Xray Stats
```

Where:
- **Baseline Usage**: Accumulated usage from previous Xray sessions (stored in bw-usage.conf)
- **Current Xray Stats**: Current session stats from Xray API (uplink + downlink)

### Reset Detection

When Xray service restarts, stats reset to 0. The system detects this by:
1. Comparing current stats with last known stats
2. If current < last, a reset is detected
3. Last known stats are added to baseline
4. Tracking continues with new session

### Unit Conversion

- Xray API returns values in **bytes**
- Display shows values in **MB** (1 MB = 1024 * 1024 bytes)
- Input limits are in **MB**
- Internal calculations use **bytes** for precision

## File Structure

```
/usr/bin/cek-bw-limit          # Main bandwidth management script
/etc/xray/bw-limit.conf         # User limits (username limit_mb account_type)
/etc/xray/bw-usage.conf         # Baseline usage in bytes
/etc/xray/bw-last-stats.conf    # Last known stats for reset detection
/etc/xray/bw-disabled.conf      # Disabled users list
/etc/systemd/system/bw-limit-check.service  # Monitoring service
```

## Integration with User Management

All user creation scripts integrate bandwidth limits:
- `add-ws.sh` (VMess)
- `add-vless.sh` (VLess)
- `add-tr.sh` (Trojan)
- `add-ssws.sh` (Shadowsocks)
- `usernew.sh` (SSH)

All user deletion scripts cleanup bandwidth tracking:
- `menu-vmess.sh`
- `menu-vless.sh`
- `menu-trojan.sh`
- `menu-ss.sh`
- `menu-ssh.sh`

## Best Practices

1. **Set realistic limits** - Consider both upload and download
2. **Monitor regularly** - Check usage before limits are exceeded
3. **Reset as needed** - Use reset feature to renew users monthly
4. **Keep service running** - Ensure bw-limit-check service is always active
5. **Regular backups** - Backup `/etc/xray/bw-*.conf` files

## Support

For issues or questions:
1. Use menu option 9 for diagnostics
2. Check service logs: `journalctl -u bw-limit-check -n 50`
3. Verify Xray logs: `tail -f /var/log/xray/access.log`
4. Check this documentation for common issues
