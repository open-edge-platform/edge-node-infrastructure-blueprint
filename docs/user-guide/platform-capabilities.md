<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Platform Capabilities

Capabilities delivered by this infrastructure blueprint.

## Operating System and Kernel

| Capability | Detail |
|---|---|
| Base OS | Ubuntu OS version 24.04 (`minimal-desktop-ubuntu`) |
| Kernel | Intel mainline-tracking 6.18 (`6.18.23-intel+260427T075939Z-r2`) from Intel Linux overlay |
| Kernel command line | `xe.max_vfs=7 xe.force_probe=* modprobe.blacklist=i915 udmabuf.list_limit=8192` |
| Extra modules | `intel_vpu`, `uas` |

## Hardware Drivers

| Capability | Detail |
|---|---|
| iGPU (Xe) | Intel® Graphics Compiler version 2.28.4, Compute Runtime version 26.05.37020.3, Level Zero version 1.22.4 |
| iGPU media | `intel-media-va-driver-non-free`, `libvpl2` (oneVPL H.264/HEVC/AV1) |
| NPU | `linux-npu-driver v1.32.0` (compiler, firmware, level-zero NPU) |
| SR-IOV virtual functions (VFs) | `xe.max_vfs=7`; auto-provision via `enable_sriov=true` in config-file; persisted across reboot via `intel-sriov-vf.service` |
| USB camera | Intel® RealSense™ SDK (`librealsense2-dkms`, `-utils`, `-dev`, `-gl`) |
| Wi-Fi or Ethernet connectivity | Kernel-provided (`iwlwifi` or `igc`); NetworkManager via netplan |
| Intel® Active Management Technology (Intel® AMT) and Intel vPro® technology | `rpc-go`, `lms`, `metee` |

## AI and Media Stack

| Capability | Detail |
|---|---|
| OpenVINO™ Runtime and OpenVINO™ toolkit | release 2025.x runtime and toolkit via `apt.repos.intel.com/openvino/2025` |
| oneAPI Deep Neural Network Library (oneDNN) | `intel-oneapi-dnnl` and `-devel` |
| Level Zero | Runtime and development headers (GPU and NPU) |
| GStreamer framework | Full plugin set that comprises base, good, bad, ugly, OpenCV, RTSP, and Qt5 |
| Container Device Interface (CDI) | GPU specification generator written in Go programming language and built from source; NPU generator script |

## Workload Management

| Capability | Detail |
|---|---|
| Container runtime | Docker CE, containerd, Buildx and the Compose plugin (host_type=container) |
| Kubernetes server | Kubernetes single-node server (host_type=kubernetes); traefik disabled |
| Helm tool | version 3.17.2 |
| Intel® device plugins | Node Feature Discovery (NFD), GPU plugin, and NPU plugin (manifests and operator) |
| SR-IOV accelerated containers | VF provisioning and CDI specifications for GPU passthrough to containers |
| NPU accelerated containers | CDI NPU generator and Intel NPU device plugin |

## Performance and Profiling Tools

| Capability | Detail |
|---|---|
| CPU profiling | `linux-perf`, `linux-cpupower`, `msr-tools`, `pcm`, `rtla` |
| GPU monitoring | `intel-gpu-tools` (`intel_gpu_top`) |
| Power monitoring and tuning | `powertop`, `pcm`; tuning scripts (`battery`, `balanced`, `performance`, `graphical` profiles) |
| Benchmarking | `sysbench`, `stress-ng`, `fio`, `glmark2` |
| Network performance and profiling | `iperf3`, `linuxptp`, `tcpdump` |

## Time Synchronization

| Capability | Detail |
|---|---|
| Network Time Protocol (NTP) | `chrony` installed; configurable via `/etc/chrony/chrony.conf` |
| Precision Time Protocol (PTP) | `linuxptp` available for precision time protocol |

## Deployment Options

| Capability | Detail |
|---|---|
| Installable USB image | A HookOS-based installer that writes the image to target storage; fully automated via `config-file` |
| Image Composer Tool image build | The Image Composer Tool produces a `.raw.gz` file from the YAML template |
| Curated image build | Uses the Ubuntu autoinstall flow, driven by the `auto-install-pkgs.yaml` configuration |
| USB artifact packaging | The `build-installation-artifacts.sh` script packages USB installation artifacts into the `usb-installation-files.tar.gz` archive |

## Host Type Dispatch

| `host_type` | Services enabled | Provisioning script |
|---|---|---|
| `kubernetes` |  Kubernetes is enabled, Docker is disabled | The `kubernetes-provision.sh` script provisions Helm tool, NFD, device plugins, and SR-IOV |
| `container` | Docker enabled, Kubernetes disabled | `container-provision.sh` |



## Coding Agent Support

| Capability | Detail |
|---|---|
| GitHub Copilot | `.github/copilot-instructions.md` and 5 skills |
| Claude Code | `CLAUDE.md` and `AGENTS.md` context catalog |
| Skills | `create-image`, `create-usb-installation-files`, `validate-platform-config`, `tune-platform-power`, `update-install-packages` |
