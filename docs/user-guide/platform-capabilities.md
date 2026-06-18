<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Infrastructure Blueprint Capabilities

## Collecting a Platform Report with system-info.sh

`system-info.sh` is a diagnostic script for Intel Panther Lake (PTL) systems on Ubuntu/Linux. After provisioning, the script is available on the target system at `/opt/edge/developer/tools/system-info/`.

### Requirements

- Ubuntu/Linux shell environment
- Common tools: `bash`, `lscpu`, `lsblk`, `ip`, etc.
- Optional tools improve report depth: `dmidecode`, `turbostat`, `intel_gpu_top`, `vulkaninfo`, `vainfo`, `clinfo`, `fwupdmgr`
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
| **INTEL PANTHER LAKE (PTL) SYSTEM INFO** | Script version, hostname, kernel, OS, uptime, `hostnamectl` output |
| **PANTHER LAKE PLATFORM CHECK** | CPUID validation (family/model/stepping), microcode, Secure Boot state, PTL-relevant firmware blobs (`xe`, `huc`, `gsc`, `vpu_50xx`) |
| **CPU INFO** | `lscpu` full output, hybrid P/E/LP-E core topology and capacities, per-CPU frequency table, `intel_pstate` governor/HWP settings, cache hierarchy (L1/L2/L3), ISA flags (AVX, AVX-VNNI, AES, SHA, etc.), hardware vulnerability mitigations, live CPU usage, top 5 CPU-consuming processes, `turbostat` summary |
| **MEMORY INFO** | `free -h`, key `/proc/meminfo` fields (hugepages, swap, slabs), DIMM details from `dmidecode` (type, speed, manufacturer, part number), NUMA topology |
| **STORAGE INFO** | `lsblk` block device tree with filesystem and mount points, `df -h` disk usage, NVMe device info (`nvme-cli`), SMART data |
| **NETWORK INFO** | Interface list with IP addresses, default routes, wireless info (`iw`), PCI network device drivers |
| **INTEL GPU INFO (Xe3 'Celestial' on PTL)** | PCI VGA devices, `/sys/class/drm` device details (vendor/device/revision, GT0/GT1 frequencies), `xe` kernel module info, `intel_gpu_top` utilisation sample, OpenGL/Mesa renderer, Vulkan info, VA-API profiles and entrypoints (`vainfo`) |
| **INTEL NPU INFO (NPU 5 on PTL)** | PCI accelerator device (`8086:b03e`), `/sys/class/accel` details, `intel_vpu` driver version and firmware version, NPU firmware blobs, relevant `dmesg` messages |
| **INTEL COMPUTE / AI RUNTIMES** | OpenCL platform/device details (`clinfo`) — EUs, device IP, USM capabilities; Level Zero library inventory; OpenVINO version and available device list (`CPU`, `GPU.0`–`GPU.7`, `NPU`); oneAPI/DPC++ runtime library paths |
| **INTEL USERSPACE PACKAGES (dpkg)** | Installed Intel packages grouped by: CPU/platform/monitoring, GPU/media/display, NPU/AI/OpenVINO/oneAPI, kernel + firmware |
| **THERMALS, POWER, FANS** | `lm-sensors` output, thermal zone temperatures, cooling device states, RAPL powercap zones (long-term/short-term power limits), battery/power supply state |
| **FIRMWARE / BIOS / SECURITY** | SMBIOS CPU and board details (`dmidecode`), UEFI boot confirmation, TPM state, `fwupd` firmware versions for CPU microcode, display controller, NVMe SSD, system firmware, BootGuard |
| **PCI / USB DEVICE SUMMARY** | Full Intel PCI device list (BDF, class, device ID), all PCI devices, USB bus/device topology |
| **DMESG: LAST 30 INTEL-RELATED LINES** | Filtered dmesg lines for `xe`, `intel_vpu`, and related Intel driver messages |
| **RECOMMENDED PACKAGES FOR INTEL PTL** | `apt install` commands grouped by: kernel/firmware, core diagnostics, GPU/media, OpenCL/Level Zero, NPU/OpenVINO, useful extras |



