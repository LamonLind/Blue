#!/bin/bash
# =========================================
# Test script for bandwidth tracking fixes
# Tests SSH iptables initialization and debug logging
# =========================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}Bandwidth Tracking Fixes - Test Suite${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""

# Test 1: Check if functions exist
echo -e "${YELLOW}Test 1: Checking if new functions exist...${NC}"

if grep -q "initialize_ssh_iptables()" /home/runner/work/Blue/Blue/cek-bw-limit.sh; then
    echo -e "${GREEN}✓${NC} initialize_ssh_iptables() function found"
else
    echo -e "${RED}✗${NC} initialize_ssh_iptables() function NOT found"
    exit 1
fi

if grep -q "initialize_all_ssh_iptables()" /home/runner/work/Blue/Blue/cek-bw-limit.sh; then
    echo -e "${GREEN}✓${NC} initialize_all_ssh_iptables() function found"
else
    echo -e "${RED}✗${NC} initialize_all_ssh_iptables() function NOT found"
    exit 1
fi

if grep -q "debug_log()" /home/runner/work/Blue/Blue/cek-bw-limit.sh; then
    echo -e "${GREEN}✓${NC} debug_log() function found"
else
    echo -e "${RED}✗${NC} debug_log() function NOT found"
    exit 1
fi

if grep -q "show_debug_diagnostics()" /home/runner/work/Blue/Blue/cek-bw-limit.sh; then
    echo -e "${GREEN}✓${NC} show_debug_diagnostics() function found"
else
    echo -e "${RED}✗${NC} show_debug_diagnostics() function NOT found"
    exit 1
fi

echo ""

# Test 2: Check if add_bandwidth_limit calls initialization
echo -e "${YELLOW}Test 2: Checking SSH initialization in add_bandwidth_limit...${NC}"

if grep -A 15 "^add_bandwidth_limit()" /home/runner/work/Blue/Blue/cek-bw-limit.sh | grep -q "initialize_ssh_iptables"; then
    echo -e "${GREEN}✓${NC} add_bandwidth_limit calls initialize_ssh_iptables for SSH users"
else
    echo -e "${RED}✗${NC} add_bandwidth_limit does NOT call initialize_ssh_iptables"
    exit 1
fi

echo ""

# Test 3: Check if check_bandwidth_limits initializes on first run
echo -e "${YELLOW}Test 3: Checking first-run initialization in check_bandwidth_limits...${NC}"

if grep -A 10 "check_bandwidth_limits()" /home/runner/work/Blue/Blue/cek-bw-limit.sh | grep -q "initialize_all_ssh_iptables"; then
    echo -e "${GREEN}✓${NC} check_bandwidth_limits calls initialize_all_ssh_iptables on first run"
else
    echo -e "${RED}✗${NC} check_bandwidth_limits does NOT initialize on first run"
    exit 1
fi

if grep -A 10 "check_bandwidth_limits()" /home/runner/work/Blue/Blue/cek-bw-limit.sh | grep -q "bw-limit-ssh-initialized"; then
    echo -e "${GREEN}✓${NC} Uses marker file to track initialization"
else
    echo -e "${RED}✗${NC} Does NOT use marker file for initialization tracking"
    exit 1
fi

echo ""

# Test 4: Check debug logging implementation
echo -e "${YELLOW}Test 4: Checking debug logging implementation...${NC}"

if grep -q "DEBUG_MODE" /home/runner/work/Blue/Blue/cek-bw-limit.sh; then
    echo -e "${GREEN}✓${NC} DEBUG_MODE variable found"
else
    echo -e "${RED}✗${NC} DEBUG_MODE variable NOT found"
    exit 1
fi

if grep -q "DEBUG_LOG=" /home/runner/work/Blue/Blue/cek-bw-limit.sh; then
    echo -e "${GREEN}✓${NC} DEBUG_LOG variable found"
else
    echo -e "${RED}✗${NC} DEBUG_LOG variable NOT found"
    exit 1
