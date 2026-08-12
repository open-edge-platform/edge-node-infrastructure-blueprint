---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: set-thermal-profile
description: Set the thermal escalation policy of an Intel host with tools/power-tuning/set_thermal_profile.sh — generate, validate, apply and verify a thermald thermal-conf.xml that stages a response on the CPU package sensor (Fan active < Processor passive < intel_powerclamp passive). Choose a ready-made profile (cool 55/70/80, warm 60/75/85, hot 70/90/95, thermal-max 95/100/104, in °C for Fan/Processor/powerclamp) or a Custom set of trip points, optionally add the CHRG cooling device, and make thermald the sole thermal authority. Also supports disabling thermald to revert to kernel default thermal control.
---

## Purpose
`set_thermal_profile.sh` generates, applies and verifies a **thermald** thermal
profile. It builds a `/etc/thermald/thermal-conf.xml` with a staged escalation on
the CPU package sensor (`x86_pkg_temp`):

```
Fan (active)  <  Processor (passive)  <  intel_powerclamp (passive)
fans on early    cap CPU frequency       inject idle cycles (hard limit)
```

then makes thermald the sole thermal authority (systemd drop-in with
`--ignore-default-control` and **without** `--adaptive`, so firmware DPTF/GDDV
adaptive tables do not override the trip points) and verifies the result.

This skill only automates the reference script. The thermal profile pairs with
the power envelope from `set-power-profile`: the power cap bounds how much heat
is produced, while this thermal profile governs how the platform reacts as
package temperature rises.

## Terminology
Acronyms and terms used throughout this skill.

| Term | Meaning |
|---|---|
| thermald | The Linux thermal daemon that consumes the generated `thermal-conf.xml` and drives the cooling devices. |
| trip point | A temperature threshold at which a cooling action is engaged. |
| active trip | A cooling response that does **not** cost performance — here, turning fans on. |
| passive trip | A cooling response that **reduces performance** to shed heat — frequency capping or idle injection. |
| x86_pkg_temp | The CPU package temperature sensor the profile escalates on. |
| Fan | The active cooling device (fans) engaged at the first (lowest) trip. |
| Processor | The passive cooling device that caps CPU frequency at the middle trip. |
| intel_powerclamp | The passive cooling device that injects idle cycles (hard limit) at the top trip. |
| CHRG | The battery-charge cooling device; optionally added to the top trip when present (`--charge`). |
| Tjmax | The silicon's maximum junction temperature (~110 °C); the top trip must stay below it. |
| DPTF / GDDV | Firmware adaptive thermal framework/tables that would override the config unless thermald runs without `--adaptive`. |
| cooling device | A `/sys/class/thermal/cooling_device*` the kernel exposes (Fan, Processor, intel_powerclamp, CHRG, …). |
| systemd drop-in | An `override.conf` that re-declares thermald's `ExecStart` so our config is authoritative. |
| dry_run | Preview mode: print the plan and generated XML without writing anything or touching the daemon. |

## Profile Table
Trip points are in Celsius, ordered Fan (active) < Processor (passive) <
powerclamp (passive).

| Profile | Fan | Processor | powerclamp | Notes |
|---|---|---|---|---|
| cool | 55 | 70 | 80 | Aggressive cooling; fans on early, runs coolest/quietest-at-cost-of-perf |
| warm *(default)* | 60 | 75 | 85 | Balanced |
| hot | 70 | 90 | 95 | Lets the platform run warmer before intervening |
| thermal-max | 95 | 100 | 104 | Pushes to Tjmax headroom; **runs hot** |
| custom | `--fan` | `--proc` | `--clamp` | Supply your own trip points |

## Trigger Phrases
- set thermal profile
- apply thermal profile
- set thermal profile to cool / warm / hot / thermal-max
- configure thermald / set thermald trip points
- set cpu thermal trip points
- generate thermal-conf.xml
- make thermald the sole thermal authority
- set custom thermal trips (fan/proc/clamp)
- add CHRG cooling device to thermal profile
- disable thermald / revert to kernel default thermal control
- run hot / run cool thermally

