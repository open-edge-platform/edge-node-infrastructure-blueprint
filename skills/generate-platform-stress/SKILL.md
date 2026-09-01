---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: generate-platform-stress
description: Create controlled CPU and integrated-GPU load on an Intel host to see how the platform behaves when it is busy. Choose how many CPU workers to run, how hard each one pushes (per-CPU load %), how many GPU workers to run, and how long the load lasts — then start it with a single command via tools/power-tuning/stress_gen.sh (stress-ng). Ideal for validating a power profile or power cap under real load, checking thermal and power headroom, and running repeatable burn-in or benchmarking workloads.
---

## Purpose
`stress_gen.sh` generates a **simulated** load (via stress-ng) for evaluation
purposes. Use it when you want a controlled, repeatable synthetic load — or
substitute the **actual workload** you want to evaluate. Either drives the
platform so a power profile/cap and the power monitor can be assessed; this
skill only automates the simulated path.

## Terminology
Acronyms and terms used throughout this skill.

| Term | Meaning |
|---|---|
| stress-ng | The load-generation tool this skill drives to exercise the CPU and integrated GPU. |
| CPU worker | One stress-ng process pinned to CPU work; `cpus` sets how many run in parallel. |
| load (per-CPU %) | How hard each CPU worker pushes, `1..100` (100 = flat out). |
| GPU worker | A stress-ng process targeting the single iGPU; `gpu` is a **worker count**, not a number of GPUs. |
| iGPU | The integrated GPU inside the CPU package (exposed as an Intel render node). |
| render node | `/dev/dri/renderD*` — the device GPU workers use; absent = software-rendering fallback. |
| nproc | The number of logical CPUs; the default and upper bound for `cpus`. |
| PkgTmp / PkgWatt | Package temperature / power (from turbostat) sampled before and during load for the report. |
| PL1 / PL2 | Sustained / short-burst power limits; a bounded stress run reveals sustained (PL1) vs burst (PL2) behavior. |
| duration | How long to run (stress-ng time syntax, e.g. `60s`, `5m`); omit to run until stopped. |
| dry_run | Preview mode: show the resolved command without launching anything. |

## Trigger Phrases
- generate platform stress
- stress the cpu / stress the gpu
- create cpu load / create gpu load
- run a stress test
- load the platform for power measurement
- stress-ng cpu gpu
- burn-in the cpu
- stress N cpus at P percent
- exercise the power profile under load

## Required Inputs
- enib_home: absolute path to this repository root (default: current workspace root). On a host provisioned with Infrastructure Blueprint, the developer source tree lives at `/opt/edge/developer`, so `enib_home` is `/opt/edge/developer` on the target system.
- cpus: number of CPU workers, `1..nproc` (default: all CPUs / `nproc`)
- load: per-CPU load percentage, `1..100` (default: `100`)
- gpu: number of stress-ng GPU worker processes targeting the single iGPU, `0..12` (default: `4`; `0` disables GPU stress). This is a worker count, NOT a GPU count. Use a maximum of `4` workers for a 4 Xe-core iGPU and `12` workers for a 12 Xe-core iGPU.
- duration: optional stress-ng timeout, e.g. `60s`, `5m`, `2h` (default: run until stopped / Ctrl-C)
- dry_run: `true` | `false` (default: `false`). When `true`, only the resolved command is shown; nothing is launched.
- auto_confirm: `true` | `false` (default: `false`). When `true`, skip the confirmation gate.

## Preconditions
Run silently without user prompts:
- [ ] Skill file exists and is readable:
  - `test -f <enib_home>/skills/generate-platform-stress/SKILL.md`
- [ ] The stress script exists and is executable:
  - `test -x <enib_home>/tools/power-tuning/stress_gen.sh`
- [ ] `stress-ng` is installed:
  - `command -v stress-ng`
  - if missing, stop and instruct: `sudo apt-get install -y stress-ng` (Debian/Ubuntu), then re-trigger.
