<!-- SPDX-FileCopyrightText: (C) 2026 Intel Corporation -->
<!-- SPDX-License-Identifier: LicenseRef-Intel -->
# Design Proposal: Power and Thermal Profiling

Author(s): Edge Infrastructure Team

Last updated: 26/07/2026

## Abstract

This document describes the design of a **power and thermal profiling** toolkit
for Intel® Core Ultra™ edge platforms (tuned for Panther Lake with runtime
detection for other silicon). The toolkit lets an operator place a platform
under a known, repeatable power envelope, drive it with a controlled or real
workload, and observe the resulting power draw and package temperature — so a
profile can be validated against the thermal and power headroom of a specific
enclosure before it ships.

The toolkit is composed of four reference shell tools under
[tools/power-tuning/](../../../tools/power-tuning/), each fronted by a Claude
skill that adds validation, a dry-run/confirmation gate, and a structured report:

| Tool | Skill | Role |
|---|---|---|
| [set_power_profile.sh](../../../tools/power-tuning/set_power_profile.sh) | `set-power-profile` | Set the power envelope (intel_lpmd tuning + hard RAPL cap) |
| [set_thermal_profile.sh](../../../tools/power-tuning/set_thermal_profile.sh) | `set-thermal-profile` | Set the thermal escalation policy (thermald trip points) |
| [stress_gen.sh](../../../tools/power-tuning/stress_gen.sh) | `generate-platform-stress` | Generate controlled CPU + iGPU load (stress-ng, synthetic) |
| [openvino_stress.sh](../../../tools/power-tuning/openvino_stress.sh) | `generate-openvino-stress` | Generate real AI inference load on CPU/GPU/NPU (OpenVINO `benchmark_app`) |
| [pt_mon.sh](../../../tools/power-tuning/pt_mon.sh) | `monitor-power-thermal` | Power and thermal monitor (turbostat) |

All five tools are **reference implementations**: an operator is free to
substitute an equivalent (a real workload for the stressor, `turbostat`
directly for the monitor). The toolkit only automates the reference path.

A fifth **orchestrator skill**, `combined-power-thermal-profiling`
([skills/combined-power-thermal-profiling/SKILL.md](../../../skills/combined-power-thermal-profiling/SKILL.md)),
composes the four above into a single apply → monitor → stress → summarize session
(one combined confirmation, a bounded `duration`) and emits a consolidated
enclosure report. It wraps no new tool — it sequences the four reference skills.

## Goals

- Provide a **repeatable** way to constrain a platform to a chosen power budget
  (sustained PL1, burst PL2, time window tau) and thermal policy (staged
  fan → frequency-cap → idle-injection escalation).
- Make the envelope **observable** under load so an operator can confirm the
  platform holds the target without throttling, and measure the real
  power/temperature headroom of an enclosure.
- Track the **silicon**, not hardcoded numbers: read Config-TDP levels
  (Nominal / Level 1 / Level 2) and RAPL power/time units from the CPU at
  runtime, with documented Panther Lake fallbacks when MSRs are unavailable.
- Fail **safe and observable**: runtime-only RAPL caps that reset on reboot,
  validate-before-install for thermal config, and a dry-run + confirmation gate
  on every mutating skill.

## Non-Goals

- Persisting the RAPL power cap across reboot (deliberately runtime-only as a
  safety net; wrapping it in a systemd unit is left to the integrator).
- Managing discrete-GPU power, or accelerators without a RAPL/powercap domain
  (legacy GNA has no power domain and is left untouched).
- Cross-platform (non-Intel) support beyond a non-fatal sanity warning.

## Background & Key Concepts

| Term | Meaning |
|---|---|
| PkgWatt | Package power — CPU cores + integrated GPU + uncore. The primary, always-enforceable budget. |
| SysWatt / psys | Whole-platform power (board rails). Not populated on all silicon; can read `0.00`. |
| PL1 / PL2 | Sustained / short-burst power limits. `PL2 = PL1 × burst_ratio`. |
| tau | PL1 time window (seconds) over which sustained power is averaged. |
| cTDP | Configurable TDP. **Level 2** is the silicon's maximum configurable sustained power. |
| RAPL | Running Average Power Limit — the hardware feature used to read/enforce limits. |
| MSR | Model-Specific Register — programmed directly to bypass the sysfs firmware clamp (needs `msr` module + `msr-tools`). |
| EPP / EPB | Energy Performance Preference / Bias — hints steering the CPU toward performance or efficiency. |
| intel_lpmd | Intel Low Power Mode daemon; configured and restarted to apply CPU tuning. |
| thermald | Linux thermal daemon; consumes the trip-point XML the thermal tool generates. |

