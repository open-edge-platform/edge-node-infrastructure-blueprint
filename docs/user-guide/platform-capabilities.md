<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Infrastructure Blueprint Capabilities

## Collecting a Platform Report with system-info.sh

`system-info.sh` is a diagnostic script for Intel Panther Lake (PTL) systems provisioned using Infrastructure Blueprint. After provisioning, the script is available on the target system at `/opt/edge/developer/tools/system-info/`.

### Summary of Tools

- Common tools: `bash`, `lscpu`, `lsblk`, `ip`, etc.
- Optional tools for a more complete report: `dmidecode`, `turbostat`, `intel_gpu_top`, `vulkaninfo`, `vainfo`, `clinfo`, `fwupdmgr`
- `sudo` recommended for full visibility (firmware, DMI, turbostat, dmesg)

### Running the script

```bash
cd /opt/edge/developer/tools/system-info
sudo ./system-info.sh
```

Save output to a file:

```bash
sudo ./system-info.sh > sys-info.txt 2>&1
```

> **Note:** If PTL is not detected (CPUID mismatch), the script still runs and reports what it finds. Some sections show "not installed" warnings when optional tools are missing.

## Output Sections Reference

The script produces the following sections. Use this table to navigate the output.

| Section | What it covers |
|---|---|
| **SYSTEM INFO** | Script version, hostname, kernel, OS, uptime, `hostnamectl` output |
| **PANTHER LAKE PLATFORM CHECK** | CPUID validation (family/model/stepping), microcode, Secure Boot state, PTL-relevant firmware blobs (`xe`, `huc`, `gsc`, `vpu_50xx`) |
| **CPU INFO** | `lscpu` full output, hybrid P/E/LP-E core topology and capacities, per-CPU frequency table, `intel_pstate` governor/HWP settings, cache hierarchy (L1/L2/L3), ISA flags (AVX, AVX-VNNI, AES, SHA, etc.), hardware vulnerability mitigations, live CPU usage, top 5 CPU-consuming processes, `turbostat` summary |
| **MEMORY INFO** | `free -h`, key `/proc/meminfo` fields (hugepages, swap, slabs), DIMM details from `dmidecode` (type, speed, manufacturer, part number), NUMA topology |
| **STORAGE INFO** | `lsblk` block device tree with filesystem and mount points, `df -h` disk usage, NVMe device info (`nvme-cli`), SMART data |
| **NETWORK INFO** | Interface list with IP addresses, default routes, wireless info (`iw`), PCI network device drivers |
| **INTEL GPU INFO** | PCI VGA devices, `/sys/class/drm` device details (vendor/device/revision, GT0/GT1 frequencies), `xe` kernel module info, `intel_gpu_top` utilisation sample, OpenGL/Mesa renderer, Vulkan info, VA-API profiles and entrypoints (`vainfo`) |
| **INTEL NPU INFO** | PCI accelerator device (`8086:b03e`), `/sys/class/accel` details, `intel_vpu` driver version and firmware version, NPU firmware blobs, relevant `dmesg` messages |
| **INTEL COMPUTE / AI RUNTIMES** | OpenCL platform/device details (`clinfo`) — EUs, device IP, USM capabilities; Level Zero library inventory; OpenVINO version and available device list (`CPU`, `GPU.0`–`GPU.7`, `NPU`); oneAPI/DPC++ runtime library paths |
| **INTEL USERSPACE PACKAGES (dpkg)** | Installed Intel packages grouped by: CPU/platform/monitoring, GPU/media/display, NPU/AI/OpenVINO/oneAPI, kernel + firmware |
| **THERMALS, POWER, FANS** | `lm-sensors` output, thermal zone temperatures, cooling device states, RAPL powercap zones (long-term/short-term power limits), battery/power supply state |
| **FIRMWARE / BIOS / SECURITY** | SMBIOS CPU and board details (`dmidecode`), UEFI boot confirmation, TPM state, `fwupd` firmware versions for CPU microcode, display controller, NVMe SSD, system firmware, BootGuard |
| **PCI / USB DEVICE SUMMARY** | Full Intel PCI device list (BDF, class, device ID), all PCI devices, USB bus/device topology |
| **DMESG: LAST 30 INTEL-RELATED LINES** | Filtered dmesg lines for `xe`, `intel_vpu`, and related Intel driver messages |
| **RECOMMENDED PACKAGES FOR INTEL PTL** | `apt install` commands grouped by: kernel/firmware, core diagnostics, GPU/media, OpenCL/Level Zero, NPU/OpenVINO, useful extras |


## Provisioned System Profile

The following tables describe what is expected to be present on a system that has been provisioned using the Infrastructure Blueprint. They cover the four key layers of a provisioned edge node: the underlying platform components, the AI and compute environment, the system services, and the orchestration stack.

