#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
# =============================================================================
# Intel Panther Lake (PTL) System Info Script for Ubuntu
# -----------------------------------------------------------------------------
# Collects CPU / GPU (Xe3) / NPU 5 / driver / firmware / userspace package /
# frequency / P-E-LPE core / power / thermal / memory / storage / network /
# compute runtime info on Intel PTL platforms.
#
# Usage:
#   sudo ./system-info.sh           # for firmware/dmidecode/turbostat
#   sudo ./system-info.sh > sys-info.txt # save to file
# =============================================================================

#set -u

WIDTH=80
SCRIPT_VERSION="1.0-ptl"

# ----------------------------- helpers ---------------------------------------

section() {
  echo
  printf '%*s\n' "$WIDTH" '' | tr ' ' '='
  echo "$1"
  printf '%*s\n' "$WIDTH" '' | tr ' ' '='
}

subsection() {
  echo
  echo "--- $1 ---"
}

have() { command -v "$1" >/dev/null 2>&1; }

read_sysfs() {
  local label="$1" path="$2"
  [[ -r "$path" ]] && echo "$label: $(cat "$path" 2>/dev/null)"
}

human_freq_khz() {
  local khz="${1:-0}"
  if [[ -z "$khz" || "$khz" == "0" ]]; then
    echo "unknown"
  else
    awk -v k="$khz" 'BEGIN { printf "%.2f GHz", k / 1000000 }'
  fi
}

human_bytes() {
  local b="${1:-0}"
  awk -v b="$b" 'BEGIN {
    split("B KB MB GB TB PB", u);
    i=1; while (b >= 1024 && i < 6) { b/=1024; i++ }
    printf "%.2f %s", b, u[i]
  }'
}

installed_pkgs_matching() {
  local pattern="$1"
  dpkg-query -W -f='${Package} ${Version}\n' 2>/dev/null \
    | grep -Ei "$pattern" || echo "  (none installed)"
}

is_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]]; }

# =============================================================================
section "INTEL PANTHER LAKE (PTL) SYSTEM INFO  -  v${SCRIPT_VERSION}"
# =============================================================================

echo "Generated     : $(date -Is)"
echo "Hostname      : $(hostname 2>/dev/null)"
echo "User          : $(id -un) (uid=$(id -u))"
echo "Root privs    : $(is_root && echo yes || echo no)"
echo "Kernel        : $(uname -r)"
echo "Architecture  : $(uname -m)"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "OS            : ${PRETTY_NAME:-unknown}"
fi

have uptime && echo "Uptime        : $(uptime -p 2>/dev/null)"
have hostnamectl && { subsection "hostnamectl"; hostnamectl 2>/dev/null || true; }

# =============================================================================
section "PANTHER LAKE PLATFORM CHECK"
# =============================================================================

vendor="$(grep -m1 'vendor_id' /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}')"
cpu_model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}')"
cpu_family="$(grep -m1 'cpu family' /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}')"
cpu_model_id="$(grep -m1 '^model' /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}')"
cpu_stepping="$(grep -m1 'stepping' /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}')"
cpu_microcode="$(grep -m1 'microcode' /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}')"

echo "Vendor        : ${vendor:-unknown}"
echo "Model name    : ${cpu_model:-unknown}"
echo "Family        : ${cpu_family:-unknown}"
echo "Model (dec)   : ${cpu_model_id:-unknown}"
echo "Stepping      : ${cpu_stepping:-unknown}"
echo "Microcode     : ${cpu_microcode:-unknown}"

if [[ "$vendor" != "GenuineIntel" ]]; then
  echo "WARNING: CPU vendor is not GenuineIntel. This script targets Intel PTL."
fi

# PTL client CPUID: family 6, model 0xCC (204).
if [[ "$cpu_family" == "6" && "$cpu_model_id" == "204" ]]; then
  echo "Platform      : Detected Intel Panther Lake (PTL) [family 6, model 0xCC]"
else
  echo "Platform      : CPUID does not match expected PTL (6/0xCC = 204)."
  echo "                Could be pre-production sample, ES, or non-PTL part."
fi

