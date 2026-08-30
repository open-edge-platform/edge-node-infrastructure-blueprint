---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: set-power-profile
description: Set how much power your Intel Core Ultra system may use — either a ready-made profile (LowPower 10 W, BalancedLow 15 W, BalancedHigh 20 W, Performance 25 W, or MaxPerformance = platform max / cTDP Level 2) or a Custom envelope with explicit PkgWatt (PL1) and optional SysWatt (psys) caps, burst ratio, and PL1 time window (tau). Runs locally with tools/power-tuning/set_power_profile.sh.
---


## Terminology
Acronyms and terms used throughout this skill.

| Term | Meaning |
|---|---|
| PkgWatt | "Package" power — the power used by the CPU package (the processor cores plus the built-in graphics). This is the main thing the skill limits. |
| SysWatt | "System / platform" power — the power of the whole platform (CPU package plus memory, voltage regulators, and other board rails). |
| PL1 | Power Limit 1 — the **sustained** power the chip is allowed to draw over the long term. Set by `pkg_watt`. |
| PL2 | Power Limit 2 — the **short burst** power the chip may briefly exceed PL1 to reach, for snappier response. Set by `burst_ratio`. |
| burst_ratio | How much higher the burst (PL2) is than the sustained limit (PL1): `PL2 = pkg_watt × burst_ratio`. `1.0` means no burst; `1.25` allows 25% higher bursts. |
| tau (PL1 tau) | The time window (in seconds) over which the sustained PL1 limit is averaged — how long a burst can last before the chip settles back to PL1. |
| TDP | Thermal Design Power — the processor's rated sustained power (its "normal" power level). |
| Nominal TDP | The processor's default rated sustained power, used as the fallback when no target is given. |
| cTDP | Configurable TDP — power levels the processor can be tuned to. **cTDP Level 2** is the chip's highest allowed sustained power (the maximum you can request). |
| uncore | The parts of the platform outside the CPU cores (memory controller, graphics fabric, I/O) whose power is included in SysWatt but not fully in PkgWatt. |
| RAPL | Running Average Power Limit — the Intel hardware feature this skill uses to read and enforce power limits. |
| MSR | Model-Specific Register — low-level CPU registers the script reads/writes to apply the limits (needs the `msr` kernel module and `msr-tools`). |
| psys | The platform (SysWatt) power domain exposed by RAPL. Some chips don't populate it, so its reading can show `0.00`. |
| EPP / EPB | Energy Performance Preference / Bias — hints that steer the CPU toward performance or power saving; the script sets these to match the chosen wattage. |
| HWP | Hardware P-States (Intel Speed Shift) — the feature that lets the OS request CPU performance levels; EPP/EPB are delivered through it. |
| Autonomous HWP | HWP "native" mode where the OS/lpmd programs HWP requests directly (rather than firmware). |
| HFI / ITD | Hardware Feedback Interface / Intel Thread Director — tells the OS which cores are most efficient right now, guiding low-power transitions. |
| SST / ISST | (Intel) Speed Select Technology — platform control of per-core performance / EPP classes on newer platforms. |
| WLT | Workload Type hint — a signal about the current workload used to bias power vs. performance. |
| SMT | Simultaneous Multi-Threading (Hyper-Threading) — two logical CPUs per physical core; lpmd selects efficient CPUs including SMT siblings. |
| C-states | CPU idle power states — deeper states (e.g. C1E, package C-states) save more power when idle. |
| DBPM | Demand-Based Power Management — firmware-driven frequency control; must be OFF so the OS/lpmd stays in charge. |
| intel_lpmd | The Intel Low Power Mode daemon the script configures and restarts to apply the CPU tuning. |
| ITMT | Intel Turbo Boost Max — a feature that favors the fastest cores; the script enables or disables it based on the target power. |
| NPU / VPU | Neural / Vision Processing Unit — the on-chip AI accelerator; capped too when it exposes a power domain. |
| dry_run | Preview mode: show the planned changes without applying anything. |


## BIOS Settings (Mandatory)
These platform firmware (BIOS) settings are **required** for the power tuning
in this skill to work. The Intel Low Power Mode daemon (`intel_lpmd`) needs the
OS to own the CPU's power/frequency controls; the settings below hand that
control to the OS. Verify them **before** running the skill — if they are wrong,
the script may run without error yet the limits or EPP/EPB tuning will not take
effect.

