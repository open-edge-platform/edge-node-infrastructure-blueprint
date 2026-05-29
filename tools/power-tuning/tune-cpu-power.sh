#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
# tune-cpu-power.sh
#
# Apply a CPU + platform power profile for Intel Core Ultra Series 3
# (Panther Lake, hybrid P/E/LPE topology). Idempotent and safe to re-run.
#
# Modes:
#   battery     - maximize battery life
#   balanced    - default daily-use profile
#   performance - maximize sustained performance
#
# Per-profile knob values:
#
# | Knob                          | battery        | balanced        | performance | Purpose (brief)                                                  |
# |-------------------------------|----------------|-----------------|-------------|------------------------------------------------------------------|
# | scaling_governor              | powersave      | powersave       | performance | cpufreq policy; powersave defers to HWP, performance pins max    |
# | EPP (energy_perf_preference)  | power          | balance_power   | performance | HWP hint inside the CPU; biggest single perf/power lever         |
# | EPB (energy_perf_bias 0..15)  | 15             | 6               | 0           | Legacy MSR 0x1B0 bias; 15=max save, 0=max perf                   |
# | intel_pstate/no_turbo         | 1 (off)        | 0               | 0           | Disables Turbo Boost when 1 to cap peak power                    |
# | intel_pstate/min_perf_pct     | 0              | 0               | 50          | Floor for P-state window; keeps perf mode from dropping low      |
# | intel_pstate/max_perf_pct     | 60             | 100             | 100         | Ceiling for P-state window; caps sustained freq on battery       |
# | platform_profile (ACPI)       | low-power      | balanced        | performance | Firmware power slider; also tunes EC fan curves and PL1/PL2      |
# | pcie_aspm policy              | powersupersave | default         | performance | PCIe link power mgmt; supersave enables L1 substates             |
# | nmi_watchdog                  | 0              | 1               | 1           | Disables per-CPU perf timer to deepen idle residency             |
# | snd_hda_intel power_save (s)  | 1              | 1               | 0           | Runtime-suspends HDA audio after N seconds of silence            |
# | USB autosuspend               | on (2000 ms)   | on (2000 ms)    | off (-1)    | Auto-suspends idle USB devices; off removes resume latency       |
# | ondemand.service              | untouched      | untouched       | disabled    | Legacy boot unit that would override the performance governor    |

set -u

PROFILE=""
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: tune-cpu-power.sh --profile {battery|balanced|performance} [--dry-run]

Tunes CPU governor, intel_pstate EPP/EPB, turbo, ACPI platform_profile,
PCIe ASPM, NMI watchdog, audio and USB autosuspend.

Options:
  --profile <name>  Required. One of: battery, balanced, performance
  --dry-run         Print actions without writing to sysfs
  -h, --help        Show this help

Requires root.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

case "$PROFILE" in
  battery|balanced|performance) ;;
  *) echo "ERROR: --profile must be battery|balanced|performance" >&2; usage; exit 2 ;;
esac

if [[ $EUID -ne 0 && $DRY_RUN -eq 0 ]]; then
  echo "ERROR: must run as root (or use --dry-run)" >&2
  exit 1
fi

log()  { printf '[tune-cpu-power] %s\n' "$*"; }
skip() { printf '[tune-cpu-power] SKIP  %s\n' "$*"; }
apply() { printf '[tune-cpu-power] APPLY %s\n' "$*"; }

write_to() {
  local value="$1" path="$2"
  if [[ ! -e "$path" ]]; then
    skip "no path: $path"
    return 0
  fi
  if [[ ! -w "$path" && $DRY_RUN -eq 0 ]]; then
    skip "not writable: $path"
    return 0
  fi
  apply "$path <= $value"
  [[ $DRY_RUN -eq 1 ]] && return 0
  printf '%s' "$value" > "$path" 2>/dev/null || skip "write failed: $path"
}

write_glob() {
  local value="$1" glob="$2" found=0
  for p in $glob; do
    [[ -e "$p" ]] || continue
    found=1
    write_to "$value" "$p"
  done
  [[ $found -eq 0 ]] && skip "no matches: $glob"
  return 0
}

