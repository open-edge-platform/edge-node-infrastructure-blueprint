<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Intel DL Streamer Pipelines Guide

## Overview

Intel Deep Learning Streamer (DL Streamer) is an open-source streaming media analytics framework built on [GStreamer](https://gstreamer.freedesktop.org). It provides a set of GStreamer elements for building video and audio analytics pipelines that perform detection, classification, tracking, and inference using [OpenVINO](https://docs.openvino.ai) on Intel CPU, GPU, and NPU devices.

A DL Streamer pipeline is constructed as a chain of GStreamer elements connected by `!` (exclamation marks):

```text
input source ! decode ! inference ! post-processing ! output sink
```

---

## Prerequisites

- Edge Node Infrastructure Blueprint image deployed
- Docker Engine 25+ with CDI enabled (see [Container Device Interface Guide](container-device-interface-guide.md))
- Intel GPU and/or NPU hardware present
- Network connectivity for pulling the DL Streamer Docker image and sample video files
- If behind a corporate proxy, pass proxy environment variables to Docker containers:

  ```bash
  docker run --rm \
    -e http_proxy=$http_proxy \
    -e https_proxy=$https_proxy \
    -e no_proxy=$no_proxy \
    ...
  ```

---

## Key DL Streamer Elements

| Element | Purpose | Supported Devices |
|---------|---------|-------------------|
| `gvadetect` | Object detection (YOLO, SSD, EfficientDet, etc.) | CPU, GPU, NPU |
| `gvaclassify` | Object classification, segmentation, pose estimation | CPU, GPU, NPU |
| `gvainference` | Raw model inference (no metadata interpretation) | CPU, GPU, NPU |
| `gvatrack` | Object tracking across frames (zero-term or short-term) | CPU |
| `gvagenai` | GenAI model inference (image/video to text) | CPU, GPU |
| `gvawatermark` | Overlay inference results on video frames | — |
| `gvafpscounter` | Measure pipeline FPS | — |
| `gvametaconvert` | Convert inference metadata to JSON | — |
| `gvametapublish` | Publish metadata to file, MQTT, or Kafka | — |

---

## Running DL Streamer with Docker and CDI

Pull the DL Streamer Docker image:

```bash
docker pull intel/dlstreamer:latest
```

Run a container with GPU access using CDI:

```bash
docker run -it --rm \
  --device intel.com/gpu=card1 \
  intel/dlstreamer:latest
```

Run with both GPU and NPU:

```bash
docker run -it --rm \
  --device intel.com/gpu=card1 \
  --device intel.com/npu=npu0 \
  intel/dlstreamer:latest
```

Verify DL Streamer is working inside the container:

```bash
gst-inspect-1.0 gvadetect
```

---

## Download Models and Sample Videos

DL Streamer inference elements require OpenVINO IR models. The DL Streamer repository includes download scripts for supported models.

### Download Models

Models can be downloaded inside the DL Streamer container using the bundled download script:

```bash
mkdir -p models

docker run --rm \
  -v $(pwd)/models:/models \
  -e MODELS_PATH=/models \
  intel/dlstreamer:latest \
  bash -c "/opt/intel/dlstreamer/samples/download_public_models.sh yolox_s"
```

This downloads the YOLOx-S model, converts it to OpenVINO IR format (FP16 and FP32), and saves it to `models/public/yolox_s/`.

To also quantize to INT8 precision, add the `coco128` argument:

```bash
docker run --rm \
  -v $(pwd)/models:/models \
  -e MODELS_PATH=/models \
  intel/dlstreamer:latest \
  bash -c "/opt/intel/dlstreamer/samples/download_public_models.sh yolox_s coco128"
```

To download additional models:

```bash
docker run --rm \
  -v $(pwd)/models:/models \
  -e MODELS_PATH=/models \
  intel/dlstreamer:latest \
  bash -c "/opt/intel/dlstreamer/samples/download_public_models.sh yolo11s coco128"
```

Supported model names include: `yolox-tiny`, `yolox_s`, `yolov7`, `yolov8s`, `yolov9c`, `yolov10s`, `yolo11s`, `yolo11s-obb`, `yolo11s-seg`, `yolo11s-pose`, and others. Pass `all` to download all supported models.

The downloaded models are stored in `$MODELS_PATH/public/<model_name>/<precision>/` structure:

```text
models/public/yolox_s/
├── FP16/
│   ├── yolox_s.xml
│   └── yolox_s.bin
└── FP32/
    ├── yolox_s.xml
    └── yolox_s.bin
```

### Sample Videos

The pipeline examples in this guide use publicly available sample videos from the [Intel IoT DevKit](https://github.com/intel-iot-devkit/sample-videos). GStreamer fetches these directly via URL using `urisourcebin` — no manual download is needed.

To use a local video file instead:

```bash
docker run --rm \
  --device intel.com/gpu=card1 \
  -v $(pwd)/models:/models \
  -v /path/to/videos:/videos \
  -e MODELS_PATH=/models \
  intel/dlstreamer:latest \
  bash -c "\
    gst-launch-1.0 \
      filesrc location=/videos/my-video.mp4 \
      ! decodebin3 \
      ! gvadetect model=\$MODELS_PATH/public/yolox_s/FP16/yolox_s.xml model-proc=/opt/intel/dlstreamer/samples/model_proc/public/yolo-x.json device=GPU pre-process-backend=va-surface-sharing \
      ! queue \
      ! gvafpscounter \
      ! fakesink async=false"
```

---

## Pipeline Examples

### Object Detection with YOLO on GPU

Run YOLO object detection on a sample video using the GPU for inference:

```bash
docker run --rm \
  --device intel.com/gpu=card1 \
  -v $(pwd)/models:/models \
  -e MODELS_PATH=/models \
  intel/dlstreamer:latest \
  bash -c "\
    gst-launch-1.0 \
      urisourcebin buffer-size=4096 uri=https://github.com/intel-iot-devkit/sample-videos/raw/master/people-detection.mp4 \
      ! decodebin3 \
      ! gvadetect model=\$MODELS_PATH/public/yolox_s/FP16/yolox_s.xml model-proc=/opt/intel/dlstreamer/samples/model_proc/public/yolo-x.json device=GPU pre-process-backend=va-surface-sharing \
      ! queue \
      ! gvafpscounter \
      ! fakesink async=false"
```

### Object Detection on CPU

Run the same pipeline on CPU (no GPU device needed):

```bash
docker run --rm \
  -v $(pwd)/models:/models \
  -e MODELS_PATH=/models \
  intel/dlstreamer:latest \
  bash -c "\
    gst-launch-1.0 \
      urisourcebin buffer-size=4096 uri=https://github.com/intel-iot-devkit/sample-videos/raw/master/people-detection.mp4 \
      ! decodebin3 \
      ! gvadetect model=\$MODELS_PATH/public/yolox_s/FP16/yolox_s.xml model-proc=/opt/intel/dlstreamer/samples/model_proc/public/yolo-x.json device=CPU pre-process-backend=opencv \
      ! queue \
      ! gvafpscounter \
      ! fakesink async=false"
```

### Object Detection on NPU

Switch inference to the NPU by changing the `device` and `pre-process-backend` parameters:

```bash
docker run --rm \
  --device intel.com/gpu=card1 \
  --device intel.com/npu=npu0 \
  -v $(pwd)/models:/models \
  -e MODELS_PATH=/models \
  intel/dlstreamer:latest \
  bash -c "\
    gst-launch-1.0 \
      urisourcebin buffer-size=4096 uri=https://github.com/intel-iot-devkit/sample-videos/raw/master/people-detection.mp4 \
      ! decodebin3 \
      ! gvadetect model=\$MODELS_PATH/public/yolox_s/FP16/yolox_s.xml model-proc=/opt/intel/dlstreamer/samples/model_proc/public/yolo-x.json device=NPU pre-process-backend=va \
      ! queue \
      ! gvafpscounter \
      ! fakesink async=false"
```

### Save Inference Results to JSON

Output detection metadata as JSON lines to a file:

```bash
docker run --rm \
  --device intel.com/gpu=card1 \
  -v $(pwd)/models:/models \
  -e MODELS_PATH=/models \
  -v /tmp/results:/results \
  intel/dlstreamer:latest \
  bash -c "\
    gst-launch-1.0 \
      urisourcebin buffer-size=4096 uri=https://github.com/intel-iot-devkit/sample-videos/raw/master/people-detection.mp4 \
      ! decodebin3 \
      ! gvadetect model=\$MODELS_PATH/public/yolox_s/FP16/yolox_s.xml model-proc=/opt/intel/dlstreamer/samples/model_proc/public/yolo-x.json device=GPU pre-process-backend=va-surface-sharing \
      ! queue \
      ! gvametaconvert add-tensor-data=true \
      ! gvametapublish file-format=json-lines file-path=/results/output.json \
      ! fakesink async=false"
```

Results are saved to `/tmp/results/output.json` on the host.

---

## Pipeline Building Blocks

### Source Elements

| Pattern | Element | Use Case |
|---------|---------|----------|
| Video file (URL) | `urisourcebin buffer-size=4096 uri=<URL>` | Remote or local media file |
| Video file (local) | `filesrc location=<path>` | Local media file |
| USB camera | `v4l2src device=/dev/video0` | Live camera capture |
| RTSP stream | `rtspsrc location=rtsp://<host>:<port>/<path>` | Network camera |

### Decode

Use `decodebin3` for automatic format detection and hardware-accelerated decode:

```text
! decodebin3 !
```

### Inference Device Selection

The `device` property on inference elements controls where the model runs:

| Device | `pre-process-backend` | Description |
|--------|----------------------|-------------|
| `CPU` | `opencv` | CPU inference via OpenVINO |
| `GPU` | `va-surface-sharing` | GPU inference with zero-copy decode-to-inference |
| `NPU` | `va` | NPU inference with VA-API pre-processing |

### Output Sinks

| Output | Sink Element Chain |
|--------|-------------------|
| FPS measurement | `gvafpscounter ! fakesink async=false` |
| JSON file | `gvametaconvert ! gvametapublish file-format=json-lines file-path=output.json ! fakesink async=false` |
| Display with overlay | `vapostproc ! gvawatermark ! videoconvert ! gvafpscounter ! autovideosink sync=false` |
| Encode to MP4 file | `vapostproc ! gvawatermark ! vah264enc ! h264parse ! mp4mux ! filesink location=out.mp4` |

---

## Running DL Streamer in Kubernetes

Deploy a DL Streamer workload as a Kubernetes pod with GPU access:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dlstreamer-gpu
  namespace: default
spec:
  restartPolicy: Never
  containers:
    - name: dlstreamer
      image: intel/dlstreamer:latest
      command:
        - bash
        - -c
        - |
          gst-launch-1.0 \
            urisourcebin buffer-size=4096 uri=https://github.com/intel-iot-devkit/sample-videos/raw/master/people-detection.mp4 \
            ! decodebin3 \
            ! gvadetect model=$MODELS_PATH/public/yolox_s/FP16/yolox_s.xml model-proc=/opt/intel/dlstreamer/samples/model_proc/public/yolo-x.json device=GPU pre-process-backend=va-surface-sharing \
            ! queue \
            ! gvafpscounter \
            ! fakesink async=false
      env:
        - name: MODELS_PATH
          value: /models
      resources:
        limits:
          gpu.intel.com/xe: "1"
      volumeMounts:
        - name: models
          mountPath: /models
  volumes:
    - name: models
      hostPath:
        path: /path/to/dlstreamer/models
```

Apply and check:

```bash
kubectl apply -f dlstreamer-gpu.yaml
kubectl wait pod/dlstreamer-gpu --for=jsonpath='{.status.phase}'=Succeeded --timeout=120s
kubectl logs dlstreamer-gpu
```

---

## Troubleshooting

### "No such element or plugin 'gvadetect'"

The DL Streamer plugins are not installed or not in the GStreamer plugin path. Verify inside the container:

```bash
gst-inspect-1.0 gvadetect
```

### GPU Device Not Available in Container

Verify CDI is configured and the GPU spec exists:

```bash
ls /etc/cdi/intel.com-gpu.yaml
docker run --rm --device intel.com/gpu=card1 ubuntu:24.04 ls /dev/dri/
```

### Pipeline Fails with "Could not initialize element"

Check that the model file exists at the specified path and matches the requested precision (FP16, INT8, FP32):

```bash
ls models/public/yolox_s/FP16/
```

If models are missing, download them using the DL Streamer container:

```bash
docker run --rm \
  -v $(pwd)/models:/models \
  -e MODELS_PATH=/models \
  intel/dlstreamer:latest \
  bash -c "/opt/intel/dlstreamer/samples/download_public_models.sh yolox_s"
```

### Low FPS on GPU

Ensure `pre-process-backend=va-surface-sharing` is set for GPU inference. This enables zero-copy between decode and inference, avoiding CPU-GPU memory transfers.

---

## References

- [DL Streamer Repository](https://github.com/open-edge-platform/dlstreamer)
- [DL Streamer Docker Hub](https://hub.docker.com/r/intel/dlstreamer)
- [DL Streamer Elements Reference](https://github.com/open-edge-platform/dlstreamer/blob/main/docs/user-guide/elements/elements.md)
- [DL Streamer Samples](https://github.com/open-edge-platform/dlstreamer/tree/main/samples)
- [Container Device Interface Guide](container-device-interface-guide.md) — CDI setup for GPU/NPU access in Docker