## Architecture Overview

The toolkit separates the three concerns of a profiling session — **constrain**,
**load**, **observe** — into independent tools that compose via a typical loop:

```
                     ┌─────────────────────────┐
   1. CONSTRAIN      │  set_power_profile.sh   │  intel_lpmd config + RAPL MSR cap
                     │  set_thermal_profile.sh │  thermald trip-point XML
                     └────────────┬────────────┘
                                  │  applies envelope
                                  ▼
   2. OBSERVE        ┌─────────────────────────┐
      (terminal A)   │  pt_mon.sh              │  turbostat: PkgTmp + RAPL domains
                     └────────────┬────────────┘
                                  │  samples every 2 s → pt_mon.txt
                                  ▼
   3. LOAD           ┌─────────────────────────┐
      (terminal B)   │  stress_gen.sh          │  stress-ng: N CPU + M iGPU workers
                     │  openvino_stress.sh     │  OpenVINO inference: CPU/GPU/NPU
                     │  (or the real workload) │
                     └─────────────────────────┘
```

**Typical loop:** apply a power/thermal profile → start the monitor → run a
bounded stress load (or the real workload) → read the min/mean/max summary →
step the profile up/down and repeat until throughput stops improving or the
platform begins to throttle.

The `combined-power-thermal-profiling` orchestrator skill automates one pass of this loop
(apply → monitor → stress → summarize) with a single confirmation and emits the
consolidated enclosure report; the operator steps the profile between passes.

### Layering

Each tool is a self-contained bash script (the reference implementation) wrapped
by a Claude skill (`skills/<name>/SKILL.md`) that adds:

- **Preconditions** — executable check, tool presence (`turbostat`, `stress-ng`,
  `msr-tools`), Intel/x86_64 sanity, non-interactive sudo probe.
- **Input validation** — fail-closed range/type checks before any write.
- **Dry-run + confirmation gate** — every mutating skill previews the resolved
  plan and pauses for confirmation (unless `auto_confirm` or `dry_run`).
- **Structured report** — run metadata, planned changes, pre→post snapshots,
  and a validation table.

## Component Design

### 1. Power Profile — `set_power_profile.sh`

Sets an intel_lpmd power profile and enforces it with a hard RAPL power cap over
the CPU package (CPU + iGPU) and, where supported, the platform (psys) domain.

**Two drive modes:**

1. **Named profile** (`--profile`), expressed as a PkgWatt budget:

   | Profile | PkgWatt | Default burst ratio |
   |---|---|---|
   | LowPower | 10 W | 1.25 |
   | BalancedLow | 15 W | 1.25 |
   | BalancedHigh | 20 W | 1.18 |
   | Performance | 25 W | 1.19 |
   | MaxPerformance | platform max (cTDP Level 2) | 1.18 |
   | Custom | explicit (`--pkgWatt`/`--sysWatt`/…) | 1.25 |

2. **Explicit targets** (`--pkgWatt` / `--sysWatt` / `--burstRatio` / `--pl1Tau`)
   for fine-grained control.

**Enforcement mechanics:**

- **CPU:** generates a single-state intel_lpmd config with EPP/EPB interpolated
  from a 5 W-spaced Panther Lake tuning table for the target wattage, then biased
  toward performance by the PL2/PL1 ratio. Installs it, restarts the daemon, and
  puts it in AUTO. Model/TDP-specific config files (e.g. `F6_M204`) are also
  overwritten (with a one-time `.orig` backup) because the daemon prefers them
  over the generic file.
- **GPU:** included implicitly — the RAPL package domain covers the iGPU.
- **NPU:** capped if it exposes a RAPL/powercap domain.
- **Cap:** PL1 = target, PL2 = target × burst_ratio, written straight to the RAPL
  **MSRs** (0x610 package / 0x65C psys) because the powercap **sysfs** interface
  clamps to the firmware-advertised max (e.g. a 25 W cTDP). sysfs is still used
  for the MMIO package mirror and NPU/VPU domains. cTDP Level 2 is selected at
  runtime (best-effort; may require a BIOS setting) when the target exceeds
  Nominal.

