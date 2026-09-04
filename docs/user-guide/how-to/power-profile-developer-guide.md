<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Power Profile Developer Guide

This guide explains the implementation details of the power profile functionality, enabling developers to create, modify, adopt, and customize power profiles on their systems.

> **Note:** For acronym definitions and additional context, refer to the user guide and skills documentation.

Legend used in the tables:
- **R** = read only, **W** = write, **RMW** = read-modify-write.

---

## 1. Summary of access surfaces
While power management exposes numerous model-specific registers and sysfs interfaces, `set_power_profile.sh` applies only the minimal set of configurations required to implement the requested power profile using LPMD.

`set_power_profile.sh` manages power profiles through the following interfaces:

1. **Model-Specific Registers (MSR)** for low-level register access
   - Power and Energy management registers (e.g., Pkg/Core energy, power limits, power time units)
   - CPU Features & Capabilities (e.g., power_limit_uw, max_power_uw, min_power_uw, power_uw)

2. **powercap sysfs** Linux kernel interface (`/sys/class/powercap/`)
   - Power limits (e.g., power_limit_uw, max_power_uw, min_power_uw)
   - Power limit constraints (e.g., constraint_0_*, constraint_1_*)
   - Zone identification (e.g., package-0)
   - RAPL and socket information

3. **CPU sysfs interface** (`/sys/devices/system/cpu/`) for LPMD profile parameters
   - Energy Performance Preference (EPP)
   - Energy Performance Bias (EPB)
   - Intel Turbo Boost Max Technology (ITMT)

4. **LPMD configuration file** (`/etc/intel_lpmd/intel_lpmd_config.xml`) generated based on the requested power profile, using EPP, EPB, ITMT, and active CPU settings

5. **Low Power Mode Daemon** (intel_lpmd) applies the LPMD profile configuration

6. **Runtime settings:** Power profile settings applied via MSRs and sysfs are runtime-only and reset to defaults upon OS reboot. To restore a profile after reboot, re-run the script with `sudo` privileges.

The following table summarizes the access interfaces and their properties:

| # | Surface | Mode | Root needed | Persists across reboot |
| --- | --- | --- | --- | --- |
| 1 | Model-Specific Registers (`rdmsr`/`wrmsr` ) | R/W | yes/yes | (runtime only) |
| 3 | powercap sysfs (`/sys/class/powercap`) | R/W | no/yes | (runtime only) |
| 5 | cpu sysfs (`/sys/devices/system/cpu`) | R/W | no/yes | (runtime only) |
| 7 | `/proc`, cpufreq/cgroup sysfs, `nproc` | R | no | n/a |
| 8 | `intel_lpmd` XML config files | R / W | yes/yes | **yes** (on-disk) |
| 9 | Kernel module load (`modprobe msr`) | W (state) | yes | no |
| 10 | systemd unit + `intel_lpmd_control` | R / W | yes | no |
| 11 | Per-CPU EPP/EPB, cpuset (via the daemon) | W (indirect) | yes | no |

---

## 3. MSR reads

All reads use `rdmsr -0` — **CPU 0 only** — because RAPL package/platform
registers are package-scoped, so one core is representative.

| Register | Purpose | Fallback |
|----------|---------|----------|
| `0x606` `MSR_RAPL_POWER_UNIT` | Establish the hardware watt granularity and time granularity used to encode tau | `HAVE_MSR=0`, `STEP=0.125 W`, sysfs-only path |
| `0x614` `MSR_PKG_POWER_INFO` | Read the nominal TDP and threshold for selecting a cTDP level | `NOMINAL_TDP=25` |
| `0x649` `MSR_CONFIG_TDP_LEVEL1` | Report the Level 1 down-configured TDP | `LEVEL1_TDP=15` |
| `0x64A` `MSR_CONFIG_TDP_LEVEL2` | Read the maximum configurable TDP (`MAX_TDP`) | `MAX_TDP=65` |
| `0x65C` `MSR_PLATFORM_POWER_LIMIT` | Probe for psys/platform-domain support when no `psys` powercap domain is registered | Treated as unsupported |
| `0x64B` `MSR_CONFIG_TDP_CONTROL` | Check whether the runtime cTDP level can be switched | Skipped when `HAVE_MSR=0` |
| `0x610` `MSR_PKG_POWER_LIMIT` | Preserve unrelated bits, refuse locked writes, and verify what the firmware accepted | `set_msr_pl` returns non-zero → sysfs `apply_cap` fallback |
| `0x65C` `MSR_PLATFORM_POWER_LIMIT` | Read and verify the psys/SysWatt power-limit register | sysfs `apply_cap` on the `psys` domain |

