---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: generate-openvino-stress
description: Generate sustained AI inference load on CPU, GPU, or NPU using OpenVINO benchmark_app in a container (K3s pod or Docker). Produces real neural-network inference stress for power/thermal profiling — unlike stress-ng synthetic load. Auto-detects whether K3s or Docker is available; supports both runtimes. Pod specs are generated inline (no external YAML files). Ideal for validating power profiles under realistic AI workloads, measuring inference throughput per watt, and thermal qualification with real compute patterns.
---

## Purpose
`openvino_stress.sh` generates a **real AI inference load** (via OpenVINO
`benchmark_app`) for power/thermal evaluation. Unlike `stress_gen.sh` which uses
synthetic stress-ng workloads, this script exercises the hardware with actual
neural-network inference — producing compute, memory, and accelerator access
patterns representative of production AI workloads.

Use it when you want to validate power/thermal behavior under realistic AI
inference load, or to compare power consumption between CPU, GPU, and NPU
inference for the same model.

## Terminology

| Term | Meaning |
|---|---|
| benchmark_app | OpenVINO's inference throughput measurement tool. |
| OpenVINO | Intel's AI inference toolkit optimized for Intel hardware. |
| device | Target accelerator: CPU, GPU (Intel Xe via SR-IOV VF), or NPU. |
| runtime | Container orchestrator: K3s (kubectl) or Docker. Auto-detected. |
| niter | Number of inference iterations; 0 = run for a fixed duration instead. |
| duration | Time in seconds to run when niter=0; the benchmark loops until time expires. |
| nthreads | CPU threads dedicated to inference; GPU default is 2 (minimal CPU for offload). |
| api | Inference mode: sync (one request at a time) or async (pipelined). |
| device plugin | K3s plugin that exposes GPU VFs or NPU accelerators as schedulable resources. |
| model | The neural network used for benchmarking (default: age-gender-recognition-retail-0013 FP16). |

## Trigger Phrases
- openvino stress
- openvino benchmark stress
- run ai inference stress / run inference load
- stress with openvino / benchmark the cpu with openvino
- stress gpu with inference / stress npu with inference
- generate ai workload for power measurement
- run openvino on cpu / gpu / npu for thermal test
- real ai load for power profiling
- benchmark_app stress test

## Changing the Model

The default model (`age-gender-recognition-retail-0013`, FP16) is lightweight and
suitable for quick stress tests. To use a different model for heavier or more
representative workloads:

1. **Download the model** via `curl` from Intel's Open Model Zoo storage
   (same method the script uses for the default model):
   ```bash
   MODEL_NAME="face-detection-retail-0005"
   PRECISION="FP16"
   MODEL_DIR="/home/user/models/intel/intel/${MODEL_NAME}/${PRECISION}"
   BASE_URL="https://storage.openvinotoolkit.org/repositories/open_model_zoo/2022.3/models_bin/1"

   mkdir -p "${MODEL_DIR}"
   curl -fSL "${BASE_URL}/${MODEL_NAME}/${PRECISION}/${MODEL_NAME}.xml" -o "${MODEL_DIR}/${MODEL_NAME}.xml"
   curl -fSL "${BASE_URL}/${MODEL_NAME}/${PRECISION}/${MODEL_NAME}.bin" -o "${MODEL_DIR}/${MODEL_NAME}.bin"
   ```

2. **Run with the model** via `--model`:
   ```bash
   ./openvino_stress.sh --device cpu --duration 120 \
       --model intel/face-detection-retail-0005/FP16/face-detection-retail-0005.xml
   ```

### Suggested models by workload intensity

| Model | Size | Use case |
|---|---|---|
| `age-gender-recognition-retail-0013` (default) | ~4 MB | Quick stress, low memory footprint |
| `face-detection-retail-0005` | ~2 MB | Detection workload, slightly heavier compute |
| `person-detection-retail-0013` | ~2 MB | Person detection, moderate compute |
| `vehicle-detection-0200` | ~3.8 MB | Object detection, heavier compute |
| `face-detection-adas-0001` | ~2.4 MB | ADAS-grade detection, sustained compute |

Larger models exercise more memory bandwidth and cache hierarchy (L2/L3),
while smaller models stress pure compute throughput. Choose based on what
aspect of the platform you want to profile.

All models above are confirmed available at the Open Model Zoo storage URL.
Use `FP16` precision for all devices; `FP32` is also available but uses more
memory with no benefit on GPU/NPU.