**Design decisions:**

- **PkgWatt is the profile parameter** because the package cap is enforceable on
  every platform via MSR 0x610, whereas psys is not implemented on all silicon.
- **Silicon-aware:** Config-TDP levels and RAPL units are read from MSRs
  (0x606/0x614/0x649/0x64A), with Panther Lake fallbacks (Nominal 25 W /
  Level 1 15 W / Level 2 65 W). Targets are clamped to `[0.125 W, Level 2]` and
  snapped to the power-unit granularity.
- **Runtime-only cap:** does not persist across reboot — a built-in safety net if
  a profile proves too aggressive. The intel_lpmd config on disk *does* persist.

**Dependencies & preconditions:** root (self-elevates via `sudo -E`), `msr`
module + `msr-tools`; a set of mandatory BIOS settings hand CPU power/frequency
control to the OS (Speed Shift, HWP autonomous, PL1/PL2 enable, C-states) —
documented in the `set-power-profile` skill.

### 2. Thermal Profile — `set_thermal_profile.sh`

Generates, applies, and verifies a thermald thermal profile that stages an
escalating response on the CPU package sensor (`x86_pkg_temp`):

```
   Fan (active)  <  Processor (passive)  <  intel_powerclamp (passive)
   fans on early     cap CPU frequency      inject idle cycles (hard limit)
```

**Profiles (Fan / Processor / powerclamp trip points, °C):**

| Profile | Fan | Processor | powerclamp |
|---|---|---|---|
| cool | 55 | 70 | 80 |
| warm *(default)* | 60 | 75 | 85 |
| hot | 70 | 90 | 95 |
| thermal-max | 95 | 100 | 104 |
| custom | `--fan` | `--proc` | `--clamp` |

**Design decisions:**

- **thermald as sole authority:** installs a systemd drop-in that runs thermald
  with `--ignore-default-control` and **without** `--adaptive`, so the generated
  trip points win over firmware DPTF/GDDV adaptive tables.
- **Validate before install:** the generated XML is parsed by thermald in
  `--no-daemon --test-mode` first; the config is only installed if the zone
  loads and the platform matches. Existing config and override are backed up.
- **Ordering invariant:** Fan < Processor < powerclamp is enforced, and the top
  trip is kept below Tjmax (~110 °C, refuses ≥ 105).
- **Graceful degradation:** only wires in cooling devices actually present on the
  platform (Fan / Processor / intel_powerclamp / optional CHRG); refuses to write
  an empty zone.
- **Modes:** `--dry-run` (print only), `-o FILE` (write XML, no daemon changes),
  `--disable` (revert to kernel default thermal control).

**Skill wrapper:** the `set-thermal-profile` skill adds the same
preconditions / dry-run / confirmation-gate / structured-report structure as the
other three tools. Note the thermald config and systemd override **persist across
reboot** (unlike the runtime-only RAPL power cap).

### 3. Load Generation — `stress_gen.sh` (synthetic) and `openvino_stress.sh` (AI inference)

Generates a controlled, repeatable synthetic load via `stress-ng`, or is
substituted by the real workload under evaluation.

| Option | Meaning | Default |
|---|---|---|
| `--cpus N` | CPU workers, `1..nproc` | all CPUs |
| `--load P` | per-CPU load %, `1..100` | 100 |
| `--gpu N` | iGPU stressor **worker count** (not GPU count) | 12 (0 = off) |
| `--duration D` | stress-ng timeout (`60s`, `5m`) | until Ctrl-C |

**Design decisions:**

- **Refuses to stack:** exits if a `stress-ng` instance is already running, so
  measurements are not skewed by overlapping stressors.
- **No root required:** runs as the current user.
- **Bounded vs open-ended:** a `--duration` run reveals sustained (PL1) vs burst
  (PL2) behavior; open-ended runs stream until stopped and should be avoided
  unattended on constrained enclosures.

For a **real AI inference** load instead of the synthetic stressor,
`openvino_stress.sh` runs OpenVINO `benchmark_app` in a container and drives the
CPU, GPU, or NPU with an actual neural network — closer to a production edge
workload for throughput-per-watt and thermal qualification.

