# Quick Reference: Real-time Monitoring Features

## 🚀 Quick Start

### View Real-time Bandwidth (10ms updates):
```bash
cek-bw-limit menu
# Select option 10
```

### View Real-time Hosts (10ms updates):
```bash
menu-captured-hosts
# Select option 8
```

---

## 📊 Command Line Usage

### Bandwidth Management:
```bash
# Set limit for a user
cek-bw-limit set john 1024

# Check user usage
cek-bw-limit usage john

# Reset user bandwidth (renew account)
cek-bw-limit reset john

# Remove limit
cek-bw-limit remove john

# View all users
cek-bw-limit list
```

### Host Capture:
```bash
# Scan for hosts now
/usr/bin/capture-host

# View captured hosts
cat /etc/myvpn/hosts.log

# Clear all captured hosts
> /etc/myvpn/hosts.log
```

---

## 🔧 Service Management

### Check Services:
```bash
systemctl status bw-limit-check    # Bandwidth monitoring (10ms)
systemctl status host-capture      # Host capture (10ms)
```

### Restart Services:
```bash
systemctl restart bw-limit-check
systemctl restart host-capture
```

### View Logs:
```bash
journalctl -u bw-limit-check -f
journalctl -u host-capture -f
```

---

## 📁 Important Files

```
/etc/xray/bw-limit.conf              # Bandwidth limits
/etc/myvpn/usage/<user>.json         # Per-user tracking
/etc/myvpn/hosts.log                 # Captured hosts
```

---

## ⚡ Features

- ✅ 10-millisecond update intervals (100 updates/second)
- ✅ Auto-delete users when bandwidth expires
- ✅ Daily/Total/Remaining bandwidth tracking
- ✅ Real-time host capture from all protocols
- ✅ No duplicate hosts in capture list
- ✅ Automatic counter reset detection
- ✅ Clean user deletion (removes home, cron, iptables)

---

## 🎯 Bandwidth Tracking

**What's tracked:**
- SSH: Outbound traffic (iptables)
- VMESS/VLESS/TROJAN/SS: Outbound traffic (Xray API)

**Display shows:**
- **DAILY**: Usage since midnight
- **TOTAL**: All-time usage
- **LIMIT**: Set bandwidth limit
- **REMAIN**: Remaining bandwidth
- **STATUS**: OK/WARNING/EXCEEDED/UNLIMITED

---

## 🌐 Host Capture

**What's captured:**
- HTTP Host headers
- SNI (TLS handshake)
- Domain names
- Proxy headers
- Source IP addresses

**Excluded:**
- VPS main domain
- VPS IP address
- Localhost/127.0.0.1

---

## 💡 Tips

1. **Real-time monitors update every 10ms** - Very responsive!
2. **Press Ctrl+C** to exit real-time views
3. **Use menu options** for easier management
4. **Check service status** if features don't work
5. **Reset bandwidth** when renewing user accounts

---

## ⚙️ Adjust Update Speed

If system load is high, edit service files:

```bash
nano /etc/systemd/system/bw-limit-check.service
```

Change `sleep 0.01` (10ms) to:
- `0.05` for 50ms
- `0.1` for 100ms
- `1` for 1 second

Then:
```bash
systemctl daemon-reload
systemctl restart bw-limit-check
```

---

## 🐛 Troubleshooting

**Bandwidth not tracking?**
```bash
systemctl status bw-limit-check
/usr/local/bin/xray api statsquery --server=127.0.0.1:10085
```

**Hosts not capturing?**
```bash
systemctl status host-capture
ls -la /var/log/xray/access.log
```

**User not deleted when over limit?**
```bash
journalctl -u bw-limit-check -n 50
cat /etc/xray/bw-limit.conf
```

---

**For detailed information, see: REALTIME_MONITORING_GUIDE.md**
