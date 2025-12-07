# Bandwidth Blocking System Guide

## Overview
This VPN server now implements a **unified bandwidth management system** that **BLOCKS** users when they exceed their bandwidth limits instead of deleting them. This ensures users remain in the system but cannot access the network until their bandwidth is renewed.

## Key Features

### 1. Network Blocking (NOT Deletion)
- When a user exceeds their bandwidth limit, they are **BLOCKED** from all network access
- User accounts remain active in the system
- No data loss - all user configurations are preserved
- Users can be easily unblocked when renewing their bandwidth

### 2. Unified Blocking for All Protocols
The blocking mechanism works for all supported protocols:
- **SSH**: Blocked via iptables DROP rules based on UID
- **VMESS**: Blocked via network rules and marker files
- **VLESS**: Blocked via network rules and marker files
- **TROJAN**: Blocked via network rules and marker files
- **Shadowsocks**: Blocked via network rules and marker files

### 3. Real-time Status Monitoring
Users can have the following statuses:
- **ACTIVE**: User is within bandwidth limit
- **BLOCKED**: User exceeded bandwidth limit and is blocked
- **WARNING**: User approaching bandwidth limit (>80%)
- **UNLIMITED**: User has no bandwidth limit

## How It Works

### Bandwidth Tracking
1. System monitors bandwidth usage every 2 seconds (configurable 1-5 seconds)
2. Tracks **outbound** (upload) traffic as primary metric
3. Stores usage data in `/etc/myvpn/usage/<username>.json`
4. Updates daily, total, and remaining bandwidth statistics

### Blocking Mechanism
When a user exceeds their limit:

1. **For SSH Users**:
   - Adds iptables DROP rule for user's UID
   - Blocks all outgoing traffic: `iptables -I OUTPUT -m owner --uid-owner <UID> -j DROP`
   - Blocks all incoming traffic: `iptables -I INPUT -m connmark --mark <UID> -j DROP`
   
2. **For Xray Users (VMESS/VLESS/TROJAN/Shadowsocks)**:
   - Creates block marker file in `/etc/myvpn/blocked_users/<username>`
   - Prevents new connections through protocol-specific blocking
   
3. **JSON Tracking**:
   - Sets `"blocked": true` in user's JSON file
   - Records `"block_reason": "Bandwidth Limit Reached"`
   - Records `"block_time": "<timestamp>"`

4. **Logging**:
   - Logs blocking event to `/etc/myvpn/blocked.log`
   - Format: `timestamp | protocol | username | reason`

### Unblocking Mechanism
Users can be unblocked in two ways:

1. **Automatic Unblock on Reset**:
   - When administrator resets user's bandwidth usage
   - System automatically removes block and resets counters

2. **Manual Unblock**:
   - Administrator can manually unblock using menu option 11
   - Useful for emergency access or exceptions

## Menu Options

### Main Bandwidth Menu
```
[1]  Show All Users + Usage + Limits + Status
[2]  Check Single User Usage
[3]  Set User Data Limit
[4]  Remove User Limit
[5]  Reset User Usage (Renew) - Also unblocks user
[6]  Reset All Users Usage
[7]  Disable User
[8]  Enable User
[9]  Check Bandwidth Service Status
[10] Real-time Bandwidth Monitor
[11] Unblock User (Manual Unblock)
[12] View Blocked Users
```

## Usage Examples

### Setting Bandwidth Limit
```bash
# Set 10GB limit for SSH user
/usr/bin/cek-bw-limit set john 10240

# Set 5GB limit for VMESS user
/usr/bin/cek-bw-limit set user123 5120
```

### Checking User Status
```bash
# Check single user
/usr/bin/cek-bw-limit usage john

# View all users
/usr/bin/cek-bw-limit list

# View only blocked users
# Use menu option 12
```

### Resetting Bandwidth (Renewing User)
```bash
# Reset usage and unblock user
/usr/bin/cek-bw-limit reset john

# This will:
# 1. Clear bandwidth usage counters
# 2. Remove block if user was blocked
# 3. User can connect again
```

### Manual Unblock
```bash
# Unblock without resetting usage
# Use menu option 11 or:
/usr/bin/cek-bw-limit enable john
```

## Configuration Files

