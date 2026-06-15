---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: tune-platform-power
description: Apply a CPU and/or GPU power profile (battery, balanced, performance, graphical) on a provisioned Intel Core Ultra node over SSH using the tools/power-tuning/ scripts.
---

## Trigger Phrases
- tune platform power
- optimize host for battery life
- optimize host for performance
- tweak power profile for graphics
- apply power profile over ssh
- set cpu power profile
- set gpu power profile
- switch node to battery mode
- switch node to performance mode
- tune gpu for graphical workload

## Required Inputs
- enib_home: absolute path to this repository root (default: current workspace root)
- ssh_host: target node IP or hostname
- ssh_user: remote login user (default: `user`)
- ssh_port: SSH port (default: `22`)
- target: which tuner(s) to run; one of `cpu`, `gpu`, `both` (default: `both`)
- cpu_profile: `battery` | `balanced` | `performance` (required when target is `cpu` or `both`)
- gpu_profile: `battery` | `balanced` | `performance` | `graphical` (required when target is `gpu` or `both`)
- dry_run: `true` | `false` (default: `false`) — when `true`, the apply phase is skipped entirely; only the mandatory dry-run preview runs
- auto_confirm: `true` | `false` (default: `false`) — when `true`, skip the interactive confirmation gate after the dry-run preview (use with care, e.g. for automation)

Note: Private key authentication follows the same pattern as `validate-platform-config`: try direct login first; only on failure fall back to discovering a key under `~/.ssh/`.

## Preconditions
Run silently without user prompts:
- [ ] Skill file exists and is readable:
  - `test -f <enib_home>/skills/tune-platform-power/SKILL.md`
- [ ] Tuner scripts exist locally and are readable:
  - `test -r <enib_home>/tools/power-tuning/tune-cpu-power.sh`
  - `test -r <enib_home>/tools/power-tuning/tune-gpu.sh`
- [ ] SSH client and scp exist locally:
  - `command -v ssh`
  - `command -v scp`
- [ ] Remote host is reachable on SSH port:
  - `timeout 5 bash -c '</dev/tcp/<ssh_host>/<ssh_port>'`
- [ ] Attempt remote login directly using the SSH agent / default keys (no key path required):
  - `ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -p <ssh_port> <ssh_user>@<ssh_host> true`
  - if exit code is `0`, proceed; record `SSH_AUTH=default`
  - only if direct login fails, fall back to explicit key discovery in `~/.ssh/`:
    - Run: `for key in ~/.ssh/id_rsa ~/.ssh/id_ed25519 ~/.ssh/id_ecdsa; do if [ -f "$key" ]; then perms=$(stat -c %a "$key" 2>/dev/null); if [ "$perms" -le 600 ]; then echo "KEY_FOUND=$key"; exit 0; fi; fi; done; echo "KEY_FOUND=none"`
    - if output contains `KEY_FOUND=none`, stop and report missing/unsafe key error
    - retry login with `-i <key>`; if it still fails, stop and report SSH auth error
- [ ] Remote user has passwordless `sudo` (writes to sysfs require root):
  - `ssh ... '<ssh_user>@<ssh_host>' "sudo -n true"`
  - if exit code is non-zero, stop and instruct the user to configure NOPASSWD on the remote node by running:
    ```
    ssh -t <ssh_user>@<ssh_host> "echo '<ssh_user> ALL=(root) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/<ssh_user>-nopasswd && sudo chmod 0440 /etc/sudoers.d/<ssh_user>-nopasswd && sudo visudo -c"
    ```
    Then re-trigger the skill.
- [ ] Target node is x86_64 with an Intel CPU (sanity check; non-fatal warning if not):
  - `ssh ... "uname -m && grep -m1 -o 'GenuineIntel' /proc/cpuinfo || true"`

Prompt only for missing required inputs:
- [ ] Ask for missing `ssh_host` and `ssh_port` only. Assume `ssh_user=user` unless the user overrides it.
- [ ] Ask for `target` if not provided.
- [ ] Ask for `cpu_profile` and/or `gpu_profile` based on the chosen `target`.

