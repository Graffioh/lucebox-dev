#!/usr/bin/env bash
set -euo pipefail

# Build and start the DeepSeek V4 Flash server from the lucebox-dev checkout.
# Use --debug to build with symbols and run the server under GDB.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/lucebox-hub/server"

BUILD_JOBS="${BUILD_JOBS:-$(nproc 2>/dev/null || echo 8)}"
MODEL_FILE="${MODEL_FILE:-DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2.gguf}"
MODEL_PATH="${MODEL_PATH:-$SERVER_DIR/models/deepseek-v4-flash/$MODEL_FILE}"
MODEL_NAME="${MODEL_NAME:-deepseek-v4-flash}"
MAX_CTX="${MAX_CTX:-32768}"
PORT="${PORT:-8000}"

DEBUG=0
GPU="${GPU:-h200}"

usage() {
  cat <<'EOF'
Usage: bash run_deepseek_v4flash.sh [--gpu <name>] [--debug]

  no flag   Build/update the Release binary and start the server.
  --gpu     Select the GPU build target (default: h200).
  --debug   Build with debug symbols and start the server under GDB.

Supported GPUs:
  h200      NVIDIA H200, CUDA architecture sm_90

Optional environment overrides:
  GPU, CUDA_ARCH, BUILD_JOBS, MODEL_PATH, MODEL_NAME, MAX_CTX, PORT

After a debug crash, run "bt full" or "thread apply all bt full" in GDB.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --gpu)
      if [ "$#" -lt 2 ]; then
        echo "ERROR: --gpu requires a value" >&2
        usage >&2
        exit 2
      fi
      GPU="$2"
      shift 2
      ;;
    --gpu=*)
      GPU="${1#--gpu=}"
      shift
      ;;
    --debug)
      DEBUG=1
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

case "$GPU" in
  h200)
    DEFAULT_CUDA_ARCH=90
    ;;
  *)
    echo "ERROR: unsupported GPU: $GPU" >&2
    echo "Supported GPUs: h200" >&2
    exit 2
    ;;
esac

CUDA_ARCH="${CUDA_ARCH:-$DEFAULT_CUDA_ARCH}"

if [ ! -f "$SERVER_DIR/CMakeLists.txt" ]; then
  echo "ERROR: lucebox-hub server not found at $SERVER_DIR" >&2
  echo "Run the setup script first: bash setup_deepseek_v4flash_h200.sh" >&2
  exit 1
fi

if [ ! -f "$MODEL_PATH" ]; then
  echo "ERROR: model not found at $MODEL_PATH" >&2
  echo "Run the setup script first: bash setup_deepseek_v4flash_h200.sh" >&2
  exit 1
fi

if [ "$DEBUG" = "1" ]; then
  BUILD_DIR="$SERVER_DIR/build-debug"
  echo "== Build DeepSeek V4 Flash server for $GPU (sm_$CUDA_ARCH) with debug symbols =="
  cmake -B "$BUILD_DIR" -S "$SERVER_DIR" \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH" \
    -DCMAKE_CXX_FLAGS_RELWITHDEBINFO="-O1 -g3 -fno-omit-frame-pointer"
else
  BUILD_DIR="$SERVER_DIR/build"
  echo "== Build DeepSeek V4 Flash server for $GPU (sm_$CUDA_ARCH, Release) =="
  cmake -B "$BUILD_DIR" -S "$SERVER_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH"
fi

cmake --build "$BUILD_DIR" --target dflash_server -j"$BUILD_JOBS"

SERVER_ARGS=(
  "$MODEL_PATH"
  --model-name "$MODEL_NAME"
  --max-ctx "$MAX_CTX"
  --port "$PORT"
)

cd "$SERVER_DIR"

if [ "$DEBUG" = "1" ]; then
  if ! command -v gdb >/dev/null 2>&1; then
    echo "ERROR: gdb is required for --debug" >&2
    exit 1
  fi

  export CUDA_LAUNCH_BLOCKING="${CUDA_LAUNCH_BLOCKING:-1}"
  echo "== Start server under GDB (CUDA_LAUNCH_BLOCKING=$CUDA_LAUNCH_BLOCKING) =="
  echo "After a crash: bt full"
  exec gdb \
    -ex "set pagination off" \
    -ex "handle SIGPIPE nostop noprint pass" \
    -ex run \
    --args "$BUILD_DIR/dflash_server" "${SERVER_ARGS[@]}"
fi

echo "== Start server on port $PORT =="
exec "$BUILD_DIR/dflash_server" "${SERVER_ARGS[@]}"