**Shared dependencies for §3:** `msr-tools` (`rdmsr`), the `msr` kernel module,
root privileges, and a kernel without a lockdown policy that blocks
`/dev/cpu/*/msr`. Secure Boot with kernel lockdown enabled will make every MSR
access fail → the script degrades to the sysfs-only path with hardcoded
fallbacks.

---

## 4. MSR writes

All writes use `wrmsr -a` — **every logical CPU** — so the value is applied
regardless of which package/core the writer lands on.

| Register | Purpose | Impact | Reversibility |
|----------|---------|--------|---------------|
| `0x610` `MSR_PKG_POWER_LIMIT` | Hard package (CPU + iGPU uncore) power cap: sustained = PL1, burst = PL2 | Bounds CPU **and** integrated GPU power together, because the RAPL "package" domain includes the uncore. Directly changes sustained clocks, thermals and fan behaviour under load | Runtime only — lost on reboot; no original value is saved, so re-run with the previous target to restore |
| `0x65C` `MSR_PLATFORM_POWER_LIMIT` | Whole-platform (psys / turbostat *SysWatt*) cap, using its own `--sysWatt` target | Caps the entire platform rail, not just the package — can throttle even when the package is below its own PL1 | Runtime only |
| `0x64B` `MSR_CONFIG_TDP_CONTROL` | Select the Config-TDP level whose thermal spec can actually sustain the requested PL1 | Changes the guaranteed (base) frequency as well as the sustained ceiling. Best-effort: on some silicon only a **BIOS** Config-TDP Level 2 fully lifts the firmware limit | Runtime only; skipped entirely when bit 31 (lock) is set |

**Write guards:** the register is skipped if bit 63 (lock) is set

---

## 5. powercap sysfs reads

Domains are discovered by globbing `/sys/class/powercap/intel-rapl:*` (MSR-backed)
and `/sys/class/powercap/intel-rapl-mmio:*` (MMIO mirror).

| Path | Purpose | Impact |
|------|---------|--------|
| `intel-rapl:*/name` | Identify each domain (`package-0`, `psys`, `npu`, …) | Selects which programming path each domain takes (MSR vs sysfs) |
| `intel-rapl:*/name == psys` | Primary psys-support probe | Sets `SYS_SUPPORTED`; when false, `--sysWatt` is reported as ignored |
| `intel-rapl:*/constraint_0_max_power_uw` (first package domain) | `PKG_MAX_W` — the firmware-advertised sustained ceiling | Adds "(register only; firmware enforces ~XW sustained)" to the output as a diagnostic |
| `<dom>/constraint_{0,1}_max_power_uw` | Clamp each sysfs write to the domain's advertised max | Prevents a failed write; the applied value may legitimately be **lower** than requested |
| `<dom>/constraint_0_power_limit_uw`, `constraint_1_power_limit_uw`, `enabled` | Read back what was applied for the per-domain report line | Output only |
| `intel-rapl:*` + `intel-rapl-mmio:*` `package-*/constraint_0_power_limit_uw` and `constraint_0_max_power_uw` | Compute the **effective** enforced PL1 = min over package domains of `min(PL1, max)` | Produces `EFF_PL1_W`, `EFF_RATIO` and the "clamped by firmware/cTDP ceiling" warning |

**Dependencies for §5:** `CONFIG_POWERCAP` + `intel_rapl_common` /
`intel_rapl_msr` drivers loaded. Reads are unprivileged; only writes (§6) need
root.

---

## 6. powercap sysfs writes

Used as the **fallback** when the MSR path is unavailable or locked, and as the
**only** path for domains with no MSR equivalent (MMIO package mirror, NPU/VPU).

| Path | Purpose | Impact |
|------|---------|--------|
| `<dom>/constraint_0_power_limit_uw` | Long-term (PL1) sustained cap | Sustained power ceiling for that domain |
| `<dom>/constraint_1_power_limit_uw` | Short-term (PL2) burst cap | Burst headroom for that domain |
| `<dom>/constraint_0_time_window_us` | PL1 averaging window (tau) | Longer tau allows brief excursions above PL1; shorter tau enforces tighter tracking |
| `<dom>/enabled` | Arm enforcement for the domain | Ensures the configured cap is active |