## Steps
1. Build SSH/SCP command using the auth method established in preconditions.
  - If `SSH_AUTH=default`:
    - `SSH="ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -p <ssh_port>"`
    - `SCP="scp -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -P <ssh_port>"`
  - Otherwise include `-i $ssh_key` (lowercase `-i` for ssh, `-i` also valid for scp).
  - Remote target: `<ssh_user>@<ssh_host>`.

2. Stage tuner scripts on the remote node.
  - `$SSH <user>@<host> "install -d -m 0755 ~/.cache/enib-power-tuning"`
  - `$SCP <enib_home>/tools/power-tuning/tune-cpu-power.sh <user>@<host>:~/.cache/enib-power-tuning/tune-cpu-power.sh`
  - `$SCP <enib_home>/tools/power-tuning/tune-gpu.sh    <user>@<host>:~/.cache/enib-power-tuning/tune-gpu.sh`
  - `$SSH <user>@<host> "chmod 0755 ~/.cache/enib-power-tuning/tune-cpu-power.sh ~/.cache/enib-power-tuning/tune-gpu.sh"`

3. Capture a brief pre-change snapshot for the report (read-only, no sudo needed when possible):
  - CPU side:
    - `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true`
    - `cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || true`
    - `cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || true`
    - `cat /sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null || true`
    - `cat /sys/firmware/acpi/platform_profile 2>/dev/null || true`
  - GPU side:
    - `for f in /sys/class/drm/card*/gt_max_freq_mhz; do [ -f "$f" ] && echo "$f=$(cat $f)"; done`
    - `for f in /sys/class/drm/card*/device/tile*/gt*/freq0/max_freq; do [ -f "$f" ] && echo "$f=$(cat $f)"; done`

4. **Mandatory dry-run preview** — always runs first, regardless of `dry_run`.
  - If `target` in (`cpu`, `both`):
    - `$SSH <user>@<host> "sudo ~/.cache/enib-power-tuning/tune-cpu-power.sh --profile <cpu_profile> --dry-run"`
  - If `target` in (`gpu`, `both`):
    - `$SSH <user>@<host> "sudo ~/.cache/enib-power-tuning/tune-gpu.sh --profile <gpu_profile> --dry-run"`
  - Parse each tuner's stdout and build a **Planned Changes** summary:
    - count of `APPLY` lines (writes that will happen)
    - count of `SKIP` lines (paths missing / not writable, with reason)
    - list each planned write as `path <= value` grouped by tuner
  - Render the Planned Changes summary to the user before doing anything else.

5. **Confirmation gate** — pause and require explicit user confirmation before any write.
  - If `dry_run=true`: report "dry-run only — no changes applied" and stop after Step 4. Do not proceed.
  - Else if `auto_confirm=true`: log `AUTO_CONFIRM=true` and continue to Step 6 without prompting.
  - Else: prompt the user with the rendered Planned Changes summary and ask:
    - "Apply these changes to `<ssh_user>@<ssh_host>`? (yes/no)"
    - On any answer other than `yes` / `y` (case-insensitive), stop. Do not proceed to Step 6. Report `CONFIRMATION=declined`.

6. Apply the requested profile(s) (only reached after confirmation).
  - If `target` in (`cpu`, `both`):
    - `$SSH <user>@<host> "sudo ~/.cache/enib-power-tuning/tune-cpu-power.sh --profile <cpu_profile>"`
  - If `target` in (`gpu`, `both`):
    - `$SSH <user>@<host> "sudo ~/.cache/enib-power-tuning/tune-gpu.sh --profile <gpu_profile>"`
  - Capture each script's stdout/stderr verbatim for the report; record the exit code.

7. Capture a post-change snapshot using the same read commands as Step 3.

8. (Optional cleanup, only on explicit user request) remove staged scripts:
  - `$SSH <user>@<host> "rm -rf ~/.cache/enib-power-tuning"`

