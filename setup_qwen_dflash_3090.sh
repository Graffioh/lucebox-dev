#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Lucebox Qwen DFlash dev setup for Vast.ai RTX 3090
#
# Downloads a Qwen target GGUF + DFlash draft, builds DFlash and
# runs a smoke test.
#
# Intended image: graffioh/lucebox-dev:cuda12.4-ubuntu22.04-amd64
#
# Run from inside lucebox-dev:
#
#   bash setup_qwen_dflash_3090.sh
#   bash setup_qwen_dflash_3090.sh --model qwen35dflash
#
# On a vanilla image where deps are not preinstalled:
#
#   INSTALL_SYSTEM_DEPS=1 INSTALL_PYTHON_TOOLS=1 bash setup_qwen_dflash_3090.sh
# ============================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup_common.sh"

SETUP_MODEL="${SETUP_MODEL:-qwen36dflash}"

usage() {
  cat <<'EOF'
Usage: bash setup_qwen_dflash_3090.sh [--model qwen36dflash|qwen35dflash]

Models:
  qwen36dflash  Qwen3.6-27B target + Lucebox GGUF DFlash draft (default)
  qwen35dflash  Qwen3.5-27B target + z-lab safetensors DFlash draft
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --model)
      if [ "$#" -lt 2 ]; then
        echo "ERROR: --model requires a value" >&2
        usage >&2
        exit 2
      fi
      SETUP_MODEL="$2"
      shift 2
      ;;
    --model=*)
      SETUP_MODEL="${1#--model=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# Per-model defaults (env vars override).
DRAFT_EXTRA_FILES=()
case "$SETUP_MODEL" in
  qwen36dflash)
    TARGET_REPO="${TARGET_REPO:-unsloth/Qwen3.6-27B-GGUF}"
    TARGET_FILE="${TARGET_FILE:-Qwen3.6-27B-Q4_K_M.gguf}"
    DRAFT_REPO="${DRAFT_REPO:-Lucebox/Qwen3.6-27B-DFlash-GGUF}"
    DRAFT_FILE="${DRAFT_FILE:-dflash-draft-3.6-q4_k_m.gguf}"
    ;;
  qwen35dflash)
    TARGET_REPO="${TARGET_REPO:-unsloth/Qwen3.5-27B-GGUF}"
    TARGET_FILE="${TARGET_FILE:-Qwen3.5-27B-Q4_K_M.gguf}"
    DRAFT_REPO="${DRAFT_REPO:-z-lab/Qwen3.5-27B-DFlash}"
    DRAFT_FILE="${DRAFT_FILE:-model.safetensors}"
    DRAFT_LOCAL_DIR="${DRAFT_LOCAL_DIR:-$MODEL_DIR/draft/qwen35-dflash}"
    DRAFT_EXTRA_FILES=(config.json)
    ;;
  *)
    echo "ERROR: unsupported --model '$SETUP_MODEL'" >&2
    usage >&2
    exit 2
    ;;
esac
DRAFT_LOCAL_DIR="${DRAFT_LOCAL_DIR:-$MODEL_DIR/draft}"

# Where the draft lands inside lucebox-hub/server: default drafts go flat
# under models/draft, custom DRAFT_LOCAL_DIRs get a per-model subdir.
if [ "$DRAFT_LOCAL_DIR" = "$MODEL_DIR/draft" ]; then
  SERVER_DRAFT_DIR="models/draft"
else
  SERVER_DRAFT_DIR="models/draft/$SETUP_MODEL"
fi
SERVER_DRAFT_PATH="$SERVER_DRAFT_DIR/$DRAFT_FILE"

echo "============================================================"
echo "Lucebox Qwen DFlash Setup (RTX 3090)"
echo "============================================================"
print_common_config
cat <<EOF
SETUP_MODEL:         $SETUP_MODEL
TARGET:              $TARGET_REPO / $TARGET_FILE
DRAFT:               $DRAFT_REPO / $DRAFT_FILE

EOF

run_common_setup

download_if_missing "Qwen target GGUF" "$TARGET_REPO" "$MODEL_DIR" "$TARGET_FILE"
download_if_missing "Qwen DFlash draft" "$DRAFT_REPO" "$DRAFT_LOCAL_DIR" \
  "$DRAFT_FILE" ${DRAFT_EXTRA_FILES[@]+"${DRAFT_EXTRA_FILES[@]}"}

echo
echo "== Symlink models into lucebox-hub/server/models =="
mkdir -p "$DFLASH_DIR/$SERVER_DRAFT_DIR"
ln -sf "$MODEL_DIR/$TARGET_FILE" "$DFLASH_DIR/models/$TARGET_FILE"
for f in "$DRAFT_FILE" ${DRAFT_EXTRA_FILES[@]+"${DRAFT_EXTRA_FILES[@]}"}; do
  if [ -f "$DRAFT_LOCAL_DIR/$f" ]; then
    ln -sf "$DRAFT_LOCAL_DIR/$f" "$DFLASH_DIR/$SERVER_DRAFT_DIR/$f"
  fi
done

echo
echo "== Smoke test =="
cd "$DFLASH_DIR"
uv run --frozen --no-sync python scripts/run.py \
  --target "models/$TARGET_FILE" \
  --draft "$SERVER_DRAFT_PATH" \
  --prompt "def fibonacci(n):"

print_common_summary
cat <<EOF
  # Smoke test again
  cd $DFLASH_DIR
  uv run --frozen --no-sync python scripts/run.py --prompt "Explain speculative decoding briefly."

  # Start the OpenAI-compatible server
  cd $DFLASH_DIR
  DFLASH27B_KV_TQ3=1 ./build/dflash_server models/$TARGET_FILE \\
    --draft $SERVER_DRAFT_PATH --ddtree --ddtree-budget 22 --fa-window 2048 --port 8000
EOF