Which domains get sysfs writes

| Domain pattern | Path taken | Reason |
|----------------|-----------|--------|
| `intel-rapl:*` → `package-*` | MSR `0x610`, sysfs only on failure | sysfs clamps to the firmware max and cannot raise the package |
| `*:psys` | MSR `0x65C`, sysfs only on failure | Same, with the independent SysWatt target |
| `intel-rapl-mmio:*` → `package-*` | sysfs only | The MMIO mirror has no MSR counterpart |
| `*npu*`, `*NPU*`, `*vpu*`, `*VPU*` | sysfs only | Modern NPUs expose a powercap domain but no RAPL MSR; legacy GNA accelerators have no domain and are left untouched |

---

## 7. procfs, cpufreq and cgroup reads

| Path / command | Purpose | Impact |
|----------------|---------|--------|
| `/proc/cpuinfo` → `cpu family` | Build the `F<family>` part of the model-specific `intel_lpmd` config filename | Without it the model-specific configuration may not be selected, so EPP/EPB/ActiveCPUs may not take effect |
| `/proc/cpuinfo` → `model` | Build the `M<model>` part of the model-specific filename, such as `F6_M204` | Ensures the matching model-specific configuration can be selected |
| `nproc` | Read the CPU count for the report line | Output only |
| `/sys/devices/system/cpu/cpu[0-9]*/cpufreq/energy_performance_preference` | Verify the EPP applied by the daemon across CPUs | Confirms that the LPMD EPP configuration was loaded |
| `/sys/devices/system/cpu/cpu[0-9]*/power/energy_perf_bias` | Verify the EPB applied by the daemon across CPUs | Confirms that the LPMD EPB configuration was loaded |
| `/sys/fs/cgroup/system.slice/cpuset.cpus.effective` | Show the effective cpuset that reflects the daemon's `ActiveCPUs` setting | Confirms the CPU placement configured by the profile |

---

## 10. Indirect writes performed by the `intel_lpmd` daemon

These are not written by the script — they are the consequence of installing the
config and restarting the daemon. They are listed because they are the
user-visible effect and the thing the report block reads back.

