# Bandwidth Limiting System - Complete Guide

## Overview

This implementation provides comprehensive bandwidth limiting for both **Xray** and **SSH** services, inspired by the [3x-ui](https://github.com/MHSanaei/3x-ui) project.

### Features

#### Xray Bandwidth Limiting (3x-ui Style)
- **Per-client data quotas** using `totalGB` field
- Real-time traffic monitoring via Xray Stats API
- Automatic client disabling when quota exceeded
- Client usage tracking (upload + download)
- Easy reset and quota management

#### SSH Bandwidth Limiting (cgroups v2)
- **Smart quota system**: Users start UNLIMITED
- Automatic rate limiting (30kbps) when quota exceeded (500MB default)
- Kernel-level enforcement using cgroups v2
- Per-user traffic accounting with iptables
- Three states: UNLIMITED, LIMITED, RESET
- Persistent usage data across reboots

## Installation

### Quick Install

```bash
chmod +x install-bandwidth-limiter.sh
./install-bandwidth-limiter.sh
```

### What Gets Installed

1. **System Dependencies**
   - iptables, iproute2, jq, bc
   - coreutils, procps, net-tools

2. **Golang** (if not already installed)
   - Version 1.21.5
   - Added to PATH automatically

3. **Xray Bandwidth Limiter**
   - Script: `/usr/local/bin/xray-bw-limit`
   - Database: `/etc/xray/client-limits.db`
   - Service: `xray-bw-monitor.service`
   - Logs: `/var/log/xray-bandwidth.log`

4. **SSH Bandwidth Limiter**
   - Script: `/usr/local/bin/ssh-limiter.sh`
   - Config: `/etc/ssh-limiter.conf`
   - Database: `/var/lib/ssh-limiter/usage.db`
   - Service: `ssh-limiter.service`
   - Logs: `/var/log/ssh-limiter.log`

5. **Interactive Menu**
   - Command: `bandwidth-manager`

## Usage

### Interactive Menu

The easiest way to manage bandwidth limits is through the interactive menu:

```bash
bandwidth-manager
```

### Xray Bandwidth Management

#### Add Bandwidth Limit to Client

```bash
# Limit client to 10GB total data
xray-bw-limit add-limit user@example.com vmess 10

# Unlimited bandwidth (0 = no limit)
xray-bw-limit add-limit premium@example.com vless 0
```

**Supported Protocols:**
- vmess
- vless
- trojan
- shadowsocks

#### Check Client Status

```bash
xray-bw-limit status
```

Example output:
```
=== Xray Client Bandwidth Status ===

EMAIL                     PROTOCOL     LIMIT (GB)   USAGE (GB)   STATE
-----                     --------     ----------   -----------  -----
user@example.com          vmess        10GB         7.32GB       UNLIMITED
blocked@example.com       vless        5GB          5.12GB       LIMITED
premium@example.com       trojan       UNLIMITED    45.67GB      UNLIMITED
```

#### Reset Client Usage

```bash
# Reset usage to 0 and re-enable client
xray-bw-limit reset-usage user@example.com
```

#### Remove Bandwidth Limit

```bash
xray-bw-limit remove-limit user@example.com
```

#### Manual Check

Force an immediate check of all limits:

```bash
xray-bw-limit check
```

### SSH Bandwidth Management

#### Add User to Monitoring

```bash
# Add user with default quota (500MB) and limit (30kbps)
ssh-limiter.sh add-user vpnuser1
```

**User States:**
- **UNLIMITED**: User has not exceeded quota (0-500MB usage)
- **LIMITED**: User exceeded quota (500MB+), bandwidth limited to 30kbps
- **RESET**: Usage reset by admin (back to UNLIMITED)

#### Check User Status

```bash
ssh-limiter.sh status
```

Example output:
```
=== SSH Bandwidth Limiter Status ===

Daemon: Running (PID: 12345)

Monitored Users:

USERNAME        QUOTA      USAGE      STATE           LIMIT
--------        -----      -----      -----           -----
vpnuser1        500MB      234MB      UNLIMITED       30kbps
vpnuser2        500MB      523MB      LIMITED         30kbps
vpnuser3        1000MB     456MB      UNLIMITED       30kbps
```

#### Reset User Usage

```bash
# Reset usage to 0, remove bandwidth limit, back to UNLIMITED state
ssh-limiter.sh reset-user vpnuser1
```

#### Custom Bandwidth Limit

```bash
# Set custom limit for specific user
ssh-limiter.sh set-limit vpnuser2 50   # 50kbps
```

#### Custom Quota

```bash
# Change quota threshold
ssh-limiter.sh set-quota vpnuser3 1000  # 1000MB = 1GB
```

#### Remove User from Monitoring

```bash
ssh-limiter.sh remove-user vpnuser1
```

#### View Logs

```bash
# View last 50 lines
ssh-limiter.sh view-logs

# View last 100 lines
ssh-limiter.sh view-logs 100
```

## Configuration

### SSH Limiter Configuration

Edit `/etc/ssh-limiter.conf`:

```bash
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
```

### How It Works

#### Xray Bandwidth Limiting

1. **Client Creation**: When creating Xray clients through menus, set `totalGB` field
2. **Traffic Monitoring**: Daemon queries Xray Stats API every 30 seconds
3. **Enforcement**: When client exceeds quota:
   - Client is disabled in Xray config
   - Xray service is reloaded
   - Client cannot connect until reset
4. **Reset**: Admin can reset usage, re-enabling the client

#### SSH Bandwidth Limiting

1. **Initial State**: User added with UNLIMITED state (no bandwidth restrictions)
2. **Traffic Tracking**: iptables tracks all traffic (upload + download) per user UID
3. **Quota Check**: Daemon checks every 30 seconds
4. **Limit Enforcement**: When user exceeds quota (e.g., 500MB):
   - User state changes to LIMITED
   - TC (traffic control) applies 30kbps bandwidth limit
   - User processes assigned to cgroup
   - Limit persists for all current and future sessions
5. **Persistence**: Usage data saved in `/var/lib/ssh-limiter/usage.db`

## Systemd Services

### Enable Services on Boot

```bash
# Enable Xray monitoring
systemctl enable xray-bw-monitor

# Enable SSH monitoring
systemctl enable ssh-limiter
```

### Start Services

```bash
# Start Xray monitoring
systemctl start xray-bw-monitor

# Start SSH monitoring
systemctl start ssh-limiter
```

### Check Service Status

```bash
# Check Xray monitor
systemctl status xray-bw-monitor

# Check SSH monitor
systemctl status ssh-limiter
```

### View Service Logs

```bash
# Xray monitor logs
journalctl -u xray-bw-monitor -f

# SSH monitor logs
journalctl -u ssh-limiter -f
```

## Advanced Usage

### Bulk User Management

Add multiple SSH users at once during installation:

```bash
ssh-limiter.sh install vpnuser1,vpnuser2,vpnuser3
```

### Database Files

#### Xray Client Limits Database

Location: `/etc/xray/client-limits.db`

Format: `email|protocol|total_gb|baseline_bytes|state|last_check`

Example:
```
user@example.com|vmess|10|0|UNLIMITED|1702056789
blocked@example.com|vless|5|5368709120|LIMITED|1702056789
```

#### SSH Usage Database

Location: `/var/lib/ssh-limiter/usage.db`

Format: `username|quota_mb|limit_kbps|current_usage_bytes|state|last_updated`

Example:
```
vpnuser1|500|30|245760000|UNLIMITED|1702056789
vpnuser2|500|30|548576000|LIMITED|1702056789
```

### Integration with Existing Scripts

#### Adding Xray Client with Bandwidth Limit

From your existing Xray client creation scripts:

```bash
# After creating client in Xray config
xray-bw-limit add-limit "$client_email" "$protocol" "$total_gb"
```

#### Adding SSH User with Monitoring

From your existing SSH user creation scripts:

```bash
# After creating SSH user
ssh-limiter.sh add-user "$username"
```

## Troubleshooting

### Xray Bandwidth Limiter

**Problem**: Clients not being limited

1. Check if monitoring daemon is running:
   ```bash
   systemctl status xray-bw-monitor
   ```

2. Check Xray API is accessible:
   ```bash
   curl -X POST http://127.0.0.1:10085 -d '{"command":"QueryStats"}'
   ```

3. Check logs:
   ```bash
   tail -f /var/log/xray-bandwidth.log
   ```

**Problem**: Client limits not applying after reset

- Ensure Xray service reloaded:
  ```bash
  systemctl reload xray
  ```

### SSH Bandwidth Limiter

**Problem**: User still has full speed after exceeding quota

1. Check if daemon is running:
   ```bash
   systemctl status ssh-limiter
   ```

2. Check iptables rules exist:
   ```bash
   iptables -L -v -n | grep SSH_TRACK
   ```

3. Check tc (traffic control) rules:
   ```bash
   tc qdisc show
   tc class show
   ```

4. Check user state:
   ```bash
   ssh-limiter.sh status
   ```

**Problem**: Usage not being tracked

1. Verify iptables tracking initialized:
   ```bash
   iptables -L OUTPUT -v -n | grep <uid>
   ```

2. Check logs:
   ```bash
   tail -f /var/log/ssh-limiter.log
   ```

### Common Issues

**cgroups v2 not available**

Some systems may not have cgroups v2 enabled. Check:

```bash
mount | grep cgroup
```

If using cgroups v1, you may need to update your kernel or enable cgroups v2:

```bash
# Add to kernel parameters
GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=1"
```

## Uninstallation

### Remove SSH Limiter

```bash
ssh-limiter.sh uninstall
```

This will:
- Stop monitoring daemon
- Remove all bandwidth limits
- Remove systemd service
- Optionally remove config and logs

### Remove Xray Limiter

```bash
# Stop service
systemctl stop xray-bw-monitor
systemctl disable xray-bw-monitor

# Remove files
rm -f /usr/local/bin/xray-bw-limit
rm -f /etc/systemd/system/xray-bw-monitor.service
rm -f /etc/xray/client-limits.db
systemctl daemon-reload
```

## Security Considerations

1. **Root Access**: Both scripts require root access for iptables and tc manipulation
2. **Log Files**: Contain user traffic data, ensure proper permissions
3. **Database Files**: Contain user information, stored with restricted permissions
4. **Email Alerts**: Configure `ALERT_EMAIL` to receive notifications of limit violations

## Performance

- **Xray Monitor**: Checks every 30 seconds, minimal CPU usage
- **SSH Monitor**: Checks every 30 seconds, minimal CPU usage
- **iptables**: Efficient kernel-level tracking, negligible overhead
- **TC (Traffic Control)**: Kernel-level bandwidth shaping, minimal overhead

## Credits

- Based on [3x-ui](https://github.com/MHSanaei/3x-ui) bandwidth limiting approach
- Inspired by LamonLind/Blue existing bandwidth monitoring system
- Uses cgroups v2 for modern kernel-level process management

## License

MIT License - See repository for full license text

## Support

For issues or questions:
1. Check logs: `/var/log/xray-bandwidth.log` and `/var/log/ssh-limiter.log`
2. Review systemd journal: `journalctl -u xray-bw-monitor` or `journalctl -u ssh-limiter`
3. Use interactive menu: `bandwidth-manager`
4. Check status: `xray-bw-limit status` or `ssh-limiter.sh status`
