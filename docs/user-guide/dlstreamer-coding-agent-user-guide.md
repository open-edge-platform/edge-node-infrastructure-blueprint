# DL Streamer Coding Agent — User Guide

## Overview

The **DL Streamer Coding Agent** is a Claude Code skill that builds complete video-analytics applications from natural-language descriptions. It generates working Python, C/C++, or GStreamer command-line applications using Intel DL Streamer, handling everything from model download to pipeline validation.

**Location:** `<dlstreamer-repo>/.github/skills/dlstreamer-coding-agent/` (where `<dlstreamer-repo>` is your local clone of the [DL Streamer repository](https://github.com/open-edge-platform/dlstreamer))

## What It Does

Given a description of a video AI pipeline, the coding agent:

1. Gathers requirements (video source, AI models, target hardware, output format)
2. Pulls the DL Streamer Docker image
3. Prepares models (download, convert to OpenVINO IR format)
4. Designs the GStreamer pipeline (element selection, structure)
5. Generates a complete application with all supporting files
6. Runs and validates the output

## When to Use

- You want to describe a vision AI pipeline in plain English and get working code
- You need to create a Python/C++/shell sample app built on DL Streamer
- You want to combine multiple capabilities (detection + tracking + recording + alerts)
- You need to convert a DeepStream application to DL Streamer
- You want custom GStreamer elements for inline analytics

## How to Invoke

Open Claude Code in the `dlstreamer` repository and describe your pipeline. The agent triggers when your prompt matches patterns like:

- "Create a Python app that detects..."
- "Build a pipeline that..."
- "Develop a vision AI application..."
- "Convert this DeepStream app to DL Streamer..."

## Writing an Effective Prompt

The more detail you provide upfront, the fewer questions the agent asks. Include:

| Field | What to specify | Example |
|-------|----------------|---------|
| **Video input** | File URL, local path, or RTSP URI | `https://videos.pexels.com/video-files/...` |
| **AI model(s)** | Model name and task | "YOLOv11 for detection, PaddleOCR for text" |
| **Target hardware** | Intel platform + accelerator | "Intel Core Ultra 3, use GPU" |
| **Output format** | What to produce | "Annotated video + JSON detections" |
| **App type** | Python, C/C++, or shell/gst-launch | "Python application" |
| **Save location** | Directory name for generated code | "Save in `my_app/` directory" |

## Example Prompts

### People Detection with Tracking

```
Create a bash script that detects and tracks (use deep sort algorithm) people on video stream.
- Read input video from a file (https://videos.pexels.com/video-files/18552655/18552655-hd_1280_720_30fps.mp4)
- Use YOLO26m model for people detection
- Use Mars-Small-128 model for re-identification
- Annotate video stream and store it as an output video file

Generate vision AI processing pipeline optimized for Intel Core Ultra 3 processors.
Save source code in people_detection_tracking directory, including README.md with setup instructions.
Follow instructions in README.md to run the application and check if it generates the expected output.
```

### License Plate Recognition

```
Develop a Python application that implements license plate recognition pipeline:
- Read input video from a file (https://github.com/open-edge-platform/edge-ai-resources/raw/main/videos/ParkingVideo.mp4) but also allow remote IP cameras
- Run YOLOv11 for object detection and PaddleOCR for character recognition
- Output license plate text for each detected object as JSON file
- Annotate video stream and store it as an output video file

Generate vision AI processing pipeline optimized for Intel Core Ultra 3 processors.
Save source code in license_plate_recognition directory, including README.md with setup instructions.
```

### Event-Based Smart NVR

```
Develop a vision AI application that implements an event-based smart video recording pipeline:
- Read input video from an RTSP camera, but allow also video file input
- Run an AI model to detect people in camera view
- Trigger recording when a person is detected and stop recording when person is out of view
- Output a sequence of files: save-1, save-2, save-3, ... for each detection event

Optimize for Intel Core Ultra 3 processors. Save source code in smart_nvr directory.
```

### Multi-Stream Composite (Mosaic)

```
Create a Python app that composes 4 RTSP camera streams into a 2x2 mosaic with
person detection overlays and streams the result via WebRTC.
```

### DeepStream Conversion

```
Convert the following DeepStream Python application to DL Streamer:
[paste source code or provide path]
Keep the same functionality — detection + classification + JSON output.
```

## What Gets Generated

The agent produces a complete application directory:

```
<app_name>/
├── <app_name>.py (or .sh/.cpp)   # Main application
├── export_models.py              # Model download/export script
├── requirements.txt              # App Python dependencies
├── export_requirements.txt       # Model export dependencies
├── README.md                     # Setup and usage instructions
├── plugins/                      # Custom GStreamer elements (if needed)
│   ├── python/
│   └── c/
├── config/                       # Configuration files (if needed)
├── models/                       # Created at runtime
├── videos/                       # Created at runtime
└── results/                      # Output files
```

## Execution Flow

The agent runs steps in parallel for speed:

```
Step 0: Gather requirements (interactive, if info missing)
  │
  ├──► Step 1:  Docker pull (async)
  ├──► Step 2a: Export scripts + pip install (async)
  ├──► Step 2b: Video download (async)
  │         └──► Step 2c: Model export (after pip install)
  └──► Step 3:  Design pipeline (reasoning)
           └──► Step 4: Generate app code
                    └──► Step 5: Run & validate (after Docker + models + code ready)
```

## Supported Capabilities

### AI Tasks
- Object detection (YOLO family, SSD, RTDETR)
- Classification
- Object tracking (DeepSORT, SORT)
- OCR / text recognition (PaddleOCR)
- Vision-Language Models / GenAI (InternVL, MiniCPM, Qwen2.5-VL, SmolVLM)
- Pose estimation
- Anomaly detection

### Pipeline Features
- Multi-stream / multi-camera with shared model instances
- Composite mosaic (2x2, 3x3, etc.)
- Event-based recording (start/stop on detection)
- WebRTC streaming output
- RTSP input
- JSON metadata publishing
- FPS throttling
- Video annotation overlays

### Target Hardware
- Intel Core Ultra processors (CPU, GPU, NPU)
- Automatic device fallback: NPU → GPU → CPU
- GPU batch processing for multi-stream workloads

## Tips for Best Results

1. **Be specific about models** — name the exact model (e.g., "YOLOv11n" not just "a detection model")
2. **Provide a test video URL** — the agent downloads and tests with it
3. **State the output format** — "annotated video + JSON" is clearer than "save results"
4. **Ask for validation** — include "run the application and check output" in your prompt
5. **Specify hardware** — helps the agent pick optimal inference device and batch sizes
6. **Include "README.md with setup instructions"** — ensures documentation is generated

## Troubleshooting

| Issue | Likely Cause | Fix |
|-------|-------------|-----|
| Docker pull fails | Network/auth issue | Check `docker login` and network connectivity |
| Model export OOM | Large model + limited RAM | Try a smaller model variant or add swap |
| Pipeline hangs | Missing EOS propagation | Agent adds `flush-on-eos=true` on queues |
| Output video unplayable | `mp4mux` didn't receive EOS | Agent sends EOS on SIGINT via signal handler |
| Slow first run (5-10 min) | GPU shader compilation for VLM | Normal for first run; subsequent runs are fast |
| NPU inference fails | Model/element doesn't support NPU | Fall back to GPU; agent will suggest this |

## Available Example Prompts

The skill includes example prompts in the `examples/` directory for common scenarios:

- `people-detection-tracking.md` — Detection + re-ID tracking
- `license-plate-recognition.md` — Detection + OCR pipeline
- `event-based-smart-nvr.md` — Event-triggered recording
- `multi-stream-compose.md` — Multi-camera mosaic
- `pose-estimation-compose.md` — Pose estimation pipeline
- `safety-compliance-checks.md` — Safety/PPE compliance
- `deepstream-cpp-conversion.md` — DeepStream C++ → DL Streamer
- `deepstream-python-conversion.md` — DeepStream Python → DL Streamer

## Requirements

- Docker installed and accessible (for `intel/dlstreamer:latest` image)
- Python 3.10+ (for model export scripts)
- Network access (to pull Docker images, download models and videos)
- Intel hardware with GPU recommended for best performance
