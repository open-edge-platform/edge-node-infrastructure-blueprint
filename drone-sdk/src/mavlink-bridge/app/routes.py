# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

from fastapi import APIRouter
from . import drone as d

router = APIRouter()


@router.get("/health")
async def health():
    return {"status": "ok", "connected": d.state["connected"]}


@router.get("/telemetry")
async def telemetry():
    return d.state


@router.post("/command/arm")
async def arm():
    await d.drone.action.arm()
    return {"status": "ok"}


@router.post("/command/disarm")
async def disarm():
    await d.drone.action.disarm()
    return {"status": "ok"}


@router.post("/command/takeoff")
async def takeoff(altitude: float = 10.0):
    await d.drone.action.set_takeoff_altitude(altitude)
    await d.drone.action.arm()
    await d.drone.action.takeoff()
    return {"status": "ok", "altitude": altitude}


@router.post("/command/land")
async def land():
    await d.drone.action.land()
    return {"status": "ok"}


@router.post("/command/return")
async def rtl():
    await d.drone.action.return_to_launch()
    return {"status": "ok"}