Settings are grouped by their BIOS menu category. The exact names and menu
paths vary by vendor; the tables below list common names and the required
values. Within each category the **Value** column states what each setting must
be set to.


### Advanced → Power & Performance → CPU – Power Management Control

| BIOS setting | Value | Reason |
|---|---|---|
| HwP Lock | Disabled | Per platform firmware requirement |
| Package Power Limit MSR Lock | Disabled | Keep the package power-limit MSRs unlocked so the script can write PL1/PL2 |

## BIOS Settings (Optional)
Not strictly required, but **recommended** — these improve idle power savings
and make sure the OS/`intel_lpmd` (not firmware) drives frequency and EPP.
Please disregard any configurations that are unavailable in your BIOS.

### Advanced → Power & Performance → CPU – Power Management Control

| BIOS setting | Value | Reason |
|---|---|---|
| Intel(R) Speed Shift Technology | Enabled | lpmd sets EPP/EPB via HWP during LP enter/exit |
| HwP Autonomous Per Core P State | Enabled | Lets HWP manage per-core P-states so OS/lpmd hints take effect |
| HwP Autonomous EPP Grouping | Enabled | Enables EPP grouping under autonomous HWP |
| Turbo Mode | Enabled | Normal operating range so lpmd's EPP/frequency management is meaningful |
| CPU C-States (C1E, package C-states) | Enabled | Idle power savings that lpmd's low-power mode relies on |
| Autonomous HWP (native mode) | Enabled | Lets OS/lpmd program HWP requests directly |
| Legacy / firmware-controlled power management ("BIOS/Firmware DBPM") | Disabled | Firmware would override lpmd's decisions |
| Fixed / High-Performance power profile forcing max frequency | Disabled | Prevents entering low-power mode |
| CPU frequency / EPP overrides fixed in firmware | Disabled | Would conflict with lpmd EPP management |
| Power/Performance policy or OS DBPM ("OS controls") | OS / Enabled | Hands frequency/EPP control to the OS + lpmd, not firmware |

## How to Use This in Your Workloads
Pick the profile whose PkgWatt budget matches what your workload needs — trading
battery life, heat, and fan noise against sustained speed. PkgWatt (the CPU
package power) is the profile parameter because it can be enforced on every
platform; on silicon that also exposes a psys (SysWatt) domain an extra
whole-platform cap is added automatically. Each profile ships a sensible default
burst ratio; override it only if you need more or less burst headroom.

- **Profile (PkgWatt budget)** — from `LowPower` (10 W) for the coolest, quietest,
  longest-battery operation up to `MaxPerformance` (the platform maximum,
  cTDP Level 2) for the most speed.
- **burst_ratio (short bursts)** — extra headroom for brief spikes so the system
  stays responsive without raising the sustained budget.

### Pick a profile for your workload

| Your workload | Goal | Suggested profile |
|---|---|---|
| Battery / fanless, mostly idle (kiosk, digital signage, edge sensor) | Longest battery, coolest, silent | `LowPower` (10 W) |
| Light interactive (basic UI, web browsing) | Efficient but responsive | `BalancedLow` (15 W) |
| Interactive / mixed (UI apps, light editing) | Balanced | `BalancedHigh` (20 W) |
| Steady general compute | Good throughput | `Performance` (25 W) |
| Sustained heavy compute (AI inference, video transcode, builds) | Max sustained throughput | `MaxPerformance` (platform max) |
| Thermally constrained enclosure (sealed / fanless) | Avoid throttling & heat | Highest profile the chassis can cool continuously; watch package temp with `turbostat` |

### Example commands

