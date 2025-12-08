# Quick Reference - Bandwidth & Host Capture System

## Installation
```bash
sudo bash install-bandwidth-system.sh
sudo bash test-blocking-system.sh    # 23/23 pass
sudo bash test-integration.sh        # 15/15 pass
```

## Commands
```bash
cek-bw-limit menu                    # Interactive menu
cek-bw-limit add user 1000 ssh       # Set 1GB limit
cek-bw-limit usage user              # Check usage
cek-bw-limit reset user              # Reset & unblock
```

## Services
```bash
systemctl status bw-limit-check      # Bandwidth monitoring
systemctl status host-capture        # Host capture
```

## Files
```
/etc/xray/bw-limit.conf             # Limits
/etc/myvpn/blocked.log              # Blocked users
/etc/myvpn/hosts.log                # Captured hosts
```

## Critical Fix
SSH bandwidth tracking: CONNMARK must be set BEFORE chain jump for proper bidirectional tracking.