- [ ] No stress-ng instance is already running (the script refuses to stack stressors):
  - `pgrep -x stress-ng`
  - if a PID is found, stop and report it; instruct the user to stop it first (`sudo pkill -x stress-ng`) before re-triggering.
- [ ] Determine the CPU worker ceiling:
  - `nproc` → `NCPU_MAX` (used to validate/derive `cpus`).
- [ ] Host is x86_64 with an Intel CPU (sanity check; non-fatal warning if not):
  - `uname -m` and `grep -m1 -o 'GenuineIntel' /proc/cpuinfo`
- [ ] (GPU only, non-fatal) an Intel render node exists when `gpu > 0`:
  - `ls /dev/dri/renderD* 2>/dev/null` — if absent, warn that GPU workers may fall back to software rendering.

Prompt only for missing required inputs:
- [ ] Do not prompt for any value; all inputs have safe defaults (all CPUs at 100% + 12 GPU workers, run until stopped). Only ask if the user's request is ambiguous about whether GPU stress is wanted.

Input validation (fail closed before launch):
- [ ] `cpus` is an integer in `[1, NCPU_MAX]`.
- [ ] `load` is an integer in `[1, 100]`.
- [ ] `gpu` is an integer in `[0, 12]`.
- [ ] `duration` (if supplied) matches stress-ng time syntax: `^[0-9]+(s|m|h|d)?$`.

## Steps
**Terminal command rules (MUST follow for every command in this skill):**
- Always invoke scripts by **absolute path** — never prefix with `cd`.
- Never combine `cd` with any output redirection in the same compound command — VS Code blocks it with an approval dialog.
- Never use `$(...)` command substitution in terminal commands — VS Code blocks them with an approval dialog. The scripts handle all internal computation themselves.

1. Resolve the effective parameters and build the command (no launch yet):
   - Base: `<enib_home>/tools/power-tuning/stress_gen.sh --cpus <cpus> --load <load> --gpu <gpu>`
   - Append `--duration <duration>` only when supplied.
   - Note: no `sudo` is required; stress-ng runs as the current user.
2. Capture a brief pre-stress snapshot for the report (read-only, best-effort; **skip entirely when `dry_run=true`**):
   - load average: `cat /proc/loadavg`
   - package temp/power if turbostat is available (single sample): `turbostat --quiet --interval 1 --num_iterations 1 --show PkgTmp,PkgWatt 2>/dev/null || true`
3. **Always render a Planned Load table** from the resolved parameters before any launch — show it unconditionally, including when `auto_confirm=true`:

   | Parameter | Value |
   |---|---|
   | Command | `<resolved stress_gen.sh command>` |
   | CPU workers | `<cpus>` of `<nproc>` |
   | Load per CPU | `<load>%` |
   | GPU workers | `<gpu>` (0 = off) |
   | Duration | `<duration or 'until stopped'>` |
   | GPU render node | `<path or 'not found (software fallback)'>` |

4. **Confirmation gate** — pause before launching:
   - If `dry_run=true`: stop here and record `CONFIRMATION=dry_run_only`. Do not launch.
   - Else if `auto_confirm=true`: log `AUTO_CONFIRM=true` and continue.
   - Else: present the tabulated Planned Load and ask "Launch stress (<cpus> CPUs @ <load>%, <gpu> GPU workers, duration=<duration or 'until stopped'>)? (yes/no)". On anything other than `yes`/`y` (case-insensitive), stop and record `CONFIRMATION=declined`.
5. Launch (only after confirmation):
   - If `duration` is set: run **synchronously** and let it complete; capture exit code.
   - If `duration` is NOT set (runs until stopped): run in the **background** so the run does not block; record the PID(s) via `pgrep -x stress-ng` and tell the user how to stop it (`sudo pkill -x stress-ng`, or Ctrl-C if launched in their own foreground terminal).
6. Confirm the stressor is active shortly after launch:
   - `pgrep -x stress-ng` returns at least one PID (for bounded runs, this is checked before completion).