```bash
# List the available profiles and their PkgWatt budgets
tools/power-tuning/set_power_profile.sh --list

# Longest battery / coolest, silent operation
sudo tools/power-tuning/set_power_profile.sh --profile LowPower

# Balanced interactive use
sudo tools/power-tuning/set_power_profile.sh --profile BalancedHigh

# Max sustained throughput (AI inference / transcode / builds)
sudo tools/power-tuning/set_power_profile.sh --profile MaxPerformance

# Override the default burst ratio for a snappier feel
sudo tools/power-tuning/set_power_profile.sh --profile Performance --burstRatio 1.4

# Profile PkgWatt with an explicit SysWatt cap (psys-capable platforms)
sudo tools/power-tuning/set_power_profile.sh --profile Performance --sysWatt 35

# Preview only — see the plan without changing anything
tools/power-tuning/set_power_profile.sh --profile Performance --dry-run

# Fine-grained control: set explicit PkgWatt/SysWatt instead of a named profile
sudo tools/power-tuning/set_power_profile.sh --pkgWatt 25 --sysWatt 35

# Custom profile: any explicit parameters, passed straight through
sudo tools/power-tuning/set_power_profile.sh --profile Custom --pkgWatt 30 --sysWatt 40 --burstRatio 1.3
```

### Tips for choosing a profile
- **Start with the profile** whose PkgWatt budget fits your power/thermal
  envelope, then step up one profile at a time until throughput stops improving.
- Each profile's **default burst ratio** is tuned for its budget; override with
  `--burstRatio` only if you need more responsiveness (higher) or a flatter, more
  predictable power/temperature (closer to `1.0`).
- The **PkgWatt cap is enforced on every platform**. On silicon that also exposes
  a psys (SysWatt) domain, the whole-platform (SysWatt) limit tracks the same
  PkgWatt budget by default, or an explicit `--sysWatt <W>` value when you pass
  one alongside the profile. On silicon **without** a psys domain the SysWatt cap
  is skipped (PkgWatt only) and any `--sysWatt` is ignored.
- **Measure** while tuning: run `turbostat` (or the `monitor-power-thermal`
  skill) under your real workload to see PkgWatt/SysWatt and package temperature.
- The **RAPL power cap** is runtime-only and resets to firmware defaults on
  reboot, so the wattage limit is safe to experiment with. The **`intel_lpmd`
  config** the script writes persists on disk and is re-read by the daemon at the
  next boot, so the daemon-side tuning is *not* undone by a reboot (see
  Rollback). Re-run a lower profile to lower the cap immediately.
- For fine-grained control of exact PkgWatt/SysWatt values (instead of named
  profiles), use the `Custom` profile with the explicit `pkg_watt`/`sys_watt`/
  `burst_ratio`/`pl1_tau` inputs described below.


## Side Effects
Every profile is a trade-off. Use this to understand what changes — for better
and worse — when you pick one, so there are no surprises in production.

### By choice

| Choice | Positive effect | Possible side effect / cost |
|---|---|---|
| **Lower profile** (`LowPower` / `BalancedLow`) | Cooler, quieter/fanless, longer battery, lower energy cost | Lower sustained throughput; heavy jobs run slower or take longer |
| **Higher profile** (`Performance` / `MaxPerformance`) | More sustained performance | More heat and fan noise, higher power draw; can hit thermal throttling in small enclosures |
| **Higher `burst_ratio`** override | Snappier response to short spikes; good for interactive/latency-sensitive apps | Brief power/thermal/current spikes; on weak power delivery or cooling the burst is cut short (effective ratio drops) |
| **`burst_ratio` = 1.0** override | Flat, predictable power and temperature; easier thermal/PSU budgeting | Less responsive to sudden load; peak performance is capped at the sustained level |

### General side effects to expect
- **Thermals & acoustics:** higher profiles raise package temperature and fan
  speed/noise; lower profiles run cooler and quieter (or fanless).
- **Throttling:** if cooling can't keep up, the firmware clamps sustained power
  below the profile's target — you'll see the "firmware clamped PL1" note and the
  effective (enforced) value in the report.
- **Battery & energy:** higher profiles shorten battery runtime and increase
  energy consumption; lower profiles extend both.
- **Perceived responsiveness vs. throughput:** burst headroom helps *feel* fast;
  the profile's PkgWatt budget drives *long-running* throughput.
- **Brief management gap:** applying a profile restarts `intel_lpmd.service`
  (~2 s) during which the daemon isn't actively managing CPU states.
- **SysWatt reads 0.00:** on some Core Ultra silicon the psys counter is frozen;
  the cap is still written but not observable via turbostat — use PkgWatt as the
  effective figure. This is a firmware limitation, not a failure.
