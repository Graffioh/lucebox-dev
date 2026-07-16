#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/env.sh"

MODE="split"
FRESH=0
BUILD_TESTS="${BUILD_TESTS:-1}"

usage() {
  printf 'Usage: %s [hip|cuda|split] [--fresh] [--release|--debug] [--jobs N] [--tests|--no-tests]\n' "$0"
}

require_value() {
  (($# >= 2)) && [[ -n "$2" ]] || { printf '%s requires a value\n' "$1" >&2; exit 2; }
}

while (($#)); do
  case "$1" in
    hip|cuda|split) MODE="$1" ;;
    --fresh) FRESH=1 ;;
    --release) BUILD_TYPE=Release ;;
    --debug) BUILD_TYPE=RelWithDebInfo ;;
    --jobs) require_value "$@"; JOBS="$2"; shift ;;
    --tests) BUILD_TESTS=1 ;;
    --no-tests) BUILD_TESTS=0 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

build_targets() {
  local build_dir="$1"
  local targets=(dflash_server backend_ipc_daemon)
  if [[ "$BUILD_TESTS" == 1 ]]; then
    targets+=(test_deepseek4_unit)
  fi
  cmake --build "$build_dir" --target "${targets[@]}" -j"$JOBS"
}

build_cuda() {
  local extra=()
  if ((FRESH)); then extra+=(--fresh); fi

  cmake "${extra[@]}" -S "$SERVER" -B "$CUDA_BUILD" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DDFLASH27B_GPU_BACKEND=cuda \
    -DCMAKE_CUDA_ARCHITECTURES=86 \
    -DDFLASH27B_ENABLE_BSA=OFF

  build_targets "$CUDA_BUILD"
}

build_hip() {
  local extra=()
  if ((FRESH)); then extra+=(--fresh); fi
  test -x "$HIP_CLANG" || { printf 'Missing ROCm Clang: %s\n' "$HIP_CLANG" >&2; exit 1; }

  cmake "${extra[@]}" -S "$SERVER" -B "$HIP_BUILD" \
    -DCMAKE_HIP_COMPILER="$HIP_CLANG" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_HIP_FLAGS:STRING="-DDFLASH_WAVE_SIZE=32" \
    -DROCM_PATH="$ROCM_PATH" \
    -DDFLASH27B_GPU_BACKEND=hip \
    -DDFLASH27B_HIP_ARCHITECTURES=gfx1151 \
    -DDFLASH27B_HIP_SM80_EQUIV=ON

  build_targets "$HIP_BUILD"
}

case "$MODE" in
  hip) build_hip ;;
  cuda) build_cuda ;;
  split) build_cuda; build_hip ;;
esac
