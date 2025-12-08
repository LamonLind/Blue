# Bandwidth Manager - Quick Reference Card

## 🚀 Quick Start

### Creating Accounts with Bandwidth Limits
When creating any account, you'll be prompted:
```
Bandwidth Limit (MB, 0 for unlimited): 
```
- Enter limit in MB (e.g., `5000` for 5GB)
- Enter `0` for unlimited
- Limit is set automatically - no extra steps needed!

### Accessing Bandwidth Manager
From main menu, select option **28** for full bandwidth management.

## 📊 Menu Options Quick Reference

| Option | Function | Use When |
|--------|----------|----------|
| **1** | Show all users + usage + limits + status | Want to see overview of all users |
| **2** | Check single user usage | Want details on one specific user |
| **3** | Set user data limit | Need to add/change limit for existing user |
| **4** | Remove user limit | Want to make user unlimited |
| **5** | Reset user usage (renew) | Monthly renewal or user paid for more data |
| **6** | Reset all users | Start of new billing cycle |
| **7** | Disable user | Manually block a user |
| **8** | Enable user | Unblock a manually disabled user |
| **9** | Check service status | Verify bandwidth monitoring is running |
| **10** | Real-time monitor | Watch live bandwidth usage |
| **11** | Unblock user manually | User blocked but should have access |
| **12** | View blocked users | See who's currently blocked |
| **13** | Debug diagnostics | Troubleshooting issues |

## 💻 Command Line Quick Reference

```bash
# Add/update limit
cek-bw-limit add <user> <MB> <type>

# Check usage
cek-bw-limit usage <user>

# Reset user (renew)
cek-bw-limit reset <user>

# List all users
cek-bw-limit list

# Remove limit
cek-bw-limit remove <user>

# Open menu
cek-bw-limit menu
```

## 🔢 Common Bandwidth Limits (in MB)

| Limit | MB Value |
|-------|----------|
| 500 MB | `500` |
| 1 GB | `1000` |
| 2 GB | `2000` |
| 5 GB | `5000` |
| 10 GB | `10000` |
| 20 GB | `20000` |
| 50 GB | `50000` |
| 100 GB | `100000` |
| Unlimited | `0` |

## ⚡ Common Tasks

### Monthly Renewal
```bash
# From menu: Option 28 → Option 6 (Reset all users)
# Or command line:
cek-bw-limit reset-all
```

### Check Who's Blocked
```bash
# From menu: Option 28 → Option 12
# Files located in: /etc/myvpn/blocked_users/
```

### Unblock a User
```bash
# From menu: Option 28 → Option 5 (Reset usage)
# Or: Option 28 → Option 11 (Manual unblock)
# Or command line:
cek-bw-limit reset <username>
```

### Change User's Limit
```bash
# From menu: Option 28 → Option 3
# Or command line:
cek-bw-limit set <username> <new_limit_MB>
```

### Make User Unlimited
```bash
# From menu: Option 28 → Option 4
# Or command line:
cek-bw-limit remove <username>
```

## 🔍 Monitoring

### View All Users
```bash
# From menu: Option 28 → Option 1
cek-bw-limit list
```

### Real-time Monitoring
```bash
# From menu: Option 28 → Option 10
realtime-bandwidth
```

### Check Service Status
```bash
# From menu: Option 28 → Option 9
# Or command line:
systemctl status bw-limit-check
```

## ⚠️ Troubleshooting

### Service Not Running
```bash
systemctl status bw-limit-check
systemctl restart bw-limit-check
```

### Enable Debug Mode
```bash
export DEBUG_MODE=1
systemctl restart bw-limit-check
tail -f /var/log/bw-limit-debug.log
```

### User Not Being Blocked
1. Check if limit set: `cek-bw-limit list`
2. Check service running: `systemctl status bw-limit-check`
3. Check debug logs: Option 28 → Option 13

## 📝 Important Notes

✅ **Set limits during account creation** - easiest method  
✅ **Limits in MB** - multiply GB by 1000 (5GB = 5000 MB)  
✅ **Blocking preserves accounts** - users not deleted, just blocked  
✅ **Automatic monitoring** - runs every 2 seconds in background  
✅ **Monthly resets** - use option 6 for billing cycles  

## 🎯 Best Practices

1. **Set limits during creation** - saves time
2. **Use menu for management** - easier than command line
3. **Reset monthly** - keeps billing organized
4. **Monitor regularly** - check option 1 weekly
5. **Debug only when needed** - adds overhead

## 📍 File Locations

```
/usr/bin/cek-bw-limit              # Main script
/etc/xray/bw-limit.conf            # User limits
/etc/myvpn/blocked_users/          # Blocked user markers
/var/log/bw-limit-debug.log        # Debug log
```

## 🆘 Quick Help

```bash
# Open bandwidth manager
menu
# Select 28

# Or directly:
cek-bw-limit menu
```

---
**Need detailed help?** See `BANDWIDTH_SYSTEM_SETUP.md`