### Bandwidth Tracking
- `/etc/xray/bw-limit.conf` - Bandwidth limits per user
- `/etc/xray/bw-usage.conf` - Current usage baseline
- `/etc/xray/bw-last-stats.conf` - Last known stats (for reset detection)

### JSON Tracking (Enhanced)
- `/etc/myvpn/usage/<username>.json` - Per-user detailed tracking
  ```json
  {
    "username": "john",
    "total_usage": 1073741824,
    "daily_usage": 104857600,
    "total_limit": 10737418240,
    "blocked": true,
    "block_reason": "Bandwidth Limit Reached",
    "block_time": "2024-12-07 14:30:45",
    "last_reset": "2024-12-01 00:00:00"
  }
  ```

### Blocking Data
- `/etc/myvpn/blocked_users/<username>` - Marker files for blocked Xray users
- `/etc/myvpn/blocked.log` - Blocking event log

## System Service

### Service Status
```bash
# Check service status
systemctl status bw-limit-check

# View recent logs
journalctl -u bw-limit-check -n 50 -f
```

### Service Configuration
Service runs every 2 seconds checking bandwidth limits:
- Location: `/etc/systemd/system/bw-limit-check.service`
- Interval: 2 seconds (configurable 1-5 seconds)
- Auto-restart: Yes

## Troubleshooting

### User Still Can Connect After Block
1. Check if user is actually blocked:
   ```bash
   /usr/bin/cek-bw-limit usage <username>
   ```

2. For SSH users, verify iptables rules:
   ```bash
   iptables -L OUTPUT -v -n | grep -A2 "BW_"
   ```

3. Restart the bandwidth service:
   ```bash
   systemctl restart bw-limit-check
   ```

### Block Not Working for Xray Users
1. Check marker file exists:
   ```bash
   ls -la /etc/myvpn/blocked_users/
   ```

2. Verify JSON tracking:
   ```bash
   cat /etc/myvpn/usage/<username>.json
   ```

### Unblock Not Working
1. Manually remove iptables rules for SSH:
   ```bash
   UID=$(id -u username)
   iptables -D OUTPUT -m owner --uid-owner $UID -j DROP
   iptables -D INPUT -m connmark --mark $UID -j DROP
   ```

2. Remove marker file for Xray:
   ```bash
   rm -f /etc/myvpn/blocked_users/<username>
   ```

3. Update JSON:
   ```bash
   # Edit /etc/myvpn/usage/<username>.json
   # Set "blocked": false
   ```

## Best Practices

1. **Regular Monitoring**: Check blocked users regularly using menu option 12
2. **Bandwidth Allocation**: Set realistic bandwidth limits based on your server capacity
3. **User Communication**: Inform users about bandwidth limits and renewal process
4. **Log Review**: Periodically review `/etc/myvpn/blocked.log` for patterns
5. **Backup Tracking Files**: Backup `/etc/myvpn/usage/` directory regularly

## Migration from Old System

If upgrading from the old deletion-based system:

1. **No Migration Needed**: The new system is backward compatible
2. **Existing Users**: Will be tracked normally
3. **Deleted Users**: Cannot be recovered (they were deleted in old system)
4. **New Behavior**: All future limit violations will result in blocking, not deletion

## Advanced Configuration

### Adjusting Check Interval
Edit `/etc/systemd/system/bw-limit-check.service`:
```ini
# Change sleep value (1-5 seconds recommended)
ExecStart=/bin/bash -c 'while true; do /usr/bin/cek-bw-limit check >/dev/null 2>&1; sleep 2; done'
```

Then reload:
```bash
systemctl daemon-reload
systemctl restart bw-limit-check
```

### Custom Block Actions
You can extend the blocking functions in `/usr/bin/cek-bw-limit`:
- Add email notifications when users are blocked
- Integrate with external monitoring systems
- Add webhook calls for automation

## Summary

The new blocking system provides:
- ✅ No data loss (users not deleted)
- ✅ Easy bandwidth renewal process
- ✅ Unified blocking for all protocols
- ✅ Real-time status monitoring
- ✅ Detailed logging and tracking
- ✅ Manual override capabilities
- ✅ Backward compatibility

For support or questions, refer to the main documentation or contact the system administrator.
