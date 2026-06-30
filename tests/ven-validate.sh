#!/bin/bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

#########################################################################
# VEN Validation Test Suite
# Runs post-deployment tests against a booted VEN VM over SSH.
# Exit code: 0 = all tests pass, 1 = one or more failures.
#
# Usage: ./ven-validate.sh [SSH_PORT] [SSH_USER] [SSH_HOST]
#########################################################################
set -euo pipefail

SSH_PORT="${1:-2222}"
SSH_USER="${2:-user}"
SSH_HOST="${3:-localhost}"
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p ${SSH_PORT}"

PASS=0
FAIL=0
WARN=0
RESULTS_FILE="${RESULTS_FILE:-/tmp/ven-test-results.txt}"

: > "$RESULTS_FILE"

# Helper: run a command on the VM and check exit code
run_test() {
    local test_name="$1"
    local command="$2"
    local expect_pass="${3:-true}"  # true = must pass, false = warn-only

    echo -n "  TEST: ${test_name}... "
    # shellcheck disable=SC2086
    if output=$(ssh $SSH_OPTS "${SSH_USER}@${SSH_HOST}" "$command" 2>&1); then
        echo "PASS"
        echo "PASS: ${test_name}" >> "$RESULTS_FILE"
        PASS=$((PASS + 1))
    else
        if [ "$expect_pass" = "true" ]; then
            echo "FAIL"
            echo "FAIL: ${test_name}" >> "$RESULTS_FILE"
            echo "       Output: ${output}" >> "$RESULTS_FILE"
            FAIL=$((FAIL + 1))
        else
            echo "WARN"
            echo "WARN: ${test_name}" >> "$RESULTS_FILE"
            WARN=$((WARN + 1))
        fi
    fi
}

echo "=== VEN Validation Test Suite ==="
echo "  Target: ${SSH_USER}@${SSH_HOST}:${SSH_PORT}"
echo ""

# ---------------------------------------------------------------
# Category 1: OS Installation Validation
# ---------------------------------------------------------------
echo "[1/6] OS Installation"
run_test "OS booted (uptime)" "uptime"
run_test "Ubuntu 24.04 detected" "grep -q '24.04' /etc/os-release"
run_test "Root filesystem mounted" "mount | grep -q 'on / '"
run_test "Disk space available (>5GB free)" "df -BG / | awk 'NR==2{gsub(/G/,\"\",\$4); exit (\$4<5)}'"
run_test "System time synced (NTP)" "timedatectl show -p NTPSynchronized --value | grep -q yes" "false"

# ---------------------------------------------------------------
# Category 2: Cloud-Init Validation
# ---------------------------------------------------------------
echo ""
echo "[2/6] Cloud-Init"
run_test "Cloud-init completed" "cloud-init status --wait 2>/dev/null | grep -q done || test -f /run/cloud-init/result.json"
run_test "User created (${SSH_USER})" "id ${SSH_USER}"
run_test "SSH service running" "systemctl is-active ssh || systemctl is-active sshd"

# ---------------------------------------------------------------
# Category 3: Network Validation
# ---------------------------------------------------------------
echo ""
echo "[3/6] Network"
run_test "Network interface up" "ip link show | grep -q 'state UP'"
run_test "IP address assigned" "ip -4 addr show | grep -q 'inet '"
run_test "DNS resolution" "getent hosts google.com || nslookup google.com" "false"
run_test "Internet connectivity" "curl -sfo /dev/null --connect-timeout 5 https://google.com || wget -q --spider --timeout=5 https://google.com" "false"

# ---------------------------------------------------------------
# Category 4: Container Runtime / Kubernetes
# ---------------------------------------------------------------
echo ""
echo "[4/6] Container Runtime & Kubernetes"
run_test "Docker or containerd installed" "command -v docker || command -v containerd || command -v ctr" "false"
run_test "K3s binary exists" "command -v k3s || test -f /usr/local/bin/k3s" "false"
run_test "K3s service active" "sudo systemctl is-active k3s" "false"
run_test "kubectl available" "command -v kubectl || sudo k3s kubectl version --client" "false"
run_test "Kubernetes nodes ready" "sudo kubectl get nodes --no-headers 2>/dev/null | grep -q ' Ready'" "false"
run_test "CoreDNS pod running" "sudo kubectl get pods -A --no-headers 2>/dev/null | grep -q coredns" "false"

# ---------------------------------------------------------------
# Category 5: Intel Device Plugins & Hardware
# ---------------------------------------------------------------
echo ""
echo "[5/6] Intel Device Plugins & Hardware"
run_test "GPU device exists (/dev/dri)" "test -d /dev/dri" "false"
run_test "Intel GPU plugin pod" "sudo kubectl get pods -n intel-device-plugins --no-headers 2>/dev/null | grep -q gpu" "false"
run_test "Intel NPU plugin pod" "sudo kubectl get pods -n intel-device-plugins --no-headers 2>/dev/null | grep -q npu" "false"
run_test "NFD worker running" "sudo kubectl get pods -n node-feature-discovery --no-headers 2>/dev/null | grep -q nfd-worker" "false"
run_test "SR-IOV VFs created" "test -d /sys/class/drm/card0/device/virtfn0 || cat /sys/kernel/debug/dri/*/sriov_info 2>/dev/null | grep -q 'enabled'" "false"

# ---------------------------------------------------------------
# Category 6: System Services & Security
# ---------------------------------------------------------------
echo ""
echo "[6/6] System Services & Security"
run_test "Firewall active (ufw/iptables)" "sudo ufw status 2>/dev/null | grep -q active || sudo iptables -L -n | grep -q Chain" "false"
run_test "No failed systemd units" "systemctl --failed --no-legend | wc -l | grep -q '^0$'" "false"
run_test "Kernel version >= 6.x" "uname -r | grep -qE '^[6-9]\.'"
run_test "Secure boot state" "mokutil --sb-state 2>/dev/null || echo 'N/A'" "false"

# ---------------------------------------------------------------
# Results Summary
# ---------------------------------------------------------------
echo ""
echo "==========================================="
echo "  VEN VALIDATION RESULTS"
echo "==========================================="
echo "  PASSED:   ${PASS}"
echo "  FAILED:   ${FAIL}"
echo "  WARNINGS: ${WARN}"
echo "  TOTAL:    $((PASS + FAIL + WARN))"
echo "==========================================="
echo ""
echo "Detailed results: ${RESULTS_FILE}"

if [ "$FAIL" -gt 0 ]; then
    echo "RESULT: FAILED (${FAIL} test(s) failed)"
    exit 1
else
    echo "RESULT: PASSED (${WARN} warning(s))"
    exit 0
fi