- **Partial revert on reboot:** the RAPL power cap resets to firmware defaults on
  reboot (a built-in safety net if a profile turns out too aggressive), but the
  `intel_lpmd` config written to disk persists and is re-read by the daemon at
  the next boot. Restore the `.orig` config (see Rollback) to undo the
  daemon-side tuning.



## Trigger Phrases
- set power profile
- apply power profile
- set profile to LowPower / BalancedLow / BalancedHigh / Performance / MaxPerformance
- switch to <profile> power profile
- set platform profile <N>W
- use the low power / max performance profile
- list power profiles
- set platform power / set power envelope / change power envelope
- set package power limit / cap cpu package power
- set pkgwatt / set syswatt
- set PL1 and PL2
- set platform power to N watts
- tune tdp / set tdp
- set power to <N>W with burst ratio <R>

## Required Inputs
- enib_home: absolute path to this repository root (default: current workspace root). On a host provisioned with Infrastructure Blueprint, the developer source tree lives at `/opt/edge/developer`, so `enib_home` is `/opt/edge/developer` on the target system.
- profile: one of `LowPower`, `BalancedLow`, `BalancedHigh`, `Performance`, `MaxPerformance`, or `Custom` (case-insensitive). Optional; defaults to `BalancedHigh` (20 W) when not supplied — the skill does not prompt for it. A named preset sets the PkgWatt budget for you; choose `Custom` to set an explicit power envelope with `pkg_watt`/`sys_watt`/`pl1_tau` (see below).
- pkg_watt: PkgWatt (PL1 sustained) target in watts. **Only for `Custom`** (a named preset sets PkgWatt itself, so it is rejected there). Must be a **multiple of 5**, from `5` up to the platform's cTDP Level 2 maximum (read from the CPU at runtime). When `Custom` is selected without `pkg_watt`, it defaults to the platform Nominal TDP (no prompt).
- burst_ratio: burst ratio (`>= 1.0`, optional). For a named profile, when omitted the profile's default is used (LowPower `1.25`, BalancedLow `1.25`, BalancedHigh `1.18`, Performance `1.19`, MaxPerformance `1.18`); for `Custom` the default is `1.25`. Overrides the default when supplied. PL2 = PkgWatt * burst_ratio, clamped to cTDP Level 2.
- sys_watt: psys/platform (SysWatt) cap in watts (optional). May be supplied alongside a named profile or `Custom` to override the SysWatt cap on psys-capable silicon; without it the SysWatt cap tracks the PkgWatt budget. When supplied, must be a **multiple of 5** in `[5, cTDP Level 2]`. Ignored on platforms without a psys domain.
- pl1_tau: PL1 time window (tau) in seconds (optional, default `28`).
- dry_run: `true` | `false` (default: `false`). When `true`, only the resolved plan is shown; nothing is applied.

## Profile Table

| Profile | PkgWatt | Default burst ratio |
|---|---|---|
| LowPower | 10 W | 1.25 |
| BalancedLow | 15 W | 1.25 |
| BalancedHigh | 20 W | 1.18 |
| Performance | 25 W | 1.19 |
| MaxPerformance | platform max (cTDP Level 2) | 1.18 |
| Custom | — (explicit) | — (from `--burstRatio`, default 1.25) |

## Preconditions
Run silently without user prompts:
- [ ] Skill file exists and is readable:
  - `test -f <enib_home>/skills/set-power-profile/SKILL.md`
- [ ] The profile script exists and is executable:
  - `test -x <enib_home>/tools/power-tuning/set_power_profile.sh`
- [ ] Host is x86_64 with an Intel CPU (sanity check; non-fatal warning if not):
  - `uname -m` and `grep -m1 -o 'GenuineIntel' /proc/cpuinfo`
- [ ] `msr-tools` and the `msr` module are available (needed to probe psys support, read cTDP levels, and program RAPL MSRs):
  - `command -v rdmsr && command -v wrmsr`
  - if missing, warn that psys support cannot be probed reliably and the script will fall back to Panther Lake defaults; the PkgWatt estimate path may be used.
