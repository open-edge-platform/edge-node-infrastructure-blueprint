<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Platform Capabilities

Capabilities delivered by this infrastructure blueprint.

## Operating System & Kernel

| Capability | Detail |
|---|---|
| Base OS | Ubuntu 24.04 (`minimal-desktop-ubuntu`) |
| Kernel | Intel mainline-tracking 6.18 (`6.18.23-intel+260427T075939Z-r2`) from Intel Linux overlay |
| Kernel cmdline | `xe.max_vfs=7 xe.force_probe=* modprobe.blacklist=i915 udmabuf.list_limit=8192` |
| Extra modules | `intel_vpu`, `uas` |

## Hardware Drivers

| Capability | Detail |
|---|---|
| iGPU (Xe) | Intel Graphics Compiler v2.28.4, Compute Runtime 26.05.37020.3, Level Zero v1.22.4 |
| iGPU media | `intel-media-va-driver-non-free`, `libvpl2` (oneVPL H.264/HEVC/AV1) |
| NPU | `linux-npu-driver v1.32.0` (compiler, firmware, level-zero NPU) |
| SR-IOV VFs | `xe.max_vfs=7`; auto-provision via `enable_sriov=true` in config-file; persisted across reboot via `intel-sriov-vf.service` |
| USB camera | Intel RealSense SDK (`librealsense2-dkms`, `-utils`, `-dev`, `-gl`) |
| WiFi / Ethernet | Kernel-provided (`iwlwifi`, `igc`); NetworkManager via netplan |
| AMT / vPro | `rpc-go`, `lms`, `metee` |

## AI & Media Stack

| Capability | Detail |
|---|---|
| OpenVINO | 2025.x runtime & toolkit via `apt.repos.intel.com/openvino/2025` |
| oneDNN | `intel-oneapi-dnnl` + `-devel` |
| Level Zero | Runtime + development headers (GPU + NPU) |
| GStreamer | Full plugin set (base, good, bad, ugly, OpenCV, RTSP, Qt5) |
| CDI (Container Device Interface) | GPU spec generator (Go, built from source); NPU generator script |

## Workload Management

| Capability | Detail |
|---|---|
| Container runtime | Docker CE + containerd + Buildx + Compose plugin (host_type=container) |
| Kubernetes | K3s single-node server (host_type=kubernetes); traefik disabled |
| Helm | v3.17.2 |
| Intel Device Plugins | NFD, GPU plugin, NPU plugin (manifests + operator) |
| SR-IOV accelerated containers | VF provisioning + CDI specs for GPU passthrough to containers |
| NPU accelerated containers | CDI NPU generator + Intel NPU device plugin |

## Performance & Profiling Tools

| Capability | Detail |
|---|---|
| CPU profiling | `linux-perf`, `linux-cpupower`, `msr-tools`, `pcm`, `rtla` |
| GPU monitoring | `intel-gpu-tools` (`intel_gpu_top`) |
| Power | `powertop`, `pcm`; tuning scripts (`battery`, `balanced`, `performance`, `graphical` profiles) |
| Benchmarking | `sysbench`, `stress-ng`, `fio`, `glmark2` |
| Network | `iperf3`, `linuxptp`, `tcpdump` |

## Time Synchronization

| Capability | Detail |
|---|---|
| NTP | `chrony` installed; configurable via `/etc/chrony/chrony.conf` |
| PTP | `linuxptp` available for precision time protocol |

## Deployment Options

| Capability | Detail |
|---|---|
| Installable USB image | HookOS-based installer writes image to target storage; fully automated via `config-file` |
| ICT image build | Image Composer Tool produces `.raw.gz` from YAML template |
| Curated image build | `auto-install-pkgs.yaml` Ubuntu autoinstall flow |
| USB artifact packaging | `build-installation-artifacts.sh` → `usb-installation-files.tar.gz` |

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
