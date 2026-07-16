#!/usr/bin/env bash

# Paths on lucebox3. Override any value before sourcing or in local.env.
export REPO="${REPO:-$HOME/lucebox-hub}"
export SERVER="${SERVER:-$REPO/server}"
export CUDA_BUILD="${CUDA_BUILD:-$SERVER/build-cuda-3090}"
export HIP_BUILD="${HIP_BUILD:-$SERVER/build-hip-halo}"
export RUN_ROOT="${RUN_ROOT:-$HOME/lucebox-runtime}"

export ROCM_PATH="${ROCM_PATH:-/opt/rocm}"
export HIP_PATH="${HIP_PATH:-$ROCM_PATH}"
export HIP_CLANG="${HIP_CLANG:-$ROCM_PATH/llvm/bin/clang++}"
export PATH="$ROCM_PATH/bin:$PATH"
export LD_LIBRARY_PATH="$ROCM_PATH/lib:$ROCM_PATH/lib64:${LD_LIBRARY_PATH:-}"

export JOBS="${JOBS:-$(nproc)}"
export BUILD_TYPE="${BUILD_TYPE:-RelWithDebInfo}" # Alternative: Release

export MODEL="${MODEL:-}"                         # Required for run-server.sh
export MODEL_NAME="${MODEL_NAME:-ds4-local}"
export HOST="${HOST:-127.0.0.1}"                 # Alternative: 0.0.0.0
export PORT="${PORT:-}"                           # Defaults: mono=8213, split=8214
export MAX_CTX="${MAX_CTX:-8192}"
export CHUNK="${CHUNK:-}"                         # Defaults: hc=1, default=512
export TARGET_SPLIT="${TARGET_SPLIT:-10,33}"      # CUDA,HIP weights
export PROFILE="${PROFILE:-hc}"                   # Alternative: default

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/local.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/local.env"
fi

mkdir -p "$RUN_ROOT/logs" "$RUN_ROOT/ipc"