## Validation
Validation section is criteria-only. Do not render the pass/fail results table here.
- SSH connectivity check passes.
- Sudo precondition passes (sudo is required for both the mandatory dry-run preview and the apply phase).
- Scripts copy successfully and become executable on the remote node.
- Mandatory dry-run preview ran for every selected tuner and returned exit code `0`.
- Planned Changes summary was rendered to the user.
- Confirmation gate outcome is recorded as one of: `confirmed`, `auto_confirm`, `declined`, `dry_run_only`.
- Apply phase only executed when the gate outcome is `confirmed` or `auto_confirm`.
- When the apply phase ran, each invoked tuner exits with code `0`.
- Post-change snapshot reflects the requested profile (only when apply phase ran):
  - CPU profile mapping (best-effort, knob present-only):
    - `battery` → `scaling_governor=powersave`, `EPP=power`, `no_turbo=1`, `max_perf_pct=60`, `platform_profile=low-power` (if supported)
    - `balanced` → `EPP=balance_power`, `no_turbo=0`, `max_perf_pct=100`, `platform_profile=balanced`
    - `performance` → `scaling_governor=performance`, `EPP=performance`, `no_turbo=0`, `min_perf_pct>=50`, `platform_profile=performance`
  - GPU profile mapping (per Intel render card with vendor `0x8086`):
    - `battery` → `gt_max_freq_mhz == 30% of gt_RP0_freq_mhz` (floor: RPn)
    - `balanced` → `gt_max_freq_mhz == 50% of gt_RP0_freq_mhz` (floor: RPn)
    - `performance` / `graphical` → `gt_min_freq_mhz == gt_max_freq_mhz == gt_RP0_freq_mhz`
- Knobs that were SKIPped (path missing / not writable) are reported but do not fail the run.

## Rollback
- These changes are not persistent across reboot; rebooting the node restores defaults.
- To revert immediately without rebooting, re-run this skill with the previous profile (or with `balanced` to return to defaults).
- If the staged scripts were copied, they live under `~/.cache/enib-power-tuning/` on the remote node; remove with the optional cleanup step above.

## Safety Rules
- Never print private key contents or paths in user-visible output.
- Do not chain `--profile performance` with thermally constrained scenarios (e.g., fanless enclosures running heavy workloads) without warning the user; report the platform_profile and current package temperature when available.
- Do not enable performance mode on a system reporting battery discharge unless the user confirms (heuristic: `cat /sys/class/power_supply/AC*/online` returns `0`).
- Do not run with `sudo` against hosts that are not the requested `ssh_host`.
- Do not modify or remove anything outside `~/.cache/enib-power-tuning/` on the remote node.

## Expected Result Summary
Render the report as the following tables.

### Run Metadata

| Field | Value |
|---|---|
| Preconditions | PASS/FAIL |
| SSH endpoint | `<ssh_user>@<ssh_host>:<ssh_port>` |
| Auth method | `default` (agent/default keys) or `key:<auto-discovered key name>` (mask path) |
| Target | `cpu` / `gpu` / `both` |
| CPU profile | `<cpu_profile or n/a>` |
| GPU profile | `<gpu_profile or n/a>` |
| Dry run only | `true` / `false` |
| Confirmation | `confirmed` / `auto_confirm` / `declined` / `dry_run_only` |

### Planned Changes (from mandatory dry-run)

| Tuner | APPLY count | SKIP count | Planned writes (path <= value) |
|---|---|---|---|
| tune-cpu-power.sh | `<n>` | `<n>` | `<list or 'n/a'>` |
| tune-gpu.sh | `<n>` | `<n>` | `<list or 'n/a'>` |

### Apply Results

(omit this table when the gate outcome is `declined` or `dry_run_only`)

| Tuner | Exit Code | APPLY count | SKIP count | Notes |
|---|---|---|---|---|
| tune-cpu-power.sh | `<code>` | `<n>` | `<n>` | summarize first failure if any |
| tune-gpu.sh | `<code>` | `<n>` | `<n>` | summarize first failure if any |

### CPU Knob Snapshot (pre → post)

