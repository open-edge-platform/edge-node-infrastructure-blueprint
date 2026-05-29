---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: validate-platform-config
description: Validate whether a provisioned platform is correctly configured over SSH, including k3s pod health, binary paths, cloud-init state, network/proxy setup, and device readiness.
---

## Trigger Phrases
- validate platform config
- validate node over ssh
- check provisioned node health
- validate k3s platform readiness
- post provision ssh validation
- ssh health check

## Required Inputs
- enib_home: absolute path to this repository root (default: current workspace root)
- ssh_host: target node IP or hostname
- ssh_user: remote login user (default: `user`)
- ssh_port: SSH port (default: `22`)
- kubeconfig_path: expected kubeconfig path (default: `/etc/rancher/k3s/k3s.yaml`)

Note: Private key authentication is auto-detected from `~/.ssh/` (searches `id_rsa`, `id_ed25519`, `id_ecdsa` in order). No prompt for key path.

## Preconditions
Run silently without user prompts:
- [ ] Skill file exists and is readable:
  - `test -f <enib_home>/skills/validate-platform-config/SKILL.md`
- [ ] SSH client exists locally:
  - `command -v ssh`
- [ ] Remote host is reachable on SSH port:
  - `timeout 5 bash -c '</dev/tcp/<ssh_host>/<ssh_port>'`
- [ ] Attempt remote login directly using the SSH agent / default keys (no key path required):
  - `ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -p <ssh_port> <ssh_user>@<ssh_host> true`
  - if exit code is `0`, proceed; record `SSH_AUTH=default`
  - only if direct login fails, fall back to explicit key discovery in `~/.ssh/`:
    - Run: `for key in ~/.ssh/id_rsa ~/.ssh/id_ed25519 ~/.ssh/id_ecdsa; do if [ -f "$key" ]; then perms=$(stat -c %a "$key" 2>/dev/null); if [ "$perms" -le 600 ]; then echo "KEY_FOUND=$key"; exit 0; fi; fi; done; echo "KEY_FOUND=none"`
    - if output contains `KEY_FOUND=none`, stop and report missing/unsafe key error
    - retry login with `-i <key>`; if it still fails, stop and report SSH auth error

Prompt only for missing required inputs:
- [ ] Ask for missing `ssh_host` and `ssh_port` only. Assume `ssh_user=user` unless the user overrides it.

## Steps
1. Build SSH command using the auth method established in preconditions.
  - If `SSH_AUTH=default` (direct login worked): `ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -p <ssh_port> <ssh_user>@<ssh_host>`
  - Otherwise, use the discovered `$ssh_key` from the fallback step: `ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -i $ssh_key -p <ssh_port> <ssh_user>@<ssh_host>`

2. Run remote check for basic k3s pods and statuses.
  - command:
    - `kubectl get pods -A --no-headers || k3s kubectl get pods -A --no-headers`
  - required pod name prefixes and expected status:
    - `intel-gpu-plugin` in `default` namespace, `Running`, `READY 1/1`
    - `intel-npu-plugin` in `default` namespace, `Running`, `READY 1/1`
    - `coredns` in `kube-system`, `Running`, `READY 1/1`
    - `local-path-provisioner` in `kube-system`, `Running`, `READY 1/1`
    - `metrics-server` in `kube-system`, `Running`, `READY 1/1`
    - `nfd-gc` in `node-feature-discovery`, `Running`, `READY 1/1`
    - `nfd-master` in `node-feature-discovery`, `Running`, `READY 1/1`
    - `nfd-worker` in `node-feature-discovery`, `Running`, `READY 1/1`

3. Validate `kubectl`, `k3s`, and Docker binaries and PATH.
  - commands:
    - `command -v kubectl`
    - `command -v k3s`
    - `command -v docker`
    - `ls -l /usr/local/bin/kubectl /usr/local/bin/k3s 2>/dev/null || true`
    - `ls -l /usr/local/bin/docker /usr/bin/docker 2>/dev/null || true`
    - `systemctl is-enabled docker 2>/dev/null || true`
    - `systemctl is-active docker 2>/dev/null || true`
    - `docker --version 2>/dev/null || true`
    - `echo "$PATH"`
  - expected:
    - `k3s` found in PATH
    - `kubectl` found in PATH (binary or symlink)
    - `docker` found in PATH when the platform is expected to support container workloads
    - one of expected locations exists: `/usr/local/bin/kubectl`, `/usr/bin/kubectl`
    - one of expected locations exists: `/usr/local/bin/k3s`, `/usr/bin/k3s`
    - one of expected locations exists: `/usr/local/bin/docker`, `/usr/bin/docker`
    - Docker service state is reported as enabled/disabled and active/inactive

4. Validate cloud-init completion.
  - commands:
    - `cloud-init status --long || true`
    - `test -f /var/lib/cloud/instance/boot-finished && echo CLOUD_INIT_BOOT_FINISHED=1 || echo CLOUD_INIT_BOOT_FINISHED=0`
    - `grep -Ei 'error|failed|traceback' /var/log/cloud-init.log | tail -n 20 || true`
  - expected:
    - cloud-init reports `status: done`
    - `/var/lib/cloud/instance/boot-finished` exists
    - no blocking cloud-init errors relevant to first boot provisioning

