# Bandwidth Quota System Guide (3x-ui Style)

## Overview
This system implements bandwidth/data quota limits for Xray protocols (VLESS, VMESS, Trojan, Shadowsocks), based on the 3x-ui implementation.

## How It Works

### Architecture
The system consists of three main components:

1. **xray-quota-manager** - Command-line tool to manage quota limits
2. **xray-traffic-monitor** - Background service that monitors traffic and enforces quotas
3. **Account creation integration** - Automatic quota prompts during account creation

### Traffic Tracking
- Uses Xray's built-in stats API to query traffic per user
- Tracks **upload (uplink)** and **download (downlink)** traffic
- Compares **total usage (Up + Down)** against the quota limit
- When quota exceeded: automatically disables user by removing from Xray config

## Setting Up Quotas

### During Account Creation
When creating a new Xray account (VLESS, VMESS, Trojan, or Shadowsocks), you'll be prompted:

```
Bandwidth Quota Limit:
Enter data quota limit (e.g., 10GB, 500MB, 1TB)
Press Enter for unlimited
Quota:
```

**Examples:**
- Enter `10GB` for 10 gigabytes
- Enter `500MB` for 500 megabytes
- Enter `1TB` for 1 terabyte
- Press Enter for unlimited bandwidth

### Manual Quota Management

#### Set/Update Quota
```bash
xray-quota-manager set user@example.com 10GB
```

#### Remove Quota (Make Unlimited)
```bash
xray-quota-manager remove user@example.com
```

#### Check Quota for User
```bash
xray-quota-manager get user@example.com
```

#### List All Quotas
```bash
xray-quota-manager list
```

Output example:
```
Email                     Total Quota          Status    
-----                     -----------          ------    
user1@test.com            10.00 GB             true      
user2@test.com            500.00 MB            true      
user3@test.com            1.00 TB              false
```

## How Quota Enforcement Works

### Monitoring Service
The `xray-quota-monitor` service runs in the background:
- Checks traffic every **60 seconds** (like 3x-ui)
- Queries Xray stats API for each user with a quota
- Calculates: `current_usage = uplink + downlink`
- Compares: `if current_usage >= quota_limit`
- **If exceeded**: Disables user by removing from Xray config and restarting service

### What Happens When Quota Exceeded
1. User is automatically removed from `/etc/xray/config.json`
2. Xray service is restarted to apply changes
3. User entry is marked as `disabled` in quota config
4. Event is logged to `/var/log/xray-quota-monitor.log`

### Checking Traffic Usage
Since this is based on Xray's stats API, you can query current usage:
```bash
xray api statsquery --server=127.0.0.1:10085 -pattern "user>>>username>>>traffic>>>uplink"
xray api statsquery --server=127.0.0.1:10085 -pattern "user>>>username>>>traffic>>>downlink"
```

## Service Management

### Check Monitor Status
```bash
systemctl status xray-quota-monitor
```

### View Logs
```bash
# System logs
journalctl -u xray-quota-monitor -f

# Quota event logs
tail -f /var/log/xray-quota-monitor.log
```

### Restart Monitor
```bash
systemctl restart xray-quota-monitor
```

### Stop Monitor (Disable Quota Enforcement)
```bash
systemctl stop xray-quota-monitor
```

### Disable Auto-Start
```bash
systemctl disable xray-quota-monitor
```

## Configuration Files

### Quota Limits Storage
**File:** `/etc/xray/client-quotas.conf`

**Format:** `email|total_bytes|enabled`

**Example:**
```
user1@test.com|10737418240|true
user2@test.com|524288000|true
user3@test.com|1099511627776|false
```

- First field: User email/identifier
- Second field: Quota in bytes (10GB = 10737418240 bytes)
- Third field: Status (true=active, false=disabled)

