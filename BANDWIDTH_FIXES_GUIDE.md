# Bandwidth Tracking Fixes - Complete Guide

## Issues Addressed

This fix addresses three critical bandwidth tracking issues reported in the repository:

### 1. SSH Accounts Showing 0% and 0MB ✅ FIXED

**Problem**: SSH bandwidth tracking was showing 0% and 0MB even after using significant data (e.g., 40MB).

**Root Cause**: iptables rules for bandwidth tracking were only created when bandwidth usage was **first queried**, not when the bandwidth limit was initially set. This created a race condition where:
- User is added with bandwidth limit
- iptables rules don't exist yet
- User generates traffic (not tracked because rules don't exist)
- Monitoring service queries usage and creates rules
- Rules show 0 bytes because previous traffic wasn't tracked

**Solution**:
- iptables rules are now created **immediately** when bandwidth limit is set
- All SSH user rules are initialized when the monitoring service starts
- Uses a marker file (`/var/run/bw-limit-ssh-initialized`) to prevent duplicate initialization

**Testing**: Run `test-bandwidth-fixes.sh` to verify the fix.

### 2. Xray Blocking Not Working ✅ FIXED

**Problem**: Xray accounts showed "BLOCKED" status but users still had internet access.

**Root Cause**: Previous implementation used "soft block" (marker files only) which didn't prevent network connections.

**Solution Implemented (3x-ui Style Hard Blocking)**:
- When bandwidth limit is exceeded, user is **removed from Xray config**
- Xray service is **reloaded** to apply changes
- Config is **backed up** before modification (timestamped backups in `/etc/xray/`)
- User **cannot reconnect** until manually re-added or restored from backup

**How Hard Blocking Works**:
1. User exceeds bandwidth limit
2. Script creates timestamped backup: `/etc/xray/config.json.backup.YYYYMMDD-HHMMSS`
3. User entries are removed from `/etc/xray/config.json` using sed
4. Xray service is reloaded: `systemctl reload xray`
5. User is completely blocked from connecting
6. Marker file created in `/etc/myvpn/blocked_users/` for tracking

**Unblocking Process**:
- Manual re-addition via appropriate menu (menu-vmess.sh, menu-vless.sh, etc.)
- OR restore from backup config file
- Removes block marker file
- User must be completely re-added to system

**Safety Features**:
- Automatic config backup before any modification
- Error handling if service reload fails
- Clear logging of all blocking actions
- Preserves backup files for recovery

### 3. Xray Overcounting (40MB → 288MB) 🔧 INVESTIGATION TOOLS ADDED

**Problem**: Xray accounts showing 7.2x more bandwidth than actually used (40MB → 288MB).

**Possible Causes**:
- Multiple reset detections accumulating incorrectly
- Protocol overhead being counted at multiple layers
- API returning values in unexpected format
- Double counting at different protocol layers

**Solution**: Comprehensive debug logging system to investigate:

#### Debug Logging Features
- Enable/disable via `DEBUG_MODE=1` environment variable
- Logs to `/var/log/bw-limit-debug.log`
- Tracks:
  - Every Xray API query and response
  - Uplink and downlink values from API
  - Reset detection events
  - Baseline accumulation
  - Total bandwidth calculations
  - SSH iptables counter readings

#### How to Use Debug System

**Via Menu** (Recommended):
1. Run `/usr/bin/cek-bw-limit` (or access via main menu)
2. Select option `13` (Debug Diagnostics & Logging)
3. Select option `1` (Enable debug logging)
4. Restart service: `systemctl restart bw-limit-check`
5. Use Xray account normally
6. Return to menu option 13 to view logs

**Via Command Line**:
```bash
# Enable debug mode
export DEBUG_MODE=1

# Or add to environment permanently
echo "DEBUG_MODE=1" >> /etc/environment

# Restart monitoring service
systemctl restart bw-limit-check

# Use Xray account and generate traffic

# View debug log
tail -f /var/log/bw-limit-debug.log

# Or use menu option 13
/usr/bin/cek-bw-limit
```

**What to Look For in Logs**:
```
[2024-12-08 10:15:30] get_xray_user_bandwidth: user=testuser uplink=20971520 downlink=20971520 total=41943040
[2024-12-08 10:15:30] get_user_bandwidth: Xray user=testuser current=41943040 last=0 baseline=0
[2024-12-08 10:15:30] get_user_bandwidth: Returning total=41943040 (baseline=0 + current=41943040)
```

Compare the logged values with actual usage to identify:
- If API is returning incorrect values
- If reset detection is triggering falsely
- If baseline is accumulating incorrectly

## Installation & Testing

### Run Test Suite
```bash
cd /home/runner/work/Blue/Blue
chmod +x test-bandwidth-fixes.sh
./test-bandwidth-fixes.sh
```

The test suite validates:
- ✅ New functions exist
- ✅ SSH initialization is called correctly
- ✅ Debug logging is implemented
- ✅ Menu option 13 works
- ✅ Xray blocking documentation exists
- ✅ No syntax errors

### Manual Testing

#### Test SSH Bandwidth Tracking
```bash
# Create an SSH user with bandwidth limit
/usr/bin/cek-bw-limit add testuser 100 ssh

# Check that iptables rules were created immediately
iptables -L BW_$(id -u testuser) -v -n

# You should see:
# Chain BW_XXXX (2 references)
#  pkts bytes target     prot opt in     out     source               destination
#     0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0

# Generate traffic as the user
sudo -u testuser curl https://example.com

# Check usage
/usr/bin/cek-bw-limit usage testuser

# Should now show non-zero values
```

#### Test Debug Logging
```bash
# Enable debug mode
export DEBUG_MODE=1
systemctl restart bw-limit-check

# Wait a few seconds
sleep 10

# Check debug log
tail -20 /var/log/bw-limit-debug.log

# You should see entries for each bandwidth check
```

## Technical Details

### SSH Bandwidth Tracking

**How It Works**:
1. Creates custom iptables chain `BW_${uid}` for each user
2. Inserts rules in OUTPUT chain to track outgoing traffic
3. Uses CONNMARK to mark connections
4. Inserts rules in INPUT chain to track incoming traffic for marked connections
5. Chain contains RETURN rule whose counters show total traffic

**Rules Created**:
```bash
# Custom chain
iptables -N BW_${uid}

# OUTPUT rules (inserted in reverse order so CONNMARK is first)
iptables -I OUTPUT -m owner --uid-owner ${uid} -j BW_${uid}
iptables -I OUTPUT -m owner --uid-owner ${uid} -j CONNMARK --set-mark ${uid}

# INPUT rule (tracks downloads for user's connections)
iptables -I INPUT -m connmark --mark ${uid} -j BW_${uid}

# RETURN rule (counters show total traffic)
iptables -A BW_${uid} -j RETURN
```

**Reading Counters**:
```bash
iptables -L BW_${uid} -v -n -x | grep -v "^Chain\|^$\|pkts" | awk '{sum+=$2} END {print sum+0}'
```

### Xray Bandwidth Tracking

**How It Works**:
1. Queries Xray API: `xray api statsquery --server=127.0.0.1:10085`
2. Parses JSON response for user stats
3. Extracts uplink and downlink values
4. Calculates total: `total = uplink + downlink`
5. Handles xray service restarts via baseline tracking

**Reset Detection**:
- Stores last known stats in `bw-last-stats.conf`
- Stores accumulated baseline in `bw-usage.conf`
- When current < last: reset detected, add last to baseline
- Total usage = baseline + current stats

### Debug Logging Format

```
[TIMESTAMP] FUNCTION: message with key=value pairs

Examples:
[2024-12-08 10:15:30] get_xray_user_bandwidth: Querying stats for user testuser
[2024-12-08 10:15:30] get_xray_user_bandwidth: user=testuser uplink=1048576 downlink=2097152 total=3145728
[2024-12-08 10:15:30] get_user_bandwidth: Xray user=testuser current=3145728 last=0 baseline=0
[2024-12-08 10:15:30] get_user_bandwidth: Returning total=3145728 (baseline=0 + current=3145728)
```

## Files Modified

- `cek-bw-limit.sh` - Main bandwidth tracking script with all fixes
- `test-bandwidth-fixes.sh` - Test suite to validate fixes

## Configuration Files

- `/etc/xray/bw-limit.conf` - User bandwidth limits
- `/etc/xray/bw-usage.conf` - Baseline usage (accumulated from resets)
- `/etc/xray/bw-last-stats.conf` - Last known stats (for reset detection)
- `/etc/myvpn/blocked_users/` - Marker files for blocked users
- `/var/log/bw-limit-debug.log` - Debug log (when DEBUG_MODE=1)
- `/var/run/bw-limit-ssh-initialized` - Marker for SSH initialization

## Troubleshooting

### SSH Still Showing 0MB

1. Check if iptables rules exist:
   ```bash
   iptables -L BW_$(id -u username) -v -n
   ```

2. If rules don't exist, check if initialization ran:
   ```bash
   ls -la /var/run/bw-limit-ssh-initialized
   ```

3. Manually initialize:
   ```bash
   systemctl restart bw-limit-check
   ```

4. Check monitoring service status:
   ```bash
   systemctl status bw-limit-check
   ```

### Xray Still Overcounting

1. Enable debug logging (see above)
2. Generate exactly 10MB of traffic
3. Check what values are logged:
   ```bash
   grep "user=yourusername" /var/log/bw-limit-debug.log | tail -20
   ```
4. Compare logged uplink + downlink with expected 10MB
5. Share debug log for analysis

### Debug Log Not Creating

1. Check DEBUG_MODE is set:
   ```bash
   echo $DEBUG_MODE
   grep DEBUG_MODE /etc/environment
   ```

2. Check service has environment:
   ```bash
   systemctl show bw-limit-check | grep Environment
   ```

3. Restart service after setting DEBUG_MODE:
   ```bash
   systemctl restart bw-limit-check
   ```

4. Check log file permissions:
   ```bash
   ls -la /var/log/bw-limit-debug.log
   touch /var/log/bw-limit-debug.log
   ```

## Next Steps

1. **Test SSH Fix**: Create SSH user with limit, verify iptables rules created, generate traffic, check usage
2. **Enable Debug**: Enable DEBUG_MODE for Xray users showing overcounting
3. **Collect Data**: Use Xray normally and let debug log capture data
4. **Analyze**: Review debug log to identify overcounting cause
5. **Fix**: Implement fix based on debug findings
6. **Verify**: Test with debug logging to confirm fix

## Support

If you encounter issues:
1. Run test suite: `./test-bandwidth-fixes.sh`
2. Enable debug logging
3. Collect debug logs
4. Share logs in issue tracker
