#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Lucebox dev setup for Vast.ai RTX 3090
#
# Intended image:
#
#   graffioh/lucebox-dev:cuda12.4-ubuntu22.04
#
# Expected repo structure:
#
#   lucebox-dev/
#   ├── lucebox-hub/          # git submodule
#   ├── .gitmodules
#   ├── docker/
#   │   └── Dockerfile
#   └── setup_lucebox_3090.sh
#
# Run from inside lucebox-dev:
#
#   bash setup_lucebox_3090.sh
#
# For custom Docker image where deps are preinstalled:
#
#   INSTALL_SYSTEM_DEPS=0 bash setup_lucebox_3090.sh
#
# ============================================================

# -------- config --------

DEV_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUCEBOX_DIR="$DEV_REPO_DIR/lucebox-hub"

# Keep large files outside the repo.
# Default: sibling directory next to lucebox-dev.
WORK_ROOT="${WORK_ROOT:-$(dirname "$DEV_REPO_DIR")}"
MODEL_DIR="${MODEL_DIR:-$WORK_ROOT/models}"
HF_HOME="${HF_HOME:-$WORK_ROOT/.cache/huggingface}"

CUDA_ARCH="${CUDA_ARCH:-86}"   # RTX 3090 = sm_86

TARGET_REPO="${TARGET_REPO:-unsloth/Qwen3.6-27B-GGUF}"
TARGET_FILE="${TARGET_FILE:-Qwen3.6-27B-Q4_K_M.gguf}"

DRAFT_REPO="${DRAFT_REPO:-Lucebox/Qwen3.6-27B-DFlash-GGUF}"
DRAFT_FILE="${DRAFT_FILE:-dflash-draft-3.6-q8_0.gguf}"

GIT_USER_NAME="${GIT_USER_NAME:-Graffioh}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-}"

# In your custom Docker image, set this to 0.
INSTALL_SYSTEM_DEPS="${INSTALL_SYSTEM_DEPS:-0}"
INSTALL_PYTHON_TOOLS="${INSTALL_PYTHON_TOOLS:-0}"

export HF_HOME

echo "============================================================"
echo "Lucebox Dev Setup"
echo "============================================================"
echo "DEV_REPO_DIR:        $DEV_REPO_DIR"
echo "LUCEBOX_DIR:         $LUCEBOX_DIR"
echo "WORK_ROOT:           $WORK_ROOT"
echo "MODEL_DIR:           $MODEL_DIR"
echo "HF_HOME:             $HF_HOME"
echo "CUDA_ARCH:           $CUDA_ARCH"
echo "INSTALL_SYSTEM_DEPS: $INSTALL_SYSTEM_DEPS"
echo "INSTALL_PYTHON_TOOLS:$INSTALL_PYTHON_TOOLS"
echo

echo "== System check =="
nvidia-smi || true
nvcc --version || true
cmake --version || true
python3 --version || true
git --version || true
gh --version || true
hf --version || true
uv --version || true
echo

if [ "$INSTALL_SYSTEM_DEPS" = "1" ]; then
  echo "== Install system packages =="
  sudo apt-get update
  sudo apt-get install -y \
    git git-lfs gh curl wget ca-certificates \
    build-essential cmake ninja-build pkg-config \
    python3 python3-pip python3-venv python3-dev \
    gdb lldb vim nano tmux htop less ripgrep fd-find jq unzip zip rsync \
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
  echo "GIT_USER_EMAIL is not set."
  echo "Commits may fail until you configure an email:"
  echo "  git config --global user.email 'you@example.com'"
  echo "or run:"
  echo "  export GIT_USER_EMAIL='you@example.com'"
fi

echo
echo "== GitHub auth status =="
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    echo "Already authenticated with GitHub."
  else
    echo "Not authenticated with GitHub."
    echo "For pushing to GitHub, run manually:"
    echo "  gh auth login"
  fi
else
  echo "gh is not installed. Install it or rebuild the Docker image."
fi

