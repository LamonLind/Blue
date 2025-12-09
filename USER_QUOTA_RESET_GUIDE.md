# User Quota Reset Feature Guide

## Overview
This guide covers the new user quota reset feature that allows administrators to reset bandwidth usage statistics and re-enable users who have been disabled due to quota limits.

## What is Quota Reset?

The quota reset feature allows you to:
- **Reset bandwidth usage statistics** to zero for a user
- **Re-enable users** who were automatically disabled when they exceeded their quota
- **Keep existing quota limits** unchanged
- **Automatically restart Xray service** to apply changes

## Why Reset User Quota?

Common scenarios where quota reset is useful:
1. **Monthly Billing Cycle**: Reset quotas at the start of each billing period
2. **Grace Period**: Give users extra bandwidth after they exceeded their limit
3. **Corrections**: Fix issues where quotas were incorrectly configured
4. **Testing**: Test quota enforcement without creating new users

## How to Reset User Quota

### Method 1: Interactive Script (Recommended for Beginners)

Run the interactive reset script:
```bash
reset-user-quota
```

This will:
1. Display all users with quotas
2. Show their current status (Active/Disabled)
3. Prompt you to enter the username/email
4. Ask for confirmation
5. Reset the user's quota and restart Xray

### Method 2: Command Line (Quick Access)

Use the xray-quota-manager directly:
```bash
xray-quota-manager reset user@example.com
```

### Method 3: Bandwidth Menu

Access via the bandwidth management menu:
```bash
menu-bandwidth
```

Then select option **[5] Reset User Quota & Re-Enable**

## What Happens During Reset?

When you reset a user's quota, the following occurs automatically:

### Step 1: Statistics Reset
- Clears **uplink** (upload) statistics via Xray API
- Clears **downlink** (download) statistics via Xray API
- Both statistics are reset to **0 bytes**

### Step 2: User Re-enable
- If the user was **disabled** (quota exceeded), they are **re-enabled**
- Updates the quota configuration file
- Changes status from `false` to `true`

### Step 3: Xray Restart
- Automatically restarts the Xray service
- Applies all configuration changes
- User can immediately start using the service again

### Step 4: Quota Limit Preserved
- The **original quota limit remains unchanged**
- Example: If user had 10GB limit, it stays 10GB after reset
- Only the **usage counter** is reset to zero

## Example Usage

### Example 1: Reset a Single User
```bash
# User "user@test.com" has exceeded their 10GB quota
# They were automatically disabled

# Reset their quota
xray-quota-manager reset user@test.com

# Output:
# === Resetting User Quota ===
# User: user@test.com
# Quota Limit: 10.00 GB
# Current Status: false
#
# [INFO] Resetting bandwidth statistics...
# ✓ Statistics reset for user@test.com
# [INFO] Re-enabling user in quota config...
# ✓ User re-enabled in quota config
# [INFO] Restarting Xray service to apply changes...
# ✓ Xray service restarted successfully
#
# === Quota Reset Complete ===
# ✓ User user@test.com has been reset and re-enabled
# ✓ Bandwidth usage statistics cleared
# ✓ Quota limit maintained: 10.00 GB
```

### Example 2: Reset via Interactive Script
```bash
reset-user-quota

# The script will show:
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#              RESET USER QUOTA & RE-ENABLE USER
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# This script will:
#  • Reset bandwidth usage statistics to zero
#  • Re-enable user if they were disabled due to quota
#  • Keep the existing quota limit unchanged
#  • Restart Xray service to apply changes
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#              USERS WITH BANDWIDTH QUOTAS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# No.  Username/Email                      Status
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1)   user@test.com                       Disabled
# 2)   user2@test.com                      Active
#
# Enter username/email to reset: user@test.com
# Are you sure you want to reset quota for 'user@test.com'? (y/n): y
# 
# [Reset proceeds as shown in Example 1]
```

## Checking User Status After Reset

After resetting, verify the user's new status:

```bash
# Check usage for the user
xray-quota-manager usage user@test.com

# Output:
# === Bandwidth Usage for user@test.com ===
#
# Quota Limit    : 10.00 GB
# Upload Used    : 0.00 Bytes
# Download Used  : 0.00 Bytes
# Total Usage    : 0.00 Bytes
# Usage Percent  : 0.0%
# Remaining      : 10.00 GB
# Status         : Active
```

## Important Notes

### What Gets Reset
✅ **Upload (uplink) statistics** - Reset to 0  
✅ **Download (downlink) statistics** - Reset to 0  
✅ **User enabled status** - Changed from disabled to enabled  
✅ **Xray service** - Restarted automatically  

