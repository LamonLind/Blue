# Quick Reference - Bandwidth Blocking System

## Common Commands

### View User Status
```bash
# Check single user
/usr/bin/cek-bw-limit usage <username>

# View all users
/usr/bin/cek-bw-limit list

# View only blocked users
/usr/bin/cek-bw-limit menu
# Select option 12
```

### Block/Unblock Users
```bash
# Manual unblock
/usr/bin/cek-bw-limit menu
# Select option 11

# Automatic unblock (via renewal)
/usr/bin/cek-bw-limit reset <username>
```

### Set Bandwidth Limits
```bash
# Set limit in MB
/usr/bin/cek-bw-limit set <username> <limit_mb>

# Examples
/usr/bin/cek-bw-limit set john 10240    # 10GB
/usr/bin/cek-bw-limit set user1 5120    # 5GB
```

### Service Management
```bash
# Check service status
systemctl status bw-limit-check
systemctl status host-capture

# Restart services
systemctl restart bw-limit-check
systemctl restart host-capture

# View logs
journalctl -u bw-limit-check -n 50 -f
tail -f /etc/myvpn/blocked.log
tail -f /etc/myvpn/hosts.log
```

## User Status Types

| Status | Meaning | Color |
|--------|---------|-------|
| ACTIVE | Within bandwidth limit | Green |
| BLOCKED | Exceeded limit, network blocked | Red |
| WARNING | Over 80% of limit | Yellow |
| UNLIMITED | No limit set | Green |

## File Locations

### Configuration
- `/etc/xray/bw-limit.conf` - Bandwidth limits per user
- `/etc/xray/bw-usage.conf` - Current usage baseline
- `/etc/xray/bw-last-stats.conf` - Last known stats

### JSON Tracking
- `/etc/myvpn/usage/<username>.json` - Per-user detailed data

### Logs
- `/etc/myvpn/blocked.log` - Blocking events log
- `/etc/myvpn/hosts.log` - Captured hosts log
- `/etc/myvpn/deleted.log` - Legacy deletion log

### Blocking Data
- `/etc/myvpn/blocked_users/<username>` - Block marker files

## Menu Options

```
[1]  Show All Users + Usage + Limits + Status
[2]  Check Single User Usage
[3]  Set User Data Limit
[4]  Remove User Limit
[5]  Reset User Usage (Renew) - Also unblocks
[6]  Reset All Users Usage
[7]  Disable User
[8]  Enable User
[9]  Check Bandwidth Service Status
[10] Real-time Bandwidth Monitor
[11] Unblock User (Manual Unblock) ← NEW
[12] View Blocked Users ← NEW
```

## Troubleshooting

### User Can't Connect After Block
```bash
# Check if actually blocked
/usr/bin/cek-bw-limit usage <username>

# Verify iptables rules (SSH)
iptables -L OUTPUT -v -n | grep BW_

# Check marker file (Xray)
ls -la /etc/myvpn/blocked_users/

# Unblock manually
/usr/bin/cek-bw-limit menu → Option 11
```

### Unblock Not Working
```bash
# For SSH users - manually remove rules
UID=$(id -u <username>)
iptables -D OUTPUT -m owner --uid-owner $UID -j DROP
iptables -D INPUT -m connmark --mark $UID -j DROP

# For Xray users - remove marker
rm -f /etc/myvpn/blocked_users/<username>

# Reset usage to auto-unblock
/usr/bin/cek-bw-limit reset <username>
```

### Service Not Running
```bash
# Start service
systemctl start bw-limit-check

# Enable auto-start
systemctl enable bw-limit-check

# Check for errors
journalctl -u bw-limit-check -xe
```

## Host Capture Commands

### View Captured Hosts
```bash
# Via menu
/usr/bin/menu-captured-hosts

# Direct view
cat /etc/myvpn/hosts.log

# Filter by protocol
grep "VLESS" /etc/myvpn/hosts.log
grep "SNI" /etc/myvpn/hosts.log
```

### Manual Host Scan
```bash
# Trigger scan
/usr/bin/capture-host

# View results
tail -n 20 /etc/myvpn/hosts.log
```

### Real-time Host Monitor
```bash
# Launch monitor
/usr/bin/realtime-hosts

# Or use menu
/usr/bin/menu-captured-hosts → Option 8
```

## Emergency Procedures

### Clear All Blocks
```bash
# Remove all iptables DROP rules
iptables -F OUTPUT
iptables -F INPUT

# Remove all marker files
rm -rf /etc/myvpn/blocked_users/*

# Restart service
systemctl restart bw-limit-check
```

### Reset Bandwidth Tracking
```bash
# Reset single user
/usr/bin/cek-bw-limit reset <username>

# Reset all users
/usr/bin/cek-bw-limit reset-all
```

### Disable Bandwidth Checking
```bash
# Stop service
systemctl stop bw-limit-check

# Disable auto-start
systemctl disable bw-limit-check
```

## Best Practices

1. **Regular Monitoring**: Check blocked users daily using option 12
2. **Set Realistic Limits**: Based on server capacity and user needs
3. **Communicate with Users**: Inform about limits and renewal process
4. **Review Logs**: Check `/etc/myvpn/blocked.log` for patterns
5. **Backup Tracking**: Backup `/etc/myvpn/usage/` directory regularly

## Support

For detailed information, refer to:
- `BANDWIDTH_BLOCKING_GUIDE.md` - Complete blocking system guide
- `HOST_CAPTURE_GUIDE.md` - Complete host capture guide
- `IMPLEMENTATION_FINAL.md` - Implementation details

---

**Note**: All blocking operations preserve user accounts and data. Users can be easily unblocked by resetting their bandwidth usage.
