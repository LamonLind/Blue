# Enhanced Bandwidth Monitoring & Host Capture Features

## Overview

This document describes the enhanced features added to the VPN management system including:
- Advanced bandwidth tracking with daily/total/remaining usage
- Automatic SSH account deletion on bandwidth expiry with complete cleanup
- Enhanced host capture with real-time monitoring and IP tracking

## 1. Enhanced Bandwidth Tracking

### New Features

#### Per-User JSON Storage
- Each user now has their own tracking file: `/etc/myvpn/usage/<username>.json`
- Stores daily usage, total usage, limits, and metadata
- Automatic daily reset at midnight

#### Usage Display Enhancement
The bandwidth monitor now shows:
- **Daily Usage**: How much bandwidth used today
- **Total Usage**: Cumulative bandwidth used since account creation/reset
- **Limit**: Configured bandwidth limit
- **Remaining**: How much bandwidth is left
- **Status**: OK, WARNING, EXCEEDED, or UNLIMITED

### JSON Data Structure

Each user's tracking file contains:
```json
{
  "username": "user1",
  "daily_usage": 1048576,
  "total_usage": 5242880,
  "daily_limit": 0,
  "total_limit": 10485760,
  "last_reset": "2024-01-15",
  "last_update": 1705334400,
  "baseline_usage": 0,
  "last_stats": 0
}
```

### Automatic Daily Reset

- Daily usage resets automatically at midnight (00:00)
- Total usage continues to accumulate
- Last reset date is tracked in the JSON file

### Backward Compatibility

- Old format (`/etc/xray/bw-*.conf`) still works
- System automatically uses new format when available
- Both formats can coexist during migration
- Library gracefully handles missing JSON files

## 2. Enhanced SSH Auto-Delete

### Complete Cleanup on Bandwidth Expiry

When an SSH user exceeds their bandwidth limit, the system now:

1. **Removes Linux User**
   - Uses `userdel -r` to delete user AND home directory
   - No orphaned home directories left behind

2. **Cleans Cron Jobs**
   - Removes user's personal crontab (`crontab -u user -r`)
   - Removes references in `/etc/cron.d/` files
   - Prevents lingering automated tasks

3. **Cleans iptables Rules**
   - Removes BW_${uid} chains
   - Removes OUTPUT chain references
   - Prevents orphaned firewall rules

4. **Cleans Tracking Data**
   - Removes from `/etc/xray/bw-limit.conf`
   - Removes from `/etc/xray/bw-usage.conf`
   - Removes from `/etc/xray/bw-last-stats.conf`
   - Removes `/etc/myvpn/usage/<username>.json`

### Monitoring Frequency

- Background service checks every **2 seconds** (not every minute)
- Configured in `/etc/systemd/system/bw-limit-check.service`
- Can be adjusted by editing `sleep 2` in the service file

### Manual Deletion Improvements

The manual SSH user deletion (via menu) now performs the same complete cleanup as automatic deletion.

## 3. Bandwidth Value Consistency

### Upload + Download = Total
- For Xray protocols: Only outbound (upload) traffic is counted
- For SSH: Only OUTPUT chain traffic is counted  
- This ensures consistent measurement across restarts

### Counter Reset Prevention
- Xray stats reset detection prevents data loss on service restart
- Baseline tracking accumulates historical usage
- SSH iptables counters persist until manually reset
- Last known stats tracked to detect anomalies

### Manual Reset Option
- Users can be renewed/reset via menu option 5
- Resets both daily and total counters
- Clears baseline and last stats
- For SSH: zeros iptables counters

## 4. Enhanced Host Capture

### New Storage Location
- Primary: `/etc/myvpn/hosts.log` (as per requirements)
- Backup: `/etc/xray/captured-hosts.txt` (backward compatibility)

### Enhanced Data Capture

For each captured host, the system now records:
- **Host/Domain**: The request host or domain name
- **Service**: SSH, VMESS, VLESS, TROJAN, SNI, Header-Host, Proxy-Host
- **Source IP**: The originating IP address (when available)
- **Timestamp**: When the host was first captured

### Storage Format

New format with IP:
```
example.com|SSH|192.168.1.100|2024-01-15 10:30:45
```

Old format (backward compatible):
```
example.com|SSH|2024-01-15 10:30:45
```

### Deduplication
- Hosts are automatically deduplicated
- Case-insensitive matching
- VPS main domain and IP are automatically excluded
- Localhost and internal addresses are filtered

### Real-Time Monitoring

The capture script scans multiple sources:

1. **SSH Logs** (`/var/log/auth.log` or `/var/log/secure`)
   - Extracts connection hosts and source IPs
   - Identifies hostname vs IP connections

2. **Xray Access Logs** (`/var/log/xray/access.log`)
   - HTTP Host headers
   - SNI (Server Name Indication)
   - Proxy Host headers
   - Destination domains

3. **Nginx Logs** (`/var/log/nginx/access.log`)
   - Host headers
   - X-Forwarded-Host
   - SNI from SSL handshakes

4. **Dropbear Logs**
   - Connection hosts and IPs

### Auto-Capture Service

Enable continuous capture (every 60 seconds):
```bash
# Via menu
menu-captured-hosts -> Option 6

# Or manually
systemctl enable capture-host
systemctl start capture-host
```

