FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

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
    nano \
    tmux \
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

# Default env for RTX 3090.
ENV INSTALL_SYSTEM_DEPS=0
ENV INSTALL_PYTHON_TOOLS=0
ENV CUDA_ARCH=86
ENV CMAKE_CUDA_ARCHITECTURES=86
ENV WORK_ROOT=/workspace
ENV HF_HOME=/workspace/.cache/huggingface

WORKDIR /workspace

# Keep container alive by default on Vast/interactive systems.
CMD ["/bin/bash"]