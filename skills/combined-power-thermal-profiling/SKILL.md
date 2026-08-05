---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: combined-power-thermal-profiling
description: Orchestrate a full platform profiling session on an Intel host — apply a power envelope and thermal policy, start the power/thermal monitor, drive a bounded stress load, then summarize the result as a single enclosure report. Chains set-power-profile → set-thermal-profile → monitor-power-thermal → generate-platform-stress and emits one consolidated report (min/mean/max of PkgTmp / PkgWatt / GFXWatt plus throttle/headroom verdict). Ideal for qualifying whether an enclosure can sustain a chosen profile under load before it ships.
---

## Purpose
`combined-power-thermal-profiling` is an **orchestrator** skill: it runs the full
**apply → monitor → stress → summarize** loop end to end and emits a single
enclosure report, instead of requiring the operator to invoke the four
power-tuning skills separately and stitch the results together.

It does **not** wrap a new script. It sequences the existing reference skills:

1. **CONSTRAIN** — `set-power-profile` (RAPL PkgWatt/SysWatt cap + `intel_lpmd`)
   and, when requested, `set-thermal-profile` (thermald trip points).
2. **OBSERVE** — `monitor-power-thermal` (turbostat → `pt_mon.txt`), bounded
   to the stress window.
3. **LOAD** — `generate-platform-stress` (stress-ng CPU + iGPU), bounded by
   `duration`.
4. **SUMMARIZE** — parse the captured trace and emit one enclosure report:
   min/mean/max of `PkgTmp` / `PkgWatt` / `GFXWatt`, whether the package power
   held at the target, and whether the thermal trips engaged / throttling
   occurred.

Each underlying skill still runs its own preconditions, dry-run, confirmation
gate, and validation. This orchestrator adds cross-skill sequencing, a single
combined confirmation, and the consolidated report. Use it to answer one
question: **"can this enclosure sustain profile X under load Y without
throttling?"**

## Terminology
Acronyms and terms used throughout this skill. See the underlying skills for the
full glossaries.

| Term | Meaning |
|---|---|
| enclosure | The physical chassis / thermal environment being qualified (fanless kiosk, sealed edge box, etc.). |
| profiling session | One apply → monitor → stress → summarize pass at a fixed power (and thermal) profile. |
| power profile | The PkgWatt/SysWatt envelope applied by `set-power-profile` (LowPower … MaxPerformance or Custom). |
| thermal profile | The thermald trip points applied by `set-thermal-profile` (cool/warm/hot/thermal-max or custom). |
| PkgTmp / PkgWatt / GFXWatt | Package temperature / package power / integrated-GPU power sampled by the monitor. |
| headroom | How far the measured PkgWatt/PkgTmp sits below the profile target / thermal trips under sustained load. |
| throttle | Firmware clamps sustained power below the target, or the platform holds at a passive trip — the enclosure cannot cool the profile. |
| enclosure report | The single consolidated report this skill emits at the end of the session. |
| dry_run | Preview mode: resolve and show the full plan for all stages without applying, monitoring, or stressing. |

## Trigger Phrases
- profile the enclosure / profile this platform
- run a full profiling session
- qualify this enclosure for <profile>
- apply, monitor, stress and summarize
- can this chassis sustain <profile> under load
- run the power/thermal profiling loop
- combined power profiling
- burn-in and report / thermal qualification run
- one-shot power and thermal profiling

