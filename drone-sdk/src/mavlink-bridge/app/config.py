# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

import os

PX4_PORT  = int(os.getenv("PX4_MAVLINK_PORT", "14540"))
API_HOST  = os.getenv("API_HOST", "0.0.0.0")
API_PORT  = int(os.getenv("API_PORT", "8080"))
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
MAV_URL   = f"udpin://0.0.0.0:{PX4_PORT}"
