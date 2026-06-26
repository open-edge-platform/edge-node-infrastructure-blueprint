# drone-sdk

A complete **drone simulation kit** running entirely on your laptop or desktop.
No physical hardware needed. Fly, test, and control a virtual drone through a
simple web API.

Under the hood this uses:
- **PX4** — the same autopilot software used in real commercial drones
- **Gazebo** — a 3D physics simulator (like a video game engine for robots)
- **MAVSDK** — Python library that talks to PX4 over the MAVLink radio protocol

Everything runs in Docker containers — you do not need to install any drone
software yourself.

---

## What you will see

A virtual X500 quadrotor (a 4-motor drone) sitting on a simulated airfield.
You can arm it, take off, fly to a GPS location, and land — all via REST API
calls, exactly as a real companion computer would do.

```
┌─────────────────────────────────────────────────────────┐
│                  Your machine                           │
│                                                         │
│  Container: px4-gazebo                                  │
│  ┌────────────────────────────────┐                     │
│  │  Gazebo physics engine         │  ← 3D simulation    │
│  │    X500 quadrotor model        │                     │
│  │    Sensors: GPS, IMU, baro,    │                     │
│  │            rangefinder, lidar  │                     │
│  │         ↕ internal bridge      │                     │
│  │  PX4 autopilot binary          │  ← flight software  │
│  │    MAVLink UDP → port 14540    │                     │
│  └────────────────────────────────┘                     │
│            ↓ MAVLink over localhost                     │
│  Container: mavlink-bridge                              │
│  ┌────────────────────────────────┐                     │
│  │  MAVSDK-Python                 │  ← drone commands   │
│  │  FastAPI REST server           │  ← your API client  │
│  │    http://localhost:8080       │                     │
│  └────────────────────────────────┘                     │
└─────────────────────────────────────────────────────────┘
```

---

## Requirements

| What | Minimum version |
|------|----------------|
| Docker Desktop or Docker Engine | 24+ |
| Docker Compose plugin | v2 |
| RAM | 4 GB free |
| Disk | 15 GB free (first build downloads & compiles PX4) |
| OS | Linux (Ubuntu 24.04+ recommended) |

**GPU (optional but recommended):** If your machine has an Intel GPU with the
`xe` or `i915` driver, Gazebo will use hardware rendering automatically.
Without a GPU it falls back to software rendering — everything still works,
just a bit slower.

---

## Step 1 — Get the code

```bash
git clone <this-repo-url> drone-sdk
cd drone-sdk
```

---

## Step 2 — Configure proxy (skip if on a home/office network)

Open `.env` in any text editor.  If you are on a **corporate network** that
requires a proxy to reach the internet, fill in your proxy address.
Otherwise leave the values empty — the defaults work.

```bash
# Example for a corporate proxy:
HTTP_PROXY=http://proxy.myproxy.com:8080
HTTPS_PROXY=http://proxy.myproxy.com:8080
NO_PROXY=localhost,127.0.0.0/8
```

> **Not sure?** If `curl https://github.com` works without any extra settings,
> leave the proxy fields empty.

---

## Step 3 — Build and start

> The **first build takes 20–30 minutes** — PX4 source code is downloaded and
> compiled inside the container. A progress bar will appear. Subsequent starts
> use the cached image and take under 10 seconds.

```bash
docker compose up -d --build
```

Watch the startup log:
```bash
docker logs -f px4-gazebo
```

The simulator is ready when you see this line:
```
INFO  [commander] Ready for takeoff!
```

Press `Ctrl+C` to stop following the log (the simulator keeps running).

Check the companion bridge is connected:
```bash
docker logs mavlink-bridge | grep -E "connected|PX4"
# Expected output: PX4 connected!
```

---

## Step 4 — Open the 3D view (optional)

The simulation runs headless (no window) by default to save resources.
To see the 3D view, open a second terminal and run the Gazebo GUI
**from inside the container** (no extra install needed on your host):

```bash
docker exec -e DISPLAY=$DISPLAY px4-gazebo gz sim -g
```

This opens the Gazebo GUI and connects to the running simulation.
You will see the X500 drone sitting on the ground, ready to fly.

> **SSH session?** The GUI requires a local display. If you are connected over
> SSH, either use SSH X11 forwarding (`ssh -X user@host`) or run the container
> on the machine that has a monitor attached.

---

## Step 5 — Control the drone

Use `curl` or any HTTP client (Postman, Python `requests`, browser) to send
commands to the drone.

### Check status

```bash
curl http://localhost:8080/health
```
```json
{ "status": "ok", "connected": true }
```

### Get live telemetry

```bash
curl http://localhost:8080/telemetry
```
```json
{
    "connected": true,
    "armed": false,
    "flight_mode": "HOLD",
    "position": { "lat": 47.397743, "lon": 8.545594, "alt_m": 489.4, "rel_alt_m": 0.0 },
    "velocity": { "n": 0.0, "e": 0.0, "d": 0.0 },
    "attitude": { "roll": 0.0, "pitch": 0.0, "yaw": 0.0 },
    "battery": { "voltage_v": 16.2, "remaining_pct": 100.0 },
    "gps": { "satellites": 10, "fix": "FIX_3D" }
}
```