5. Validate network connectivity and assigned IP.
  - commands:
    - `ip -o -4 addr show scope global`
    - `ip route show default`
    - `ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1 && echo NET_INTERNET=ok || echo NET_INTERNET=fail`
    - `getent hosts github.com >/dev/null 2>&1 && echo DNS=ok || echo DNS=fail`
    - `curl -I --max-time 8 https://github.com >/dev/null 2>&1 && echo HTTPS_EGRESS=ok || echo HTTPS_EGRESS=fail`
  - expected:
    - at least one global IPv4 address assigned
    - default route present
    - connectivity result is classified explicitly:
      - direct internet OK: `NET_INTERNET=ok`
      - restricted/proxy-likely: `NET_INTERNET=fail` and `DNS=ok`
      - DNS/config issue: `DNS=fail`
    - if `NET_INTERNET=fail` and `DNS=ok`, do not hard-fail validation; report as "likely proxy required" with proxy evidence from Step 6

6. Collect proxy values.
  - commands:
    - `grep -E '^(http_proxy|https_proxy|no_proxy|HTTP_PROXY|HTTPS_PROXY|NO_PROXY)=' /etc/environment || true`
    - `test -f /etc/systemd/system/k3s.service.env && (sudo cat /etc/systemd/system/k3s.service.env 2>/dev/null || cat /etc/systemd/system/k3s.service.env 2>&1) || true`
    - `test -f /etc/systemd/system/docker.service.d/proxy.conf && (sudo cat /etc/systemd/system/docker.service.d/proxy.conf 2>/dev/null || cat /etc/systemd/system/docker.service.d/proxy.conf 2>&1) || true`
  - expected:
    - report exact current values from `/etc/environment` (guaranteed readable)
    - report k3s.service.env values when readable; if permission denied, report that explicitly
    - report docker proxy.conf values when readable; if permission denied, report that explicitly

7. Inventory CPU/GPU/NPU devices.
  - commands:
    - `nproc`
    - `lscpu`
    - `lscpu | grep -E 'Model name|Vendor ID|CPU family|Model:|Stepping'`
    - `grep -E '^(model name|flags|cpu cores|siblings)' /proc/cpuinfo | head -20`
    - `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || true`
    - `cat /proc/cpuinfo | grep -E 'cpu family|model|stepping|flags' | head -10`
    - `if ls /sys/devices/system/cpu/cpu*/topology/core_type >/dev/null 2>&1; then for f in /sys/devices/system/cpu/cpu*/topology/core_type; do cat "$f"; done | awk '{c[$1]++} END {for (t in c) printf "CORE_TYPE_RAW_%s_COUNT=%d\n", t, c[t]}' | sort; else echo CORE_TYPE_EXPOSED=no; fi`
    - `if ls /sys/devices/system/cpu/cpu*/topology/core_type >/dev/null 2>&1; then for f in /sys/devices/system/cpu/cpu*/topology/core_type; do cat "$f"; done | awk '{c[$1]++} END {printf "P_CORE_COUNT=%d\n", c[2]+0; printf "E_CORE_COUNT=%d\n", c[1]+0; printf "LPE_CORE_COUNT=%d\n", c[3]+0}'; else echo "P_CORE_COUNT=unavailable"; echo "E_CORE_COUNT=unavailable"; echo "LPE_CORE_COUNT=unavailable"; fi`
    - `for cpu in /sys/devices/system/cpu/cpu*/topology/thread_siblings_list; do [ -f "$cpu" ] && echo "$cpu=$(cat $cpu)"; done | head -10`
    - `lspci -nn | grep -Ei 'vga|3d|display|npu|neural|vpu|accel|intel' || true`
    - `ls -l /dev/dri 2>/dev/null || true`
  - expected:
    - Total CPU core count and logical processors reported
    - P-core, E-core, and LPE-core counts are reported when `core_type` is exposed
    - raw `core_type` counts are always reported alongside decoded counts for traceability
    - if `core_type` is not exposed by kernel/platform, report P/E/LPE counts as `unavailable`
    - CPU model, family, stepping, and feature flags documented
    - CPU codename is reported only when verified from trusted identifiers (family/model/stepping mapping); never infer codename from model name text alone
    - if codename cannot be verified confidently, report `CPU_CODENAME=unverified` instead of guessing
    - CPU frequency scaling driver reported
    - Core type information from `/sys/devices/system/cpu/cpu*/topology/core_type` is decoded using common Linux hybrid mapping (`2=P`, `1=E`, `3=LPE`) and may vary by kernel/platform
    - Thread siblings mapping for logical CPU layout
    - GPU presence determined from PCI and/or `/dev/dri`
    - NPU presence determined from PCI scan output

