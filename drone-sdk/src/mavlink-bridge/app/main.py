# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

import asyncio
import logging
import uvicorn
from contextlib import asynccontextmanager

from fastapi import FastAPI

from .config import API_HOST, API_PORT, LOG_LEVEL
from .drone import connect
from .routes import router

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL.upper(), logging.INFO),
    format="%(asctime)s [%(levelname)s] %(message)s",
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    asyncio.create_task(connect())
    yield


app = FastAPI(title="PX4 Gazebo Bridge", lifespan=lifespan)
app.include_router(router)

if __name__ == "__main__":
    uvicorn.run("app.main:app", host=API_HOST, port=API_PORT, reload=False)
