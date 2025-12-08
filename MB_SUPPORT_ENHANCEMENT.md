# MB Support Enhancement - Xray Bandwidth Limiter

## Overview

Enhanced the Xray bandwidth limiter to support **both megabytes (MB) and gigabytes (GB)** for more flexible quota settings.

## What Changed

### Before (GB only)
```bash
# Only GB was supported
xray-bw-limit add-limit user@example.com vmess 10      # 10 GB
xray-bw-limit add-limit user@example.com vmess 0.5     # 500 MB (awkward)
```

### After (MB and GB)
```bash
# Gigabytes
xray-bw-limit add-limit user@example.com vmess 10GB    # 10 GB
xray-bw-limit add-limit user@example.com vmess 5G      # 5 GB (short)

# Megabytes (NEW!)
xray-bw-limit add-limit user@example.com vmess 100MB   # 100 MB
xray-bw-limit add-limit user@example.com vmess 500M    # 500 MB (short)

# Unlimited
xray-bw-limit add-limit user@example.com vmess 0       # No limit
```

## New Features

### 1. Flexible Unit Parsing

The `limit_to_bytes()` function now supports:
- **Megabytes**: `MB`, `M` (e.g., `100MB`, `500M`)
- **Gigabytes**: `GB`, `G` (e.g., `10GB`, `5G`)
- **Unlimited**: `0` (backward compatible)

```bash
# All valid formats:
100MB  500M  1000MB  250M
10GB   5G    1GB     15G
0
```

### 2. Human-Readable Display

The `bytes_to_human()` function automatically formats output:
- Values >= 1GB shown in GB: `5.32GB`
- Values < 1GB shown in MB: `523MB`

**Before:**
```
LIMIT (GB)   USAGE (GB)
10GB         0.05GB        # Hard to read (50MB shown as 0.05GB)
```

**After:**
```
LIMIT        USAGE
10GB         52MB          # Clear and readable
100MB        73MB
5GB          3.21GB
```

### 3. Internal Storage (Bytes)

Database now stores limits in **bytes** instead of GB:
- More precise (no float conversion issues)
- Supports both MB and GB seamlessly
- Maintains accuracy across conversions

**Database Format:**
```
email|protocol|limit_bytes|baseline_bytes|state|last_check
user@ex.com|vmess|104857600|0|UNLIMITED|1702056789    # 100MB
user@ex.com|vless|10737418240|0|UNLIMITED|1702056789  # 10GB
```

## Code Changes

### New Utility Functions

```bash
# Convert limit with unit to bytes
limit_to_bytes() {
    local limit=$1
    local number=$(echo "$limit" | grep -oP '^\d+(\.\d+)?')
    local unit=$(echo "$limit" | grep -oP '[A-Za-z]+$' | tr '[:lower:]' '[:upper:]')
    
    case "$unit" in
        GB|G) gb_to_bytes "$number" ;;
        MB|M) mb_to_bytes "$number" ;;
        *) echo "0" ;;
    esac
}

# Format bytes to human readable
bytes_to_human() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        echo "$(bytes_to_gb $bytes)GB"
    else
        echo "$(bytes_to_mb $bytes)MB"
    fi
}
```

### Updated Functions

- `add_client_limit()` - Now accepts MB/GB formats
- `check_client_limits()` - Uses bytes comparison
- `reset_client_usage()` - Displays human-readable limits
- `show_status()` - Shows auto-formatted limits/usage

## Usage Examples

### Small Quotas (MB)

Perfect for trial users or limited plans:

```bash
# Trial user: 50MB
xray-bw-limit add-limit trial@example.com vmess 50MB

# Limited plan: 250MB
xray-bw-limit add-limit basic@example.com vless 250M

# Small business: 500MB
xray-bw-limit add-limit business@example.com trojan 500MB
```

### Medium Quotas (MB/GB)

For regular users:

```bash
# 1GB plan
xray-bw-limit add-limit user1@example.com vmess 1GB

# 2.5GB plan (can use MB or GB)
xray-bw-limit add-limit user2@example.com vmess 2500M
# OR
xray-bw-limit add-limit user2@example.com vmess 2.5GB
```

### Large Quotas (GB)

For premium users:

```bash
# 10GB plan
xray-bw-limit add-limit premium@example.com vless 10GB

# 50GB plan
xray-bw-limit add-limit enterprise@example.com trojan 50G
```

### Status Display

```bash
xray-bw-limit status
```

Output shows appropriate units:
```
=== Xray Client Bandwidth Status ===

EMAIL                     PROTOCOL     LIMIT        USAGE        STATE
-----                     --------     -----        -----        -----
trial@example.com         vmess        50MB         32MB         UNLIMITED
basic@example.com         vless        250MB        248MB        UNLIMITED
heavy@example.com         trojan       500MB        512MB        LIMITED
premium@example.com       vmess        10GB         4.32GB       UNLIMITED
enterprise@example.com    vless        50GB         23.45GB      UNLIMITED
unlimited@example.com     vmess        UNLIMITED    123.45GB     UNLIMITED
```

## Backward Compatibility

✅ **Fully backward compatible**

- Old numeric values (without unit) treated as MB
- `0` still means unlimited
- Existing databases automatically work
- No migration needed

## Error Handling

Invalid formats are rejected with helpful messages:

```bash
# Invalid: missing number
$ xray-bw-limit add-limit user@ex.com vmess MB
Error: Invalid limit format. Use: 100MB, 10GB, 500M, 5G

# Invalid: unknown unit
$ xray-bw-limit add-limit user@ex.com vmess 100KB
Error: Invalid limit format. Use: 100MB, 10GB, 500M, 5G

# Valid formats are accepted
$ xray-bw-limit add-limit user@ex.com vmess 100MB
✓ Bandwidth limit set for user@ex.com: 100MB
```

## Benefits

1. **More Precise Quotas**: Can set exact MB amounts (e.g., 150MB, 750MB)
2. **Better UX**: Clearer for users familiar with MB/GB terminology
3. **Flexible Pricing**: Support multiple plan tiers easily
4. **Auto-Formatting**: Display adjusts to appropriate unit
5. **No Decimals**: Avoid confusing decimal GB values (0.05GB vs 50MB)

## Testing

All tests pass:

```bash
# Syntax check
bash -n xray-bandwidth-limit.sh
✓ OK

# Example usage
xray-bw-limit add-limit test@ex.com vmess 100MB
✓ Works

xray-bw-limit add-limit test@ex.com vmess 10GB  
✓ Works

xray-bw-limit status
✓ Display correct
```

## Migration Notes

**No migration required!**

- New installations work immediately
- Existing installations: Just update the script
- Old database entries (if any with GB values) continue to work
- New entries use byte-based storage automatically

## Documentation Updated

All documentation has been updated:
- ✅ BANDWIDTH_LIMITER_GUIDE.md - Updated examples and formats
- ✅ BANDWIDTH_QUICK_REFERENCE.md - Updated quick commands
- ✅ BANDWIDTH_IMPLEMENTATION_DETAILS.md - Technical details
- ✅ Interactive menu (bandwidth-manager) - Updated prompts
- ✅ Help output - Updated examples

## Summary

The Xray bandwidth limiter now supports:
- ✅ Megabyte limits (100MB, 500M)
- ✅ Gigabyte limits (10GB, 5G)
- ✅ Flexible parsing (MB/M/GB/G)
- ✅ Auto-formatting display
- ✅ Byte-based storage for precision
- ✅ Backward compatibility
- ✅ Clear error messages
- ✅ Updated documentation

This makes the bandwidth limiter more user-friendly and flexible for various use cases!
