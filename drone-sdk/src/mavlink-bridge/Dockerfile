# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

FROM python:3.11-slim

ARG http_proxy
ARG https_proxy
ARG no_proxy
ENV http_proxy=${http_proxy} https_proxy=${https_proxy} no_proxy=${no_proxy}

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

ENV http_proxy= https_proxy= no_proxy=

COPY app/ ./app/

ENV API_HOST=0.0.0.0 API_PORT=8080 LOG_LEVEL=INFO

EXPOSE 8080
CMD ["python", "-m", "app.main"]