### Xray Configuration
Users are removed from `/etc/xray/config.json` when quota exceeded. The monitor service removes entries for all protocols:
- VLESS: `#vls`, `#vlsg`, `#vlsx`
- VMESS: `#vms`, `#vmsg`, `#vmsx`
- Trojan: `#tr`, `#trg`
- Shadowsocks: `#ssw`, `#sswg`

## Size Conversion

### Supported Units
- KB (Kilobytes) - `10KB`
- MB (Megabytes) - `500MB`
- GB (Gigabytes) - `10GB`
- TB (Terabytes) - `1TB`

### Conversion Examples
- 1 GB = 1,073,741,824 bytes
- 500 MB = 524,288,000 bytes
- 1 TB = 1,099,511,627,776 bytes

## Troubleshooting

### Quota Not Being Enforced
1. Check if monitor service is running:
   ```bash
   systemctl status xray-quota-monitor
   ```

2. Verify Xray stats API is working:
   ```bash
   xray api stats --server=127.0.0.1:10085
   ```

3. Check logs for errors:
   ```bash
   journalctl -u xray-quota-monitor -n 50
   ```

### User Still Has Access After Quota Exceeded
1. Verify user was removed from config:
   ```bash
   grep "email.*username" /etc/xray/config.json
   ```

2. Check Xray service status:
   ```bash
   systemctl status xray
   ```

3. Manually restart Xray:
   ```bash
   systemctl restart xray
   ```

### Reset User Quota/Usage
To allow a user to use the service again after quota exceeded:

1. Remove and re-add the user account (which resets stats)
2. Or update their quota to a higher limit:
   ```bash
   xray-quota-manager set username 20GB
   ```

### Check Current Usage
The traffic monitor logs when users exceed quotas:
```bash
tail -f /var/log/xray-quota-monitor.log
```

Example log entry:
```
[2024-12-08 15:30:45] Quota exceeded: user1@test.com (10737418240 >= 10737418240 bytes)
[2024-12-08 15:30:46] DISABLED: user1@test.com (quota exceeded)
```

## Best Practices

1. **Set Appropriate Quotas**: Consider typical user usage patterns
   - Light users: 5-10GB/month
   - Medium users: 20-50GB/month
   - Heavy users: 100GB+/month

2. **Monitor Regularly**: Check quota status weekly
   ```bash
   xray-quota-manager list
   ```

3. **Plan for Resets**: Consider implementing monthly quota resets if needed

4. **Keep Logs**: Monitor logs for quota violations to detect abuse

5. **Test Before Production**: Test quota enforcement with a test account

## Integration with Existing Tools

### Compatible Protocols
- ✅ VLESS (WebSocket, gRPC, XHTTP)
- ✅ VMESS (WebSocket, gRPC, XHTTP)
- ✅ Trojan (WebSocket, gRPC)
- ✅ Shadowsocks (WebSocket, gRPC)

### Works With
- Host capture system (already implemented)
- User expiry system (xp.sh)
- Account creation menus
- All existing Xray configurations

## Differences from 3x-ui

While based on 3x-ui's implementation, this system is adapted for bash scripts:

**Similarities:**
- Uses same quota check logic: `(Up + Down) >= Total`
- Periodic monitoring (60-second interval)
- Automatic user disable when exceeded
- Per-user quota limits

**Differences:**
- No web UI (command-line only)
- Simple text file storage instead of database
- Manual quota reset (no automatic monthly reset yet)
- Bash scripts instead of Go backend

## Future Enhancements

Possible improvements:
- Automatic monthly quota resets
- Traffic usage notifications
- Web-based quota management UI
- Integration with Telegram bot for alerts
- Per-protocol quota limits
- Quota usage API endpoint

## Summary

This bandwidth quota system provides:
- ✅ Data quota limits for all Xray protocols
- ✅ Automatic prompts during account creation
- ✅ Background monitoring and enforcement
- ✅ Easy management via command-line tools
- ✅ 3x-ui compatible logic
- ✅ Systemd service integration
- ✅ Comprehensive logging

For questions or issues, refer to the main project documentation or check system logs.
