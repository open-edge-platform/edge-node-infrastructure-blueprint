---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: monitor-power-thermal
description: Run a live power and thermal monitor locally on an Intel host using tools/power-tuning/pt_mon.sh (turbostat), sampling package temperature and the RAPL power domains (PkgWatt, CorWatt, GFXWatt, RAMWatt, SysWatt) at a fixed interval and logging to pt_mon.txt. Useful for observing a power profile from set-power-profile under load from generate-platform-stress.
---

## Purpose
`pt_mon.sh` is provided as a **reference** power/thermal monitor (it wraps
`turbostat`). Use it, or any other power-monitoring tool you prefer (e.g.
`turbostat` directly, `powertop`, `intel_gpu_top`, a BMC/OEM utility, or reading
`/sys/class/powercap/intel-rapl*`). This skill only automates the reference
monitor path.

## Terminology
Acronyms and terms used throughout this skill.

| Term | Meaning |
|---|---|
| turbostat | Intel tool that samples CPU frequency, temperature, and power; the monitor wraps it. |
| RAPL | Running Average Power Limit — the Intel hardware feature exposing per-domain energy counters that turbostat reads. |
| PkgTmp | Package temperature (°C) of the CPU package. |
| PkgWatt | Package power — the whole CPU package (cores + integrated GPU + uncore). The most reliable effective figure. |
| CorWatt | Power drawn by the CPU cores portion of the package. |
| GFXWatt | Power drawn by the integrated GPU (graphics) portion of the package. |
| RAMWatt | Power attributed to the DRAM/memory RAPL domain. |
| SysWatt | Platform (psys) power — the whole board; on some silicon the counter is frozen/absent and reads `0.00`. |
| psys | The platform-level RAPL domain that backs SysWatt. |
| MSR | Model-Specific Register — low-level CPU registers turbostat reads (needs the `msr` kernel module); MSR `0x65C` is the psys counter checked here. |
| interval | How often (seconds) turbostat takes a sample (default `2`). |
| duration | How long to monitor; when set, the skill bounds the run, otherwise it streams until stopped. |
| dry_run | Preview mode: show the resolved command without starting the monitor. |

## Trigger Phrases
- monitor platform power
- watch cpu power / watch package power
- live power and thermal monitor
- run turbostat monitor
- log power to file
- observe power under load
- show pkgwatt / gfxwatt / ramwatt live
- capture a power trace for N seconds