### What Does NOT Get Reset
❌ **Quota limit** - Stays the same (e.g., 10GB remains 10GB)  
❌ **User account** - Not deleted or recreated  
❌ **Expiry date** - User expiry date remains unchanged  
❌ **User credentials** - UUID/password remains the same  

### When Reset Might Fail

The reset operation might fail if:
1. **User doesn't exist** in quota configuration
   - Solution: Set a quota first with `xray-quota-manager set user@test.com 10GB`

2. **Xray service is not running**
   - Solution: Start Xray service with `systemctl start xray`

3. **Xray API is not accessible**
   - Solution: Verify Xray config has stats API enabled on port 10085

4. **Insufficient permissions**
   - Solution: Run the command as root user

## Automation and Scheduling

### Monthly Quota Reset

You can automate monthly quota resets using cron:

```bash
# Edit crontab
crontab -e

# Add this line to reset all users on the 1st of each month at 00:00
0 0 1 * * /usr/bin/reset-all-quotas.sh
```

Create `/usr/bin/reset-all-quotas.sh`:
```bash
#!/bin/bash
# Reset all user quotas

# Get all users from quota config
while IFS='|' read -r email total_bytes enabled; do
    [ -z "$email" ] && continue
    echo "Resetting quota for: $email"
    /usr/bin/xray-quota-manager reset "$email"
done < /etc/xray/client-quotas.conf

echo "All quotas reset successfully!"
```

Make it executable:
```bash
chmod +x /usr/bin/reset-all-quotas.sh
```

## Troubleshooting

### Issue: "User does not have a quota configured"
**Cause**: User has no quota entry in the configuration  
**Solution**: Set a quota first:
```bash
xray-quota-manager set user@test.com 10GB
```

### Issue: "Failed to restart Xray service"
**Cause**: Xray service is not installed or has configuration errors  
**Solution**: 
1. Check Xray status: `systemctl status xray`
2. Check Xray config: `xray test -c /etc/xray/config.json`
3. Restart manually: `systemctl restart xray`

### Issue: Statistics Not Clearing
**Cause**: Xray stats API not responding  
**Solution**:
1. Verify Xray is running: `systemctl status xray`
2. Check stats API: `xray api stats --server=127.0.0.1:10085`
3. Restart Xray: `systemctl restart xray`

### Issue: User Still Disabled After Reset
**Cause**: Xray service didn't restart properly  
**Solution**:
```bash
# Manually restart Xray
systemctl restart xray

# Verify user is enabled in config
grep "user@test.com" /etc/xray/client-quotas.conf
# Should show: user@test.com|10737418240|true (true = enabled)
```

## Integration with Bandwidth Menu

The reset feature is integrated into the bandwidth management menu:

```bash
menu-bandwidth
```

Menu options:
```
┌─────────────────────────────────────────────────────┐
       BANDWIDTH QUOTA MANAGEMENT MENU 

     [1] View All User Quotas & Usage      
     [2] View Specific User Quota      
     [3] Set/Update User Quota      
     [4] Remove User Quota     
     [5] Reset User Quota & Re-Enable     ← NEW FEATURE
     [6] Check Monitor Status     
     [7] Restart Monitor Service     
└─────────────────────────────────────────────────────┘
     Press x or [ Ctrl+C ] • To-Exit
```

## Best Practices

1. **Backup Before Reset**: Always backup quota configuration before bulk resets
   ```bash
   cp /etc/xray/client-quotas.conf /etc/xray/client-quotas.conf.backup
   ```

2. **Verify User Exists**: Check if user has a quota before attempting reset
   ```bash
   xray-quota-manager list | grep user@test.com
   ```

3. **Monitor After Reset**: Check service logs after reset
   ```bash
   journalctl -u xray -n 50
   ```

4. **Document Resets**: Keep a log of manual quota resets for billing/audit purposes

5. **Test First**: Test quota reset on a single user before bulk operations

## Related Commands

```bash
# View all quotas
xray-quota-manager list

# Check specific user usage
xray-quota-manager usage user@test.com

# Set new quota
xray-quota-manager set user@test.com 20GB

# Remove quota (make unlimited)
xray-quota-manager remove user@test.com

# Reset quota (new feature)
xray-quota-manager reset user@test.com

# Interactive reset
reset-user-quota
```

## Summary

The user quota reset feature provides a simple and effective way to:
- Give users a fresh start with their bandwidth quota
- Re-enable users who exceeded their limits
- Maintain consistent quota limits across billing periods
- Automate quota management tasks

For additional help, check the main documentation or contact support.