## Required Inputs
- enib_home: absolute path to this repository root (default: current workspace root). On a host provisioned with Infrastructure Blueprint, the developer source tree lives at `/opt/edge/developer`, so `enib_home` is `/opt/edge/developer` on the target system.
- profile: one of `cool`, `warm`, `hot`, `thermal-max`, or `custom`. Optional; defaults to `warm` when not supplied — the skill does not prompt for it. Passed via `--profile/-p` (a bare positional word is rejected by the script).
- fan_c: Fan (active) trip in Celsius. **Only for `custom`** (required there); ignored for named profiles unless explicitly overriding.
- proc_c: Processor (passive) trip in Celsius. **Only for `custom`** (required there).
- clamp_c: powerclamp (passive) trip in Celsius. **Only for `custom`** (required there).
- charge: `true` | `false` (default: `false`). When `true`, add the CHRG (battery charge) cooling device to the top trip **if present** on the platform (`--charge`).
- output_file: optional path. When set, write the generated XML there and make **no** daemon changes (`-o FILE`). Implies no install.
- disable: `true` | `false` (default: `false`). When `true`, stop thermald and disable it at boot (`--disable`), reverting to kernel default thermal control. Ignores profile options; leaves config/override files untouched.
- dry_run: `true` | `false` (default: `false`). When `true`, only the plan and generated XML are shown; nothing is written and no service is touched (`--dry-run`).
- auto_confirm: `true` | `false` (default: `false`). When `true`, skip the confirmation gate.

## Preconditions
Run silently without user prompts:
- [ ] Skill file exists and is readable:
  - `test -f <enib_home>/skills/set-thermal-profile/SKILL.md`
- [ ] The thermal script exists and is executable:
  - `test -x <enib_home>/tools/power-tuning/set_thermal_profile.sh`
- [ ] `thermald` is installed (needed to validate and run the config; not needed for `dry_run` or `output_file` mode):
  - `test -x /usr/sbin/thermald`
  - if missing, stop and instruct: install it (Ubuntu: `sudo apt-get install -y thermald`), then re-trigger.
- [ ] Host is x86_64 with an Intel CPU (sanity check; non-fatal warning if not):
  - `uname -m` and `grep -m1 -o 'GenuineIntel' /proc/cpuinfo`
- [ ] Detect the cooling devices present (informational; the script omits steps for absent devices and refuses to write an empty zone):
  - `grep -s . /sys/class/thermal/cooling_device*/type` — note whether `Fan`, `Processor`, `intel_powerclamp` (and `CHRG` when `charge=true`) are present.
