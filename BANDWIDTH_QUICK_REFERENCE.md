# Bandwidth Limiting - Quick Reference

## Installation

```bash
chmod +x install-bandwidth-limiter.sh
./install-bandwidth-limiter.sh
```

## Interactive Menu

```bash
bandwidth-manager
```

## Xray Quick Commands

```bash
# Add 10GB limit to client
xray-bw-limit add-limit user@example.com vmess 10

# Check status
xray-bw-limit status

# Reset client (re-enable + reset usage)
xray-bw-limit reset-usage user@example.com

# Remove limit
xray-bw-limit remove-limit user@example.com

# Force check now
xray-bw-limit check
```

## SSH Quick Commands

```bash
# Add user to monitoring (500MB quota, 30kbps limit when exceeded)
ssh-limiter.sh add-user vpnuser1

# Check status
ssh-limiter.sh status

# Reset user (back to UNLIMITED, usage = 0)
ssh-limiter.sh reset-user vpnuser1

# Custom limit
ssh-limiter.sh set-limit vpnuser1 50     # 50kbps

# Custom quota
ssh-limiter.sh set-quota vpnuser1 1000   # 1000MB = 1GB

# Remove from monitoring
ssh-limiter.sh remove-user vpnuser1

# View logs
ssh-limiter.sh view-logs 100
```

## Service Management

```bash
# Start services
systemctl start xray-bw-monitor
systemctl start ssh-limiter

# Enable on boot
systemctl enable xray-bw-monitor
systemctl enable ssh-limiter

# Check status
systemctl status xray-bw-monitor
systemctl status ssh-limiter

# View logs
journalctl -u xray-bw-monitor -f
journalctl -u ssh-limiter -f
```

## Configuration Files

```bash
# SSH configuration
/etc/ssh-limiter.conf

# Databases
/etc/xray/client-limits.db
/var/lib/ssh-limiter/usage.db

# Logs
/var/log/xray-bandwidth.log
/var/log/ssh-limiter.log
```

## User States

### Xray Clients
- **UNLIMITED**: No quota exceeded, client can connect
- **LIMITED**: Quota exceeded, client disabled (cannot connect)

### SSH Users
- **UNLIMITED**: Usage < quota (500MB), full speed
- **LIMITED**: Usage >= quota (500MB), limited to 30kbps
- **RESET**: Admin reset usage, back to UNLIMITED

## Default Settings

### Xray
- Default quota: Set when adding limit (0 = unlimited)
- Check interval: 30 seconds

### SSH
- Default quota: 500MB
- Default limit: 30kbps (when quota exceeded)
- Check interval: 30 seconds

## Examples

### Xray: Limit client with MB or GB
```bash
# Small quota: 100MB
xray-bw-limit add-limit user@example.com vmess 100MB

# Medium quota: 500MB
xray-bw-limit add-limit user2@example.com vless 500M

# Large quota: 5GB
xray-bw-limit add-limit premium@example.com vless 5GB
```

### SSH: Monitor 3 users
```bash
ssh-limiter.sh add-user vpnuser1
ssh-limiter.sh add-user vpnuser2
ssh-limiter.sh add-user vpnuser3
```

### SSH: Reset heavy user
```bash
ssh-limiter.sh reset-user vpnuser2
```

### SSH: Custom settings
```bash
ssh-limiter.sh set-quota vpnuser1 2000  # 2GB quota
ssh-limiter.sh set-limit vpnuser1 100   # 100kbps when exceeded
```

## Troubleshooting

### Check if daemons running
```bash
systemctl status xray-bw-monitor
systemctl status ssh-limiter
```

### Check iptables rules
```bash
iptables -L -v -n | grep SSH_TRACK
```

### Check TC rules
```bash
tc qdisc show
tc class show
```

### Check logs
```bash
tail -f /var/log/xray-bandwidth.log
tail -f /var/log/ssh-limiter.log
```

### Force immediate check
```bash
xray-bw-limit check
ssh-limiter.sh status
```

## Support

Full documentation:
- `/path/to/BANDWIDTH_LIMITER_GUIDE.md`
- `/path/to/BANDWIDTH_IMPLEMENTATION_DETAILS.md`