## Required Inputs
- enib_home: absolute path to this repository root (default: current workspace root). On a host provisioned with Infrastructure Blueprint, the developer source tree lives at `/opt/edge/developer`, so `enib_home` is `/opt/edge/developer` on the target system.
- duration: optional monitoring window, e.g. `30s`, `2m` (default: run until stopped / Ctrl-C). Implemented by the skill (the script itself samples until interrupted).
- interval: sampling interval in seconds (default: `2`, matching the script). Only applied when the skill is allowed to pass it through; otherwise the script default is used.
- log_path: where to tee the output (default: `<enib_home>/tools/power-tuning/pt_mon.txt`, the script's built-in location when run from that directory).
- dry_run: `true` | `false` (default: `false`). When `true`, only the resolved command is shown; the monitor is not started.
- auto_confirm: `true` | `false` (default: `false`). When `true`, skip the confirmation gate.

## Preconditions
Run silently without user prompts:
- [ ] Skill file exists and is readable:
  - `test -f <enib_home>/skills/monitor-power-thermal/SKILL.md`
- [ ] The monitor script exists and is executable:
  - `test -x <enib_home>/tools/power-tuning/pt_mon.sh`
- [ ] `turbostat` is installed:
  - `command -v turbostat`
  - if missing, stop and instruct: install `linux-tools-generic` (Ubuntu: `sudo apt-get install -y linux-tools-generic`), then re-trigger. Do NOT run `linux-tools-$(uname -r)` in a terminal command — the `$(...)` triggers a VS Code approval dialog; use the generic package name instead.
- [ ] **Sudo probe (MANDATORY before starting the monitor)** (turbostat reads MSRs; the script uses `sudo turbostat`): run `sudo -n true`. If exit is non-zero, do NOT start the monitor; stop and instruct the user to run `sudo -v` in their terminal (or add a scoped `NOPASSWD` entry for the absolute path to `turbostat`, e.g. `/usr/bin/turbostat`, in `/etc/sudoers.d/`), then re-trigger the skill. If `sudo -v` was already run but `sudo -n true` still fails, the user must make sudo timestamps global (tty_tickets issue): `echo 'Defaults timestamp_type=global' | sudo tee /etc/sudoers.d/agent-timestamp && sudo chmod 0440 /etc/sudoers.d/agent-timestamp && sudo visudo -c`. Never collect a password via prompts, env vars, scripts, or logs. See [AGENTS.md](../../AGENTS.md#sudo-handling-must-follow-for-all-skills-that-invoke-sudo).
- [ ] `msr` module available (turbostat + the script's psys check need it):
  - `lsmod | grep -qw msr || sudo modprobe msr 2>/dev/null || true` (non-fatal warning if it cannot load)
- [ ] Host is x86_64 with an Intel CPU (sanity check; non-fatal warning if not):
  - `uname -m` and `grep -m1 -o 'GenuineIntel' /proc/cpuinfo`
- [ ] (Informational) Detect whether the psys/SysWatt domain is live so the report can annotate a `0.00` reading:
  - `grep -qs psys /sys/class/powercap/intel-rapl*/name` → if absent, note `SysWatt` will read `0.00`.
  - else read MSR `0x65C` twice ~1 s apart; if unchanged, note the psys counter is frozen (firmware limitation) → `SysWatt` will read `0.00`.

Prompt only for missing required inputs:
- [ ] Do not prompt; all inputs have safe defaults (2 s interval, run until stopped, tee to `pt_mon.txt`). Only ask if the user's request is ambiguous about `duration`.

Input validation (fail closed before starting):
- [ ] `duration` (if supplied) matches `^[0-9]+(s|m|h)?$`.
- [ ] `interval` (if supplied) is a positive integer.
- [ ] `log_path`'s parent directory exists and is writable.

## Steps
**Terminal command rules (MUST follow for every command in this skill):**
- Always invoke scripts by **absolute path** — never prefix with `cd`.
- Never combine `cd` with any output redirection (`>`, `>>`, `2>`, `2>&1`, `| tee`) in the same compound command — VS Code blocks it with an approval dialog.
- Never use `$(...)` command substitution in terminal commands — VS Code blocks them with an approval dialog. The scripts handle all internal computation themselves.

1. Resolve the command (no start yet):
   - Default: `<enib_home>/tools/power-tuning/pt_mon.sh` run from its directory (tees to `pt_mon.txt`). Invoke by absolute path — do NOT use `cd ... && sudo ./pt_mon.sh` (combines `cd` with the implicit `tee` redirection inside the script).
   - The script hard-codes `turbostat -S --interval 2 --show PkgTmp,PkgWatt,CorWatt,GFXWatt,RAMWatt,SysWatt | tee pt_mon.txt`.
   - If a non-default `interval`, `log_path`, or `duration` is requested, do NOT edit the script; instead run turbostat directly with the same columns, e.g.:
     - `sudo turbostat -S --interval <interval> --show PkgTmp,PkgWatt,CorWatt,GFXWatt,RAMWatt,SysWatt --num_iterations <N>`
     - where `<N> = ceil(duration_seconds / interval)` when a `duration` is given. Pipe to `tee <log_path>` as a separate step if capturing to a file.
2. **Render the Planned Monitor summary** to the user: command, interval, duration (or "until stopped"), log path, and the psys/SysWatt annotation from preconditions.
3. **Confirmation gate** — pause before starting:
   - If `dry_run=true`: report "dry-run only — monitor not started" and stop.
   - Else if `auto_confirm=true`: log `AUTO_CONFIRM=true` and continue.
   - Else: ask "Start power monitor (interval <interval>s, duration <duration or 'until stopped'>, log <log_path>)? (yes/no)". On anything other than `yes`/`y` (case-insensitive), stop and record `CONFIRMATION=declined`.
4. Start the monitor (only after confirmation):
   - **Bounded** (`duration` set): run synchronously with `--num_iterations <N>` (or the default script under `timeout <duration>`); capture exit code and the tee'd log.
   - **Open-ended** (no `duration`): run in the **background** so it does not block; record the turbostat/tee PID and tell the user how to stop it (`sudo pkill -x turbostat`, or Ctrl-C if launched in their own foreground terminal).
5. Confirm sampling started:
   - `test -s <log_path>` and/or `pgrep -x turbostat` returns a PID.
6. Summarize the capture:
   - For bounded runs: report row count and the min/mean/max of `PkgTmp`, `PkgWatt`, and `GFXWatt` parsed from `<log_path>`.
   - For open-ended runs: report the first sampled row and the running PID.

## Validation
Validation section is criteria-only. Do not render the pass/fail results table here.
- Preconditions passed (script executable; `turbostat` present; sudo probe = 0 when a start is intended).
- `duration`/`interval`/`log_path` validated.
- Planned Monitor summary rendered before starting.
- Confirmation gate outcome recorded as one of: `confirmed`, `auto_confirm`, `declined`, `dry_run_only`.
- Start only occurred when the outcome is `confirmed` or `auto_confirm`.
- After start, the log file is non-empty (`test -s`) and/or `turbostat` is running.
- For bounded runs, the process exited with code `0` and the log has at least one data row.
- `SysWatt=0.00` is reported as a known firmware limitation (per the psys detection), NOT a monitor failure.

## Rollback
- Stop an open-ended monitor at any time: `sudo pkill -x turbostat` (or Ctrl-C in the launching terminal).
- Monitoring is read-only; it changes no system state. The only artifact is the log file at `<log_path>` (default `tools/power-tuning/pt_mon.txt`), which the user may delete.

## Safety Rules
- Never collect a sudo password via prompts, env vars, scripts, or logs. Only `sudo -v` (by the user) or a scoped NOPASSWD entry for the absolute path to `turbostat`.
- Do not edit `pt_mon.sh` to change interval/log path; run turbostat directly for non-default parameters.
- The monitor is read-only — do not pair it with any write action implicitly; power capping/stress are separate skills the user must invoke explicitly.
- Do not run against MSRs on non-Intel hardware; warn and stop if the Intel sanity check fails.

## Expected Result Summary
Render the report as the following tables.

### Run Metadata

| Field | Value |
|---|---|
| Preconditions | PASS/FAIL |
| Host | `<uname -m>` + CPU model name |
| Interval | `<interval>s` |
| Duration | `<duration or 'until stopped'>` |
| Log path | `<log_path>` |
| SysWatt availability | `live` / `frozen (0.00)` / `no psys domain (0.00)` |
| Dry run only | `true` / `false` |
| Confirmation | `confirmed` / `auto_confirm` / `declined` / `dry_run_only` |

### Capture Result

(omit when the outcome is `declined` or `dry_run_only`)

| Field | Value |
|---|---|
| Command | `turbostat -S --interval <i> --show PkgTmp,PkgWatt,CorWatt,GFXWatt,RAMWatt,SysWatt` |
| Mode | `synchronous (bounded)` / `background (open-ended)` |
| turbostat PID | `<pid or n/a>` |
| Exit code | `<code or 'running'>` |
| Rows captured | `<n or 'streaming'>` |
| Stop command | `sudo pkill -x turbostat` |

### Sample Summary (bounded runs)

| Metric | Min | Mean | Max |
|---|---|---|---|
| PkgTmp (°C) | `<v>` | `<v>` | `<v>` |
| PkgWatt (W) | `<v>` | `<v>` | `<v>` |
| GFXWatt (W) | `<v>` | `<v>` | `<v>` |

### Validation Results

| Check Area | Status | Evidence | Notes |
|---|---|---|---|
| script executable | PASS/FAIL | `test -x` result | |
| turbostat present | PASS/FAIL | `command -v turbostat` | install hint on FAIL |
| sudo availability | PASS/FAIL/SKIP | `sudo -n true` exit code | SKIP when `dry_run=true` |
| monitor started | PASS/FAIL/N/A | `test -s <log>` / `pgrep -x turbostat` | N/A when not started |
| bounded run completed | PASS/FAIL/N/A | exit code + row count | N/A for open-ended |
| SysWatt annotation | INFO | psys detection result | not a failure |

### Failures and Troubleshooting

| Failed Check | Raw Evidence | Troubleshooting Note |
|---|---|---|
| `<check area>` | `<snippet>` | `<action>` |

## Troubleshooting Notes
- `turbostat: command not found`: install the kernel tools package (`sudo apt-get install -y linux-tools-generic` on Ubuntu), then re-trigger. Use `linux-tools-generic` rather than `linux-tools-$(uname -r)` to avoid the VS Code `$(...)` approval dialog.
- If `sudo -n true` fails: run `sudo -v` in your own terminal, or add a scoped entry via `sudo visudo -f /etc/sudoers.d/monitor-power-thermal`:
  ```
  <user> ALL=(root) NOPASSWD: /usr/bin/turbostat
  ```
  Never use `NOPASSWD: ALL`. Adjust the path to match `command -v turbostat`. If `sudo -v` was already run but `sudo -n true` still fails (tty_tickets), make sudo timestamps global: `echo 'Defaults timestamp_type=global' | sudo tee /etc/sudoers.d/agent-timestamp && sudo chmod 0440 /etc/sudoers.d/agent-timestamp && sudo visudo -c`.
- `SysWatt` reads `0.00`: the platform (psys) RAPL energy counter (MSR 0x65C) is frozen or the psys domain is absent on some Core Ultra platforms (e.g. Core Ultra 5 335 / F6_M204). turbostat derives power as Δenergy/Δtime, so a frozen counter yields `0.00`. This is a firmware limitation; use `PkgWatt` (CPU package = cores + iGPU + uncore) as the effective figure, or measure whole-system power from the battery discharge rate (`/sys/class/power_supply/BAT*/power_now`).
- Blank/zero columns other than SysWatt: confirm the `msr` module is loaded (`lsmod | grep msr`) and that turbostat is recent enough for this CPU (`turbostat --version`).
- To generate load while monitoring, run the `generate-platform-stress` skill (synthetic stress-ng) or `generate-openvino-stress` skill (real AI inference via OpenVINO benchmark_app) in another terminal; to cap power first, use the `set-power-profile` skill.
- The default log file is overwritten each run (`tee`, not `tee -a`); pass a unique `log_path` to keep multiple traces.

## Related Skills
- **generate-platform-stress** — apply configurable synthetic CPU/iGPU load (stress-ng) in another terminal so this monitor captures power/thermals under stress.
- **generate-openvino-stress** — apply real AI inference load (OpenVINO benchmark_app on CPU/GPU/NPU) for power/thermal profiling with realistic compute patterns.
- **set-power-profile** — cap the package/platform power (PkgWatt/SysWatt) before or during a capture to observe the effect of a limit or named profile.
- **Typical loop:** apply a limit/profile → start this monitor → run `generate-platform-stress` or `generate-openvino-stress` → read the min/mean/max summary.
