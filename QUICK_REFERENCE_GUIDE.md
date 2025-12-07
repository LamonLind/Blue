# Quick Reference Guide - VPN Script Features

## Fast Access Commands

### Bandwidth Management
```bash
# Set bandwidth limit for a user
cek-bw-limit set <username> <limit_mb> <type>
# Examples:
cek-bw-limit set john 5000 ssh      # 5GB limit for SSH user
cek-bw-limit set alice 10000 vless  # 10GB limit for VLESS user

# Check user bandwidth usage
cek-bw-limit usage <username>

# View all users with limits
cek-bw-limit list

# Reset user bandwidth (renew)
cek-bw-limit reset <username>

# Remove bandwidth limit
cek-bw-limit remove <username>

# Interactive menu
cek-bw-limit menu
# Or from main menu: Option 17 "CEK BANDWIDTH USE"
```

### Captured Hosts
```bash
# View captured hosts menu
menu-captured-hosts
# Or from main menu: Option 27 "CAPTURED HOSTS"

# View hosts log file directly
cat /etc/myvpn/hosts.log

# Check host capture service
systemctl status host-capture

# Real-time host monitor
/usr/bin/realtime-hosts
```

### SSH Account Management
```bash
# Create new SSH user (from menu)
menu-ssh  # Then option 1

# Delete SSH user (from menu)
menu-ssh  # Then option 2

# Delete SSH user directly (with full cleanup)
# This is done automatically when bandwidth limit exceeded
```

### Service Management
```bash
# Bandwidth limit checker service
systemctl status bw-limit-check
systemctl restart bw-limit-check
systemctl enable bw-limit-check

# Host capture service
systemctl status host-capture
systemctl restart host-capture  
systemctl enable host-capture

# View service logs
journalctl -u bw-limit-check -f
journalctl -u host-capture -f
```

## Important File Locations

### Bandwidth Tracking
- **User limits**: `/etc/xray/bw-limit.conf`
- **Usage data (old)**: `/etc/xray/bw-usage.conf`
- **Per-user JSON (new)**: `/etc/myvpn/usage/<username>.json`
- **Deletion log**: `/etc/myvpn/deleted.log`

### Host Capture
- **Captured hosts**: `/etc/myvpn/hosts.log`
- **Old location**: `/etc/xray/captured-hosts.txt` (backward compatibility)

### Configuration
- **Xray config**: `/etc/xray/config.json`
- **Domain**: `/etc/xray/domain`
- **Service files**: `/etc/systemd/system/`

## Common Tasks

### 1. Set Bandwidth Limit for New User
```bash
# After creating user, set limit
cek-bw-limit set username 5000 ssh     # For SSH users
cek-bw-limit set username 10000 vmess  # For VMESS users
cek-bw-limit set username 10000 vless  # For VLESS users
cek-bw-limit set username 10000 trojan # For Trojan users
cek-bw-limit set username 10000 ssws   # For Shadowsocks users
```

### 2. Monitor Bandwidth Usage
```bash
# Real-time monitoring (updates every 2 seconds)
/usr/bin/realtime-bandwidth

# One-time check
cek-bw-limit show

# Check specific user
cek-bw-limit usage username
```

### 3. Check Deleted Users
```bash
# View deletion log
cat /etc/myvpn/deleted.log

# View recent deletions
tail -20 /etc/myvpn/deleted.log

# Watch for new deletions (real-time)
tail -f /etc/myvpn/deleted.log
```

### 4. View Captured Hosts
```bash
# Interactive menu
menu-captured-hosts

# Real-time monitor
/usr/bin/realtime-hosts

# View raw log
cat /etc/myvpn/hosts.log

# Count unique hosts
cat /etc/myvpn/hosts.log | cut -d'|' -f1 | sort -u | wc -l
```

### 5. Troubleshooting

#### Service Not Running
```bash
# Check status
systemctl status bw-limit-check
systemctl status host-capture

# Restart services
systemctl restart bw-limit-check
systemctl restart host-capture

# Check logs
journalctl -u bw-limit-check --since "1 hour ago"
journalctl -u host-capture --since "1 hour ago"
```

#### Bandwidth Not Tracking
```bash
# Check if iptables is available
which iptables
iptables -L -n

# Check Xray API
/usr/local/bin/xray api statsquery --server=127.0.0.1:10085

# Verify user has bandwidth limit set
grep username /etc/xray/bw-limit.conf
```

