---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: validate-platform-config
description: Validate whether a provisioned platform is correctly configured when run locally on that host, including k3s pod health, binary paths, cloud-init state, network and proxy setup, and device readiness.
---

## Trigger Phrases
- validate platform config
- validate provisioned host
- check provisioned node health
- validate k3s platform readiness
- post provision local validation
- host health check

## Required Inputs
- enib_home: absolute path to this repository root (default: current workspace root)
- kubeconfig_path: expected kubeconfig path (default: `/etc/rancher/k3s/k3s.yaml`)

## Preconditions
Run silently without user prompts:
- [ ] Skill file exists and is readable:
  - `test -f <enib_home>/skills/validate-platform-config/SKILL.md`
- [ ] Verify this skill is running on the provisioned host (local execution model):
  - `test -f /etc/cloud/config-file`
- [ ] Required local tools exist:
  - `command -v grep`
  - `command -v ip`
  - `command -v systemctl`
  - `command -v lscpu`
  - `command -v lspci`
  - `command -v curl`
- [ ] Probe sudo non-interactively before any sudo fallback command:
  - `sudo -n true`
  - if exit code is `0`, record `SUDO_NONINTERACTIVE=yes`
  - if non-zero, record `SUDO_NONINTERACTIVE=no` and skip sudo fallback commands later (do not fail preconditions)

Prompt only for missing required inputs:
- [ ] Ask only for missing `enib_home` and/or `kubeconfig_path`.

## Steps
1. Detect the `host_type` from local configuration.
  - command:
    - `grep -E '^host_type' /etc/cloud/config-file 2>/dev/null || echo 'host_type=unknown'`
  - parse the output to extract the value (e.g. `kubernetes`, `container`, or `unknown`)
  - store as `HOST_TYPE` for conditional branching in Steps 2 and 3

2. **If HOST_TYPE=kubernetes**: Validate k3s pods and device plugins.
  - command (try in order until one succeeds):
    - `kubectl get pods -A --no-headers`
    - `KUBECONFIG=~/.kube/config kubectl get pods -A --no-headers`
    - if `SUDO_NONINTERACTIVE=yes`: `sudo -n kubectl get pods -A --no-headers`
    - if `SUDO_NONINTERACTIVE=yes`: `sudo -n k3s kubectl get pods -A --no-headers`
  - required pod name prefixes and expected status:
    - `intel-gpu-plugin` in `default` namespace, `Running`, `READY 1/1`
    - `intel-npu-plugin` in `default` namespace, `Running`, `READY 1/1`
    - `coredns` in `kube-system`, `Running`, `READY 1/1`
    - `local-path-provisioner` in `kube-system`, `Running`, `READY 1/1`
    - `metrics-server` in `kube-system`, `Running`, `READY 1/1`
    - `nfd-gc` in `node-feature-discovery`, `Running`, `READY 1/1`
    - `nfd-master` in `node-feature-discovery`, `Running`, `READY 1/1`
    - `nfd-worker` in `node-feature-discovery`, `Running`, `READY 1/1`
  - also validate binaries:
    - `command -v kubectl`
    - `command -v k3s`
    - `ls -l /usr/local/bin/kubectl /usr/local/bin/k3s 2>/dev/null || true`
    - `systemctl is-enabled k3s 2>/dev/null || true`
    - `systemctl is-active k3s 2>/dev/null || true`
  - expected:
    - `k3s` found in PATH
    - `kubectl` found in PATH (binary or symlink)
    - one of expected locations exists: `/usr/local/bin/kubectl`, `/usr/bin/kubectl`
    - one of expected locations exists: `/usr/local/bin/k3s`, `/usr/bin/k3s`
    - k3s service is enabled and active