if [ "$INSTALL_PYTHON_TOOLS" = "1" ]; then
  echo
  echo "== Install Python tools =="
  python3 -m pip install --upgrade pip setuptools wheel
  python3 -m pip install --upgrade "huggingface_hub[cli]" uv
else
  echo
  echo "== Skipping Python tool install =="
fi

echo
echo "== Verify required commands =="
required_commands=(git cmake python3 hf uv)
for cmd in "${required_commands[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd"
    echo "Either rebuild the Docker image or run:"
    echo "  INSTALL_SYSTEM_DEPS=1 INSTALL_PYTHON_TOOLS=1 bash setup_lucebox_3090.sh"
    exit 1
  fi
done

if ! command -v nvcc >/dev/null 2>&1; then
  echo "ERROR: nvcc not found."
  echo "You need a CUDA devel image, not a runtime image."
  echo "Recommended image:"
  echo "  graffioh/lucebox-dev:cuda12.4-ubuntu22.04"
  exit 1
fi

echo
echo "== Initialize/update lucebox-hub submodule =="
cd "$DEV_REPO_DIR"
git submodule update --init --recursive

if [ ! -d "$LUCEBOX_DIR" ]; then
  echo "ERROR: lucebox-hub submodule not found at $LUCEBOX_DIR"
  exit 1
fi

echo
echo "== Create model/cache directories =="
mkdir -p "$MODEL_DIR/draft"
mkdir -p "$HF_HOME"

echo
echo "== Build DFlash for CUDA arch $CUDA_ARCH =="
cd "$LUCEBOX_DIR/dflash"

cmake -B build -S . \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH"

cmake --build build --target test_dflash -j"$(nproc)"

echo
echo "== Download target GGUF if missing =="
if [ ! -f "$MODEL_DIR/$TARGET_FILE" ]; then
  hf download "$TARGET_REPO" "$TARGET_FILE" --local-dir "$MODEL_DIR"
else
  echo "Target already exists: $MODEL_DIR/$TARGET_FILE"
fi

echo
echo "== Download DFlash draft GGUF if missing =="
if [ ! -f "$MODEL_DIR/draft/$DRAFT_FILE" ]; then
  hf download "$DRAFT_REPO" "$DRAFT_FILE" --local-dir "$MODEL_DIR/draft"
else
  echo "Draft already exists: $MODEL_DIR/draft/$DRAFT_FILE"
fi

echo
echo "== Symlink models into lucebox-hub/dflash/models =="
mkdir -p "$LUCEBOX_DIR/dflash/models/draft"

ln -sf "$MODEL_DIR/$TARGET_FILE" \
  "$LUCEBOX_DIR/dflash/models/$TARGET_FILE"

ln -sf "$MODEL_DIR/draft/$DRAFT_FILE" \
  "$LUCEBOX_DIR/dflash/models/draft/$DRAFT_FILE"

echo
echo "== Smoke test =="
cd "$LUCEBOX_DIR/dflash"

python3 scripts/run.py --prompt "def fibonacci(n):"

echo
echo "============================================================"
echo "Done."
echo "============================================================"
echo "Dev repo:     $DEV_REPO_DIR"
echo "Lucebox repo: $LUCEBOX_DIR"
echo "Models:       $MODEL_DIR"
echo
echo "Useful commands:"
echo
echo "  # GitHub login, only needed once per machine/container"
echo "  gh auth login"
echo
echo "  # Re-run setup"
echo "  cd $DEV_REPO_DIR"
echo "  bash setup_lucebox_3090.sh"
echo
echo "  # Fast dev loop"
echo "  cd $LUCEBOX_DIR/dflash"
echo "  cmake --build build --target test_dflash -j\"\$(nproc)\""
echo "  python3 scripts/run.py --prompt \"Explain speculative decoding briefly.\""
echo
echo "  # If using a non-custom image"
echo "  INSTALL_SYSTEM_DEPS=1 INSTALL_PYTHON_TOOLS=1 bash setup_lucebox_3090.sh"