| Option | Meaning | Default |
|---|---|---|
| `--device cpu\|gpu\|npu` | Target accelerator | `cpu` |
| `--runtime k3s\|docker` | Container runtime | auto-detect |
| `--niter N` | Iterations (`0` = time-based) | 0 |
| `--duration D` | Run time in seconds when `niter=0` | 60 |
| `--api sync\|async` | Inference API mode | `sync` |

**Design decisions:**

- **Real compute pattern:** exercises the inference engine (and the GPU/NPU
  device plugins) rather than synthetic ALU/memory loops, so the measured power
  and thermals reflect a representative AI workload.
- **Runtime auto-detection:** picks Docker or K3s automatically; K3s pod specs
  are generated inline (no external YAML).
- **Model auto-download:** fetches the default model on first run if absent, and
  supports overriding the model, image, and thread count.

### 4. Monitor — `pt_mon.sh`

Wraps `turbostat -S` to print a periodic (2 s) summary of package temperature and
the RAPL power domains, teed to `pt_mon.txt`.

**Columns:** `PkgTmp`, `SysWatt` (psys), `PkgWatt`, `CorWatt`, `GFXWatt`,
`RAMWatt`.

**Design decisions:**

- **psys frozen-counter detection:** on some Core Ultra silicon MSR 0x65C exists
  but the firmware never updates it, so turbostat's Δenergy/Δtime yields
  `SysWatt = 0.00`. `check_psys()` detects the absent-domain and frozen-counter
  cases and warns; **PkgWatt is the effective figure** in that case. This is a
  documented firmware limitation, not a bug.
- **Read-only:** changes no system state; the only artifact is the log file.
- **Requires root** (turbostat reads MSRs) and the `msr` module.

## Cross-Cutting Concerns

### Silicon detection & fallbacks

All wattage/timing math derives from MSRs read at runtime (RAPL power/time units,
Config-TDP levels). When `msr-tools`/`msr` are unavailable the power tool falls
back to documented Panther Lake defaults and reports that it did so — the tool
never silently guesses.

### Safety & reversibility

| Concern | Mechanism |
|---|---|
| Too-aggressive power cap | RAPL cap is runtime-only; resets to firmware defaults on reboot |
| Bad thermal config | Validated in thermald test-mode before install; prior config/override backed up |
| Overwritten lpmd config | One-time `.orig` backup of any model-specific file |
| Unmanaged thermal window | Thermal tool restarts the daemon and restores it if it aborts mid-run |
| Accidental application | Dry-run + confirmation gate on every mutating skill |

### Sudo handling

Per repository policy ([AGENTS.md](../../../AGENTS.md)), skills probe with
`sudo -n true` and **never** collect a password. Passwordless sudo is expected to
be pre-configured out of band with a scoped `NOPASSWD` entry for the specific
binary (the script or `turbostat`) — never `NOPASSWD: ALL`.

### Persistence summary

| Change | Persists across reboot? | How to revert |
|---|---|---|
| RAPL power cap (PL1/PL2) | No — resets to firmware default | Reboot, or re-run a lower profile |
| intel_lpmd config on disk | Yes — re-read by daemon at boot | Restore `.orig`, restart `intel_lpmd` |
| thermald config + override | Yes | `--disable`, or restore `.bak` |

## Validation Approach

A profiling session is validated by the compose loop itself:

1. Apply a profile with `--dry-run`, confirm the resolved plan matches intent.
2. Apply for real; confirm the post-change RAPL snapshot reflects the target
   PL1/PL2 (allowing for documented firmware/cTDP clamping).
3. Start the monitor; run a bounded stress load at the profile's budget.
4. Confirm package temperature stays within the thermal profile's trip points
   and PkgWatt holds at the target without sustained throttling.
5. Record min/mean/max of PkgTmp / PkgWatt / GFXWatt for the enclosure's report.

**Known-good signals:** `SysWatt = 0.00` on frozen-psys silicon is expected;
"firmware clamped PL1" indicates the BIOS cTDP ceiling needs raising to
Level 2; a brief (~2 s) management gap occurs while `intel_lpmd` restarts.

## Open Items

- **Boot persistence:** optionally provide a systemd unit template that re-applies
  a chosen power cap at boot for operators who want the envelope to persist.
- **Platform coverage:** document tested silicon beyond Panther Lake and expand
  the EPP/EPB tuning table if other Core Ultra models need distinct sampling.
