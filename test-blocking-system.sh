#!/bin/bash
# ===========================================
# Bandwidth Blocking System - Validation Test
# Tests all key functionality of the new blocking system
# ===========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Bandwidth Blocking System - Validation${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Function to report test result
test_result() {
    local test_name=$1
    local result=$2
    
    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        ((TESTS_FAILED++))
    fi
}

echo -e "${YELLOW}Running validation tests...${NC}"
echo ""

# Test 1: Check if main script exists and has correct permissions
echo -e "${BLUE}[1] Script Installation${NC}"
if [ -f "/usr/bin/cek-bw-limit" ] && [ -x "/usr/bin/cek-bw-limit" ]; then
    test_result "cek-bw-limit script installed and executable" 0
else
    test_result "cek-bw-limit script installed and executable" 1
fi

if [ -f "/usr/bin/capture-host" ] && [ -x "/usr/bin/capture-host" ]; then
    test_result "capture-host script installed and executable" 0
else
    test_result "capture-host script installed and executable" 1
fi

# Test 2: Check directory structure
echo ""
echo -e "${BLUE}[2] Directory Structure${NC}"
if [ -d "/etc/myvpn/usage" ]; then
    test_result "/etc/myvpn/usage directory exists" 0
else
    test_result "/etc/myvpn/usage directory exists" 1
fi

if [ -d "/etc/myvpn/blocked_users" ]; then
    test_result "/etc/myvpn/blocked_users directory exists" 0
else
    test_result "/etc/myvpn/blocked_users directory exists" 1
fi

# Test 3: Check log files
echo ""
echo -e "${BLUE}[3] Log Files${NC}"
if [ -f "/etc/myvpn/blocked.log" ]; then
    test_result "/etc/myvpn/blocked.log exists" 0
else
    test_result "/etc/myvpn/blocked.log exists" 1
fi

if [ -f "/etc/myvpn/hosts.log" ]; then
    test_result "/etc/myvpn/hosts.log exists" 0
else
    test_result "/etc/myvpn/hosts.log exists" 1
fi

# Test 4: Check configuration files
echo ""
echo -e "${BLUE}[4] Configuration Files${NC}"
if [ -f "/etc/xray/bw-limit.conf" ]; then
    test_result "/etc/xray/bw-limit.conf exists" 0
else
    test_result "/etc/xray/bw-limit.conf exists" 1
fi

if [ -f "/etc/xray/bw-usage.conf" ]; then
    test_result "/etc/xray/bw-usage.conf exists" 0
else
    test_result "/etc/xray/bw-usage.conf exists" 1
fi

# Test 5: Check systemd services
echo ""
echo -e "${BLUE}[5] Systemd Services${NC}"
if systemctl list-unit-files | grep -q "bw-limit-check.service"; then
    test_result "bw-limit-check.service exists" 0
else
    test_result "bw-limit-check.service exists" 1
fi

if systemctl list-unit-files | grep -q "host-capture.service"; then
    test_result "host-capture.service exists" 0
else
    test_result "host-capture.service exists" 1
fi

# Test 6: Check bash syntax
echo ""
echo -e "${BLUE}[6] Script Syntax${NC}"
if bash -n /usr/bin/cek-bw-limit 2>/dev/null; then
    test_result "cek-bw-limit syntax valid" 0
else
    test_result "cek-bw-limit syntax valid" 1
fi

if bash -n /usr/bin/capture-host 2>/dev/null; then
    test_result "capture-host syntax valid" 0
else
    test_result "capture-host syntax valid" 1
fi

# Test 7: Check for blocking functions
echo ""
echo -e "${BLUE}[7] Blocking Functions${NC}"
if grep -q "block_user_network" /usr/bin/cek-bw-limit; then
    test_result "block_user_network function exists" 0
else
    test_result "block_user_network function exists" 1
fi

if grep -q "unblock_user_network" /usr/bin/cek-bw-limit; then
    test_result "unblock_user_network function exists" 0
else
    test_result "unblock_user_network function exists" 1
fi

if grep -q "is_user_blocked" /usr/bin/cek-bw-limit; then
    test_result "is_user_blocked function exists" 0
else
    test_result "is_user_blocked function exists" 1
fi

# Test 8: Check menu options
echo ""
echo -e "${BLUE}[8] Menu Options${NC}"
if grep -q "Unblock User" /usr/bin/cek-bw-limit; then
    test_result "Unblock User menu option exists" 0
else
    test_result "Unblock User menu option exists" 1
fi

if grep -q "View Blocked Users" /usr/bin/cek-bw-limit; then
    test_result "View Blocked Users menu option exists" 0
else
    test_result "View Blocked Users menu option exists" 1
fi

# Test 9: Check enhanced host capture patterns
echo ""
echo -e "${BLUE}[9] Enhanced Host Capture${NC}"
if grep -q "ws-host" /usr/bin/capture-host; then
    test_result "WebSocket host capture pattern exists" 0
else
    test_result "WebSocket host capture pattern exists" 1
fi

if grep -q "serviceName" /usr/bin/capture-host; then
    test_result "gRPC service name capture pattern exists" 0
else
    test_result "gRPC service name capture pattern exists" 1
fi

if grep -q "serverAddress" /usr/bin/capture-host; then
    test_result "Server address capture pattern exists" 0
else
    test_result "Server address capture pattern exists" 1
fi

# Test 10: Check iptables availability
echo ""
echo -e "${BLUE}[10] System Requirements${NC}"
if command -v iptables &>/dev/null; then
    test_result "iptables command available" 0
else
    test_result "iptables command available" 1
fi

# Test 11: Check documentation
echo ""
echo -e "${BLUE}[11] Documentation${NC}"
if [ -f "BANDWIDTH_BLOCKING_GUIDE.md" ]; then
    test_result "BANDWIDTH_BLOCKING_GUIDE.md exists" 0
else
    test_result "BANDWIDTH_BLOCKING_GUIDE.md exists" 1
fi

if [ -f "HOST_CAPTURE_GUIDE.md" ]; then
    test_result "HOST_CAPTURE_GUIDE.md exists" 0
else
    test_result "HOST_CAPTURE_GUIDE.md exists" 1
fi

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}"
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed! System is ready for use.${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠ Some tests failed. Please review the results above.${NC}"
    exit 1
fi