fi

# Check if debug logging is used in critical functions
if grep -A 100 "get_xray_user_bandwidth()" /home/runner/work/Blue/Blue/cek-bw-limit.sh | grep -q "debug_log"; then
    echo -e "${GREEN}✓${NC} get_xray_user_bandwidth() includes debug logging"
else
    echo -e "${RED}✗${NC} get_xray_user_bandwidth() missing debug logging"
    exit 1
fi

if grep -A 50 "get_user_bandwidth()" /home/runner/work/Blue/Blue/cek-bw-limit.sh | grep -q "debug_log"; then
    echo -e "${GREEN}✓${NC} get_user_bandwidth() includes debug logging"
else
    echo -e "${RED}✗${NC} get_user_bandwidth() missing debug logging"
    exit 1
fi

echo ""

# Test 5: Check Xray blocking documentation improvements
echo -e "${YELLOW}Test 5: Checking Xray blocking documentation...${NC}"

if grep -qi "soft block" /home/runner/work/Blue/Blue/cek-bw-limit.sh; then
    echo -e "${GREEN}✓${NC} Xray soft block limitation documented"
else
    echo -e "${RED}✗${NC} Xray soft block limitation NOT documented"
    exit 1
fi

if grep "soft block" /home/runner/work/Blue/Blue/cek-bw-limit.sh | grep -q "WARN\|NOTE\|YELLOW"; then
    echo -e "${GREEN}✓${NC} Warning message included for Xray blocking"
else
    echo -e "${RED}✗${NC} Warning message NOT included for Xray blocking"
    exit 1
fi

echo ""

# Test 6: Check menu option for debug diagnostics
echo -e "${YELLOW}Test 6: Checking debug diagnostics menu option...${NC}"

if grep "13" /home/runner/work/Blue/Blue/cek-bw-limit.sh | grep -i "debug"; then
    echo -e "${GREEN}✓${NC} Menu option 13 for debug diagnostics found"
else
    echo -e "${RED}✗${NC} Menu option 13 for debug diagnostics NOT found"
    exit 1
fi

if grep -A 5 "13)" /home/runner/work/Blue/Blue/cek-bw-limit.sh | grep -q "show_debug_diagnostics"; then
    echo -e "${GREEN}✓${NC} Menu option 13 calls show_debug_diagnostics"
else
    echo -e "${RED}✗${NC} Menu option 13 does NOT call show_debug_diagnostics"
    exit 1
fi

echo ""

# Test 7: Syntax check
echo -e "${YELLOW}Test 7: Running syntax check on cek-bw-limit.sh...${NC}"

if bash -n /home/runner/work/Blue/Blue/cek-bw-limit.sh 2>/dev/null; then
    echo -e "${GREEN}✓${NC} No syntax errors found"
else
    echo -e "${RED}✗${NC} Syntax errors detected!"
    bash -n /home/runner/work/Blue/Blue/cek-bw-limit.sh
    exit 1
fi

echo ""

# Summary
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}All tests passed successfully!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "Summary of fixes:"
echo -e "  ${GREEN}✓${NC} SSH iptables rules are now initialized proactively"
echo -e "  ${GREEN}✓${NC} Initialization happens on service start and when adding limits"
echo -e "  ${GREEN}✓${NC} Debug logging system implemented"
echo -e "  ${GREEN}✓${NC} Debug diagnostics menu added (option 13)"
echo -e "  ${GREEN}✓${NC} Xray blocking limitations documented"
echo -e "  ${GREEN}✓${NC} No syntax errors"
echo ""
echo -e "${YELLOW}To test in production:${NC}"
echo -e "  1. Add a bandwidth limit to an SSH user"
echo -e "  2. Check that iptables rules are created immediately"
echo -e "  3. Enable debug mode and monitor logs for Xray users"
echo -e "  4. Use menu option 13 to view debug information"
echo ""

exit 0
