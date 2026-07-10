# Build for Vast.ai / NVIDIA GPU cloud machines with:
#
# docker buildx build \
#   --platform linux/amd64 \
#   -f docker/Dockerfile \
#   --build-arg CUDA_ARCH=86 \
#   -t graffioh/lucebox-dev:cuda12.4-ubuntu22.04-amd64 \
#   --push \
#   .
#
# CUDA_ARCH picks the target GPU: 86 = RTX 3090 (default), 90 = H200.
# For the H200 image use --build-arg CUDA_ARCH=90 and tag
# graffioh/lucebox-dev:cuda12.4-ubuntu22.04-h200-amd64.
#
# Vast.ai machines are linux/amd64.
# Do not push an arm64 image from Apple Silicon for these tags.

FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Rome

# Core system dependencies for Lucebox/DFlash development.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    git-lfs \
    gh \
    curl \
    wget \
    ca-certificates \
    build-essential \
    cmake \
    ninja-build \
    pkg-config \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    gdb \
    lldb \
    vim \
    htop \
    less \
    ripgrep \
    fd-find \
    jq \
    unzip \
    zip \
    rsync \
    openssh-client \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Python tools used by the Lucebox docs/setup.
RUN python3 -m pip install --no-cache-dir --upgrade pip setuptools wheel \
    && python3 -m pip install --no-cache-dir \
       "huggingface_hub[cli]" \
       uv

# Git LFS setup.
RUN git lfs install --system

# Convenience symlink: Ubuntu package calls it fdfind.
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd || true

# Default env for the target GPU (86 = RTX 3090, 90 = H200).
# Declared late so both images share every layer above.
ARG CUDA_ARCH=86
ENV INSTALL_SYSTEM_DEPS=0
ENV INSTALL_PYTHON_TOOLS=0
ENV CUDA_ARCH=${CUDA_ARCH}
ENV CMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH}
ENV WORK_ROOT=/workspace
ENV HF_HOME=/workspace/.cache/huggingface

WORKDIR /workspace

# Keep development containers alive when a platform launches the image without
# an interactive TTY. Cloud runtimes can still override this command to start a
# service, and local interactive use remains available with `docker run ... /bin/bash`.
CMD ["sleep", "infinity"]