### Take off

```bash
# Take off to 10 metres
curl -X POST "http://localhost:8080/command/takeoff?altitude=10.0"
```

### Fly to a GPS location

```bash
curl -X POST "http://localhost:8080/command/goto" \
  -H "Content-Type: application/json" \
  -d '{"lat": 47.3985, "lon": 8.5456, "alt": 20.0}'
```

### Land

```bash
curl -X POST http://localhost:8080/command/land
```

### All commands

| Method | Endpoint              | What it does                        |
|--------|-----------------------|-------------------------------------|
| GET    | `/health`             | Is the bridge connected?            |
| GET    | `/telemetry`          | Live position, speed, battery, GPS  |
| POST   | `/command/arm`        | Arm motors (required before takeoff)|
| POST   | `/command/disarm`     | Disarm motors                       |
| POST   | `/command/takeoff`    | Arm + take off (`?altitude=10.0`)   |
| POST   | `/command/land`       | Land at current position            |
| POST   | `/command/return`     | Fly back to launch point and land   |

---

## Smoke test (run all API checks at once)

```bash
./scripts/test_api.sh
```

---

## GPU monitoring (Intel GPU)

If you have an Intel GPU, check it is being used:

```bash
# Install once
sudo apt install xpu-smi

# Show GPU memory and utilisation
xpu-smi stats -d 0 | grep -E "Memory Used|Memory Util|Frequency"
```

When the simulation is running you should see `GPU Memory Used` above a few
hundred MiB. This confirms hardware rendering is active (not software fallback).

---

## Stop the simulation

```bash
docker compose down
```

To also delete the built images (frees ~10 GB):
```bash
docker compose down --rmi all
```

---

## Troubleshooting

**Build hangs downloading packages**

You are probably on a corporate network. Set `HTTP_PROXY` / `HTTPS_PROXY` in
`.env` (see Step 2).

**`Ready for takeoff!` never appears (stuck at 50 lines)**

The Gazebo renderer failed to start. Try the software rendering fallback:
open `docker-compose.yml` and uncomment these two lines, then restart:
```yaml
LIBGL_ALWAYS_SOFTWARE: "1"
GALLIUM_DRIVER: "llvmpipe"
```

**`/dev/dri: no such file or directory` error**

Your machine has no GPU DRI nodes.
Remove the `devices:` and `group_add:` blocks from `docker-compose.yml` and
enable the software rendering fallback above.

**Bridge shows `connected: false`**

PX4 may still be initialising. Wait for `Ready for takeoff!` in `px4-gazebo`
logs, then check again.

---

## Project layout

```
drone-sdk/
├── .env                        ← proxy + simulation settings (edit this)
├── docker-compose.yml          ← defines both containers
├── px4-gazebo/
│   └── Dockerfile              ← Ubuntu 24.04 + Intel Mesa + PX4 v1.17.0
├── mavlink-bridge/
│   ├── Dockerfile
│   ├── requirements.txt        ← mavsdk, fastapi, uvicorn
│   └── app/
│       ├── main.py             ← FastAPI entry point
│       ├── config.py           ← reads env vars
│       ├── drone.py            ← MAVSDK connection + telemetry cache
│       └── routes.py           ← REST endpoints
└── scripts/
    └── test_api.sh             ← automated API smoke test
```

---

## Port reference

| Port  | Protocol       | Purpose                          |
|-------|----------------|----------------------------------|
| 14540 | MAVLink v2 UDP | PX4 → companion bridge           |
| 14550 | MAVLink v2 UDP | PX4 → QGroundControl (optional)  |
| 8080  | HTTP REST      | Companion bridge API             |

---

## Configuration

### `docker-compose.yml` — px4-gazebo environment

| Variable              | Default     | Description                     |
|-----------------------|-------------|---------------------------------|
| `HEADLESS`            | `1`         | Run Gazebo without GUI          |
| `PX4_HOME_LAT`        | `47.397742` | Home latitude (Zurich default)  |
| `PX4_HOME_LON`        | `8.545594`  | Home longitude                  |
| `PX4_HOME_ALT`        | `488.0`     | Home altitude (m)               |
| `PX4_SIM_SPEED_FACTOR`| `1`         | Simulation speed (1 = realtime) |

### `docker-compose.yml` — mavlink-bridge environment

| Variable           | Default | Description              |
|--------------------|---------|--------------------------|
| `PX4_MAVLINK_PORT` | `14540` | PX4 onboard MAVLink port |
| `API_HOST`         | `0.0.0.0` | REST API bind address  |
| `API_PORT`         | `8080`  | REST API port            |

### Change vehicle model

Edit `px4-gazebo/Dockerfile` CMD:
```dockerfile
# Quadrotor X500 (default)
CMD ["bash", "-c", "HEADLESS=1 make px4_sitl gz_x500"]

# X500 with depth camera
CMD ["bash", "-c", "HEADLESS=1 make px4_sitl gz_x500_depth"]

# Fixed-wing Cessna
CMD ["bash", "-c", "HEADLESS=1 make px4_sitl gz_rc_cessna"]

# VTOL
CMD ["bash", "-c", "HEADLESS=1 make px4_sitl gz_standard_vtol"]
```