# Kernel version check.
kver_raw="$(uname -r)"
kmaj="$(echo "$kver_raw" | awk -F. '{print $1}')"
kmin="$(echo "$kver_raw" | awk -F. '{print $2}')"
if (( kmaj < 6 )) || { (( kmaj == 6 )) && (( kmin < 13 )); }; then
  echo "Kernel check  : WARNING - $kver_raw < 6.13. PTL enablement (Xe3, NPU 5,"
  echo "                hybrid topology) may be incomplete. Recommend 6.15+."
else
  echo "Kernel check  : OK for PTL ($kver_raw >= 6.13)"
fi

# linux-firmware version.
if dpkg-query -W -f='${Version}\n' linux-firmware >/dev/null 2>&1; then
  echo "linux-firmware: $(dpkg-query -W -f='${Version}\n' linux-firmware)"
else
  echo "linux-firmware: package not detected via dpkg"
fi

# Secure Boot status (affects driver/firmware loading).
if have mokutil; then
  echo "Secure Boot   : $(mokutil --sb-state 2>/dev/null | tr '\n' ' ')"
fi

subsection "PTL-relevant firmware blobs in /lib/firmware"
found_any=false
for pat in 'xe/*ptl*' 'xe/ptl*' 'i915/*ptl*' 'intel/vpu/*' 'intel/ivpu/*'; do
  matches=$(ls /lib/firmware/$pat 2>/dev/null)
  if [[ -n "$matches" ]]; then
    echo "$matches" | sed 's/^/  /'
    found_any=true
  fi
done
$found_any || echo "  (no PTL-specific firmware blobs found)"

# =============================================================================
section "CPU INFO"
# =============================================================================

subsection "lscpu"
have lscpu && lscpu || echo "lscpu not found (install util-linux)"

subsection "CPU Core Counts"
logical_cpus="$(nproc --all 2>/dev/null || grep -c '^processor' /proc/cpuinfo)"
physical_cores="$(lscpu 2>/dev/null | awk -F: '
  /^Core\(s\) per socket:/ {gsub(/ /,"",$2); c=$2}
  /^Socket\(s\):/         {gsub(/ /,"",$2); s=$2}
  END {if (c && s) print c*s}')"
threads_per_core="$(lscpu 2>/dev/null | awk -F: '/^Thread\(s\) per core:/ {gsub(/ /,"",$2); print $2}')"
sockets="$(lscpu 2>/dev/null | awk -F: '/^Socket\(s\):/ {gsub(/ /,"",$2); print $2}')"
numa_nodes="$(lscpu 2>/dev/null | awk -F: '/^NUMA node\(s\):/ {gsub(/ /,"",$2); print $2}')"

echo "Logical CPUs      : $logical_cpus"
echo "Physical cores    : ${physical_cores:-unknown}"
echo "Threads per core  : ${threads_per_core:-unknown}"
echo "Sockets           : ${sockets:-unknown}"
echo "NUMA nodes        : ${numa_nodes:-unknown}"

subsection "Intel Hybrid P / E / LP-E Core Detection (PTL: Cougar Cove + Darkmont + LP-E)"

declare -A pcores=()
declare -A ecores=()
declare -A lpecores=()
declare -A unknown_cores=()
has_core_type=false

for cpu_path in /sys/devices/system/cpu/cpu[0-9]*; do
  [[ -d "$cpu_path" ]] || continue
  pkg="unknown"; core="unknown"
  [[ -r "$cpu_path/topology/physical_package_id" ]] && pkg="$(cat "$cpu_path/topology/physical_package_id")"
  [[ -r "$cpu_path/topology/core_id" ]] && core="$(cat "$cpu_path/topology/core_id")"
  key="${pkg}:${core}"

  if [[ -r "$cpu_path/topology/core_type" ]]; then
    has_core_type=true
    ct="$(cat "$cpu_path/topology/core_type")"
    case "$ct" in
      10|core|Core|p|P|performance|Performance) pcores["$key"]=1 ;;
      40|atom|Atom|e|E|efficiency|Efficiency)   ecores["$key"]=1 ;;
      20|lpe|LPE|low_power|LowPower)            lpecores["$key"]=1 ;;
      *)                                        unknown_cores["$key"]=1 ;;
    esac
  fi
done