| Knob | Before | After | Expected for profile |
|---|---|---|---|
| `scaling_governor` (cpu0) | `<value>` | `<value>` | `<expected or n/a>` |
| `energy_performance_preference` (cpu0) | `<value>` | `<value>` | `<expected or n/a>` |
| `intel_pstate/no_turbo` | `<value>` | `<value>` | `<expected or n/a>` |
| `intel_pstate/max_perf_pct` | `<value>` | `<value>` | `<expected or n/a>` |
| `platform_profile` | `<value>` | `<value>` | `<expected or n/a>` |

### GPU Knob Snapshot (pre → post)

| Card | Knob | Before | After | Expected for profile |
|---|---|---|---|---|
| `cardN` | `gt_max_freq_mhz` (or `freq0/max_freq`) | `<MHz>` | `<MHz>` | `<RP0/RPn>` |
| `cardN` | `gt_min_freq_mhz` (or `freq0/min_freq`) | `<MHz>` | `<MHz>` | `<RP0/RPn>` |

### Validation Results

| Check Area | Status | Evidence | Notes |
|---|---|---|---|
| SSH connectivity | PASS/FAIL | `ssh ... true` exit code | include auth method |
| sudo availability | PASS/FAIL/SKIP | `sudo -n true` exit code | SKIP allowed when `dry_run=true` |
| script staging | PASS/FAIL | scp result + remote `ls -l` | include destination path |
| tune-cpu-power.sh apply | PASS/FAIL/N/A | exit code + APPLY/SKIP counts | first error line on FAIL |
| tune-gpu.sh apply | PASS/FAIL/N/A | exit code + APPLY/SKIP counts | first error line on FAIL |
| post-change CPU snapshot matches profile | PASS/FAIL/N/A | pre→post diff | N/A when `dry_run=true` |
| post-change GPU snapshot matches profile | PASS/FAIL/N/A | pre→post diff | N/A when `dry_run=true` |

### Failures and Troubleshooting

| Failed Check | Raw Evidence | Troubleshooting Note |
|---|---|---|
| `<check area>` | `<snippet>` | `<action>` |

## Troubleshooting Notes
- If `sudo -n true` fails: configure passwordless sudo on the remote node by running interactively:
  ```
  ssh -t <ssh_user>@<ssh_host> "echo '<ssh_user> ALL=(root) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/<ssh_user>-nopasswd && sudo chmod 0440 /etc/sudoers.d/<ssh_user>-nopasswd && sudo visudo -c"
  ```
  For a scoped entry (more secure), replace `ALL` with the specific script paths:
  ```
  ssh -t <ssh_user>@<ssh_host> "echo '<ssh_user> ALL=(root) NOPASSWD: /home/<ssh_user>/.cache/enib-power-tuning/tune-cpu-power.sh, /home/<ssh_user>/.cache/enib-power-tuning/tune-gpu.sh' | sudo tee /etc/sudoers.d/enib-power-tuning && sudo chmod 0440 /etc/sudoers.d/enib-power-tuning && sudo visudo -c"
  ```
- If many CPU knobs are SKIPped on `intel_pstate/*` paths: confirm the `intel_pstate` driver is active with `cat /sys/devices/system/cpu/intel_pstate/status` (expect `active`).
- If `platform_profile` writes are SKIPped: confirm the firmware exposes choices with `cat /sys/firmware/acpi/platform_profile_choices`; some OEM firmware does not expose this interface.
- If GPU writes are SKIPped on all paths: confirm an Intel render card is present (`lspci -nn | grep -Ei 'vga|display|3d' | grep -i intel`) and the active driver (`grep -H . /sys/class/drm/card*/device/driver/module/version 2>/dev/null || readlink /sys/class/drm/card*/device/driver`).
- If SR-IOV scheduling knobs are SKIPped: the debugfs paths only appear when VFs are configured (`echo N > /sys/class/drm/cardX/device/sriov_numvfs`); this is expected on systems without SR-IOV.
- If `performance` profile produces no measurable change: the platform may already be at hw max under HWP; verify with `turbostat --quiet --interval 1 --num_iterations 3` if available.
- To make a profile persist across reboots, install the script invocation as a systemd unit; this skill intentionally does not modify persistent state.