| Field | Detail |
|---|---|
| Platform | Intel Panther Lake Client Platform (`PTL-UH DDR5 T3 RVP4`) |
| CPU | Intel Core Ultra X7 358HR |
| Cores / Threads | 16 cores, 16 threads (1 thread/core) — hybrid: 1×P-core @ 4.8 GHz, 3×P-core @ 4.7 GHz, 8×E-core @ 3.7 GHz, 4×LP-E @ 3.3 GHz |
| Memory | 16 GiB DDR5-6400 (2×8 GiB SK Hynix HMCG66AHBVA315N, dual-channel) |
| Storage | Samsung SSD 980 PRO 500 GB NVMe (PCIe) |
| Firmware | `PTLPFWI1.R00.3393.D60.2511181224` (2025-11-18) |
| Secure Boot | Disabled (Setup Mode) |

## Operating System & Kernel

| Capability | Detail |
|---|---|
| Base OS | Ubuntu 24.04.4 LTS (`minimal-desktop-ubuntu`) |
| Kernel | `linux-image-6.18-intel 260427T075939Z-r2` — Intel mainline-tracking 6.18 from Intel Linux overlay |
| Kernel cmdline | `xe.max_vfs=7 xe.force_probe=* modprobe.blacklist=i915 udmabuf.list_limit=8192` |
| Extra kernel modules | `intel_vpu` (NPU 5), `uas` |
| linux-firmware | `20240318.git3b128b60-0.2.25-1ppa1-noble4` |

## CPU Capabilities

| Capability | Detail |
|---|---|
| ISA extensions | SSE4.2, AVX, AVX2, AVX-VNNI, AES-NI, SHA-NI, VAES, VPCLMULQDQ, GFNI, MOVDIRI, MOVDIR64B |
| Not present | AVX-512, AMX |
| Cache | L1d 576 KiB (16×36 KiB), L1i 1 MiB (16×64 KiB), L2 24 MiB (7×3 MiB), L3 18 MiB shared |
| CPU governor | `intel_pstate` / `powersave` (HWP active, turbo enabled) |
| Power envelope | 25 W long-term / 65 W short-term (RAPL package-0) |
| Microcode | `0x10f` |
| Vulnerabilities | All mitigated or not affected (Spectre v1/v2 mitigated; all others Not affected) |

## Hardware Drivers

| Capability | Detail |
|---|---|
| iGPU (Xe3 "Celestial") | `xe` kernel driver 1.1.0; device `8086:b08f`; 8 PFs exposed (00:02.0–00:02.7) |
| iGPU firmware | `ptl_guc_70.bin.zst`, `ptl_huc.bin.zst`, `ptl_gsc_1.bin.zst` |
| iGPU compute runtime | Intel OpenCL ICD `26.05.37020.3`; 96 EUs (2 slices × 6 sub-slices × 8 EUs × 10 threads) |
| iGPU media | `intel-media-va-driver-non-free 25.4.6`, `libvpl2 2.16.0` (oneVPL), VA-API iHD driver 25.4.6 |
| VA-API codecs | Decode: H.264, HEVC (Main/Main10/SCC/444), VP8, VP9 (all profiles), AV1, VVC, MPEG-2, JPEG; Encode: H.264, HEVC, VP9, AV1, JPEG |
| NPU (NPU 5) | `intel_vpu` 1.0.0 (in-kernel); firmware `vpu_50xx_v1.bin` (Mar 5 2026); `intel-level-zero-npu 1.32.0` |
| SR-IOV VFs | `xe.max_vfs=7` — 7 VFs provisioned at runtime; VF mode confirmed in dmesg; persisted via `intel-sriov-vf.service` |
| Ethernet | Intel I226-V (`8086:57b4`); `igc` driver; managed via netplan/NetworkManager |
| USB camera | Intel RealSense SDK (`librealsense2-dkms`, `-utils`, `-dev`, `-gl`) |
| AMT / vPro | `rpc-go`, `lms`, `metee` (MEI controller `8086:e470` present) |

