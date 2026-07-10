#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Lucebox DeepSeek V4 Flash dev setup for Vast.ai H200
# (target-only, no DFlash draft)
#
# Downloads the DeepSeek V4 Flash target GGUF (~102 GB) for
# lucebox-hub's deepseek4 backend and builds DFlash.
#
# Defaults to CUDA_ARCH=90 (H200 = sm_90). For a different GPU,
# override the arch:
#
#   CUDA_ARCH=86 bash setup_deepseek_v4flash_h200.sh
#
# Intended image: graffioh/lucebox-dev:cuda12.4-ubuntu22.04-h200-amd64
# Note: the 3090 image exports CUDA_ARCH=86, which wins over this
# script's default — a warning below catches that mismatch.
#
# Run from inside lucebox-dev:
#
#   bash setup_deepseek_v4flash_h200.sh
#
# On a vanilla image where deps are not preinstalled:
#
#   INSTALL_SYSTEM_DEPS=1 INSTALL_PYTHON_TOOLS=1 bash setup_deepseek_v4flash_h200.sh
# ============================================================

# H200 = sm_90. Must be set before sourcing common, whose default is the 3090's 86.
CUDA_ARCH="${CUDA_ARCH:-90}"
INTENDED_IMAGE="${INTENDED_IMAGE:-graffioh/lucebox-dev:cuda12.4-ubuntu22.04-h200-amd64}"

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup_common.sh"

case "${1:-}" in
  "") ;;
  -h|--help)
    echo "Usage: bash setup_deepseek_v4flash_h200.sh   (configure via env vars, see header comment)"
    exit 0
    ;;
  *)
    echo "ERROR: unknown argument: $1 (this script takes no arguments)" >&2
    exit 2
    ;;
esac

DEEPSEEK_V4_FLASH_REPO="${DEEPSEEK_V4_FLASH_REPO:-Lucebox/DeepSeek-V4-Flash-ROCMFPX}"
DEEPSEEK_V4_FLASH_FILE="${DEEPSEEK_V4_FLASH_FILE:-DeepSeek-V4-Flash-ROCMFP2-STRIX.gguf}"
DEEPSEEK_V4_FLASH_DIR="${DEEPSEEK_V4_FLASH_DIR:-$MODEL_DIR/deepseek-v4-flash}"

echo "============================================================"
echo "Lucebox DeepSeek V4 Flash Setup (H200)"
echo "============================================================"
print_common_config
cat <<EOF
DEEPSEEK_REPO:       $DEEPSEEK_V4_FLASH_REPO
DEEPSEEK_FILE:       $DEEPSEEK_V4_FLASH_FILE
DEEPSEEK_DIR:        $DEEPSEEK_V4_FLASH_DIR

EOF

if [ "$CUDA_ARCH" != "90" ]; then
  echo "WARNING: building for CUDA_ARCH=$CUDA_ARCH, but the H200 is sm_90."
  echo "         The 3090 image exports CUDA_ARCH=86; on an H200 run:"
  echo "           CUDA_ARCH=90 bash $SETUP_SCRIPT_NAME"
  echo
fi

run_common_setup

download_if_missing "DeepSeek V4 Flash GGUF" \
  "$DEEPSEEK_V4_FLASH_REPO" "$DEEPSEEK_V4_FLASH_DIR" "$DEEPSEEK_V4_FLASH_FILE"

echo
echo "== Symlink model into lucebox-hub/server/models =="
mkdir -p "$DFLASH_DIR/models/deepseek-v4-flash"
ln -sf "$DEEPSEEK_V4_FLASH_DIR/$DEEPSEEK_V4_FLASH_FILE" \
  "$DFLASH_DIR/models/deepseek-v4-flash/$DEEPSEEK_V4_FLASH_FILE"

print_common_summary
cat <<EOF
  # Start DeepSeek V4 Flash target-only (large model, no draft)
  cd $DFLASH_DIR
  ./build/dflash_server models/deepseek-v4-flash/$DEEPSEEK_V4_FLASH_FILE \\
    --model-name deepseek-v4-flash --max-ctx 32768 --port 8000

  # If the server OOMs, lower the context: --max-ctx 8192
EOF