- [ ] **Sudo (non-interactive — never prompt for sudo approval).** This skill assumes passwordless sudo is already configured for the script (run the `setup-agent-sudo` prerequisite once per host). Do NOT ask the user for sudo approval, a password, or interactive authentication at any point in the skill execution. You MAY run a silent `sudo -n true` for the report only, but never pause, prompt, or block on its result. `dry_run=true` needs no sudo (read-only). Never collect a password via prompts, env vars, scripts, or logs. See [AGENTS.md](../../AGENTS.md#sudo-handling-must-follow-for-all-skills-that-invoke-sudo).
- [ ] Determine the cTDP Level 2 maximum (upper bound for a `Custom` `pkg_watt`/`sys_watt`):
  - The script reads the cTDP MSRs internally and prints the resolved values (`Config-TDP levels: Nominal=…W Level1=…W Level2=…W`) in its output. Use `CTDP_MAX=65` (Panther Lake fallback) as the reported ceiling for input validation before running; the script will clamp to the real value at runtime.

Defaults for missing inputs (do NOT prompt):
- [ ] If `profile` is not provided, default to `BalancedHigh` and continue — do not prompt.
- [ ] If `profile=Custom` and `pkg_watt` is missing, default to the platform Nominal TDP (from the CPU's Config-TDP MSRs; Panther Lake fallback if unreadable) — do not prompt.
- [ ] Use defaults for `burst_ratio`, `sys_watt`, `pl1_tau`, and `dry_run` unless the user supplied them.

Input validation (fail closed before running the script):
- [ ] `profile` matches one of the five names or `Custom` (case-insensitive). Otherwise stop and list the valid profiles.
- [ ] `burst_ratio` (if supplied) is a number `>= 1.0`.
- [ ] With a named preset, `pkg_watt` is rejected (the preset sets PkgWatt); `sys_watt` is allowed as a platform-cap override.
- [ ] For `Custom`: `pkg_watt` is required — an integer, a multiple of 5, and `5 <= pkg_watt <= CTDP_MAX`. Do not silently round; stop and report the valid range/step if invalid.
- [ ] If `sys_watt` is supplied (with a preset or `Custom`): integer, a multiple of 5, `5 <= sys_watt <= CTDP_MAX`.
- [ ] `pl1_tau` (if supplied) is a positive number of seconds.

## Steps
**Terminal command rules (MUST follow for every command in this skill):**
- Always invoke scripts by **absolute path** — never prefix with `cd`.
- Never combine `cd` with any output redirection (`>`, `>>`, `2>`, `2>&1`, `| tee`) in the same compound command — this triggers the VS Code "Compound command contains cd with output redirection" approval dialog. Run them as separate commands if both are needed.
- Never use `$(...)` command substitution in terminal commands — VS Code blocks them with a "Contains command_substitution" approval dialog. The scripts handle all internal computation themselves.

1. Resolve the plan (no writes yet):
   - `PkgWatt = profile target` (from the Profile Table; `MaxPerformance` = cTDP Level 2).
   - `burst_ratio = supplied value or the profile default`.
   - `SysWatt cap = sys_watt if supplied, else PkgWatt` (only applied on psys-capable silicon).
2. Determine psys (SysWatt) support (read-only best effort):
   - Supported when a powercap domain named `psys` exists under `/sys/class/powercap/intel-rapl:*/name`, or `MSR_PLATFORM_POWER_LIMIT` (0x65C) reads non-zero.
   - When supported, the script enforces the PkgWatt cap AND a SysWatt cap (the explicit `sys_watt` when given, otherwise tracking the PkgWatt budget).
   - When not supported, only the PkgWatt cap is enforced (the SysWatt domain does not exist on this platform, and any `sys_watt` is ignored).
3. Capture a pre-change RAPL snapshot for the report (read-only). Use individual `cat` commands — no `$(...)` substitution, no `cd` prefix. Read each file separately:
   - `cat /sys/class/powercap/intel-rapl:0/name`
   - `cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw`
   - `cat /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw`
   - `cat /sys/class/powercap/intel-rapl:0/enabled`
   - Repeat for `:1` (psys) if present. Record the values for the post-change comparison.
4. **Always execute a dry run first** (read-only, no sudo, no writes):
   - Run `<enib_home>/tools/power-tuning/set_power_profile.sh --profile <profile> [--pkgWatt <pkg_watt>] [--sysWatt <sys_watt>] [--burstRatio <burst_ratio>] [--pl1Tau <pl1_tau>] --dry-run` and capture the resolved plan verbatim (it prints the effective explicit-target command line, the resolved PkgWatt/PL2/SysWatt values, and any firmware/cTDP clamping).
  - This step runs unconditionally on every invocation.
5. **Render the Planned Changes as a table** built from the dry-run output (profile, PkgWatt target, resolved burst ratio, PL2, SysWatt cap, psys-supported yes/no, and any clamp note). Show it to the user before any write.
6. **Confirmation gate** — pause before any write:
   - If `dry_run=true`: stop here and record `CONFIRMATION=dry_run_only`. Do not apply.
  - Otherwise, present the tabulated Planned Changes and ask "Apply the <profile> profile (PkgWatt <N>W, burstRatio <R>) on this host? (yes/no)". On anything other than `yes`/`y` (case-insensitive), stop and record `CONFIRMATION=declined`.
7. Apply (only after confirmation). `set_power_profile.sh` self-elevates with `sudo -E` internally when not root, so the agent calls it directly — no `sudo` prefix in the terminal command, which avoids the VS Code approval dialog. Build the argument list:
   - Base: `<enib_home>/tools/power-tuning/set_power_profile.sh --profile <profile>`
   - For `Custom`, also append `--pkgWatt <pkg_watt>` and, when supplied, `--pl1Tau <pl1_tau>` (default 28).
   - Append `--sysWatt <sys_watt>` only when the user supplied one.
   - Append `--burstRatio <burst_ratio>` only when the user supplied one (otherwise the script uses the profile default; for `Custom` the script default is 1.25).
   - Capture stdout/stderr verbatim and record the exit code.
8. Capture a post-change RAPL snapshot using the same individual `cat` commands as Step 3.

## Validation
Validation section is criteria-only. Do not render the pass/fail results table here.
- Preconditions passed (script executable). Passwordless sudo is assumed pre-configured; the sudo probe is informational only and never blocks execution.
- `profile` validated against the five names; `burst_ratio` validated when supplied.
- A dry run was executed first on every invocation, and the Planned Changes table was rendered from its output before the confirmation gate.
- Confirmation gate outcome recorded as one of: `confirmed`, `declined`, `dry_run_only`.
- Apply phase only executed when the outcome is `confirmed`.
- When applied, the script exited with code `0`.
- Post-change package RAPL PL1/PL2 reflect the profile PkgWatt (allowing for firmware/cTDP clamping); when psys is supported the psys domain reflects the SysWatt cap (the explicit `sys_watt` when given, otherwise the PkgWatt budget).
- Note: on platforms where the psys counter is frozen/unavailable, the SysWatt cap is written to the register but turbostat still reads `SysWatt=0.00`; this is a firmware limitation, not a failure.

## Rollback
- The RAPL power cap (PL1/PL2 wattage) is runtime-only and reverts to firmware defaults on reboot.
- The `intel_lpmd` config the script writes persists on disk and is re-read by the daemon at the next boot, so it does NOT revert on its own.
- To revert immediately, re-run with a lower profile (e.g. `LowPower`) or a `Custom` envelope at the platform Nominal TDP (reported in the script output as `Config-TDP levels: Nominal=…`).
- `set_power_profile.sh` keeps a one-time `.orig` backup of any model-specific intel_lpmd config it overrides; restore it and restart `intel_lpmd.service` to return the daemon config to stock.

## Safety Rules
- Never collect a sudo password and never prompt for sudo approval during skill execution; passwordless sudo is expected to be pre-configured (see the `setup-agent-sudo` prerequisite). Never collect a password via prompts, env vars, scripts, or logs.
- **Never combine `cd` with output redirection** (`>`, `>>`, `2>`, `2>&1`, `| tee`) in the same compound terminal command — VS Code blocks such commands with an approval dialog. Always use absolute paths and split commands if redirection is needed.
- **Never use `$(...)` command substitution in terminal commands** — VS Code blocks them with an approval dialog. Delegate all computation to the scripts themselves.
- Warn before applying a high profile (`MaxPerformance`) or a high `burst_ratio` on thermally constrained (e.g. fanless) enclosures; report package temperature via `turbostat` when available.
- The script restarts `intel_lpmd.service` to load the new profile; note the brief (~2 s) management gap to the user.
- Do not modify anything outside `tools/power-tuning/` and the intel_lpmd config directory the script manages.

## Expected Result Summary
Render the report as the following tables.

### Run Metadata

| Field | Value |
|---|---|
| Preconditions | PASS/FAIL |
| Host | `<uname -m>` + CPU model name |
| Profile | `<profile>` |
| PkgWatt target | `<N>W` |
| Burst ratio | `<burst_ratio>` (profile default or overridden) |
| SysWatt cap | `<sys_watt or PkgWatt>W` (psys-capable only) |
| PL1 tau | `<pl1_tau>s` |
| cTDP Level 2 max | `<CTDP_MAX>W` (msr / fallback) |
| psys (SysWatt) supported | `yes` / `no` |
| Dry run only | `true` / `false` |
| Confirmation | `confirmed` / `declined` / `dry_run_only` |

### Planned Changes

| Domain | Target | Notes |
|---|---|---|
| Package (PkgWatt) | `<PkgWatt>W` | always enforced (MSR 0x610) |
| psys (SysWatt) | `<sys_watt or PkgWatt>W` | enforced only when psys is supported |

### RAPL Snapshot (pre → post)

(omit when the outcome is `declined` or `dry_run_only`)

| Domain | PL1 before | PL1 after | PL2 before | PL2 after | enabled |
|---|---|---|---|---|---|
| `package-0` | `<uw>` | `<uw>` | `<uw>` | `<uw>` | `<0/1>` |
| `psys` (if present) | `<uw>` | `<uw>` | `<uw>` | `<uw>` | `<0/1>` |

### Validation Results

| Check Area | Status | Evidence | Notes |
|---|---|---|---|
| script executable | PASS/FAIL | `test -x` result | set_power_profile.sh |
| sudo availability | INFO | `sudo -n true` exit code | informational only; never blocks |
| profile/inputs valid | PASS/FAIL | profile name + numeric options | |
| psys support probe | INFO | `yes` / `no` | selects enforcement path |
| script apply | PASS/FAIL/N/A | exit code | N/A when not applied |
| package PL enforced | PASS/FAIL/N/A | post RAPL uw vs PkgWatt | note firmware clamp |

### Failures and Troubleshooting

| Failed Check | Raw Evidence | Troubleshooting Note |
|---|---|---|
| `<check area>` | `<snippet>` | `<action>` |

## Troubleshooting Notes
- List the available profiles at any time with `<enib_home>/tools/power-tuning/set_power_profile.sh --list`.
- The skill never prompts for sudo approval. If the script fails because sudo needs a password, configure passwordless sudo **out of band** first by running the `setup-agent-sudo` prerequisite (installs a scoped entry via `sudo visudo -f /etc/sudoers.d/set-power-profile`):
  ```
  <user> ALL=(root) NOPASSWD: /home/<user>/enib/tools/power-tuning/set_power_profile.sh
  ```
  Never use `NOPASSWD: ALL` or global sudo timestamps; keep the entry restricted to the script's absolute path.
- If `rdmsr`/`wrmsr` are missing: `sudo apt-get install -y msr-tools` and `sudo modprobe msr`. Without them psys support cannot be probed and the script uses Panther Lake defaults.
- If psys is reported "not supported": only the PkgWatt cap is applied (this platform has no psys/SysWatt domain), which is the expected behaviour on such silicon.
- If `SysWatt` still reads `0.00` in turbostat after applying: the platform (psys) RAPL counter is frozen/unpopulated on some Core Ultra platforms. This is a firmware limitation; use PkgWatt as the effective figure.
- If the script reports "firmware clamped PL1 to <lower>W": set Config-TDP Level 2 in BIOS to raise the ceiling.
- The RAPL power cap does not persist across reboot; to re-apply it automatically at boot, wrap the invocation in a systemd unit (out of scope for this skill). The `intel_lpmd` config the script writes does persist on disk and is re-read by the daemon at boot.