## AI & Media Stack

| Capability | Detail |
|---|---|
| OpenVINO | `2025.4.1-20426` runtime & toolkit; available devices: `CPU`, `GPU.0`–`GPU.7`, `NPU` (Intel AI Boost) |
| OpenCL | OpenCL 3.0 via `intel-opencl-icd 26.05.37020.3`; device IP `0x7800004` (Xe3); DP4A + DPAS supported |
| Level Zero | `level-zero 1.22.4` + `level-zero-devel`; `libze_intel_gpu` + `libze_intel_npu` loaded |
| oneDNN | `intel-oneapi-dnnl 2026.0.0-688` + `-devel` |
| oneAPI TBB | `intel-oneapi-tbb 2023.0.0-724` |
| GStreamer | Full plugin set (base, good, bad, ugly, OpenCV, RTSP, Qt5) |
| CDI (Container Device Interface) | GPU spec generator (Go, built from source); NPU generator script |
| Mesa | `mesa-vulkan-drivers 25.3.4`, `mesa-va-drivers 25.2.8` |

## Workload Management

| Capability | Detail |
|---|---|
| Container runtime | Docker CE + containerd + Buildx + Compose plugin (`host_type=container`) |
| Kubernetes | K3s single-node server (`host_type=kubernetes`); traefik disabled |
| Helm | v3.x (installed via `get-helm-3`) |
| Intel Device Plugins | NFD, GPU plugin, NPU plugin (manifests + operator) |
| SR-IOV accelerated containers | VF provisioning + CDI specs for GPU passthrough to containers |
| NPU accelerated containers | CDI NPU generator + Intel NPU device plugin |

## Performance & Profiling Tools

| Capability | Detail |
|---|---|
| CPU profiling | `linux-cpupower 6.18.23-intel`, `linux-perf`, `msr-tools`, `pcm`, `rtla` |
| GPU monitoring | `intel-gpu-tools 1.28` (`intel_gpu_top`) |
| Power | `powertop 2.15`; RAPL powercap exposed; tuning scripts (`battery`, `balanced`, `performance`, `graphical` profiles) |
| Benchmarking | `sysbench`, `stress-ng`, `fio`, `glmark2` |
| Network | `iperf3`, `linuxptp`, `tcpdump` |
| System info | `tools/system-info/system-info.sh` — full PTL platform snapshot |

## Time Synchronization

| Capability | Detail |
|---|---|
| NTP | `chrony` installed and enabled; configurable via `/etc/chrony/chrony.conf` |
| PTP | `linuxptp` available for precision time protocol |

## Deployment Options

| Capability | Detail |
|---|---|
| Installable USB image | HookOS-based installer writes image to target storage; fully automated via `config-file` |
| ICT image build | Image Composer Tool produces `.raw.gz` from YAML template |
| Curated image build | `auto-install-pkgs.yaml` Ubuntu autoinstall flow |
| USB artifact packaging | `build-installation-artifacts.sh` → `usb-installation-files.tar.gz` |
| Developer tools | `edge-node-infrastructure-blueprint` cloned to `/opt/edge/developer/` on first provision |

## Host Type Dispatch

| `host_type` | Services enabled | Provisioning script |
|---|---|---|
| `kubernetes` | k3s enabled, docker disabled | `kubernetes-provision.sh` (Helm, NFD, device plugins, SR-IOV) |
| `container` | docker enabled, k3s disabled | `container-provision.sh` |

## Coding Agent Support

| Capability | Detail |
|---|---|
| GitHub Copilot | `.github/copilot-instructions.md` + 5 skills |
| Claude Code | `CLAUDE.md` + `AGENTS.md` context catalog |
| Skills | `create-image`, `create-usb-installation-files`, `validate-platform-config`, `tune-platform-power`, `update-install-packages` |