7. **Verify GPU load is real (only when `gpu > 0`)** — a running GPU worker does
   not by itself prove the iGPU is busy; it may be falling back to software
   rendering. Confirm with as many of these as are available (best-effort,
   read-only):
   - **iGPU engine utilization** (most direct): `sudo intel_gpu_top -o - -s 1000` for a
     couple of samples, or interactive `sudo intel_gpu_top`. The **Render/3D**
     (and Blitter/Video) engine busy % should climb well above idle (toward
     ~100%). Requires `intel-gpu-tools` (`sudo apt-get install -y intel-gpu-tools`).
   - **Graphics power rises**: sample `GFXWatt` via turbostat
     (`turbostat --quiet --interval 1 --num_iterations 1 --show PkgTmp,PkgWatt,GFXWatt 2>/dev/null || true`)
     or the `monitor-power-thermal` skill — `GFXWatt` should rise above its idle
     value under GPU load and fall when the run stops.
   - **Workers hold the render node**: `sudo fuser -v /dev/dri/renderD128` should
     list `stress-ng-gpu` PIDs attached to the device (proves attachment, not
     work — pair with one of the signals above).
   - If none of these move while GPU workers are "running", the load is not
     reaching the iGPU (software fallback); note it and treat the run as CPU-only.
8. Capture a post/steady-state snapshot using the same reads as Step 2 (for bounded runs after completion; for open-ended runs, one sample a few seconds in).

## Validation
Validation section is criteria-only. Do not render the pass/fail results table here.
- Preconditions passed (script executable; `stress-ng` present; no pre-existing stress-ng instance).
- `cpus`, `load`, `gpu`, and `duration` validated against their ranges/syntax.
- A Planned Load table was rendered unconditionally before the confirmation gate.
- Confirmation gate outcome recorded as one of: `confirmed`, `auto_confirm`, `declined`, `dry_run_only`.
- Launch only occurred when the outcome is `confirmed` or `auto_confirm`.
- After launch, `pgrep -x stress-ng` shows the expected activity (one or more workers).
- For bounded runs (`duration` set), the script exited with code `0` at completion.
- For open-ended runs, the PID(s) and stop instructions were reported to the user.

## Rollback
- Stop an open-ended run at any time: `sudo pkill -x stress-ng` (or Ctrl-C in the launching terminal).
- Stress load is transient and leaves no persistent state; stopping the process fully restores idle behaviour.
- If a power profile was applied via `set-power-profile` before stressing, the profile persists (runtime-only) until reboot regardless of the stress run.

