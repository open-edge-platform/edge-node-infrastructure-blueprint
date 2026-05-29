#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
# tune-gpu.sh
#
# Apply a GPU power/performance profile for the Intel Xe3 iGPU on
# Intel Core Ultra Series 3 (Panther Lake). Supports both i915 and xe
# kernel drivers. Idempotent and safe to re-run.
#
# Modes:
#   battery     - clamp gt freq to hw min, longer SR-IOV quanta
#   balanced    - restore hw min/max defaults
#   performance - clamp gt freq to hw max, raise boost
#   graphical   - performance freqs + short SR-IOV quanta for responsive UI
#
# GPU frequency (RP0 = hw max, RPn = hw min; same intent for i915 and xe):
#
# | Profile     | gt_min | gt_max | gt_boost | Intent (brief)                                                       |
# |-------------|--------|--------|----------|----------------------------------------------------------------------|
# | battery     | RPn    | RPn    | RPn      | Pin to lowest hw freq; iGPU spends max time in RC6                   |
# | balanced    | RPn    | RP0    | RP0      | Kernel default range; on-demand scaling                              |
# | performance | RP0    | RP0    | RP0      | Pin to max; removes ramp latency under bursty render load            |
# | graphical   | RP0    | RP0    | RP0      | Same as performance; pairs with short SR-IOV quanta below            |
#
# SR-IOV scheduling (only when VFs are configured; i915 debugfs):
#
# | Profile     | exec_quantum_ms | preempt_timeout_us | Intent (brief)                                                |
# |-------------|-----------------|--------------------|---------------------------------------------------------------|
# | battery     | 50              | 50000              | Longer slices = fewer context switches, more GPU idle windows |
# | balanced    | 20              | 20000              | Driver-typical defaults                                       |
# | performance | 20              | 20000              | Defaults; freq pinning does the work                          |
# | graphical   | 8               | 10000              | Short slices = snappier compositor / interactive UI           |

set -u

PROFILE=""
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: tune-gpu.sh --profile {battery|balanced|performance|graphical} [--dry-run]

Tunes Intel Xe3 iGPU min/max/boost frequencies (i915 and xe drivers) and
SR-IOV scheduling quanta when exposed via debugfs.

Options:
  --profile <name>  Required. One of: battery, balanced, performance, graphical
  --dry-run         Print actions without writing to sysfs/debugfs
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
  battery|balanced|performance|graphical) ;;
  *) echo "ERROR: --profile must be battery|balanced|performance|graphical" >&2; usage; exit 2 ;;
esac

if [[ $EUID -ne 0 && $DRY_RUN -eq 0 ]]; then
  echo "ERROR: must run as root (or use --dry-run)" >&2
  exit 1
fi

log()   { printf '[tune-gpu] %s\n' "$*"; }
skip()  { printf '[tune-gpu] SKIP  %s\n' "$*"; }
apply() { printf '[tune-gpu] APPLY %s\n' "$*"; }

read_first() { [[ -r "$1" ]] && cat "$1" 2>/dev/null || true; }

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

log "selected profile: $PROFILE (dry-run=$DRY_RUN)"

# --- Tune each Intel render card -------------------------------------------
shopt -s nullglob
tuned_card=0
for card in /sys/class/drm/card*; do
  [[ -e "$card/device/vendor" ]] || continue
  vendor=$(read_first "$card/device/vendor")
  [[ "$vendor" == "0x8086" ]] || continue
  cname=$(basename "$card")
  log "card: $cname"
  tuned_card=1

  # i915 driver layout: /sys/class/drm/cardN/gt_{min,max,boost,RP0,RPn}_freq_mhz
  if [[ -e "$card/gt_max_freq_mhz" ]]; then
    rp0=$(read_first "$card/gt_RP0_freq_mhz")   # hw max
    rpn=$(read_first "$card/gt_RPn_freq_mhz")   # hw min
    [[ -z "$rp0" ]] && rp0=$(read_first "$card/gt_max_freq_mhz")
    [[ -z "$rpn" ]] && rpn=$(read_first "$card/gt_min_freq_mhz")
    log "  i915 hw range: ${rpn:-?}-${rp0:-?} MHz"
    case "$PROFILE" in
      battery)
        write_to "$rpn" "$card/gt_min_freq_mhz"
        write_to "$rpn" "$card/gt_max_freq_mhz"
        [[ -e "$card/gt_boost_freq_mhz" ]] && write_to "$rpn" "$card/gt_boost_freq_mhz"
        ;;
      balanced)
        write_to "$rpn" "$card/gt_min_freq_mhz"
        write_to "$rp0" "$card/gt_max_freq_mhz"
        [[ -e "$card/gt_boost_freq_mhz" ]] && write_to "$rp0" "$card/gt_boost_freq_mhz"
        ;;
      performance|graphical)
        write_to "$rp0" "$card/gt_max_freq_mhz"
        write_to "$rp0" "$card/gt_min_freq_mhz"
        [[ -e "$card/gt_boost_freq_mhz" ]] && write_to "$rp0" "$card/gt_boost_freq_mhz"
        ;;
    esac
  fi

  # xe driver layout: /sys/class/drm/cardN/device/tile*/gt*/freq0/{min,max,rp0,rpn}_freq
  for freq in "$card"/device/tile*/gt*/freq0; do
    [[ -d "$freq" ]] || continue
    rp0=$(read_first "$freq/rp0_freq")
    rpn=$(read_first "$freq/rpn_freq")
    log "  xe freq: $(basename $(dirname $(dirname "$freq")))/$(basename $(dirname "$freq")) hw range: ${rpn:-?}-${rp0:-?} MHz"
    case "$PROFILE" in
      battery)
        write_to "$rpn" "$freq/min_freq"
        write_to "$rpn" "$freq/max_freq"
        ;;
      balanced)
        write_to "$rpn" "$freq/min_freq"
        write_to "$rp0" "$freq/max_freq"
        ;;
      performance|graphical)
        write_to "$rp0" "$freq/max_freq"
        write_to "$rp0" "$freq/min_freq"
        ;;
    esac
  done

  # SR-IOV scheduling (i915 debugfs) — only present when SR-IOV is enabled.
  bdf=$(basename "$(readlink -f "$card/device")")
  for pf_dir in /sys/kernel/debug/dri/$bdf/gt*/pf; do
    [[ -d "$pf_dir" ]] || continue
    case "$PROFILE" in
      battery)     EQ_MS=50;  PT_US=50000 ;;
      balanced)    EQ_MS=20;  PT_US=20000 ;;
      performance) EQ_MS=20;  PT_US=20000 ;;
      graphical)   EQ_MS=8;   PT_US=10000 ;;
    esac
    write_to "$EQ_MS" "$pf_dir/exec_quantum_ms"
    write_to "$PT_US" "$pf_dir/preempt_timeout_us"
  done
done

if [[ $tuned_card -eq 0 ]]; then
  skip "no Intel render card found under /sys/class/drm"
fi

log "done"