- [ ] **Sudo probe (MANDATORY before any apply / `--disable`)** — the script mutates `/etc/thermald/` and restarts the service and does **not** self-elevate: run `sudo -n true`. If exit is non-zero, do NOT apply; stop and instruct the user to run `sudo -v` in their terminal (or add a scoped `NOPASSWD` entry for the absolute path to `set_thermal_profile.sh` in `/etc/sudoers.d/`), then re-trigger. If `sudo -v` was already run but `sudo -n true` still fails (tty_tickets), make timestamps global: `echo 'Defaults timestamp_type=global' | sudo tee /etc/sudoers.d/agent-timestamp && sudo chmod 0440 /etc/sudoers.d/agent-timestamp && sudo visudo -c`. Never collect a password via prompts, env vars, scripts, or logs. `dry_run=true` and `output_file` mode need no sudo (read-only / no daemon changes). See [AGENTS.md](../../AGENTS.md#sudo-handling-must-follow-for-all-skills-that-invoke-sudo).

Prompt only for missing required inputs:
- [ ] Do not prompt when `profile` is omitted — default to `warm`.
- [ ] Only for `profile=custom`: if any of `fan_c`, `proc_c`, `clamp_c` is missing, ask for the three trip points (the script requires all three for `custom`).

Input validation (fail closed before running the script):
- [ ] `profile` matches one of `cool|warm|hot|thermal-max|custom`. Otherwise stop and list the valid profiles.
- [ ] For `custom` (or when overriding a named profile): `fan_c`, `proc_c`, `clamp_c` are positive integers satisfying `fan_c < proc_c < clamp_c` and `clamp_c < 105` (must stay below Tjmax). Warn if `fan_c < 30` (near idle; CPU may stay throttled).
- [ ] `output_file`'s parent directory exists and is writable (when supplied).
- [ ] `disable`, `charge`, `dry_run`, `auto_confirm` are booleans. `disable=true` is mutually exclusive with profile/custom trip options (the script ignores them under `--disable`).

## Steps
**Terminal command rules (MUST follow for every command in this skill):**
- Always invoke scripts by **absolute path** — never prefix with `cd`.
- Never combine `cd` with any output redirection (`>`, `>>`, `2>`, `2>&1`, `| tee`) in the same compound command — this triggers the VS Code approval dialog. Run them as separate commands if both are needed.
- Never use `$(...)` command substitution in terminal commands — VS Code blocks them with an approval dialog. The script handles all internal computation itself.

1. Resolve the plan (no writes yet). Build the argument list:
   - Base: `<enib_home>/tools/power-tuning/set_thermal_profile.sh --profile <profile>`
   - For `custom`, append `--fan <fan_c> --proc <proc_c> --clamp <clamp_c>`.
   - Append `--charge` only when `charge=true`.
   - For `output_file` mode, append `-o <output_file>` (no daemon changes).
   - For `disable=true`, use `--disable` instead of the profile/trip options.
2. **Always execute a dry run first** (read-only, no sudo, no writes) unless the invocation is `output_file`-only:
   - Run the resolved command with `--dry-run` (add `--disable` when disabling) and capture the summary and the generated XML verbatim.
   - This runs unconditionally on every apply invocation, including when `auto_confirm=true`.
3. **Render the Planned Changes as a table** built from the dry-run output: profile, resolved Fan/Processor/powerclamp trips, CHRG yes/no, which cooling devices are present vs will be wired in, config target (`/etc/thermald/thermal-conf.xml` or `output_file`), and the effective `ExecStart`. Show it before any write.
4. **Confirmation gate** — pause before any write:
   - If `dry_run=true`: stop here and record `CONFIRMATION=dry_run_only`. Do not apply.
   - Else if `output_file` is set: this only writes the XML (no daemon changes) — treat as low-risk; still show the plan, then proceed (respect `auto_confirm`; otherwise confirm).
   - Else if `auto_confirm=true`: log `AUTO_CONFIRM=true` and continue.
   - Else: present the tabulated Planned Changes and ask "Apply the <profile> thermal profile (Fan <F>°C / Processor <P>°C / powerclamp <C>°C) and make thermald the sole thermal authority on this host? (yes/no)" (or, for disable: "Stop and disable thermald, reverting to kernel default thermal control? (yes/no)"). On anything other than `yes`/`y` (case-insensitive), stop and record `CONFIRMATION=declined`.
5. Apply (only after confirmation). The script does **not** self-elevate, so prefix with `sudo` for apply / `--disable` (not for `--dry-run` or `-o`):
   - `sudo <enib_home>/tools/power-tuning/set_thermal_profile.sh --profile <profile> [custom/charge flags]`
   - The script validates the generated XML in thermald test-mode, backs up any existing config/override, installs, `daemon-reload`s, restarts thermald, and verifies the running daemon. Capture stdout/stderr verbatim and record the exit code.
6. Capture the effective state for the report (read-only):
   - `systemctl is-active thermald`
   - the effective `ExecStart` and the confirmation line the script prints (sole thermal authority ✔ / warning).
   - current package temperature (the script prints it at the end).

## Validation
Validation section is criteria-only. Do not render the pass/fail results table here.
- Preconditions passed (script executable; `thermald` present for apply; sudo probe = 0 when an apply/disable is intended).
- `profile` validated; for `custom`, trip points validated for ordering (`fan < proc < clamp`), `clamp < 105`, and positive integers.
- A dry run was executed first on every apply invocation, and the Planned Changes table was rendered from its output before the confirmation gate.
- Confirmation gate outcome recorded as one of: `confirmed`, `auto_confirm`, `declined`, `dry_run_only`.
- Apply phase only executed when the outcome is `confirmed` or `auto_confirm`.
- When applied, the script exited with code `0`, thermald is `active`, and the effective `ExecStart` contains `--ignore-default-control` and **not** `--adaptive` (sole thermal authority).
- When `output_file` mode, the XML was written to the given path and no daemon changes were made.
- When `disable=true`, thermald is stopped and disabled and the script reported kernel default thermal control now applies.

## Rollback
- Re-run with a different `profile` to change the trip points (the script backs up the previous config to `${CONF_FILE}.bak` and the override to `${OVERRIDE_FILE}.bak`).
- Restore the previous config manually: `sudo cp /etc/thermald/thermal-conf.xml.bak /etc/thermald/thermal-conf.xml && sudo systemctl restart thermald`.
- To fully revert to kernel default thermal control, run the skill with `disable=true` (`--disable`): it stops thermald and disables it at boot, leaving config/override files untouched. Re-enable later with `sudo systemctl enable --now thermald`.
- The config and systemd override persist across reboot (unlike the runtime-only RAPL power cap from `set-power-profile`).

## Safety Rules
- Never collect a sudo password and never prompt for sudo approval during skill execution; passwordless sudo is expected to be pre-configured (scoped `NOPASSWD` for the absolute path to `set_thermal_profile.sh`). Never collect a password via prompts, env vars, scripts, or logs.
- **Never combine `cd` with output redirection** in the same compound terminal command — VS Code blocks such commands. Use absolute paths; split commands if redirection is needed.
- **Never use `$(...)` command substitution in terminal commands** — VS Code blocks them. Delegate all computation to the script.
- Warn before applying `thermal-max` (runs near Tjmax) or a high `custom` `clamp_c` on thermally constrained (e.g. fanless) enclosures — the platform will run hot and may thermally throttle only very late.
- On a fanless enclosure the `Fan` active step is omitted (no such device); note that the platform then relies solely on the passive steps (frequency cap + idle injection).
- The script restarts `thermald` to load the new profile; note the brief management gap. If the script aborts mid-run it restores the previously running daemon.
- Do not modify anything outside `tools/power-tuning/`, `/etc/thermald/`, and the thermald systemd drop-in the script manages.

## Expected Result Summary
Render the report as the following tables.

### Run Metadata

| Field | Value |
|---|---|
| Preconditions | PASS/FAIL |
| Host | `<uname -m>` + CPU model name |
| Mode | `apply` / `output-file` / `disable` |
| Profile | `<profile>` (n/a when disabling) |
| Fan trip | `<F>°C (active)` |
| Processor trip | `<P>°C (passive)` |
| powerclamp trip | `<C>°C (passive)` |
| CHRG device | `yes` / `no` |
| Config target | `/etc/thermald/thermal-conf.xml` or `<output_file>` |
| Dry run only | `true` / `false` |
| Confirmation | `confirmed` / `auto_confirm` / `declined` / `dry_run_only` |

### Planned Changes

| Item | Value | Notes |
|---|---|---|
| STEP 1 (active) | Fan @ `<F>`°C | omitted if no Fan device |
| STEP 2 (passive) | Processor @ `<P>`°C | frequency cap; omitted if no Processor device |
| STEP 3 (passive) | intel_powerclamp @ `<C>`°C | idle injection; omitted if absent |
| Thermal authority | `--ignore-default-control`, no `--adaptive` | thermald is sole authority |

### Effective State (pre → post)

(omit when the outcome is `declined` or `dry_run_only`)

| Field | Before | After |
|---|---|---|
| thermald active | `<0/1>` | `<0/1>` |
| ExecStart | `<prev>` | `<new>` |
| Config file | `<present?>` | installed / written |
| Package temp (°C) | `<v>` | `<v>` |

### Validation Results

| Check Area | Status | Evidence | Notes |
|---|---|---|---|
| script executable | PASS/FAIL | `test -x` result | set_thermal_profile.sh |
| thermald present | PASS/FAIL/N/A | `test -x /usr/sbin/thermald` | N/A for dry-run/output-file |
| sudo availability | PASS/FAIL/SKIP | `sudo -n true` exit code | SKIP for dry-run/output-file |
| profile/trips valid | PASS/FAIL | ordering + range checks | |
| config validated | PASS/FAIL/N/A | thermald test-mode parse | N/A when not applied |
| script apply | PASS/FAIL/N/A | exit code | N/A when not applied |
| sole thermal authority | PASS/FAIL/N/A | ExecStart flags | ignore-default-control set, adaptive off |

### Failures and Troubleshooting

| Failed Check | Raw Evidence | Troubleshooting Note |
|---|---|---|
| `<check area>` | `<snippet>` | `<action>` |

## Troubleshooting Notes
- `thermald not found at /usr/sbin/thermald`: install it (`sudo apt-get install -y thermald`) and re-trigger.
- The skill never prompts for sudo approval. If the script fails because sudo needs a password, configure passwordless sudo **out of band** first via `sudo visudo -f /etc/sudoers.d/set-thermal-profile`:
  ```
  <user> ALL=(root) NOPASSWD: /home/<user>/enib/tools/power-tuning/set_thermal_profile.sh
  ```
  Never use `NOPASSWD: ALL`. If a `sudo -v` timestamp exists but is not honored (tty_tickets), make timestamps global: `echo 'Defaults timestamp_type=global' | sudo tee /etc/sudoers.d/agent-timestamp && sudo chmod 0440 /etc/sudoers.d/agent-timestamp && sudo visudo -c`.
- "None of the expected cooling devices are present; refusing to write an empty zone": this platform exposes no `Fan`/`Processor`/`intel_powerclamp` cooling devices (check `grep . /sys/class/thermal/cooling_device*/type`). The profile cannot be applied as-is.
- "thermald did not accept the generated config": the script validates in test-mode before installing and aborts without changing the system; inspect the logged excerpt for the offending zone/trip.
- "powerclamp trip too close to Tjmax; use < 105": lower `clamp_c` below 105 °C.
- "Fan trip (…) must be < Processor trip (…)": trip points must satisfy `fan < proc < clamp`; reorder them.
- `--charge` requested but skipped: no `CHRG` cooling device on this platform; the top trip is written without it.
- If firmware adaptive tables seem to override the profile: confirm the effective `ExecStart` has `--ignore-default-control` and **no** `--adaptive` (the script's systemd override sets this); check `${OVERRIDE_FILE}` if not.

## Related Skills
- **set-power-profile** — cap the package/platform power (PkgWatt/SysWatt) so less heat is produced; the thermal profile then governs the escalation as temperature rises. Apply the power envelope first, then the thermal policy.
- **monitor-power-thermal** — watch PkgTmp against the trip points while a load runs, to confirm the escalation engages where intended.
- **generate-platform-stress** — drive the platform hot enough with synthetic load (stress-ng) to exercise the trip points and observe the fan / frequency-cap / idle-injection stages.
- **generate-openvino-stress** — drive the platform with real AI inference load (OpenVINO benchmark_app on CPU/GPU/NPU) to exercise trip points under realistic workload patterns.
- **Typical loop:** set a power profile → set this thermal profile → start `monitor-power-thermal` → run `generate-platform-stress` or `generate-openvino-stress` with a bounded duration → confirm temperature holds within the trips without unexpected throttling.