8. If GPU is present, report GPU VF counts.
  - commands:
    - `for f in /sys/class/drm/card*/device/sriov_numvfs; do [ -f "$f" ] && echo "$f=$(cat $f)"; done`
    - `for f in /sys/class/drm/card*/device/sriov_totalvfs; do [ -f "$f" ] && echo "$f=$(cat $f)"; done`
  - expected:
    - report per-GPU `sriov_numvfs` and `sriov_totalvfs`
    - if GPU exists but no SR-IOV files are present, report as unsupported/not enabled.

## Validation
Validation section is criteria-only. Do not render the pass/fail results table here.
- SSH connectivity check passes.
- All required k3s pods listed in Step 2 are found in correct namespaces and healthy (`Running`, `1/1`).
- `kubectl`, `k3s`, and Docker availability are reported with expected locations and service state.
- cloud-init completion indicators are successful.
- Network check reports assigned IP and route; connectivity is classified as direct or proxy/restricted with explicit reason.
- Proxy values are collected and reported from system files.
- CPU/GPU/NPU inventory is collected with clear present/absent status.
- CPU codename labeling is verification-based and avoids false platform naming.
- GPU VF data is reported when GPU exists.

## Rollback
This is a read-only validation skill. No rollback required.

## Safety Rules
- Never print private key contents or paths in user-visible output.
- Prefer read-only commands; do not alter target host configuration in this skill.
- Do not use destructive or privileged write operations.
- If a check fails, continue collecting remaining checks and return a complete report.

## Expected Result Summary
Render the report as the following tables.

### Run Metadata

| Field | Value |
|---|---|
| Preconditions | PASS/FAIL |
| SSH endpoint | `<ssh_user>@<ssh_host>:<ssh_port>` |
| Auth method | `default` (agent/default keys) or `key:<auto-discovered key name>` (mask path) |

### Validation Results

| Check Area | Status | Evidence | Notes |
|---|---|---|---|
| k3s pods | PASS/FAIL/WARN | key pod states from `kubectl get pods -A` | include namespace/name mismatches |
| binaries and PATH | PASS/FAIL/WARN | `command -v` and path outputs | include missing binary locations |
| docker availability | PASS/FAIL/WARN | `command -v docker`, `systemctl is-enabled/is-active` | include inactive/disabled reason |
| cloud-init | PASS/FAIL/WARN | `cloud-init status`, `boot-finished` marker | include relevant error lines |
| network and IP | PASS/FAIL/WARN | IP/route, `NET_INTERNET`, `DNS`, `HTTPS_EGRESS` | classify restricted/proxy-likely cases |
| proxy values | PASS/FAIL/WARN | `/etc/environment`, k3s/docker proxy files | report permission-denied explicitly |
| CPU/GPU/NPU inventory | PASS/FAIL/WARN | CPU topology, lspci, `/dev/dri` | codename must be verified or `unverified` |
| GPU VF counts | PASS/FAIL/WARN | `sriov_numvfs`, `sriov_totalvfs` | unsupported/not-enabled if files missing |

### Observed Proxy Values

| Variable | Source | Value |
|---|---|---|
| `http_proxy` | `/etc/environment` | `<value or unset>` |
| `https_proxy` | `/etc/environment` | `<value or unset>` |
| `no_proxy` | `/etc/environment` | `<value or unset>` |
| k3s proxy env | `/etc/systemd/system/k3s.service.env` | `<values or permission-denied>` |
| docker proxy | `/etc/systemd/system/docker.service.d/proxy.conf` | `<values or permission-denied>` |

### GPU VF Counts

| Device | `sriov_numvfs` | `sriov_totalvfs` |
|---|---|---|
| `/sys/class/drm/card<N>` | `<n>` | `<total>` |

### Failures and Troubleshooting

| Failed Check | Raw Evidence | Troubleshooting Note |
|---|---|---|
| `<check area>` | `<snippet>` | `<action>` |

## Troubleshooting Notes
- If `kubectl` fails due to kubeconfig permissions, retry with `k3s kubectl`.
- If Docker is installed but inactive, include `systemctl status docker --no-pager` and recent `journalctl -u docker -n 50 --no-pager` output.
- If reading k3s.service.env or docker proxy.conf returns "Permission denied", try: `sudo cat /etc/systemd/system/k3s.service.env` or `sudo cat /etc/systemd/system/docker.service.d/proxy.conf` respectively.
- If pods are `Pending` or `CrashLoopBackOff`, include `kubectl describe` and recent logs for those pods.
- If cloud-init is not complete, inspect `/var/log/cloud-init-output.log` and relevant systemd units.
- If `NET_INTERNET=fail` but `DNS=ok`, classify as "likely proxy required/restricted ICMP" and include proxy values, route output, and `HTTPS_EGRESS` result in findings.
- If detected CPU codename conflicts with known platform information (for example Panther Lake vs Lunar Lake), treat codename as `unverified` unless family/model/stepping mapping confirms it.
- If GPU exists but VF count is 0, report whether SR-IOV is disabled or unsupported on that platform.
