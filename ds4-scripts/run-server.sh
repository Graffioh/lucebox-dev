#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/env.sh"

MODE=hip
EXTRA_ARGS=()

usage() {
  printf 'Usage: %s [hip|cuda|split] [options] [-- SERVER_ARGS...]\n' "$0"
}

require_value() {
  (($# >= 2)) && [[ -n "$2" ]] || { printf '%s requires a value\n' "$1" >&2; exit 2; }
}

while (($#)); do
  case "$1" in
    hip|cuda|split) MODE="$1"; shift ;;
    --profile) require_value "$@"; PROFILE="$2"; shift 2 ;;
    --model) require_value "$@"; MODEL="$2"; shift 2 ;;
    --model-name) require_value "$@"; MODEL_NAME="$2"; shift 2 ;;
    --host) require_value "$@"; HOST="$2"; shift 2 ;;
    --port) require_value "$@"; PORT="$2"; shift 2 ;;
    --max-ctx) require_value "$@"; MAX_CTX="$2"; shift 2 ;;
    --chunk) require_value "$@"; CHUNK="$2"; shift 2 ;;
    --target-split) require_value "$@"; TARGET_SPLIT="$2"; shift 2 ;;
    --) shift; EXTRA_ARGS=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$MODEL" ]] || { printf 'Set MODEL or create %s/local.env\n' "$SCRIPT_DIR" >&2; exit 1; }
test -r "$MODEL" || { printf 'Model not readable: %s\n' "$MODEL" >&2; exit 1; }

unset DFLASH_DS4_FUSED_DECODE DFLASH_DS4_FUSED_STABLE_GRAPH
unset DFLASH_DS4_FFN_RAW_MMID DFLASH_DS4_FFN_FUSED_COMBINE
unset DFLASH_DS4_ROCMFPX_HC_GPU DFLASH_DS4_HC_DIRECT_NO_SYNC

case "$PROFILE" in
  hc)
    export DFLASH_DS4_HC_CPU=1
    export DFLASH_DS4_HC_DEBUG=1
    export DFLASH_DS4_TIMING=1
    CHUNK="${CHUNK:-1}"
    ;;
  default)
    unset DFLASH_DS4_HC_CPU DFLASH_DS4_HC_DEBUG DFLASH_DS4_TIMING
    CHUNK="${CHUNK:-512}"
    ;;
  *) printf 'Unknown PROFILE: %s\n' "$PROFILE" >&2; exit 2 ;;
esac

common_args=(
  "$MODEL"
  --host "$HOST"
  --max-ctx "$MAX_CTX"
  --chunk "$CHUNK"
  --prefix-cache-slots 0
  --prefill-cache-slots 0
  --disk-prefix-cache off
  --model-name "$MODEL_NAME"
)

case "$MODE" in
  hip)
    PORT="${PORT:-8213}"
    BIN="$HIP_BUILD/dflash_server"
    LOG="$RUN_ROOT/logs/ds4-monolithic-hip-$(date +%Y%m%d-%H%M%S).log"
    test -x "$BIN" || { printf 'Missing binary: %s\n' "$BIN" >&2; exit 1; }
    printf 'URL=http://%s:%s LOG=%s\n' "$HOST" "$PORT" "$LOG"
    HIP_VISIBLE_DEVICES=0 "$BIN" "${common_args[@]}" \
      --target-device hip:0 --port "$PORT" "${EXTRA_ARGS[@]}" 2>&1 | tee "$LOG"
    ;;
  cuda)
    PORT="${PORT:-8213}"
    BIN="$CUDA_BUILD/dflash_server"
    LOG="$RUN_ROOT/logs/ds4-monolithic-cuda-$(date +%Y%m%d-%H%M%S).log"
    test -x "$BIN" || { printf 'Missing binary: %s\n' "$BIN" >&2; exit 1; }
    printf 'URL=http://%s:%s LOG=%s\n' "$HOST" "$PORT" "$LOG"
    CUDA_VISIBLE_DEVICES=0 "$BIN" "${common_args[@]}" \
      --target-device cuda:0 --port "$PORT" "${EXTRA_ARGS[@]}" 2>&1 | tee "$LOG"
    ;;
  split)
    PORT="${PORT:-8214}"
    BIN="$CUDA_BUILD/dflash_server"
    IPC_BIN="$HIP_BUILD/backend_ipc_daemon"
    IPC_DIR="$RUN_ROOT/ipc/ds4-target-$(date +%Y%m%d-%H%M%S)"
    LOG="$RUN_ROOT/logs/ds4-split-cuda-hip-$(date +%Y%m%d-%H%M%S).log"
    mkdir -p "$IPC_DIR"
    test -x "$BIN" || { printf 'Missing binary: %s\n' "$BIN" >&2; exit 1; }
    test -x "$IPC_BIN" || { printf 'Missing binary: %s\n' "$IPC_BIN" >&2; exit 1; }
    printf 'URL=http://%s:%s LOG=%s IPC_DIR=%s\n' "$HOST" "$PORT" "$LOG" "$IPC_DIR"
    CUDA_VISIBLE_DEVICES=0 HIP_VISIBLE_DEVICES=0 \
      "$BIN" "${common_args[@]}" \
      --target-devices cuda:0,hip:0 \
      --target-layer-split "$TARGET_SPLIT" \
      --target-shard-ipc-bin "$IPC_BIN" \
      --target-shard-ipc-work-dir "$IPC_DIR" \
      --port "$PORT" "${EXTRA_ARGS[@]}" 2>&1 | tee "$LOG"
    ;;
esac