3. **If HOST_TYPE!=kubernetes** (container or unknown): Validate Docker, Docker Compose, and Container Device Interface (CDI).
  - commands:
    - `command -v docker`
    - `docker --version 2>/dev/null || true`
    - `docker compose version 2>/dev/null || true`
    - `ls -l /usr/local/bin/docker /usr/bin/docker 2>/dev/null || true`
    - `systemctl is-enabled docker 2>/dev/null || true`
    - `systemctl is-active docker 2>/dev/null || true`
    - `docker info 2>/dev/null | grep -E 'Server Version|Storage Driver|Cgroup|data-root' || true`
    - `ls /etc/cdi/ 2>/dev/null || true`
    - `ls /var/run/cdi/ 2>/dev/null || true`
    - `cat /etc/cdi/*.json 2>/dev/null | python3 -c "import sys,json; [print(d.get('kind','?')) for d in json.load(sys.stdin).get('cdiDevices',json.load(open('/dev/stdin'))) if isinstance(d,dict)]" 2>/dev/null || ls /etc/cdi/ 2>/dev/null || true`
    - `docker info 2>/dev/null | grep -i cdi || true`
  - expected:
    - `docker` found in PATH
    - Docker version reported
    - Docker Compose plugin available (`docker compose version` succeeds)
    - Docker service is enabled and active
    - CDI spec files present in `/etc/cdi/` or `/var/run/cdi/` (e.g. `intel-gpu.json`, `intel-npu.json`)
    - CDI devices exposed to Docker runtime

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

6. Collect proxy values (brief).
  - command:
    - `grep -hsE '^(https?_proxy|no_proxy)=' /etc/environment 2>/dev/null | head -5 || echo 'no proxy configured'`
  - expected:
    - report proxy variables from `/etc/environment` if set; otherwise report "no proxy configured"
    - do NOT dump k3s.service.env or docker proxy.conf unless network checks in Step 6 indicate proxy issues

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
    - if `core_type` is not exposed by the kernel or platform, report P/E/LPE counts as `unavailable`
    - CPU model, family, stepping, and feature flags documented
    - CPU codename is reported only when verified from trusted identifiers (family/model/stepping mapping); never infer codename from model name text alone
    - if codename cannot be verified confidently, report `CPU_CODENAME=unverified` instead of guessing
    - CPU frequency scaling driver reported
    - Core type information from `/sys/devices/system/cpu/cpu*/topology/core_type` is decoded using common Linux hybrid mapping (`2=P`, `1=E`, `3=LPE`) and may vary by kernel/platform
    - Thread siblings mapping for logical CPU layout
    - GPU presence determined from Peripheral Component Interconnect (PCI) and/or `/dev/dri`
    - NPU presence determined from PCI scan output

8. If GPU is present, report GPU Virtual Function (VF) counts.
  - commands:
    - `for f in /sys/class/drm/card*/device/sriov_numvfs; do [ -f "$f" ] && echo "$f=$(cat $f)"; done`
    - `for f in /sys/class/drm/card*/device/sriov_totalvfs; do [ -f "$f" ] && echo "$f=$(cat $f)"; done`
  - expected:
    - report per-GPU `sriov_numvfs` and `sriov_totalvfs`
    - if GPU exists but no SR-IOV files are present, report as unsupported/not enabled.

9. Check SR-IOV service if `enable_sriov` is set to true.
  - first check:
    - `grep -E '^enable_sriov' /etc/cloud/config-file 2>/dev/null || echo 'enable_sriov=unset'`
  - if value is `true`, validate:
    - `systemctl is-enabled intel-sriov-vf.service 2>/dev/null || echo 'not-found'`
  - expected:
    - if enabled: report `intel-sriov-vf.service` is enabled — VFs will be preserved across reboots
    - if disabled/not-found: report service not enabled — VFs will NOT persist across reboots
    - if `enable_sriov` is not `true`, SKIP this check