| Written by daemon | Source value | Impact |
|-------------------|--------------|--------|
| `/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference` | `<EPP>` — interpolated from the 5 W-spaced Panther Lake table, then divided by the effective burst ratio ([508-533](../../../tools/power-tuning/set_power_profile.sh#L508-L533)) | Changes turbo aggressiveness and idle-to-load ramp |
| `/sys/devices/system/cpu/cpu*/power/energy_perf_bias` | `<EPB>` — same interpolation, clamped 0–15 | Same direction as EPP, coarser |
| ITMT / preferred-core bias | `<ITMTState>` — nearest table sample (`-1` = leave, `0` = off, `1` = on) | At low wattage disables preferred-core bias; from 40 W up enables it |
| Task placement / cpuset | `<ActiveCPUs>` — `0-1`/`0-3`/`0-5`/`0-7` at 5–20 W, `all` from 25 W | Large latency/throughput effect at low wattages; visible in `cpuset.cpus.effective` |

---

## 13. Clamping and precedence chain (why a requested watt may not be what you get)

The `set_power_profile.sh` script processes a requested power profile through
several validation, conversion, and hardware-enforcement stages. The requested
value is first normalized to the platform's supported range and power-unit
granularity, then used to calculate burst limits and select the appropriate
cTDP level. The script applies the result through MSRs where possible and uses
powercap sysfs as a fallback or for domains without an MSR interface. Finally,
it reads back the configured limits to report the effective value enforced by
the platform rather than only the value requested by the user.

---

## 14. Worked example — `--profile BalancedHigh` in logical sequence

```bash
sudo tools/power-tuning/set_power_profile.sh --profile BalancedHigh
```

**Assumed platform** (Panther Lake, F6_M204, 16 logical CPUs). Every value below
is derived from these five reads; on different silicon the numbers change but the
sequence does not:

| Assumption | Source | Value |
|------------|--------|-------|
| Power-unit exponent `PU_BITS` | MSR `0x606` bits `3:0` | `3` → `STEP` = 1/2³ = **0.125 W** |
| Time-unit exponent `TU_BITS` | MSR `0x606` bits `19:16` | `10` → time unit = 1/1024 s |
| Nominal TDP | MSR `0x614` | **25 W** |
| Level 1 TDP | MSR `0x649` | 15 W |
| Level 2 TDP (`MAX_TDP`) | MSR `0x64A` | **65 W** |
| psys domain | `/sys/class/powercap/intel-rapl:*/name` | present |

### 14.1 Step-by-step sequence

| # | Step | Access (R/W) | Value / result |
|---|------|--------------|----------------|
| 1 | Load MSR driver | **W** `modprobe msr` | `/dev/cpu/*/msr` available |
| 2 | Probe RAPL units | **R** MSR `0x606` | `HAVE_MSR=1`, `PU_BITS=3`, `TU_BITS=10` |
| 3 | Read Config-TDP triple | **R** MSR `0x614`, `0x649`, `0x64A` | `NOMINAL_TDP=25`, `LEVEL1_TDP=15`, `MAX_TDP=65` |
| 4 | Probe psys support | **R** `intel-rapl:*/name`, else MSR `0x65C` | `SYS_SUPPORTED=1`, method `psys RAPL domain / MSR 0x65C` |
| 5 | Resolve the requested profile and generate its runtime parameters | — | `WATTS=20` is clamped and snapped to **20 W**; `PL1_W=20`, `PL2_W=23.625`, `PSYS_W=20`, `PSYS_PL2_W=23.625`, `TAU_S=28` is encoded as `Y=14`, `Z=3` (`TAU_FIELD=110`), and the LPMD table resolves to `EPP=160`, `EPB=8`, `ITMT=0`, `ActiveCPUs=0-7` before burst-ratio biasing to `EPP=136`, `EPB=7` |
| 6 | Stage + install generic config | **W** `mktemp`, `install -m 644 → $LPMD_CONF_DIR/intel_lpmd_config.xml` | single pinned state `POWER_20W` — **no backup of the generic file** |
| 7 | Override model-specific config | **W** `cp -a` → `.orig`, then `install -m 644` | `intel_lpmd_config_F6_M204.xml` (+ any `_T*.xml`) replaced; original preserved once as `.orig` |
| 8 | Restart the daemon | **W** `systemctl daemon-reload` → `reset-failed` → `restart intel_lpmd.service` | daemon reloads the new XML |
| 9 | Force AUTO | **W** `intel_lpmd_control AUTO` | state pushed to all CPUs (`sleep 2` before, `sleep 1` after) |
| 10 | Select cTDP level | **R** MSR `0x64B` (lock bit 31), **W** MSR `0x64B` | 20 W ≤ Nominal 25 W → level **0** (`Nominal/25W`); Level 2 is *not* needed here |
| 11 | Read package ceiling | **R** `intel-rapl:*/constraint_0_max_power_uw` | `PKG_MAX_W=25` (annotation only) |
| 12 | Cap `package-0` and `psys` | **RMW** MSRs `0x610` and `0x65C` | Apply and verify `PL1=20 W` and `PL2=23.625 W` for both domains |
| 13 | Cap MMIO package mirror | **W** sysfs `constraint_0/1_power_limit_uw`, `constraint_0_time_window_us`, `enabled` | `20000000` / `23625000` µW (both under the 25 W max, so no sysfs clamp), tau `28000000` µs, `enabled=1` |
| 14 | Cap NPU domain (if present) | **W** sysfs, same fields | `20000000` / `23625000` µW, clamped down to the NPU domain's own much lower max |
| 15 | Verify effective PL1 | **R** `constraint_0_power_limit_uw` + `constraint_0_max_power_uw` over all package domains | `min(20000000, 25000000) = 20000000` → `EFF_PL1_W=20`, **not clamped**; `EFF_RATIO = 23.625/20 = 1.18` |
| 16 | Report | **R** `intel_lpmd_control STATUS`, per-CPU EPP/EPB, `cpuset.cpus.effective` | Console summary |

Because 20 W sits below Nominal TDP and below every advertised ceiling,
BalancedHigh is the clean case: **nothing is clamped anywhere** — requested,
programmed and enforced PL1 are all 20 W. Contrast `--profile MaxPerformance`,
which resolves to 65 W, trips the cTDP Level 2 switch at step 10, and typically
gets clamped back to ~25 W at step 15 unless BIOS Config-TDP Level 2 is set.

### 14.2 MSR `0x610` bit layout for this example

| Field | Bits | Value | Meaning |
|-------|------|-------|---------|
| PL1 power limit | `14:0` | `160` (`0x0A0`) | 160 × 0.125 W = **20 W** sustained |
| PL1 enable | `15` | `1` | limit armed |
| PL1 clamp | `16` | preserved | untouched by the script |
| PL1 time window | `23:17` | `110` (`Y=14`, `Z=3`) | tau = **28 s** |
| PL2 power limit | `46:32` | `189` (`0x0BD`) | 189 × 0.125 W = **23.625 W** burst |
| PL2 enable | `47` | `1` | limit armed |
| Lock | `63` | `0` (checked) | write refused if set |

Assembled write (clamp/lock bits clear in the read-back value):
`wrmsr -a 0x610 0x000080bd00dc80a0`.

### 14.3 Generated `intel_lpmd` config

The interesting subset of the XML installed at step 17 (full template at
[set_power_profile.sh:554-593](../../../tools/power-tuning/set_power_profile.sh#L554-L593)):

```xml
<!-- Auto-generated by set_power_profile.sh for ~20W. Pinned single state. -->
<State>
    <ID> 1 </ID>
    <Name> POWER_20W </Name>
    <EPP> 136 </EPP>          <!-- table 160, biased by ratio 1.18 -->
    <EPB> 7 </EPB>            <!-- table 8,   biased by ratio 1.18 -->
    <ITMTState> 0 </ITMTState><!-- preferred-core bias off below 25 W -->
    <IRQMigrate> -1 </IRQMigrate>
    <ActiveCPUs> 0-7 </ActiveCPUs>  <!-- work folded onto the 8 low-index cores -->
</State>
```

### 14.4 Console output

```text
Config-TDP levels: Nominal=25W  Level1=15W  Level2(max)=65W
Profile          : BalancedHigh
PkgWatt target   : 20W
Burst ratio      : 1.18
SysWatt support  : yes (psys RAPL domain / MSR 0x65C) -> SysWatt tracks PkgWatt (20W)
PL1 time window: requested 28s -> encoded ~28s (Y=14 Z=3)
Target: PL1=20W PL2=23.625W (ratio 1.18)  ->  EPP=136 EPB=7 ITMT=0 ActiveCPUs=0-7
Overrode model-specific config /usr/local/etc/intel_lpmd/intel_lpmd_config_F6_M204.xml (original saved as ....orig)
  cTDP level -> 0 (Nominal/25W)
Applying RAPL caps:
  capped package-0 (0x610 via MSR) -> PL1 20W  PL2 23.625W
  capped psys (0x65C via MSR) -> PL1 20W  PL2 23.625W
  capped package-0 -> PL1 20000000 uw, PL2 23625000 uw (enabled=1)
=== Result ===
  intel_lpmd state : AUTO
  CPU tuning       : EPP=136 EPB=7 ITMT=0 cpuset=0-7 (16 CPUs)
  Package (PkgWatt): PL1=20W, PL2=23.625W (effective ratio 1.18), tau=28s
  psys (SysWatt)   : PL1=20W, PL2=23.625W
Done. (runtime only; does not persist across reboot)
```

The third `capped` line is the **MMIO package mirror** (`intel-rapl-mmio:0`,
also named `package-0`), written via sysfs because it has no MSR counterpart —
not a duplicate of the first line.

> `EPP=136` in the report assumes the `energy_performance_preference` files hold
> raw numbers. With `intel_pstate` in active mode those files may instead report
> a named string (`balance_performance`, `performance`, …) — the value is still
> the one the daemon applied.

### 14.5 Preview without touching the platform

```console
$ tools/power-tuning/set_power_profile.sh --profile BalancedHigh --dry-run
```

Runs steps 1-3 and 10-16, printing the resolved plan and its explicit-target
equivalent. Steps 5-9 are still *attempted* (the probes are not gated on
`DRY_RUN`) but fail without root, and steps 17-30 are skipped entirely:

```text
Dry run - no changes applied.
Effective command line (resolved explicit-target equivalent):
  sudo tools/power-tuning/set_power_profile.sh --pkgWatt 20 --sysWatt 20 --burstRatio 1.18 --pl1Tau 28
```

No elevation happens, so the MSRs are usually unreadable and the Config-TDP
levels shown come from the hardcoded fallbacks (25 / 15 / 65 W) rather than the
silicon — see the `--dry-run` callout in [§1](#1-summary-of-access-surfaces).