# Per-profile knob values
case "$PROFILE" in
  battery)
    GOV="powersave";    EPP="power";              EPB=15
    NO_TURBO=1;         MIN_PCT=0;                MAX_PCT=60
    ACPI_PROFILE="low-power"; ASPM="powersupersave"
    NMI_WATCHDOG=0;     AUDIO_PS=1;               USB_AUTOSUSPEND=1
    ;;
  balanced)
    GOV="powersave";    EPP="balance_power";      EPB=6
    NO_TURBO=0;         MIN_PCT=0;                MAX_PCT=100
    ACPI_PROFILE="balanced";  ASPM="default"
    NMI_WATCHDOG=1;     AUDIO_PS=1;               USB_AUTOSUSPEND=1
    ;;
  performance)
    GOV="performance";  EPP="performance";        EPB=0
    NO_TURBO=0;         MIN_PCT=50;               MAX_PCT=100
    ACPI_PROFILE="performance"; ASPM="performance"
    NMI_WATCHDOG=1;     AUDIO_PS=0;               USB_AUTOSUSPEND=0
    ;;
esac

log "selected profile: $PROFILE (dry-run=$DRY_RUN)"

# Hybrid topology summary (read-only, informational)
if ls /sys/devices/system/cpu/cpu*/topology/core_type >/dev/null 2>&1; then
  awk '{c[$1]++} END {
    printf "[tune-cpu-power] hybrid topology: P=%d E=%d LPE=%d\n",
      c[2]+0, c[1]+0, c[3]+0
  }' /sys/devices/system/cpu/cpu*/topology/core_type
else
  log "hybrid topology: core_type not exposed by kernel"
fi

# 1) cpufreq governor (all online CPUs)
write_glob "$GOV" "/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"

# 2) intel_pstate EPP (per-CPU)
write_glob "$EPP" "/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference"

# 3) Energy/Performance Bias
write_glob "$EPB" "/sys/devices/system/cpu/cpu*/power/energy_perf_bias"

# 4) intel_pstate global knobs
write_to "$NO_TURBO" /sys/devices/system/cpu/intel_pstate/no_turbo
write_to "$MIN_PCT"  /sys/devices/system/cpu/intel_pstate/min_perf_pct
write_to "$MAX_PCT"  /sys/devices/system/cpu/intel_pstate/max_perf_pct

# 5) ACPI platform_profile (firmware-exposed power slider)
if [[ -e /sys/firmware/acpi/platform_profile_choices ]]; then
  if grep -qw "$ACPI_PROFILE" /sys/firmware/acpi/platform_profile_choices 2>/dev/null; then
    write_to "$ACPI_PROFILE" /sys/firmware/acpi/platform_profile
  else
    skip "platform_profile '$ACPI_PROFILE' not in choices"
  fi
fi

# 6) PCIe ASPM policy
write_to "$ASPM" /sys/module/pcie_aspm/parameters/policy

# 7) NMI watchdog
write_to "$NMI_WATCHDOG" /proc/sys/kernel/nmi_watchdog

# 8) HD-audio runtime PM
write_glob "$AUDIO_PS" "/sys/module/snd_hda_intel/parameters/power_save"

# 9) USB autosuspend (default for new devices, in ms; -1 disables)
if [[ "$USB_AUTOSUSPEND" -eq 1 ]]; then
  write_to 2000 /sys/module/usbcore/parameters/autosuspend
  write_glob auto "/sys/bus/usb/devices/*/power/control"
else
  write_to -1 /sys/module/usbcore/parameters/autosuspend
  write_glob on "/sys/bus/usb/devices/*/power/control"
fi

# 10) Disable legacy ondemand unit for the performance profile
if [[ "$PROFILE" == "performance" && $DRY_RUN -eq 0 ]]; then
  if systemctl list-unit-files ondemand.service >/dev/null 2>&1; then
    apply "systemctl disable --now ondemand.service"
    systemctl disable --now ondemand.service >/dev/null 2>&1 || skip "could not disable ondemand"
  fi
fi

log "done"