## Required Inputs
- enib_home: absolute path to this repository root (default: current workspace root). On a provisioned host: `/opt/edge/developer`.
- device: target accelerator — `cpu` | `gpu` | `npu` (default: `cpu`)
- runtime: container runtime — `k3s` | `docker` (default: auto-detect; prefers Docker if available, falls back to K3s)
- niter: iteration count; `0` = time-based run (default: `0`)
- duration: seconds to run when niter=0 (default: `60`)
- nthreads: CPU threads for inference (default: auto — all for CPU, 2 for GPU, 0 for NPU)
- api: inference API mode — `sync` | `async` (default: `sync`)
- model_path: host path to models directory (default: `/home/user/models/intel`)
- model: model subpath within model_path (default: `intel/age-gender-recognition-retail-0013/FP16/age-gender-recognition-retail-0013.xml`)
- image: OpenVINO container image (default: `openvino/ubuntu24_dev:2026.0.0`)

## Preconditions
Run silently without user prompts:
- [ ] Skill file exists and is readable:
  - `test -f <enib_home>/skills/generate-openvino-stress/SKILL.md`
- [ ] The stress script exists and is executable:
  - `test -x <enib_home>/tools/power-tuning/openvino_stress.sh`
- [ ] At least one container runtime is available:
  - K3s: `command -v kubectl && kubectl cluster-info`
  - Docker: `command -v docker && docker info`
  - if neither is available, stop and instruct.
- [ ] For K3s + GPU: Intel GPU device plugin is running:
  - `kubectl get daemonset -n kube-system | grep intel-gpu` (non-fatal warning if absent)
- [ ] For K3s + NPU: Intel NPU device plugin is running:
  - `kubectl get daemonset -n kube-system | grep intel-npu` (non-fatal warning if absent)
- [ ] Any existing openvino-stress pod/container for the same device is automatically removed before launching (no manual cleanup needed).
- [ ] Model auto-download: if the model is not found at `<model_path>/<model_subpath>`, the script automatically downloads it via `curl` from Intel's Open Model Zoo storage (no python/pip dependency). Requires internet access. The download URL base is `https://storage.openvinotoolkit.org/repositories/open_model_zoo/2022.3/models_bin/1/`.
- [ ] Host is x86_64 with an Intel CPU (sanity check; non-fatal warning if not):
  - `uname -m` and `grep -m1 -o 'GenuineIntel' /proc/cpuinfo`

Prompt only for missing required inputs:
- [ ] Do not prompt; all inputs have safe defaults (CPU device, 60s duration, auto runtime). Only ask if the user's request is ambiguous about which device to target.

Input validation (fail closed before launch):
- [ ] `device` is one of: cpu, gpu, npu.
- [ ] `runtime` is one of: k3s, docker (or empty for auto-detect).
- [ ] `niter` is a non-negative integer.
- [ ] `duration` is a positive integer.
- [ ] `nthreads` (if set) is a positive integer.
- [ ] `api` is one of: sync, async.

## Steps
**Terminal command rules (MUST follow for every command in this skill):**
- Always invoke scripts by **absolute path** — never prefix with `cd`.
- Never combine `cd` with any output redirection in the same compound command.
- Never use `$(...)` command substitution in terminal commands.

1. Resolve the effective parameters and build the command (no launch yet):
   - Base: `<enib_home>/tools/power-tuning/openvino_stress.sh --device <device> --runtime <runtime> --api <api>`
   - Add `--duration <duration>` when niter=0.
   - Add `--niter <niter>` when niter>0.
   - Add `--nthreads <nthreads>` when explicitly provided.
   - Add `--model-path <model_path>` when non-default.
   - Add `--model <model>` when non-default.
   - Add `--image <image>` when non-default.

2. Capture a brief pre-stress snapshot (best-effort; skip when `dry_run=true`):
   - load average: `cat /proc/loadavg`
   - package temp/power if turbostat is available:
     `turbostat --quiet --interval 1 --num_iterations 1 --show PkgTmp,PkgWatt,GFXWatt 2>/dev/null || true`

3. **Always render a Planned Load table** from the resolved parameters:

   | Parameter | Value |
   |---|---|
   | Command | `<resolved openvino_stress.sh command>` |
   | Device | `<CPU/GPU/NPU>` |
   | Runtime | `<k3s/docker>` |
   | API mode | `<sync/async>` |
   | Duration / Iterations | `<duration>s` or `<niter> iterations` |
   | Threads | `<nthreads or auto>` |
   | Model | `<model subpath>` |
   | Container image | `<image>` |

4. **Confirmation gate** — pause before launching:
   - If `dry_run=true`: stop here and record `CONFIRMATION=dry_run_only`. Do not launch.
   - Else if `auto_confirm=true`: log `AUTO_CONFIRM=true` and continue.
   - Else: present the Planned Load table and ask for confirmation.

5. Launch (only after confirmation):
   - Run the resolved command. The script handles pod/container creation internally.
   - The benchmark runs asynchronously inside the container; the script returns once it confirms the workload is active.

6. Confirm the workload is active:
   - K3s: `kubectl get pod openvino-stress-<device>` shows Running.
   - Docker: `docker ps --filter name=openvino-stress-<device>` shows running container.