## Validation
Validation section is criteria-only. Do not render the pass/fail results table here.
- `host_type` is detected and reported; conditional checks branch accordingly.
- **If kubernetes**: All required k3s pods listed in Step 2 are found in the correct namespaces and are healthy (`Running`, `1/1`); `kubectl` and `k3s` binaries are present.
- **If container/unknown**: Docker and Docker Compose are available, Docker service is active, and CDI specification files are present.
- cloud-init completion indicators are successful.
- Network check reports assigned IP and route; connectivity is classified as direct or proxy/restricted with explicit reason.
- Proxy values are collected briefly from `/etc/environment`; expanded only if network issues are detected.
- CPU/GPU/NPU inventory is collected with clear present/absent status.
- CPU codename labeling is verification-based and avoids false platform naming.
- GPU VF data is reported when the GPU exists.
- SR-IOV service (`intel-sriov-vf.service`) is validated when `enable_sriov=true` in config-file.

## Rollback
This is a read-only validation skill. No rollback required.

## Safety Rules
- Prefer read-only commands; do not alter target host configuration in this skill.
- Do not use destructive or privileged write operations.
- If a check fails, continue collecting remaining checks and return a complete report.

## Expected Result Summary
Render the report as the following tables.

### Run Metadata

| Field | Value |
|---|---|
| Preconditions | PASS/FAIL |
| Execution mode | `local` |
| Host context | `provisioned host` |
| Sudo fallback availability | `yes/no` from `sudo -n true` probe |

### Validation Results

| Check Area | Status | Evidence | Notes |
|---|---|---|---|
| host_type detection | PASS/FAIL/WARN | value from `/etc/cloud/config-file` | `kubernetes`, `container`, or `unknown` |
| k3s pods (kubernetes only) | PASS/FAIL/WARN/SKIP | key pod states from `kubectl get pods -A` | skipped if host_type!=kubernetes |
| k3s binaries (kubernetes only) | PASS/FAIL/WARN/SKIP | `command -v k3s`, `kubectl` | skipped if host_type!=kubernetes |
| docker + compose (container only) | PASS/FAIL/WARN/SKIP | `docker --version`, `docker compose version` | skipped if host_type=kubernetes |
| CDI specs (container only) | PASS/FAIL/WARN/SKIP | `/etc/cdi/`, `/var/run/cdi/` contents | skipped if host_type=kubernetes |
| cloud-init | PASS/FAIL/WARN | `cloud-init status`, `boot-finished` marker | include relevant error lines |
| network and IP | PASS/FAIL/WARN | IP/route, `NET_INTERNET`, `DNS`, `HTTPS_EGRESS` | classify restricted/proxy-likely cases |
| proxy values | PASS/FAIL/WARN | `/etc/environment` summary | only expanded if network issues detected |
| SR-IOV service | PASS/FAIL/WARN/SKIP | `intel-sriov-vf.service` state | skipped if enable_sriov!=true |
| CPU/GPU/NPU inventory | PASS/FAIL/WARN | CPU topology, lspci, `/dev/dri` | codename must be verified or `unverified` |
| GPU VF counts | PASS/FAIL/WARN | `sriov_numvfs`, `sriov_totalvfs` | unsupported/not-enabled if files missing |

### Observed Proxy Values

| Variable | Value |
|---|---|
| `http_proxy` | `<value or unset>` |
| `https_proxy` | `<value or unset>` |
| `no_proxy` | `<value or unset>` |

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
- If reading k3s.service.env or docker proxy.conf returns "Permission denied" and `SUDO_NONINTERACTIVE=yes`, try: `sudo -n cat /etc/systemd/system/k3s.service.env` or `sudo -n cat /etc/systemd/system/docker.service.d/proxy.conf` respectively.
- If pods are `Pending` or `CrashLoopBackOff`, include `kubectl describe` and recent logs for those pods.
- If cloud-init is not complete, inspect `/var/log/cloud-init-output.log` and relevant systemd units.
- If `NET_INTERNET=fail` but `DNS=ok`, classify as "likely proxy required/restricted ICMP" and include proxy values, route output, and `HTTPS_EGRESS` result in findings.
- If detected CPU codename conflicts with known platform information (for example Panther Lake vs Lunar Lake), treat codename as `unverified` unless family/model/stepping mapping confirms it.
- If GPU exists but VF count is 0, report whether SR-IOV is disabled or unsupported on that platform.