### Viewing Captured Hosts

Access via menu:
```bash
menu-captured-hosts
```

Options:
1. View Captured Hosts - Display all captured hosts with details
2. Scan for New Hosts - Manually trigger a scan
3. Add Host Manually - Add a custom host
4. Remove Host - Remove a specific host
5. Clear All Hosts - Clear the entire list
6. Turn ON Auto Capture - Enable continuous monitoring
7. Turn OFF Auto Capture - Disable continuous monitoring

## Installation

### Automatic Installation

The enhanced features are automatically installed during setup:
```bash
bash setup.sh
```

### Manual Installation

If you already have the system installed:

1. **Install bandwidth tracking library:**
```bash
cp bw-tracking-lib.sh /usr/bin/bw-tracking-lib
chmod +x /usr/bin/bw-tracking-lib
```

2. **Create storage directories:**
```bash
mkdir -p /etc/myvpn/usage
chmod 755 /etc/myvpn/usage
```

3. **Update scripts:**
```bash
cp cek-bw-limit.sh /usr/bin/cek-bw-limit
cp capture-host.sh /usr/bin/capture-host
cp menu-captured-hosts.sh /usr/bin/menu-captured-hosts
chmod +x /usr/bin/cek-bw-limit
chmod +x /usr/bin/capture-host
chmod +x /usr/bin/menu-captured-hosts
```

4. **Restart monitoring service:**
```bash
systemctl restart bw-limit-check
```

## Usage Examples

### Setting Bandwidth Limits

```bash
# Set 10GB total limit for a user
cek-bw-limit set username 10240

# Set limit via menu
cek-bw-limit menu
# -> Option 3: Set User Data Limit
```

### Checking Usage

```bash
# Check all users
cek-bw-limit show

# Check specific user
cek-bw-limit usage username

# Via menu
cek-bw-limit menu
# -> Option 1: Show All Users + Usage + Limits
```

### Resetting Usage

```bash
# Reset specific user
cek-bw-limit reset username

# Reset all users
cek-bw-limit reset-all

# Via menu
cek-bw-limit menu
# -> Option 5: Reset User Usage (Renew)
```

### Viewing Captured Hosts

```bash
# Via menu
menu-captured-hosts

# Manual scan
/usr/bin/capture-host
```

## Troubleshooting

### Bandwidth Not Updating

1. Check service status:
```bash
systemctl status bw-limit-check
```

2. Check if library is installed:
```bash
ls -la /usr/bin/bw-tracking-lib
```

3. Check JSON files:
```bash
ls -la /etc/myvpn/usage/
cat /etc/myvpn/usage/<username>.json
```

4. Restart service:
```bash
systemctl restart bw-limit-check
```

### SSH User Not Deleted

1. Check logs:
```bash
journalctl -u bw-limit-check -n 50
```

2. Manual deletion test:
```bash
/usr/bin/cek-bw-limit check
```

3. Verify user has limit:
```bash
grep username /etc/xray/bw-limit.conf
```

### Hosts Not Capturing

1. Check log files exist:
```bash
ls -la /var/log/auth.log
ls -la /var/log/xray/access.log
```

2. Manual capture:
```bash
/usr/bin/capture-host
```

3. Check output file:
```bash
cat /etc/myvpn/hosts.log
```

4. Check auto-capture service:
```bash
systemctl status capture-host
```

## System Requirements

- Ubuntu 20.04 - 24.04 LTS
- Root access
- Xray installed and configured
- Systemd for service management
- Standard logging enabled (rsyslog or similar)

## Performance Impact

- **Bandwidth Monitoring**: Negligible (checks every 2 seconds using API calls)
- **Host Capture**: Minimal (reads log files, no network overhead)
- **JSON Storage**: Faster than flat file parsing for individual user lookups
- **Auto-Capture Service**: Low CPU usage (60 second intervals)

## Security Considerations

1. **JSON Files**: Stored in `/etc/myvpn/usage/` with 755 permissions
2. **Host Log**: Stored in `/etc/myvpn/hosts.log` with standard permissions
3. **User Deletion**: Completely removes user data, preventing data leaks
4. **Cron Cleanup**: Prevents unauthorized scheduled tasks from persisting

## Migration from Old System

The system maintains backward compatibility:

1. Old tracking files (`/etc/xray/bw-*.conf`) continue to work
2. New JSON files are created as users are accessed
3. Both systems can run simultaneously
4. No data loss during transition
5. Old host file (`/etc/xray/captured-hosts.txt`) still accessible

To fully migrate:
1. Let the system run for 24-48 hours
2. Verify new JSON files are created for active users
3. Old files can be archived (not deleted) for reference

## Known Limitations

1. Daily reset happens at system midnight (not configurable timezone yet)
2. Historical daily usage is not retained (only current day)
3. IP capture depends on log format (may show N/A for some services)
4. Host capture quality depends on log verbosity settings

## Future Enhancements

Possible improvements for future versions:
- Timezone-aware daily reset
- Historical usage graphs
- Bandwidth usage alerts via email/telegram
- Per-protocol bandwidth limits
- Traffic shaping integration
- Export to CSV/JSON for analysis