## Required Inputs
- enib_home: absolute path to this repository root (default: current workspace root). On a host provisioned with Infrastructure Blueprint, the developer source tree lives at `/opt/edge/developer`, so `enib_home` is `/opt/edge/developer` on the target system.
- profile: power profile to apply — one of `LowPower`, `BalancedLow`, `BalancedHigh`, `Performance`, `MaxPerformance`, or `Custom` (default: `BalancedHigh`). Passed to `set-power-profile`.
- pkg_watt / sys_watt / burst_ratio / pl1_tau: optional power-envelope overrides, forwarded verbatim to `set-power-profile` (same rules/validation as that skill; `pkg_watt` only for `Custom`).
- thermal_profile: thermal policy to apply — one of `cool`, `warm`, `hot`, `thermal-max`, `custom`, or `none` (default: `none` — leave the current thermal policy untouched). When `custom`, also supply `fan_c`/`proc_c`/`clamp_c`. Passed to `set-thermal-profile`.
- fan_c / proc_c / clamp_c: custom thermal trip points (only when `thermal_profile=custom`), forwarded to `set-thermal-profile`.
- duration: bounded stress/monitor window in stress-ng time syntax, e.g. `60s`, `3m` (default: `3m`). **Required to be bounded** — an open-ended session is rejected (see Safety Rules).
- cpus / load / gpu: stress parameters forwarded to `generate-platform-stress` (defaults: all CPUs, `100`%, `12` GPU workers).
- interval: monitor sampling interval in seconds (default: `2`), forwarded to `monitor-power-thermal`.
- log_path: where the monitor trace is written (default: `<enib_home>/tools/power-tuning/pt_mon.txt`).
- dry_run: `true` | `false` (default: `false`). When `true`, every stage runs its own dry-run only; nothing is applied, monitored, or stressed.
- auto_confirm: `true` | `false` (default: `false`). When `true`, skip the single combined confirmation gate and each sub-skill's gate.

## Preconditions
Run silently without user prompts. This orchestrator's preconditions are the
**union** of the sub-skills' preconditions; delegate to each and aggregate.

- [ ] This skill file exists and is readable:
  - `test -f <enib_home>/skills/combined-power-thermal-profiling/SKILL.md`
- [ ] All four sub-skill files exist and are readable:
  - `test -f <enib_home>/skills/set-power-profile/SKILL.md`
  - `test -f <enib_home>/skills/set-thermal-profile/SKILL.md` (only when `thermal_profile != none`)
  - `test -f <enib_home>/skills/monitor-power-thermal/SKILL.md`
  - `test -f <enib_home>/skills/generate-platform-stress/SKILL.md`
- [ ] All four reference scripts exist and are executable:
  - `test -x <enib_home>/tools/power-tuning/set_power_profile.sh`
  - `test -x <enib_home>/tools/power-tuning/set_thermal_profile.sh` (only when `thermal_profile != none`)
  - `test -x <enib_home>/tools/power-tuning/pt_mon.sh`
  - `test -x <enib_home>/tools/power-tuning/stress_gen.sh`
- [ ] Required tools present: `command -v turbostat`, `command -v stress-ng`, `command -v rdmsr && command -v wrmsr`, and (when `thermal_profile != none`) `test -x /usr/sbin/thermald`. On any miss, stop with the same install hint the owning sub-skill gives.
- [ ] No stress-ng or turbostat instance is already running (would skew the capture):
  - `pgrep -x stress-ng` and `pgrep -x turbostat` — if either returns a PID, stop and instruct the user to stop it first (`sudo pkill -x stress-ng` / `sudo pkill -x turbostat`) before re-triggering.
