#!/bin/bash
# =========================================
# End-to-End Integration Test
# Tests complete bandwidth monitoring and blocking workflow
# =========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}End-to-End Integration Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

TEST_USER="e2etest$$"
SUCCESS=0
FAILED=0

test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((SUCCESS++))
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

cleanup() {
    echo -e "\n${YELLOW}Cleaning up test user...${NC}"
    /usr/bin/cek-bw-limit remove "$TEST_USER" 2>/dev/null
    userdel -r "$TEST_USER" 2>/dev/null
    # Clean up iptables
    local uid=$(id -u "$TEST_USER" 2>/dev/null)
    if [ -n "$uid" ]; then
        iptables -D OUTPUT -m owner --uid-owner "$uid" -j CONNMARK --set-mark "$uid" 2>/dev/null
        iptables -D OUTPUT -m owner --uid-owner "$uid" -j "BW_${uid}" 2>/dev/null
        iptables -D INPUT -m connmark --mark "$uid" -j "BW_${uid}" 2>/dev/null
        iptables -D OUTPUT -m owner --uid-owner "$uid" -j DROP 2>/dev/null
        iptables -D INPUT -m connmark --mark "$uid" -j DROP 2>/dev/null
        iptables -F "BW_${uid}" 2>/dev/null
        iptables -X "BW_${uid}" 2>/dev/null
    fi
}

trap cleanup EXIT

echo -e "${YELLOW}Test 1: Create SSH user${NC}"
if useradd -m "$TEST_USER" 2>/dev/null; then
    test_pass "Created SSH user $TEST_USER"
else
    test_fail "Failed to create SSH user"
    exit 1
fi

echo ""
echo -e "${YELLOW}Test 2: Set bandwidth limit${NC}"
if /usr/bin/cek-bw-limit add "$TEST_USER" 5 ssh 2>&1 | grep -q "OKEY"; then
    test_pass "Set 5MB bandwidth limit"
else
    test_fail "Failed to set bandwidth limit"
    exit 1
fi

echo ""
echo -e "${YELLOW}Test 3: Verify iptables rules created${NC}"
# Trigger chain creation by checking usage
/usr/bin/cek-bw-limit usage "$TEST_USER" >/dev/null 2>&1
sleep 1
uid=$(id -u "$TEST_USER" 2>/dev/null)
if [ -n "$uid" ]; then
    # Check OUTPUT CONNMARK rule
    if iptables -L OUTPUT -n 2>/dev/null | grep -q "owner UID match $uid.*CONNMARK set"; then
        test_pass "OUTPUT CONNMARK rule created"
    else
        test_fail "OUTPUT CONNMARK rule missing"
    fi
    
    # Check OUTPUT chain jump
    if iptables -L OUTPUT -n 2>/dev/null | grep -q "BW_${uid}.*owner UID match $uid"; then
        test_pass "OUTPUT chain jump created"
    else
        test_fail "OUTPUT chain jump missing"
    fi
    
    # Check INPUT connmark rule
    mark_hex=$(printf "0x%x" "$uid")
    if iptables -L INPUT -n 2>/dev/null | grep -q "BW_${uid}.*connmark match.*$mark_hex"; then
        test_pass "INPUT connmark rule created"
    else
        test_fail "INPUT connmark rule missing"
    fi
    
    # Check BW chain exists with 2 references
    if iptables -L "BW_${uid}" -n 2>/dev/null | grep -q "Chain BW_${uid} (2 references)"; then
        test_pass "BW_${uid} chain created with 2 references"
    else
        test_fail "BW_${uid} chain incorrect or missing"
    fi
else
    test_fail "Could not get UID for test user"
fi

echo ""
echo -e "${YELLOW}Test 4: Verify rule order (CONNMARK before chain jump)${NC}"
if [ -n "$uid" ]; then
    # Get line numbers of both rules
    connmark_line=$(iptables -L OUTPUT -n -v --line-numbers 2>/dev/null | grep "owner UID match $uid.*CONNMARK" | awk '{print $1}' | head -1)
    chain_line=$(iptables -L OUTPUT -n -v --line-numbers 2>/dev/null | grep "BW_${uid}.*owner UID match $uid" | awk '{print $1}' | head -1)
    
    if [ -n "$connmark_line" ] && [ -n "$chain_line" ]; then
        if [ "$connmark_line" -lt "$chain_line" ]; then
            test_pass "CONNMARK rule is BEFORE chain jump (correct order)"
        else
            test_fail "CONNMARK rule is AFTER chain jump (wrong order)"
        fi
    else
        test_fail "Could not verify rule order"
    fi
fi

echo ""
echo -e "${YELLOW}Test 5: Simulate bandwidth usage and test blocking${NC}"
# Manually set iptables counter to exceed limit (5MB = 5242880 bytes)
if [ -n "$uid" ]; then
    # Add rule with counter to simulate 6MB traffic
    iptables -I "BW_${uid}" 1 -j RETURN -c 6000 6291456 2>/dev/null
    iptables -D "BW_${uid}" 2 2>/dev/null
    
    # Run bandwidth check
    /usr/bin/cek-bw-limit check 2>/dev/null
    
    # Check if DROP rules were created
    if iptables -L OUTPUT -n 2>/dev/null | grep -q "DROP.*owner UID match $uid"; then
        test_pass "OUTPUT DROP rule created (user blocked)"
    else
        test_fail "OUTPUT DROP rule not created"
    fi
    
    mark_hex=$(printf "0x%x" "$uid")
    if iptables -L INPUT -n 2>/dev/null | grep -q "DROP.*connmark match.*$mark_hex"; then
        test_pass "INPUT DROP rule created (download blocked)"
    else
        test_fail "INPUT DROP rule not created"
    fi
fi

echo ""
echo -e "${YELLOW}Test 6: Test unblock functionality${NC}"
if /usr/bin/cek-bw-limit reset "$TEST_USER" 2>&1 | grep -q "unblocked"; then
    test_pass "User unblock command executed"
    
    # Verify DROP rules removed
    if ! iptables -L OUTPUT -n 2>/dev/null | grep -q "DROP.*owner UID match $uid"; then
        test_pass "OUTPUT DROP rule removed"
    else
        test_fail "OUTPUT DROP rule still present"
    fi
    
    if ! iptables -L INPUT -n 2>/dev/null | grep -q "DROP.*connmark match.*$(printf "0x%x" "$uid")"; then
        test_pass "INPUT DROP rule removed"
    else
        test_fail "INPUT DROP rule still present"
    fi
else
    test_fail "User unblock failed"
fi

echo ""
echo -e "${YELLOW}Test 7: Verify services are running${NC}"
if systemctl is-active --quiet bw-limit-check; then
    test_pass "bw-limit-check service is running"
else
    test_fail "bw-limit-check service is not running"
fi

if systemctl is-active --quiet host-capture; then
    test_pass "host-capture service is running"
else
    test_fail "host-capture service is not running"
fi

echo ""
echo -e "${YELLOW}Test 8: Test host capture script${NC}"
if /usr/bin/capture-host 2>&1 | grep -q "Host capture complete"; then
    test_pass "Host capture script executes successfully"
else
    test_fail "Host capture script failed"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Tests Passed: $SUCCESS${NC}"
echo -e "${RED}Tests Failed: $FAILED${NC}"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}✓ All integration tests passed!${NC}"
    echo -e "${GREEN}  System is fully functional.${NC}"
    exit 0
else
    echo -e "${RED}✗ Some integration tests failed.${NC}"
    echo -e "${YELLOW}  Please review the failures above.${NC}"
    exit 1
fi