if $has_core_type; then
  echo "P-cores       : ${#pcores[@]}"
  echo "E-cores       : ${#ecores[@]}"
  echo "LP-E cores    : ${#lpecores[@]}"
  echo "Unknown type  : ${#unknown_cores[@]}"
else
  echo "Kernel does not expose topology/core_type. Falling back to heuristics."
  declare -A cap_groups=() freq_groups=()
  for cpu_path in /sys/devices/system/cpu/cpu[0-9]*; do
    cpu="${cpu_path##*/cpu}"
    if [[ -r "$cpu_path/cpu_capacity" ]]; then
      cap="$(cat "$cpu_path/cpu_capacity")"; cap_groups["$cap"]+="$cpu "
    elif [[ -r "$cpu_path/cpufreq/cpuinfo_max_freq" ]]; then
      f="$(cat "$cpu_path/cpufreq/cpuinfo_max_freq")"; freq_groups["$f"]+="$cpu "
    fi
  done
  if (( ${#cap_groups[@]} > 1 )); then
    echo "Capacity groups (highest = P-core):"
    for c in "${!cap_groups[@]}"; do
      echo "  capacity=$c count=$(wc -w <<<"${cap_groups[$c]}") cpus=${cap_groups[$c]}"
    done
  elif (( ${#freq_groups[@]} > 1 )); then
    echo "Max-freq groups (highest = P-core):"
    for f in "${!freq_groups[@]}"; do
      echo "  max_freq=$(human_freq_khz "$f") count=$(wc -w <<<"${freq_groups[$f]}") cpus=${freq_groups[$f]}"
    done
  else
    echo "Could not classify P/E/LP-E cores."
  fi
fi

subsection "CPU Frequency (per-CPU)"
printf "%-6s %-12s %-12s %-12s %-12s %s\n" "CPU" "cur" "min" "max" "hw_max" "governor"
for cpu_path in /sys/devices/system/cpu/cpu[0-9]*; do
  [[ -d "$cpu_path/cpufreq" ]] || continue
  cpu="${cpu_path##*/cpu}"
  cur="$(cat "$cpu_path/cpufreq/scaling_cur_freq" 2>/dev/null)"
  mn="$(cat  "$cpu_path/cpufreq/scaling_min_freq" 2>/dev/null)"
  mx="$(cat  "$cpu_path/cpufreq/scaling_max_freq" 2>/dev/null)"
  hw="$(cat  "$cpu_path/cpufreq/cpuinfo_max_freq" 2>/dev/null)"
  gov="$(cat "$cpu_path/cpufreq/scaling_governor" 2>/dev/null)"
  printf "%-6s %-12s %-12s %-12s %-12s %s\n" \
    "$cpu" "$(human_freq_khz "$cur")" "$(human_freq_khz "$mn")" \
    "$(human_freq_khz "$mx")" "$(human_freq_khz "$hw")" "${gov:-?}"
done

subsection "CPU Driver / Governor / Intel P-State"
read_sysfs "scaling_driver"  /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver
read_sysfs "scaling_governor" /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
read_sysfs "intel_pstate status"      /sys/devices/system/cpu/intel_pstate/status
read_sysfs "intel_pstate no_turbo"    /sys/devices/system/cpu/intel_pstate/no_turbo
read_sysfs "intel_pstate turbo_pct"   /sys/devices/system/cpu/intel_pstate/turbo_pct
read_sysfs "intel_pstate num_pstates" /sys/devices/system/cpu/intel_pstate/num_pstates
read_sysfs "intel_pstate max_perf_pct" /sys/devices/system/cpu/intel_pstate/max_perf_pct
read_sysfs "intel_pstate min_perf_pct" /sys/devices/system/cpu/intel_pstate/min_perf_pct
read_sysfs "hwp_dynamic_boost"        /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost
read_sysfs "energy_perf_bias (cpu0)"  /sys/devices/system/cpu/cpu0/power/energy_perf_bias
read_sysfs "energy_performance_preference (cpu0)" \
  /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference

subsection "CPU Cache"
have lscpu && lscpu -C 2>/dev/null || true
if [[ -d /sys/devices/system/cpu/cpu0/cache ]]; then
  echo
  for idx in /sys/devices/system/cpu/cpu0/cache/index*; do
    [[ -d "$idx" ]] || continue
    lvl="$(cat "$idx/level" 2>/dev/null)"
    typ="$(cat "$idx/type"  2>/dev/null)"
    sz="$(cat  "$idx/size"  2>/dev/null)"
    way="$(cat "$idx/ways_of_associativity" 2>/dev/null)"
    echo "  L${lvl} ${typ}: size=${sz} ways=${way}"
  done
fi

subsection "CPU Flags / ISA Highlights (AVX, AVX2, AVX-VNNI, AMX, SHA, AES, etc.)"
flags="$(grep -m1 '^flags' /proc/cpuinfo | awk -F': ' '{print $2}')"
for f in sse4_2 avx avx2 avx_vnni avx512f amx_bf16 amx_int8 amx_tile aes sha_ni vaes vpclmulqdq rdrand rdseed gfni movdiri movdir64b serialize tdx tsxldtrk hwp hwp_act_window hwp_epp hybrid; do
  echo "$flags" | grep -qw "$f" && echo "  [x] $f" || echo "  [ ] $f"
done

subsection "CPU Vulnerabilities / Mitigations"
if compgen -G "/sys/devices/system/cpu/vulnerabilities/*" >/dev/null; then
  for f in /sys/devices/system/cpu/vulnerabilities/*; do
    echo "$(basename "$f"): $(cat "$f" 2>/dev/null)"
  done
else
  echo "(none reported)"
fi

subsection "CPU Live Usage"
have top && top -bn1 | grep -E 'Cpu\(s\)|%Cpu' || true
if have mpstat; then
  echo; mpstat -P ALL 1 1 2>/dev/null || true
else
  echo "Tip: sudo apt install sysstat (for mpstat per-core stats)"
fi

subsection "Top 5 CPU-consuming processes"
ps -eo pid,user,pcpu,pmem,comm --sort=-pcpu | head -n 6

subsection "Intel turbostat (power/freq summary)"
if have turbostat; then
  if is_root; then
    timeout 5s turbostat --quiet --Summary --show \
      Busy%,Bzy_MHz,TSC_MHz,IRQ,PkgTmp,PkgWatt,CorWatt,GFXWatt,RAMWatt 2>/dev/null \
      || echo "turbostat failed"
  else
    echo "Run with sudo for turbostat data."
  fi
else
  echo "turbostat not found. Install: sudo apt install linux-tools-common linux-tools-generic"
fi

# =============================================================================
section "MEMORY INFO"
# =============================================================================

subsection "free -h"
have free && free -h

subsection "/proc/meminfo (key fields)"
grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|HugePages_Total|Hugepagesize|Dirty|Writeback|Slab|KernelStack):' /proc/meminfo

subsection "DIMM / Memory modules (requires sudo dmidecode)"
if have dmidecode && is_root; then
  dmidecode -t memory 2>/dev/null | grep -E 'Size:|Type:|Speed:|Configured Memory Speed:|Manufacturer:|Part Number:|Locator:|Rank:|Form Factor:' \
    | grep -v 'No Module Installed\|Unknown' || true
else
  echo "Run as root with dmidecode for DIMM details."
fi

subsection "NUMA"
have numactl && numactl --hardware 2>/dev/null || echo "numactl not installed."

# =============================================================================
section "STORAGE INFO"
# =============================================================================

subsection "Block devices"
have lsblk && lsblk -o NAME,MODEL,SIZE,TYPE,ROTA,TRAN,MOUNTPOINT,FSTYPE 2>/dev/null

subsection "Disk usage"
have df && df -hT --exclude-type=tmpfs --exclude-type=devtmpfs --exclude-type=squashfs

subsection "NVMe devices"
if have nvme; then
  nvme list 2>/dev/null || echo "(no NVMe or insufficient perms)"
else
  echo "nvme-cli not installed (sudo apt install nvme-cli)"
fi

subsection "SMART (first disk, requires sudo)"
if have smartctl && is_root; then
  first_disk="$(lsblk -dno NAME,TYPE | awk '$2=="disk"{print "/dev/"$1; exit}')"
  [[ -n "$first_disk" ]] && smartctl -i "$first_disk" 2>/dev/null | head -25
else
  echo "smartctl not available or not root (sudo apt install smartmontools)"
fi

# =============================================================================
section "NETWORK INFO"
# =============================================================================

subsection "Interfaces"
have ip && ip -brief addr 2>/dev/null

subsection "Default route"
have ip && ip route show default 2>/dev/null

subsection "Wireless (iw)"
have iw && iw dev 2>/dev/null | grep -E 'Interface|ssid|type|channel|txpower' || echo "iw not installed."

subsection "Network drivers (PCI net devices)"
if have lspci; then
  lspci -nnk | grep -EA2 'Ethernet|Network controller|Wireless' || true
fi

# =============================================================================
section "INTEL GPU INFO (Xe3 'Celestial' on PTL)"
# =============================================================================

subsection "Intel PCI GPU Devices"
if have lspci; then
  lspci -nnk | grep -EA5 -i 'VGA|3D|Display|Intel.*Graphics|Arc|Iris|UHD|Xe' \
    || echo "No Intel GPU found via lspci."
fi

subsection "Intel DRM Devices (/sys/class/drm)"
if compgen -G "/sys/class/drm/card*" >/dev/null; then
  for card in /sys/class/drm/card*; do
    [[ -d "$card" ]] || continue
    vendor="$(cat "$card/device/vendor" 2>/dev/null)"
    [[ "$vendor" == "0x8086" ]] || continue
    echo
    echo "Device: $(basename "$card")"
    read_sysfs "  vendor"           "$card/device/vendor"
    read_sysfs "  device"           "$card/device/device"
    read_sysfs "  subsystem_vendor" "$card/device/subsystem_vendor"
    read_sysfs "  subsystem_device" "$card/device/subsystem_device"
    read_sysfs "  revision"         "$card/device/revision"
    [[ -L "$card/device/driver" ]] && echo "  kernel driver: $(basename "$(readlink "$card/device/driver")")"
    [[ -r "$card/device/driver/module/version" ]] && \
      echo "  driver module version: $(cat "$card/device/driver/module/version")"
    # Xe driver exposes GT and frequency info.
    for gt in "$card"/device/tile*/gt* "$card"/gt/gt*; do
      [[ -d "$gt" ]] || continue
      echo "  GT: $gt"
      read_sysfs "    cur_freq" "$gt/freq0/cur_freq"
      read_sysfs "    min_freq" "$gt/freq0/min_freq"
      read_sysfs "    max_freq" "$gt/freq0/max_freq"
      read_sysfs "    rp0_freq" "$gt/freq0/rp0_freq"
    done
  done
else
  echo "No DRM card devices."
fi

subsection "PTL GPU Driver Check (Xe3 expects 'xe' driver)"
if lsmod | awk '{print $1}' | grep -qx xe; then
  echo "OK: 'xe' kernel driver loaded (correct for PTL Xe3)."
elif lsmod | awk '{print $1}' | grep -qx i915; then
  echo "WARNING: 'i915' loaded. PTL Xe3 prefers the 'xe' driver."
  echo "         Ensure CONFIG_DRM_XE is enabled and 'xe' binds to your GPU PCI ID."
else
  echo "WARNING: Neither 'xe' nor 'i915' loaded."
fi

subsection "Intel GPU Kernel Modules"
lsmod | grep -Ei '^(xe|i915|drm|drm_buddy|ttm|drm_kms_helper)' || echo "(none)"
for mod in xe i915; do
  if lsmod | awk '{print $1}' | grep -qx "$mod"; then
    echo
    echo "Module: $mod"
    modinfo "$mod" 2>/dev/null | grep -Ei '^(filename|version|license|description|srcversion|vermagic|depends):'
  fi
done

subsection "Intel GPU Runtime Utilization (intel_gpu_top)"
if have intel_gpu_top; then
  echo "Sampling intel_gpu_top for 3 seconds..."
  if is_root; then
    timeout 3s intel_gpu_top -l 3 2>/dev/null || echo "intel_gpu_top failed."
  else
    timeout 3s intel_gpu_top -l 3 2>/dev/null || \
      echo "intel_gpu_top failed. Try: sudo intel_gpu_top"
  fi
else
  echo "intel_gpu_top not installed: sudo apt install intel-gpu-tools"
fi

subsection "OpenGL (Mesa) Renderer"
if have glxinfo; then
  glxinfo -B 2>/dev/null | grep -Ei 'OpenGL vendor|OpenGL renderer|OpenGL version|Device|Mesa'
else
  echo "Install: sudo apt install mesa-utils"
fi

subsection "Vulkan"
if have vulkaninfo; then
  vulkaninfo --summary 2>/dev/null | grep -Ei 'GPU|deviceName|driver|apiVersion|Intel|Mesa|ANV' \
    || vulkaninfo --summary 2>/dev/null | head -60
else
  echo "Install: sudo apt install vulkan-tools"
fi

subsection "VA-API / Media driver"
if have vainfo; then
  vainfo 2>/dev/null | grep -Ei 'Driver version|VAProfile|vainfo|Intel|iHD|i965' | head -80
else
  echo "Install: sudo apt install vainfo"
fi

# =============================================================================
section "INTEL NPU INFO (NPU 5 on PTL)"
# =============================================================================

subsection "Intel NPU PCI Devices"
if have lspci; then
  lspci -nnk | grep -EA6 -i 'Intel.*NPU|AI Boost|Neural|Processing accelerators|Vision Processing|VPU|NPU|IVPU' \
    || echo "No Intel NPU device found via lspci."
fi

subsection "Linux /sys/class/accel devices"
if compgen -G "/sys/class/accel/accel*" >/dev/null; then
  for accel in /sys/class/accel/accel*; do
    [[ -d "$accel" ]] || continue
    vendor="$(cat "$accel/device/vendor" 2>/dev/null)"
    echo
    echo "Accelerator: $(basename "$accel")"
    read_sysfs "  vendor"           "$accel/device/vendor"
    read_sysfs "  device"           "$accel/device/device"
    read_sysfs "  subsystem_vendor" "$accel/device/subsystem_vendor"
    read_sysfs "  subsystem_device" "$accel/device/subsystem_device"
    read_sysfs "  numa_node"        "$accel/device/numa_node"
    [[ -L "$accel/device/driver" ]] && echo "  kernel driver: $(basename "$(readlink "$accel/device/driver")")"
    [[ -r "$accel/device/driver/module/version" ]] && \
      echo "  driver module version: $(cat "$accel/device/driver/module/version")"
  done
else
  echo "No /sys/class/accel devices."
fi

subsection "PTL NPU 5 Driver Check (ivpu / intel_vpu)"
npu_loaded=false
for m in intel_vpu ivpu; do
  if lsmod | awk '{print $1}' | grep -qx "$m"; then
    npu_loaded=true
    echo "OK: '$m' loaded."
    modinfo "$m" 2>/dev/null | grep -Ei '^(filename|version|srcversion|vermagic):'
  fi
done
$npu_loaded || echo "WARNING: No NPU kernel driver loaded. PTL NPU 5 needs ivpu/intel_vpu."

subsection "NPU Firmware Blobs"
for d in /lib/firmware/intel/vpu /lib/firmware/intel/ivpu; do
  if [[ -d "$d" ]]; then
    ls -1 "$d" 2>/dev/null | sed "s|^|  ${d}/|"
  fi
done

subsection "NPU dmesg messages"
if is_root || dmesg >/dev/null 2>&1; then
  dmesg 2>/dev/null | grep -Ei 'ivpu|intel_vpu|npu|vpu' | tail -20 \
    || echo "(no NPU dmesg lines)"
else
  echo "Run as root to read dmesg."
fi

echo
echo "NOTE: NPU utilization metrics are vendor-specific. Use OpenVINO benchmark_app"
echo "      with -d NPU, or 'intel_npu_top'/'npu-smi' if shipped with your driver."

# =============================================================================
section "INTEL COMPUTE / AI RUNTIMES"
# =============================================================================

subsection "OpenCL (clinfo)"
if have clinfo; then
  clinfo 2>/dev/null | grep -Ei 'Platform Name|Platform Version|Platform Vendor|Device Name|Device Type|Driver Version|Device Version|Max compute units|Global memory size|Intel' \
    || clinfo -l 2>/dev/null
else
  echo "Install: sudo apt install clinfo intel-opencl-icd"
fi

subsection "Level Zero"
have sycl-ls && { echo "SYCL devices:"; sycl-ls 2>/dev/null; } || echo "sycl-ls not found."
have ze_info && { echo; echo "ze_info:"; ze_info 2>/dev/null | head -80; } || echo "ze_info not found."
ldconfig -p 2>/dev/null | grep -E 'libze_loader|libze_intel' | head -5 || true

subsection "OpenVINO"
have benchmark_app && echo "benchmark_app: $(command -v benchmark_app)"
python3 - <<'PY' 2>/dev/null || true
try:
    import openvino as ov
    print("Python OpenVINO version:", ov.__version__)
    core = ov.Core()
    print("OpenVINO available devices:", core.available_devices)
    for d in core.available_devices:
        try:
            print(f"  [{d}] FULL_DEVICE_NAME: {core.get_property(d, 'FULL_DEVICE_NAME')}")
        except Exception:
            pass
except Exception:
    print("Python OpenVINO not installed (pip install openvino).")
PY

subsection "oneAPI / DPC++ runtime libs"
ldconfig -p 2>/dev/null | grep -Ei 'libsycl|libmkl|libtbb|libdnnl|libonnxruntime' | head -10 || true

# =============================================================================
section "INTEL USERSPACE PACKAGES (dpkg)"
# =============================================================================

subsection "CPU / platform / monitoring"
installed_pkgs_matching '^(intel-microcode|linux-tools|linux-tools-common|linux-tools-generic|cpufrequtils|linux-cpupower|sysstat|lm-sensors|powertop|tuned|thermald|i7z)'

subsection "GPU / media / display"
installed_pkgs_matching '^(intel-gpu-tools|intel-media|intel-opencl|intel-level-zero|level-zero|libze|libmfx|libvpl|libva|i965|mesa|vulkan|intel-vulkan|va-driver|onevpl|vpl|xserver-xorg-video-intel)'

subsection "NPU / AI / OpenVINO / oneAPI"
installed_pkgs_matching '(openvino|intel-npu|intel-vpu|ivpu|level-zero|libze|oneapi|dpcpp|icx|tbb|mkl|onnxruntime|tensorflow|torch|pytorch)'

subsection "Kernel + firmware"
installed_pkgs_matching '^(linux-image|linux-headers|linux-firmware|linux-modules)'

# =============================================================================
section "THERMALS, POWER, FANS"
# =============================================================================

subsection "lm-sensors"
have sensors && sensors || echo "Install: sudo apt install lm-sensors && sudo sensors-detect"

subsection "Thermal zones"
for z in /sys/class/thermal/thermal_zone*; do
  [[ -d "$z" ]] || continue
  t="$(cat "$z/temp" 2>/dev/null)"
  typ="$(cat "$z/type" 2>/dev/null)"
  [[ -n "$t" ]] && printf "  %-20s %s = %.1f C\n" "$typ" "$(basename "$z")" "$(awk -v x="$t" 'BEGIN{print x/1000}')"
done

subsection "Cooling devices"
for c in /sys/class/thermal/cooling_device*; do
  [[ -d "$c" ]] || continue
  echo "  $(basename "$c"): type=$(cat "$c/type" 2>/dev/null) cur=$(cat "$c/cur_state" 2>/dev/null)/$(cat "$c/max_state" 2>/dev/null)"
done

subsection "Intel RAPL powercap"
if compgen -G "/sys/class/powercap/intel-rapl:*" >/dev/null; then
  for rapl in /sys/class/powercap/intel-rapl:*; do
    [[ -d "$rapl" ]] || continue
    echo
    echo "RAPL zone: $(basename "$rapl")"
    read_sysfs "  name"                          "$rapl/name"
    read_sysfs "  energy_uj"                     "$rapl/energy_uj"
    read_sysfs "  max_energy_range_uj"           "$rapl/max_energy_range_uj"
    read_sysfs "  constraint_0_name"             "$rapl/constraint_0_name"
    read_sysfs "  constraint_0_power_limit_uw"   "$rapl/constraint_0_power_limit_uw"
    read_sysfs "  constraint_0_time_window_us"   "$rapl/constraint_0_time_window_us"
    read_sysfs "  constraint_1_name"             "$rapl/constraint_1_name"
    read_sysfs "  constraint_1_power_limit_uw"   "$rapl/constraint_1_power_limit_uw"
  done
else
  echo "No Intel RAPL data."
fi

subsection "Battery / power supply"
if compgen -G "/sys/class/power_supply/*" >/dev/null; then
  for ps in /sys/class/power_supply/*; do
    [[ -d "$ps" ]] || continue
    echo
    echo "$(basename "$ps"):"
    for f in type status capacity energy_now energy_full power_now voltage_now current_now manufacturer model_name technology cycle_count; do
      [[ -r "$ps/$f" ]] && echo "  $f: $(cat "$ps/$f")"
    done
  done
else
  echo "No power supply info."
fi

# =============================================================================
section "FIRMWARE / BIOS / SECURITY"
# =============================================================================

if have dmidecode; then
  if is_root; then
    dmidecode -t bios -t system -t baseboard -t processor 2>/dev/null \
      | grep -Ei 'Manufacturer|Product Name|Version|Release Date|Serial|Family|Core Count|Thread Count|Max Speed|Current Speed|ID:|UUID' || true
  else
    echo "Run with sudo for dmidecode (BIOS, baseboard, processor)."
  fi
else
  echo "Install: sudo apt install dmidecode"
fi

subsection "EFI / Boot"
[[ -d /sys/firmware/efi ]] && echo "Booted via UEFI" || echo "Booted via BIOS/Legacy"
have bootctl && bootctl status 2>/dev/null | head -20 || true

subsection "TPM"
if [[ -e /dev/tpm0 || -e /dev/tpmrm0 ]]; then
  echo "TPM device present: $(ls /dev/tpm* 2>/dev/null | tr '\n' ' ')"
  have tpm2_getcap && tpm2_getcap properties-fixed 2>/dev/null | head -20
else
  echo "No TPM device exposed."
fi

subsection "fwupd firmware versions"
if have fwupdmgr; then
  fwupdmgr get-devices 2>/dev/null | head -60 || true
else
  echo "Install: sudo apt install fwupd"
fi

# =============================================================================
section "PCI / USB DEVICE SUMMARY"
# =============================================================================

subsection "Intel PCI devices"
have lspci && lspci -nn | grep -i 'Intel' || true

subsection "All PCI devices"
have lspci && lspci -nn || true

subsection "USB devices"
have lsusb && lsusb || echo "Install: sudo apt install usbutils"

# =============================================================================
section "DMESG: LAST 30 INTEL-RELATED LINES"
# =============================================================================

if dmesg >/dev/null 2>&1; then
  dmesg 2>/dev/null | grep -Ei 'intel|xe |i915|ivpu|vpu|npu|microcode|pstate|rapl|thermal' | tail -30
else
  echo "Cannot read dmesg (try sudo)."
fi

# =============================================================================
section "RECOMMENDED PACKAGES FOR INTEL PTL"
# =============================================================================

cat <<'EOF'
# Kernel + firmware (PTL needs Linux >= 6.13, ideally 6.15+)
sudo apt install -y linux-generic-hwe-24.04 linux-firmware

# Core diagnostics
sudo apt install -y pciutils usbutils util-linux procps sysstat lm-sensors \
  dmidecode linux-tools-common linux-tools-generic intel-microcode \
  thermald powertop nvme-cli smartmontools numactl fwupd mokutil

# GPU (Xe3) + media
sudo apt install -y intel-gpu-tools mesa-utils vulkan-tools vainfo \
  mesa-vulkan-drivers intel-media-va-driver-non-free

# Compute (OpenCL + Level Zero) - use Intel's compute-runtime repo for PTL
sudo apt install -y clinfo intel-opencl-icd intel-level-zero-gpu level-zero libze1

# NPU 5 + OpenVINO
# - Use latest ivpu/intel_vpu kernel driver (in kernel >= 6.15).
# - Install matching userspace from Intel NPU driver release.
# - For inference: pip install --upgrade openvino   (2025.x or newer for PTL)

# Useful extras
sudo apt install -y iw ethtool tpm2-tools i7z
EOF

section "DONE"
echo "Tip: run as root for firmware/turbostat/dmidecode:  sudo $0"
echo "Tip: save full output:  $0 > ptl-info-$(hostname)-$(date +%Y%m%d).txt 2>&1"