#### Hosts Not Being Captured
```bash
# Check service
systemctl status host-capture

# Manually run capture once
/usr/bin/capture-host

# Check Xray is running
systemctl status xray

# Check nginx is running  
systemctl status nginx
```

## Service Intervals

### Background Services
- **Bandwidth Checker**: Every 2 seconds
- **Host Capture**: Every 2 seconds
- **CPU Impact**: Minimal (both use safe 2-second sleep)

### Display Updates
- **Real-time Bandwidth Monitor**: Data every 2s, display refresh every 0.1s
- **Real-time Host Monitor**: Data every 2s, display refresh every 0.1s

## Automatic Features

### Auto-Delete on Bandwidth Expiry
- **Trigger**: When user exceeds bandwidth limit
- **Affected Protocols**: SSH, VLESS, VMESS, Trojan, Shadowsocks
- **Actions Performed**:
  - Delete user account
  - Remove home directory
  - Remove SSH keys
  - Remove cron jobs
  - Remove usage files
  - Remove database entries
  - Log to /etc/myvpn/deleted.log

### Auto-Capture Hosts
- **Frequency**: Every 2 seconds
- **Protocols Monitored**: SSH, VLESS, VMESS, Trojan, Shadowsocks
- **Duplicate Prevention**: Yes (case-insensitive)
- **Storage**: /etc/myvpn/hosts.log

## Menu Structure

### Main Menu (menu.sh)
- **Option 1**: SSH Menu
- **Option 2**: VMESS Menu
- **Option 3**: VLESS Menu
- **Option 4**: TROJAN Menu
- **Option 5**: Shadowsocks Menu
- **Option 17**: Bandwidth Usage Monitor
- **Option 27**: Captured Hosts Menu

### Bandwidth Menu (Option 17)
- **Option 1**: Show all users with usage
- **Option 2**: Check single user
- **Option 3**: Set user limit
- **Option 4**: Remove user limit
- **Option 5**: Reset user usage
- **Option 6**: Reset all users
- **Option 7**: Disable user
- **Option 8**: Enable user
- **Option 9**: Check service status
- **Option 10**: Real-time bandwidth monitor

### Captured Hosts Menu (Option 27)
- **Option 1**: View captured hosts
- **Option 2**: Scan for new hosts
- **Option 3**: Add host manually
- **Option 4**: Remove host
- **Option 5**: Clear all hosts
- **Option 6**: Turn ON auto capture
- **Option 7**: Turn OFF auto capture
- **Option 8**: Real-time host monitor

## Data Formats

### Bandwidth Limit File Format
```
username limit_mb account_type
john 5000 ssh
alice 10000 vless
```

### Captured Hosts Format
```
host|service|source_ip|timestamp
example.com|SSH|192.168.1.100|2024-12-07 10:30:45
cdn.example.com|VLESS|192.168.1.101|2024-12-07 10:35:22
```

### Deletion Log Format
```
timestamp | protocol | username | reason
2024-12-07 10:30:45 | SSH | testuser | Bandwidth limit exceeded - Account deleted
```

### JSON Bandwidth Data (per user)
```json
{
  "username": "john",
  "daily_usage": 1048576,
  "total_usage": 5242880,
  "daily_limit": 0,
  "total_limit": 10737418240,
  "last_reset": "2024-12-07",
  "last_update": 1701943845,
  "baseline_usage": 0,
  "last_stats": 1048576
}
```

## Best Practices

### 1. Set Reasonable Limits
- Consider user needs
- Account for both upload and download
- Monitor usage before setting strict limits

### 2. Regular Monitoring
- Check deletion log weekly
- Review captured hosts monthly
- Verify services are running daily

### 3. Backup Important Data
- Backup before major changes
- Keep deletion log for audit trail
- Archive captured hosts periodically

### 4. Service Maintenance
- Restart services after Xray updates
- Check logs after system updates
- Verify iptables rules after firewall changes

---

**Quick Start**: After installation, services start automatically. Use `menu` command to access all features.
**Support**: Check logs with `journalctl` for troubleshooting.
**Documentation**: See IMPLEMENTATION_FINAL_SUMMARY.md for complete details.