- [ ] **Sudo probe (MANDATORY unless `dry_run=true`).** The session applies power/thermal changes and runs `sudo turbostat`. Run `sudo -n true`; if exit is non-zero, do NOT proceed — stop and instruct the user to run `sudo -v` (or add the scoped `NOPASSWD` entries the sub-skills document), then re-trigger. Never collect a password via prompts, env vars, scripts, or logs. See [AGENTS.md](../../AGENTS.md#sudo-handling-must-follow-for-all-skills-that-invoke-sudo).
- [ ] Host is x86_64 with an Intel CPU (sanity check; non-fatal warning if not): `uname -m` and `grep -m1 -o 'GenuineIntel' /proc/cpuinfo`.
- [ ] (Informational) Detect psys/SysWatt support so the report can annotate a `0.00` reading (as in `monitor-power-thermal`).

Prompt only for missing required inputs:
- [ ] Do not prompt when `profile`, `thermal_profile`, or the stress/monitor knobs are omitted — use the defaults above.
- [ ] Only for `thermal_profile=custom`: if any of `fan_c`/`proc_c`/`clamp_c` is missing, ask for the three trip points (required by `set-thermal-profile`).

Input validation (fail closed before running anything):
- [ ] `profile` and the power overrides validate against `set-power-profile`'s rules; `thermal_profile` and any custom trips validate against `set-thermal-profile`'s rules; `cpus`/`load`/`gpu` against `generate-platform-stress`'s ranges; `interval` is a positive integer.
- [ ] `duration` matches `^[0-9]+(s|m|h)?$` **and is present** — a bounded window is mandatory for this orchestrator.

## Steps
**Terminal command rules (MUST follow for every command, inherited by every stage):**
- Always invoke scripts by **absolute path** — never prefix with `cd`.
- Never combine `cd` with any output redirection (`>`, `>>`, `2>`, `2>&1`, `| tee`) in the same compound command — VS Code blocks it with an approval dialog.
- Never use `$(...)` command substitution in terminal commands — VS Code blocks them with an approval dialog. The scripts handle all internal computation themselves.

1. **Resolve the full session plan (no writes yet).** Build the argument lines
   for all four stages from the resolved inputs and render a single **Planned
   Session** table: power profile + envelope, thermal profile + trips (or
   "unchanged"), monitor interval/duration/log path, and stress cpus/load/gpu/duration.
2. **Dry-run every mutating stage** (read-only, no sudo). Run `set-power-profile`
   with `--dry-run`, and `set-thermal-profile` with `--dry-run` when
   `thermal_profile != none`; capture each resolved plan verbatim and fold any
   firmware/cTDP clamp or thermal notes into the Planned Session table.
3. **Single combined confirmation gate** — pause before any write:
   - If `dry_run=true`: stop here and record `CONFIRMATION=dry_run_only`. Do not apply/monitor/stress.
   - Else if `auto_confirm=true`: log `AUTO_CONFIRM=true`, propagate `auto_confirm=true` to each sub-skill, and continue.
   - Else: present the Planned Session table and ask **once**: "Run the full profiling session — apply <profile> (+ <thermal_profile> thermal), monitor for <duration>, and stress <cpus> CPUs @ <load>% + <gpu> GPU workers on this host? (yes/no)". On anything other than `yes`/`y`, stop and record `CONFIRMATION=declined`. A `yes` authorizes all stages; still surface (do not re-prompt for) each sub-skill's plan as it runs.
4. **CONSTRAIN — apply the envelope** (only after confirmation), in order:
   - Invoke **set-power-profile** with the resolved `profile` and any `pkg_watt`/`sys_watt`/`burst_ratio`/`pl1_tau`, `auto_confirm=true`. Capture its report and exit code. Abort the session if it fails.
   - If `thermal_profile != none`: invoke **set-thermal-profile** with the resolved `thermal_profile` (+ custom trips / `--charge` if given), `auto_confirm=true`. Capture its report and exit code. Abort if it fails.
5. **OBSERVE — start the monitor**, bounded to the stress window. Invoke
   **monitor-power-thermal** with `duration` (≈ the stress `duration`, plus a
   few seconds of lead/tail), `interval`, and `log_path`. Start it **before** the
   stress load so the trace captures the ramp. Record the log path and PID.
6. **LOAD — drive the stress**, synchronously and bounded. Invoke
   **generate-platform-stress** with the resolved `cpus`/`load`/`gpu` and the
   bounded `duration`, `auto_confirm=true`. Let it complete; capture its report
   (including the GPU-load verification when `gpu > 0`) and exit code.
7. **Stop the monitor** if it is still running (bounded runs self-terminate;
   otherwise `sudo pkill -x turbostat`). Confirm the trace file is non-empty
   (`test -s <log_path>`).
8. **SUMMARIZE — build the enclosure report.** Parse `<log_path>` for the
   min/mean/max of `PkgTmp`, `PkgWatt`, and `GFXWatt` over the stress window.
   Compare against the applied profile target and the thermal trips to derive the
   verdict (see Expected Result Summary). Emit the single consolidated report.

## Validation
Validation section is criteria-only. Do not render the pass/fail results table here.
- Preconditions passed (all required sub-skill files/scripts executable; tools present; no pre-existing stress-ng/turbostat; sudo probe = 0 when a run is intended).
- Inputs validated against each sub-skill's rules; `duration` present and bounded.
- A single Planned Session table was rendered from the stage dry-runs before the combined confirmation gate.
- Confirmation gate outcome recorded as one of: `confirmed`, `auto_confirm`, `declined`, `dry_run_only`.
- Stages executed only when the outcome is `confirmed` or `auto_confirm`, and in order: power → thermal (if any) → monitor → stress → summarize.
- Each executed sub-skill reported success (exit `0`); the session aborted (and rolled back per Rollback) on the first failure.
- The monitor trace is non-empty and covers the stress window; the enclosure report's min/mean/max were parsed from it.
- `SysWatt=0.00` is annotated as a known firmware limitation (per psys detection), NOT a session failure.

## Rollback
- The session is composed of the sub-skills' own reversible actions; roll back in reverse order of application.
- **Stress** leaves no persistent state — if aborted, stop it: `sudo pkill -x stress-ng`.
- **Monitor** is read-only — stop it (`sudo pkill -x turbostat`); the only artifact is the trace at `<log_path>`.
- **Power profile**: the RAPL cap is runtime-only (reverts on reboot); to revert immediately re-run `set-power-profile` with a lower profile, or restore the `intel_lpmd` `.orig` config (see that skill's Rollback).
- **Thermal profile** (if applied): re-run `set-thermal-profile` with a different profile (previous config backed up to `.bak`), restore the `.bak`, or run it with `disable=true` to return to kernel default thermal control. This config persists across reboot.
- If any stage fails mid-session, stop the already-started monitor/stress, report which stages applied, and propose the matching rollback for each applied stage.

## Safety Rules
- **Bounded only.** Refuse to run with an open-ended (missing/zero) `duration` — an orchestrated apply-and-load session must self-terminate. Direct the user to the individual skills for open-ended runs.
- Never collect a sudo password and never prompt for sudo approval; passwordless sudo is expected to be pre-configured for the underlying scripts/`turbostat`. Never collect a password via prompts, env vars, scripts, or logs.
- **Never combine `cd` with output redirection** and **never use `$(...)`** in terminal commands — VS Code blocks both with approval dialogs.
- Warn before a session that combines a high power profile (`MaxPerformance`) or a hot thermal profile (`thermal-max`) with full-load stress on a thermally constrained / fanless enclosure — this is exactly the case that can throttle or overheat; recommend starting cooler and stepping up.
- Do not stack stressors or monitors: honor the pre-existing-instance precondition.
- Delegate all writes to the sub-skills; this orchestrator does not modify anything outside what those skills manage (`tools/power-tuning/`, the `intel_lpmd` config, `/etc/thermald/`, and the monitor trace).
- Confirm once before the whole session; a single `yes` authorizes all stages. Do not silently apply a profile the user only asked to preview.

## Expected Result Summary
Emit the single **enclosure report** as the following tables.

### Session Metadata

| Field | Value |
|---|---|
| Preconditions | PASS/FAIL |
| Host | `<uname -m>` + CPU model name |
| Enclosure / label | `<user-supplied or 'unspecified'>` |
| Power profile | `<profile>` (+ any `pkg_watt`/`sys_watt`/`burst_ratio`) |
| Thermal profile | `<thermal_profile>` (Fan/Proc/clamp °C) or `unchanged` |
| Stress | `<cpus>` CPUs @ `<load>%` + `<gpu>` GPU workers |
| Duration | `<duration>` |
| Monitor | interval `<interval>s`, log `<log_path>` |
| SysWatt availability | `live` / `frozen (0.00)` / `no psys domain (0.00)` |
| Dry run only | `true` / `false` |
| Confirmation | `confirmed` / `auto_confirm` / `declined` / `dry_run_only` |

### Stage Results

(omit when the outcome is `declined` or `dry_run_only`)

| Stage | Skill | Status | Evidence |
|---|---|---|---|
| CONSTRAIN (power) | `set-power-profile` | PASS/FAIL | exit code, enforced PL1/PL2 vs target |
| CONSTRAIN (thermal) | `set-thermal-profile` | PASS/FAIL/N/A | exit code, trips installed, sole authority | 
| OBSERVE | `monitor-power-thermal` | PASS/FAIL | trace rows captured |
| LOAD | `generate-platform-stress` | PASS/FAIL | exit code, stressor active, iGPU loaded (if `gpu>0`) |

### Enclosure Report — Sample Summary (over the stress window)

| Metric | Min | Mean | Max | Target / Trip | Verdict |
|---|---|---|---|---|---|
| PkgTmp (°C) | `<v>` | `<v>` | `<v>` | Processor `<P>`°C / powerclamp `<C>`°C | within trips / hit passive trip |
| PkgWatt (W) | `<v>` | `<v>` | `<v>` | `<PkgWatt target>`W | held / firmware-clamped below target |
| GFXWatt (W) | `<v>` | `<v>` | `<v>` | — | loaded / idle (software fallback) |

### Verdict

| Question | Answer |
|---|---|
| Package power held at the profile target? | `yes` / `no (clamped to <W>)` |
| Package temperature stayed within the thermal trips? | `yes` / `no (reached <trip>)` |
| Sustained throttling observed? | `yes` / `no` |
| **Can this enclosure sustain `<profile>` under this load?** | **`yes` / `no` / `marginal`** |

### Validation Results

| Check Area | Status | Evidence | Notes |
|---|---|---|---|
| sub-skills present/executable | PASS/FAIL | `test -x` results | all four scripts |
| tools present | PASS/FAIL | turbostat/stress-ng/msr-tools/thermald | install hint on FAIL |
| no pre-existing stressor/monitor | PASS/FAIL | `pgrep -x stress-ng`/`turbostat` | list PIDs on FAIL |
| sudo availability | PASS/FAIL/SKIP | `sudo -n true` exit code | SKIP when `dry_run=true` |
| stage order + success | PASS/FAIL/N/A | per-stage exit codes | aborts on first failure |
| trace covers stress window | PASS/FAIL/N/A | `test -s <log>` + row count | N/A when not run |
| SysWatt annotation | INFO | psys detection result | not a failure |

### Failures and Troubleshooting

| Failed Check | Raw Evidence | Troubleshooting Note |
|---|---|---|
| `<check area>` | `<snippet>` | `<action>` |

## Troubleshooting Notes
- A stage failed mid-session: the orchestrator aborts on the first non-zero exit, stops any started monitor/stress, and reports which stages applied. Consult the failing sub-skill's own Troubleshooting Notes, fix the cause, and re-trigger.
- "stress-ng / turbostat is already running": a previous session did not clean up. Stop it (`sudo pkill -x stress-ng` / `sudo pkill -x turbostat`) and re-trigger.
- PkgWatt sits below the target under load ("firmware clamped PL1"): the enclosure/cooling or BIOS cTDP ceiling limits sustained power — raise Config-TDP Level 2 in BIOS or accept the lower effective figure (see `set-power-profile`).
- PkgTmp pins at the Processor/powerclamp trip: the platform is throttling to hold temperature — the enclosure cannot cool this profile at this load; step down the power profile or choose a cooler thermal profile.
- `SysWatt` reads `0.00`: frozen/absent psys counter on some Core Ultra silicon; use `PkgWatt` as the effective figure (see `monitor-power-thermal`).
- GFXWatt stays at idle while `gpu > 0`: the iGPU is not actually loaded (software fallback) — see the GPU-load verification in `generate-platform-stress`.
- For open-ended runs, ambiguous single-stage needs, or step-by-step tuning, invoke the individual skills directly rather than this orchestrator.

## Related Skills
This orchestrator composes the power-tuning skills; use them directly for finer control:
- **set-power-profile** — apply the PkgWatt/SysWatt envelope (stage 1).
- **set-thermal-profile** — apply the thermald trip points (stage 1, optional).
- **monitor-power-thermal** — capture the PkgTmp/PkgWatt/GFXWatt trace (stage 2).
- **generate-platform-stress** — drive bounded synthetic CPU/iGPU load via stress-ng (stage 3).
- **generate-openvino-stress** — alternative to stress-ng: drive bounded real AI inference load via OpenVINO benchmark_app on CPU/GPU/NPU (stage 3). Use when you want to profile under realistic AI workload patterns instead of synthetic load.
- **Manual equivalent:** apply a power profile → apply a thermal profile → start `monitor-power-thermal` → run `generate-platform-stress` or `generate-openvino-stress` with a bounded `duration` → read the min/mean/max summary. This skill automates exactly that loop and emits one enclosure report.