### Platform Components

| Component | Detail |
|---|---|
| Platform | Intel Panther Lake Client Platform |
| ISA extensions | SSE4.2, AVX, AVX2, AVX-VNNI, AES-NI, SHA-NI, VAES, VPCLMULQDQ, GFNI, MOVDIRI, MOVDIR64B (no AVX-512 / AMX) |
| CPU governor | `intel_pstate` / `powersave`; HWP active, turbo enabled; |
| OS | Ubuntu 24.04.4 LTS (`minimal-desktop-ubuntu`) |
| Kernel | `linux-image-6.18-intel 260427T075939Z-r2`; cmdline: `xe.max_vfs=7 xe.force_probe=* modprobe.blacklist=i915 udmabuf.list_limit=8192` |
| iGPU | `xe` driver 1.1.0; device `8086:b08f`; 8 PFs, 7 SR-IOV VFs; persisted via `intel-sriov-vf.service` |
| iGPU firmware | `ptl_guc_70.bin.zst`, `ptl_huc.bin.zst`, `ptl_gsc_1.bin.zst` |
| NPU (NPU 5) | `intel_vpu` 1.0.0 (in-kernel); firmware `vpu_50xx_v1.bin` (Mar 2026); `intel-level-zero-npu 1.32.0` |
| Ethernet | Intel I226-V (`8086:57b4`); `igc` driver; managed via netplan/NetworkManager |
| Firmware | `PTLPFWI1.R00.3393.D60.2511181224` (2025-11-18); Secure Boot disabled (Setup Mode) |

### AI & Compute Environment

| Component | Detail |
|---|---|
| OpenVINO | `2025.4.1-20426` runtime & toolkit; inference targets: `CPU`, `GPU.0`–`GPU.7`, `NPU` (Intel AI Boost) |
| OpenCL | OpenCL 3.0 via `intel-opencl-icd 26.05.37020.3`; device IP `0x7800004` (Xe3); DP4A + DPAS; USM supported |
| Level Zero | `level-zero 1.22.4` + `level-zero-devel`; `libze_intel_gpu` + `libze_intel_npu` loaded |
| oneDNN | `intel-oneapi-dnnl 2026.0.0-688` + `-devel` |
| oneAPI TBB | `intel-oneapi-tbb 2023.0.0-724` |
| VA-API / media | iHD driver `25.4.6`; `intel-media-va-driver-non-free`; `libvpl2 2.16.0` (oneVPL); decode: H.264, HEVC, VP9, AV1, VVC, MPEG-2, JPEG; encode: H.264, HEVC, VP9, AV1, JPEG |
| GStreamer | Full plugin set (base, good, bad, ugly, OpenCV, RTSP, Qt5) |
| Mesa | `mesa-vulkan-drivers 25.3.4`, `mesa-va-drivers 25.2.8` |
| CDI | GPU spec generator (Go, built from source) at `/opt/edge/scripts/cdi/`; NPU CDI generator script |
| Developer tools | `edge-node-infrastructure-blueprint` repo at `/opt/edge/developer/`; `system-info.sh` at `/opt/edge/developer/tools/system-info/` |

### Services

| Service | Detail |
|---|---|
| NTP | `chrony` installed and enabled; configurable via `/etc/chrony/chrony.conf` |
| PTP | `linuxptp` available for precision time protocol |
| Container runtime | Docker CE + containerd + Buildx + Compose plugin (active when `host_type=container`) |
| Kubernetes | K3s single-node server (active when `host_type=kubernetes`); traefik disabled |
| SR-IOV | `intel-sriov-vf.service` — provisions and persists 7 GPU VFs across reboots |
| CPU power profiling | `linux-cpupower 6.18.23-intel`, `powertop 2.15`; power tuning scripts (`battery`, `balanced`, `performance`, `graphical` profiles) |
| GPU monitoring | `intel-gpu-tools 1.28` (`intel_gpu_top`) |
| Network diagnostics | `iperf3`, `linuxptp`, `tcpdump` |

### Orchestration

| Component | Detail |
|---|---|
| Host type dispatch | `kubernetes`: K3s + Helm + device plugins; `container`: Docker + containerd |
| Helm | v3.x — deployed via `get-helm-3` during provisioning |
| Intel Device Plugins | Node Feature Discovery (NFD), GPU plugin, NPU plugin — deployed as Helm charts |
| SR-IOV accelerated containers | VF provisioning + CDI GPU specs → passthrough to containers via device plugin |
| NPU accelerated containers | CDI NPU generator + Intel NPU device plugin for workload scheduling to NPU |
| Provisioning scripts | `/opt/edge/scripts/` — `kubernetes-provision.sh`, `container-provision.sh`, `setup-kernel-depended-pkgs.sh` |
