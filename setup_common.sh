#!/usr/bin/env bash
# Shared config and setup steps for the setup_*.sh scripts.
# This file is meant to be sourced, not run directly.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "ERROR: source this file from a setup_*.sh script, don't run it directly." >&2
  exit 1
fi

SETUP_SCRIPT_NAME="$(basename "${BASH_SOURCE[1]}")"

# -------- common config (env vars override any of these) --------

DEV_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUCEBOX_DIR="$DEV_REPO_DIR/lucebox-hub"
DFLASH_DIR="$LUCEBOX_DIR/server"

# Keep large files outside the repo (default: sibling directory of lucebox-dev).
WORK_ROOT="${WORK_ROOT:-$(dirname "$DEV_REPO_DIR")}"
MODEL_DIR="${MODEL_DIR:-$WORK_ROOT/models}"
export HF_HOME="${HF_HOME:-$WORK_ROOT/.cache/huggingface}"

# Default: RTX 3090 = sm_86. Scripts for other GPUs set CUDA_ARCH before sourcing.
CUDA_ARCH="${CUDA_ARCH:-86}"
INTENDED_IMAGE="${INTENDED_IMAGE:-graffioh/lucebox-dev:cuda12.4-ubuntu22.04-amd64}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 8)}"

GIT_USER_NAME="${GIT_USER_NAME:-Graffioh}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-}"

# Both default to 0 because the custom Docker images preinstall everything.
INSTALL_SYSTEM_DEPS="${INSTALL_SYSTEM_DEPS:-0}"
INSTALL_PYTHON_TOOLS="${INSTALL_PYTHON_TOOLS:-0}"

# -------- helpers --------

print_common_config() {
  cat <<EOF
DEV_REPO_DIR:        $DEV_REPO_DIR
LUCEBOX_DIR:         $LUCEBOX_DIR
DFLASH_DIR:          $DFLASH_DIR
WORK_ROOT:           $WORK_ROOT
MODEL_DIR:           $MODEL_DIR
HF_HOME:             $HF_HOME
CUDA_ARCH:           $CUDA_ARCH
BUILD_JOBS:          $BUILD_JOBS
INSTALL_SYSTEM_DEPS: $INSTALL_SYSTEM_DEPS
INSTALL_PYTHON_TOOLS:$INSTALL_PYTHON_TOOLS
EOF
}

download_if_missing() {  # <label> <repo> <local dir> <file> [extra files...]
  local label="$1" repo="$2" dir="$3" file="$4"
  shift 4
  echo
  echo "== Download $label if missing =="
  mkdir -p "$dir"
  if [ -f "$dir/$file" ]; then
    echo "$label already exists: $dir/$file"
  else
    hf download "$repo" "$file" "$@" --local-dir "$dir"
  fi
}

# System check, dependency install, git/gh setup, submodule init,
# uv sync and DFlash build. Everything up to the model downloads.
run_common_setup() {
  local cmd

  echo "== System check =="
  nvidia-smi || true
  for cmd in nvcc cmake python3 git gh hf uv; do
    "$cmd" --version || true
  done
  echo

  if [ "$INSTALL_SYSTEM_DEPS" = "1" ]; then
    echo "== Install system packages =="
    sudo apt-get update
    sudo apt-get install -y \
      git git-lfs gh curl wget ca-certificates \
      build-essential cmake ninja-build pkg-config \
      python3 python3-pip python3-venv python3-dev \
      gdb lldb vim htop less ripgrep fd-find jq unzip zip rsync \
      openssh-client sudo
  else
    echo "== Skipping system package install =="
  fi

  echo
  echo "== Git identity =="
  git config --global user.name "$GIT_USER_NAME"
  if [ -n "$GIT_USER_EMAIL" ]; then
    git config --global user.email "$GIT_USER_EMAIL"
  else
    echo "GIT_USER_EMAIL is not set. Commits may fail until you configure an email:"
    echo "  git config --global user.email 'you@example.com'"
  fi

  echo
  echo "== GitHub auth status =="
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh is not installed. Install it or rebuild the Docker image."
  elif gh auth status >/dev/null 2>&1; then
    echo "Already authenticated with GitHub."
  else
    echo "Not authenticated with GitHub. For pushing to GitHub, run manually:"
    echo "  gh auth login"
  fi

  echo
  if [ "$INSTALL_PYTHON_TOOLS" = "1" ]; then
    echo "== Install Python tools =="
    python3 -m pip install --upgrade pip setuptools wheel
    python3 -m pip install --upgrade "huggingface_hub[cli]" uv
  else
    echo "== Skipping Python tool install =="
  fi

  echo
  echo "== Verify required commands =="
  for cmd in git cmake python3 hf uv; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "ERROR: required command not found: $cmd"
      echo "Either rebuild the Docker image or run:"
      echo "  INSTALL_SYSTEM_DEPS=1 INSTALL_PYTHON_TOOLS=1 bash $SETUP_SCRIPT_NAME"
      exit 1
    fi
  done

  if ! command -v nvcc >/dev/null 2>&1; then
    echo "ERROR: nvcc not found. You need a CUDA devel image, not a runtime image."
    echo "Recommended image: $INTENDED_IMAGE"
    exit 1
  fi

  echo
  echo "== Initialize/update lucebox-hub submodule =="
  cd "$DEV_REPO_DIR"
  git submodule update --init --recursive

  if [ ! -f "$DFLASH_DIR/CMakeLists.txt" ]; then
    echo "ERROR: DFlash CMake project not found at $DFLASH_DIR"
    echo "The current lucebox-hub layout is expected to contain server/CMakeLists.txt."
    exit 1
  fi

  echo
  echo "== Sync Python workspace dependencies =="
  cd "$LUCEBOX_DIR"
  read -r -a UV_SYNC_ARGS <<< "${UV_SYNC_ARGS:---no-install-package torch}"
  uv sync --frozen "${UV_SYNC_ARGS[@]}"

  mkdir -p "$MODEL_DIR" "$HF_HOME"

  echo
  echo "== Build DFlash for CUDA arch $CUDA_ARCH =="
  cd "$DFLASH_DIR"
  cmake -B build -S . \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH"
  cmake --build build --target test_dflash dflash_server -j"$BUILD_JOBS"
}

# Common tail of the final summary; scripts append their model-specific
# server command after this.
print_common_summary() {
  cat <<EOF

============================================================
Done.
============================================================
Dev repo:     $DEV_REPO_DIR
Lucebox repo: $LUCEBOX_DIR
DFlash dir:   $DFLASH_DIR
Models:       $MODEL_DIR

Useful commands:

  # GitHub login, only needed once per machine/container
  gh auth login

  # Re-run setup (add INSTALL_SYSTEM_DEPS=1 INSTALL_PYTHON_TOOLS=1 on a non-custom image)
  cd $DEV_REPO_DIR
  bash $SETUP_SCRIPT_NAME

  # Rebuild only
  cd $DFLASH_DIR
  cmake --build build --target test_dflash dflash_server -j"$BUILD_JOBS"

EOF
}
