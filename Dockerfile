# syntax=docker/dockerfile:1
#
# Multi-stage build for GeoLab.
#   Stage 1 (build)   : full toolchain (g++, cmake, Boost, Eigen) compiles the C++ apps.
#   Stage 2 (runtime) : slim image shipping only the built binaries + Python scripts and
#                       their runtime dependencies (core pipeline only).
#
# Both stages share python:3.11-slim-bookworm so glibc/Boost ABI match between them.
#
# Build (amd64):
#   docker buildx build --platform linux/amd64 -t geolab:latest --load .
#
# Run (mount the ESBA Atlas, available on request, plus your data):
#   docker run --rm -v /path/to/Atlas:/atlas -e ESBA_DIR=/atlas -v "$PWD/data:/data" \
#       geolab:latest ProjectAtlasGeoLab -i /data/input.tck -o /data/out -nbPoints 15 -nbThreads 4

########################################  build stage  #########################################
FROM --platform=linux/amd64 python:3.11-slim-bookworm AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        libboost-all-dev \
        libeigen3-dev \
        libncurses-dev \
    && rm -rf /var/lib/apt/lists/*

COPY . /src

# Configure and build. PYTHON_BINARY defaults to "/usr/bin/env python3" (see CMakeLists.txt),
# which resolves to /usr/local/bin/python3 in the runtime image.
RUN cmake -S /src -B /src/build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /src/build -j "$(nproc)"

#######################################  runtime stage  ########################################
FROM --platform=linux/amd64 python:3.11-slim-bookworm

# Shared libraries the compiled binaries link against at runtime:
#   libboost-system (Boost.System / boost::process), libgomp (OpenMP).
# Eigen and LBFGSpp are header-only; std::filesystem is part of libstdc++.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libboost-system1.74.0 \
        libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Core Python dependencies (pinned to the user's known-good versions; numpy <2 for dipy).
RUN pip install --no-cache-dir \
        numpy==1.26.4 \
        scipy \
        dipy==1.12.1 \
        nibabel==5.4.2 \
        setproctitle

# Ship the built binaries + configured Python scripts.
COPY --from=build /src/build/bin /opt/geolab/bin

ENV PATH=/opt/geolab/bin:$PATH \
    ESBA_DIR=/atlas

WORKDIR /data

ENTRYPOINT ["ProjectAtlasGeoLab"]