## Safety Rules
- Do not launch if another stress-ng instance is already running (respect the script's own guard) — stacking stressors skews load and any power measurements.
- Warn before an **open-ended** (no `duration`) high-load run on thermally constrained or fanless enclosures; recommend a bounded `duration` and monitoring temperature (see `pt_mon.sh`).
- Do not run with `sudo` (stress-ng needs no root here); only use `sudo` for the documented `pkill` stop command.
- Do not launch GPU workers (`gpu > 0`) as a way to interfere with a live display/compositor workload without the user's awareness.
- Never mask a failing precondition (missing stress-ng, existing instance) as success.

## Expected Result Summary
Render the report as the following tables.

### Run Metadata

| Field | Value |
|---|---|
| Preconditions | PASS/FAIL |
| Host | `<uname -m>` + CPU model name |
| CPU workers | `<cpus>` of `<NCPU_MAX>` |
| Per-CPU load | `<load>%` |
| GPU workers | `<gpu>` (0 = off) |
| Duration | `<duration or 'until stopped'>` |
| Dry run only | `true` / `false` |
| Confirmation | `confirmed` / `auto_confirm` / `declined` / `dry_run_only` |


### Launch Result

(omit when the outcome is `declined` or `dry_run_only`)

| Field | Value |
|---|---|
| Command | `stress_gen.sh --cpus <n> --load <p> --gpu <g> [--duration <d>]` |
| Mode | `synchronous (bounded)` / `background (open-ended)` |
| stress-ng PID(s) | `<pids or n/a>` |
| Exit code | `<code or 'running'>` |
| Stop command | `sudo pkill -x stress-ng` |

### Load Snapshot (pre → during/post)

| Metric | Before | During/After |
|---|---|---|
| loadavg (1m) | `<value>` | `<value>` |
| PkgTmp (°C) | `<value or n/a>` | `<value or n/a>` |
| PkgWatt (W) | `<value or n/a>` | `<value or n/a>` |
| GFXWatt (W) | `<value or n/a>` | `<value or n/a>` |

### GPU Load Verification

(only when `gpu > 0`; omit when the outcome is `declined` or `dry_run_only`)

| Signal | Idle / Before | Under Load | Verdict |
|---|---|---|---|
| iGPU engine busy % (`intel_gpu_top`) | `<value or n/a>` | `<value or n/a>` | loaded / software-fallback / n/a |
| GFXWatt (turbostat) | `<value or n/a>` | `<value or n/a>` | rose / flat / n/a |
| Render node holders (`fuser`) | — | `<stress-ng-gpu PID count or n/a>` | attached / none |

### Validation Results

| Check Area | Status | Evidence | Notes |
|---|---|---|---|
| script executable | PASS/FAIL | `test -x` result | |
| stress-ng present | PASS/FAIL | `command -v stress-ng` | install hint on FAIL |
| no pre-existing instance | PASS/FAIL | `pgrep -x stress-ng` | list PIDs on FAIL |
| input range/syntax | PASS/FAIL | cpus/load/gpu/duration checks | |
| stressor active | PASS/FAIL/N/A | `pgrep -x stress-ng` after launch | N/A when not launched |
| iGPU actually loaded | PASS/FAIL/N/A | engine busy % / GFXWatt rise / render-node holders | N/A when `gpu = 0`; FAIL = software fallback |
| bounded run completed | PASS/FAIL/N/A | exit code | N/A for open-ended |

### Failures and Troubleshooting

| Failed Check | Raw Evidence | Troubleshooting Note |
|---|---|---|
| `<check area>` | `<snippet>` | `<action>` |

## Troubleshooting Notes
- `stress-ng: command not found`: install it with `sudo apt-get install -y stress-ng` (Debian/Ubuntu) and re-trigger.
- "stress-ng is already running": another instance is active. Stop it with `sudo pkill -x stress-ng` (confirm with the user first), then re-trigger.
- **Verify the iGPU is actually loaded** (a running GPU worker is not proof — it
  can fall back to software rendering). In order of directness:
  - `sudo intel_gpu_top` (from `intel-gpu-tools`) — the **Render/3D** engine busy
    % should climb toward ~100% under load. Near-0% while workers run = fallback.
  - `GFXWatt` in `pt_mon.sh` / turbostat should rise above idle and drop when
    the run stops.
  - `sudo fuser -v /dev/dri/renderD128` should list `stress-ng-gpu` PIDs holding
    the render node (confirms attachment; pair with one of the signals above to
    confirm real work).
- GPU workers show little effect: confirm an Intel render node exists (`ls /dev/dri/renderD*`) and that the build of stress-ng includes the `gpu` stressor (`stress-ng --gpu 1 --timeout 2s` should succeed); otherwise use `--gpu 0` and stress CPU only.
- To watch the effect under load, run [tools/power-tuning/pt_mon.sh](tools/power-tuning/pt_mon.sh) in another terminal (PkgTmp/PkgWatt), remembering that `SysWatt` may read `0.00` on platforms with a frozen psys counter.
- To combine with a power cap, apply a profile first via the `set-power-profile` skill, then run this skill with a bounded `duration` to observe sustained (PL1) vs burst (PL2) behaviour.
- An open-ended run keeps the CPUs busy indefinitely; always provide a `duration` for automated/unattended use so it self-terminates.

## Related Skills
- **monitor-power-thermal** — run in another terminal to record PkgTmp/PkgWatt/GFXWatt while this load runs; the two are designed to be paired.
- **set-power-profile** — apply a package/platform power cap or named profile first, then stress to see how the limit holds under load.
- **Typical loop:** apply a limit/profile → start `monitor-power-thermal` → run this skill with a bounded `duration` → read the min/mean/max summary.