7. Report monitoring and stop commands to the user.

## Validation
- Preconditions passed (script executable; runtime available; no existing instance).
- All inputs validated against their constraints.
- A Planned Load table was rendered before the confirmation gate.
- Confirmation gate outcome recorded.
- Launch only occurred on `confirmed` or `auto_confirm`.
- After launch, the workload is active (pod Running or container running).
- Monitoring and stop instructions provided to the user.

## Rollback
- K3s: `kubectl delete pod openvino-stress-<device>`
- Docker: `docker rm -f openvino-stress-<device>`
- Or use the script's cleanup: `<enib_home>/tools/power-tuning/openvino_stress.sh --cleanup`
- The workload is ephemeral — stopping the pod/container fully restores idle behavior.

## Safety Rules
- The script automatically removes any existing instance before launching — no stale state.
- Warn before long-duration runs on thermally constrained enclosures.
- Do not run GPU/NPU benchmarks without confirming device plugins (K3s) or device nodes (Docker) exist.
- Never mask a failing precondition as success.

## Expected Result Summary

### Run Metadata

| Field | Value |
|---|---|
| Preconditions | PASS/FAIL |
| Host | `<uname -m>` + CPU model name |
| Device | `<CPU/GPU/NPU>` |
| Runtime | `<k3s/docker>` |
| Duration / Iterations | `<value>` |
| Dry run only | `true` / `false` |
| Confirmation | `confirmed` / `auto_confirm` / `declined` / `dry_run_only` |

### Launch Result

(omit when outcome is `declined` or `dry_run_only`)

| Field | Value |
|---|---|
| Command | `openvino_stress.sh --device <d> ...` |
| Pod/Container | `<name>` |
| Status | `Running` / `Error` |
| Monitor cmd | `kubectl logs -f ...` or `docker logs -f ...` |
| Stop cmd | `kubectl delete pod ...` or `docker rm -f ...` |

### Load Snapshot (pre → during)

| Metric | Before | During |
|---|---|---|
| loadavg (1m) | `<value>` | `<value>` |
| PkgTmp (C) | `<value or n/a>` | `<value or n/a>` |
| PkgWatt (W) | `<value or n/a>` | `<value or n/a>` |
| GFXWatt (W) | `<value or n/a>` | `<value or n/a>` |

### Validation Results

| Check Area | Status | Evidence | Notes |
|---|---|---|---|
| script executable | PASS/FAIL | `test -x` result | |
| runtime available | PASS/FAIL | kubectl/docker check | |
| no existing instance | PASS/FAIL | pod/container check | |
| device plugin (K3s) | PASS/FAIL/N/A | daemonset check | GPU/NPU only |
| model directory | PASS/FAIL | `test -d` result | |
| input validation | PASS/FAIL | range checks | |
| workload active | PASS/FAIL/N/A | pod/container status | N/A when not launched |

## Troubleshooting Notes
- "Neither K3s nor Docker detected": install K3s (`curl -sfL https://get.k3s.io | sh -`) or Docker (`sudo apt-get install -y docker.io`).
- Pod stays Pending (K3s + GPU/NPU): check device plugin is running (`kubectl get pods -n kube-system | grep intel`); verify allocatable resources (`kubectl describe node | grep -A5 Allocatable`).
- Docker GPU benchmark fails: ensure `/dev/dri` exists and user is in `video`/`render` group. Check OpenCL ICD (`ls /etc/OpenCL/vendors/`).
- Model not found: the script auto-downloads via curl on first run. If download fails (no internet, proxy issues), manually download from `https://storage.openvinotoolkit.org/repositories/open_model_zoo/2022.3/models_bin/1/<model_name>/<precision>/` and place the `.xml` and `.bin` files at `<model_path>/intel/<model_name>/<precision>/`.
- Low throughput on GPU: confirm `-hint none` and `-nthreads 2` are set; higher thread counts can cause CPU-GPU contention.
- To watch power effect under load, run `pt_mon.sh` in another terminal.
- To combine with a power cap, apply a profile first via `set-power-profile`, then run this skill.

## Related Skills
- **generate-platform-stress** — synthetic stress-ng load (CPU + iGPU); use when you don't need realistic AI inference patterns.
- **combined-power-thermal-profiling** — end-to-end power/thermal qualification workflow that pairs profiling with sustained workload generation.
- **monitor-power-thermal** — run in another terminal to record PkgTmp/PkgWatt/GFXWatt while inference runs.
- **set-power-profile** — apply a power cap first, then stress with OpenVINO to see how inference throughput degrades.
- **set-thermal-profile** — set thermal trip points, then run inference to validate the thermal policy.
- **profile-enclosure** — full profiling session; can be extended to use OpenVINO stress instead of stress-ng.
