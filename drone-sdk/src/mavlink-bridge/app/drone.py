# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

import asyncio
import logging

from mavsdk import System

from .config import MAV_URL

log = logging.getLogger(__name__)

drone = System()
state = {
    "connected": False,
    "armed": False,
    "flight_mode": "UNKNOWN",
    "position": None,
    "velocity": None,
    "attitude": None,
    "battery": None,
    "gps": None,
    "rangefinder": None,
    "status_texts": [],
}


async def connect() -> None:
    for attempt in range(1, 13):
        try:
            log.info("Connecting to %s (attempt %d)", MAV_URL, attempt)
            await drone.connect(system_address=MAV_URL)
            break
        except Exception as exc:
            log.warning("Attempt %d failed: %s", attempt, exc)
            await asyncio.sleep(5)
    else:
        log.error("Could not connect to PX4 after multiple attempts.")
        return

    async for conn in drone.core.connection_state():
        if conn.is_connected:
            log.info("PX4 connected!")
            state["connected"] = True
            break

    for coro in [
        _watch(drone.telemetry.armed(),
               lambda v: state.update({"armed": v})),
        _watch(drone.telemetry.flight_mode(),
               lambda v: state.update({"flight_mode": str(v).replace("FlightMode.", "")})),
        _watch(drone.telemetry.position(),
               lambda v: state.update({"position": {
                   "lat": v.latitude_deg, "lon": v.longitude_deg,
                   "alt_m": v.absolute_altitude_m, "rel_alt_m": v.relative_altitude_m}})),
        _watch(drone.telemetry.velocity_ned(),
               lambda v: state.update({"velocity": {
                   "n": v.north_m_s, "e": v.east_m_s, "d": v.down_m_s}})),
        _watch(drone.telemetry.attitude_euler(),
               lambda v: state.update({"attitude": {
                   "roll": v.roll_deg, "pitch": v.pitch_deg, "yaw": v.yaw_deg}})),
        _watch(drone.telemetry.battery(),
               lambda v: state.update({"battery": {
                   "voltage_v": v.voltage_v, "remaining_pct": v.remaining_percent}})),
        _watch(drone.telemetry.gps_info(),
               lambda v: state.update({"gps": {
                   "satellites": v.num_satellites,
                   "fix": str(v.fix_type).replace("FixType.", "")}})),
        _watch(drone.telemetry.distance_sensor(),
               lambda v: state.update({"rangefinder": {
                   "current_m": v.current_distance_m,
                   "min_m": v.minimum_distance_m,
                   "max_m": v.maximum_distance_m}})),
        _watch_status(),
        _watch(drone.core.connection_state(),
               lambda v: state.update({"connected": v.is_connected})),
    ]:
        asyncio.create_task(coro)


async def _watch_status():
    #PX4 only sends STATUSTEXT on specific events (arming, mode change, errors). It stays null until one fires.
    #status_text is event driven stream that only emits when new status text is available, so we can keep a rolling log of the last 50 messages
    async for msg in drone.telemetry.status_text():
        entry = {"type": str(msg.type).replace("StatusTextType.", ""), "text": msg.text}
        log.info("PX4 status [%s]: %s", entry["type"], entry["text"])
        state["status_texts"].append(entry)
        state["status_texts"] = state["status_texts"][-50:]


async def _watch(stream, fn):
    try:
        async for val in stream:
            fn(val)
    except Exception as exc:
        log.warning("Telemetry stream error: %s", exc)
