#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUCEBOX_DIR="$SCRIPT_DIR/lucebox-hub"
SERVER_DIR="$LUCEBOX_DIR/server"

COMMAND="${1:-help}"
if [ "$#" -gt 0 ]; then
  shift
fi

REMOTE="origin"
BRANCH=""
BUILD_TYPE="Release"
BUILD_DIR=""
BUILD_JOBS="${BUILD_JOBS:-2}"
CUDA_ARCH="${CUDA_ARCH:-}"
MODEL_PATH="${MODEL_PATH:-}"
MODEL_NAME="${MODEL_NAME:-deepseek-v4-flash}"
MAX_CTX="${MAX_CTX:-32768}"
PORT="${PORT:-8000}"
DEBUG=0
NO_BUILD=0
TARGETS=()
SERVER_EXTRA_ARGS=()

usage() {
  cat <<'EOF'
Usage: bash dev_lucebox.sh <command> [options] [-- server args]

Commands:
  doctor              Check GPU, CUDA, tools, repositories, model, and build state.
  switch              Fetch and switch lucebox-hub to a remote branch safely.
  build               Configure and incrementally build the server and unit test.
  test                Build and run test_deepseek4_unit.
  run                 Incrementally build and run DeepSeek V4 Flash.
  update-build-test   Switch branch, build, and run the unit test.
  help                 Show this help.

Common options:
  --remote NAME        Git remote used by switch (default: origin).
  --branch NAME        Branch used by switch/update-build-test.
  --cuda-arch N        CUDA architecture, e.g. 86 or 90.
  --jobs N             Parallel build jobs (default: 2).
  --debug              Use RelWithDebInfo/build-debug; run under GDB.
  --build-dir PATH     Override the CMake build directory.
  --no-build           Skip the build before test/run.
  --target NAME        Build a specific target; repeatable.

Run options:
  --model PATH         GGUF path.
  --model-name NAME    Served model name (default: deepseek-v4-flash).
  --max-ctx N          Maximum context (default: 32768).
  --port N             Server port (default: 8000).
  --                    Pass all remaining arguments to dflash_server.

Examples:
  bash dev_lucebox.sh doctor
  bash dev_lucebox.sh switch --remote origin --branch codex/my-fix
  bash dev_lucebox.sh build --cuda-arch 90 --jobs 2
  bash dev_lucebox.sh test
  bash dev_lucebox.sh run --debug
  bash dev_lucebox.sh run -- --target-device cuda:0
  bash dev_lucebox.sh update-build-test --remote origin --branch codex/my-fix
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_repo() {
  [ -d "$LUCEBOX_DIR/.git" ] || [ -f "$LUCEBOX_DIR/.git" ] ||
    die "lucebox-hub is not initialized; run git submodule update --init --recursive"
  [ -f "$SERVER_DIR/CMakeLists.txt" ] || die "server/CMakeLists.txt not found"
}

detect_cuda_arch() {
  if [ -n "$CUDA_ARCH" ]; then
    return
  fi
  if command -v nvidia-smi >/dev/null 2>&1; then
    local capability
    capability="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n1 | tr -d '. ' || true)"
    if [[ "$capability" =~ ^[0-9]+$ ]]; then
      CUDA_ARCH="$capability"
      return
    fi
  fi
  CUDA_ARCH=86
  echo "WARNING: could not detect GPU compute capability; defaulting CUDA_ARCH=86" >&2
}

resolve_build_dir() {
  detect_cuda_arch
  if [ -z "$BUILD_DIR" ]; then
    if [ "$DEBUG" = "1" ]; then
      BUILD_DIR="$SERVER_DIR/build-debug"
    else
      BUILD_DIR="$SERVER_DIR/build"
    fi
  elif [[ "$BUILD_DIR" != /* ]]; then
    BUILD_DIR="$SCRIPT_DIR/$BUILD_DIR"
  fi
}

resolve_model_path() {
  if [ -z "$MODEL_PATH" ]; then
    MODEL_PATH="$SERVER_DIR/models/deepseek-v4-flash/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2.gguf"
  elif [[ "$MODEL_PATH" != /* ]]; then
    MODEL_PATH="$SCRIPT_DIR/$MODEL_PATH"
  fi
}

parse_options() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --remote)      [ "$#" -ge 2 ] || die "--remote requires a value"; REMOTE="$2"; shift 2 ;;
      --branch)      [ "$#" -ge 2 ] || die "--branch requires a value"; BRANCH="$2"; shift 2 ;;
      --cuda-arch)   [ "$#" -ge 2 ] || die "--cuda-arch requires a value"; CUDA_ARCH="$2"; shift 2 ;;
      --jobs)        [ "$#" -ge 2 ] || die "--jobs requires a value"; BUILD_JOBS="$2"; shift 2 ;;
      --build-dir)   [ "$#" -ge 2 ] || die "--build-dir requires a value"; BUILD_DIR="$2"; shift 2 ;;
      --target)      [ "$#" -ge 2 ] || die "--target requires a value"; TARGETS+=("$2"); shift 2 ;;
      --model)       [ "$#" -ge 2 ] || die "--model requires a value"; MODEL_PATH="$2"; shift 2 ;;
      --model-name)  [ "$#" -ge 2 ] || die "--model-name requires a value"; MODEL_NAME="$2"; shift 2 ;;
      --max-ctx)     [ "$#" -ge 2 ] || die "--max-ctx requires a value"; MAX_CTX="$2"; shift 2 ;;
      --port)        [ "$#" -ge 2 ] || die "--port requires a value"; PORT="$2"; shift 2 ;;
      --debug)       DEBUG=1; shift ;;
      --no-build)    NO_BUILD=1; shift ;;
      --)            shift; SERVER_EXTRA_ARGS=("$@"); break ;;
      -h|--help)     usage; exit 0 ;;
      *)             die "unknown option: $1" ;;
    esac
  done

  [[ "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"
  if [ -n "$CUDA_ARCH" ]; then
    [[ "$CUDA_ARCH" =~ ^[0-9]+$ ]] || die "--cuda-arch must be numeric"
  fi
}

print_git_state() {
  echo "Repository: $LUCEBOX_DIR"
  echo "Branch:     $(git -C "$LUCEBOX_DIR" branch --show-current 2>/dev/null || echo detached)"
  echo "Commit:     $(git -C "$LUCEBOX_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  if [ -n "$(git -C "$LUCEBOX_DIR" status --porcelain)" ]; then
    echo "Working tree: DIRTY"
    git -C "$LUCEBOX_DIR" status --short
  else
    echo "Working tree: clean"
  fi
}

doctor() {
  require_repo
  detect_cuda_arch
  resolve_model_path

  echo "== GPU =="
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,compute_cap,memory.total --format=csv,noheader || true
  else
    echo "nvidia-smi: missing"
  fi
  echo "CUDA_ARCH: $CUDA_ARCH"

  echo
  echo "== Tools =="
  local cmd
  for cmd in nvcc cmake git gdb python3 hf uv jq; do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf '%-8s %s\n' "$cmd" "$(command -v "$cmd")"
    else
      printf '%-8s missing\n' "$cmd"
    fi
  done

  echo
  echo "== Git =="
  print_git_state
  echo "Remotes:"
  git -C "$LUCEBOX_DIR" remote -v || true

  echo
  echo "== Storage =="
  df -h "$SCRIPT_DIR" | tail -n1

  echo
  echo "== Model =="
  if [ -f "$MODEL_PATH" ]; then
    ls -lh "$MODEL_PATH"
  else
    echo "missing: $MODEL_PATH"
  fi
}

switch_branch() {
  require_repo
  [ -n "$BRANCH" ] || die "switch requires --branch"
  git -C "$LUCEBOX_DIR" remote get-url "$REMOTE" >/dev/null 2>&1 ||
    die "remote '$REMOTE' is not configured"
  [ -z "$(git -C "$LUCEBOX_DIR" status --porcelain)" ] ||
    die "lucebox-hub has local changes; commit or handle them before switching"

  echo "== Fetch $REMOTE =="
  git -C "$LUCEBOX_DIR" fetch "$REMOTE" \
    "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH"
  git -C "$LUCEBOX_DIR" show-ref --verify --quiet "refs/remotes/$REMOTE/$BRANCH" ||
    die "$REMOTE/$BRANCH was not found"

  if git -C "$LUCEBOX_DIR" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$LUCEBOX_DIR" switch "$BRANCH"
    git -C "$LUCEBOX_DIR" merge --ff-only "$REMOTE/$BRANCH"
  else
    git -C "$LUCEBOX_DIR" switch --track -c "$BRANCH" "$REMOTE/$BRANCH"
  fi
  print_git_state
}

configure_build() {
  require_repo
  resolve_build_dir
  local cmake_args=(
    -S "$SERVER_DIR"
    -B "$BUILD_DIR"
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH"
  )
  if [ "$DEBUG" = "1" ]; then
    cmake_args+=(
      -DCMAKE_BUILD_TYPE=RelWithDebInfo
      -DCMAKE_CXX_FLAGS_RELWITHDEBINFO="-O1 -g3 -fno-omit-frame-pointer"
    )
  else
    cmake_args+=(-DCMAKE_BUILD_TYPE="$BUILD_TYPE")
  fi
  echo "== Configure $(basename "$BUILD_DIR") for sm_$CUDA_ARCH =="
  cmake "${cmake_args[@]}"
}

build_targets() {
  configure_build
  if [ "${#TARGETS[@]}" -eq 0 ]; then
    TARGETS=(dflash_server test_deepseek4_unit)
  fi
  echo "== Incremental build: ${TARGETS[*]} (-j$BUILD_JOBS) =="
  cmake --build "$BUILD_DIR" --target "${TARGETS[@]}" -j"$BUILD_JOBS"
}

run_tests() {
  require_repo
  resolve_build_dir
  if [ "$NO_BUILD" != "1" ]; then
    TARGETS=(test_deepseek4_unit)
    build_targets
  fi
  local test_bin="$BUILD_DIR/test_deepseek4_unit"
  [ -x "$test_bin" ] || die "test binary not found: $test_bin"
  echo "== Run test_deepseek4_unit =="
  "$test_bin"
}

run_server() {
  require_repo
  resolve_build_dir
  resolve_model_path
  [ -f "$MODEL_PATH" ] || die "model not found: $MODEL_PATH"
  if [ "$NO_BUILD" != "1" ]; then
    TARGETS=(dflash_server)
    build_targets
  fi
  local server_bin="$BUILD_DIR/dflash_server"
  [ -x "$server_bin" ] || die "server binary not found: $server_bin"

  local args=(
    "$MODEL_PATH"
    --model-name "$MODEL_NAME"
    --max-ctx "$MAX_CTX"
    --port "$PORT"
    "${SERVER_EXTRA_ARGS[@]}"
  )
  cd "$SERVER_DIR"
  if [ "$DEBUG" = "1" ]; then
    command -v gdb >/dev/null 2>&1 || die "gdb is required for --debug"
    export CUDA_LAUNCH_BLOCKING="${CUDA_LAUNCH_BLOCKING:-1}"
    echo "== Run under GDB on port $PORT =="
    exec gdb \
      -ex "set pagination off" \
      -ex "set print thread-events off" \
      -ex "handle SIGPIPE nostop noprint pass" \
      -ex run \
      --args "$server_bin" "${args[@]}"
  fi
  echo "== Run server on port $PORT =="
  exec "$server_bin" "${args[@]}"
}

parse_options "$@"

case "$COMMAND" in
  doctor)            doctor ;;
  switch)            switch_branch ;;
  build)             build_targets ;;
  test)              run_tests ;;
  run)               run_server ;;
  update-build-test)
    switch_branch
    TARGETS=(dflash_server test_deepseek4_unit)
    build_targets
    NO_BUILD=1
    run_tests
    ;;
  help|-h|--help)    usage ;;
  *)                 die "unknown command: $COMMAND (run 'bash dev_lucebox.sh help')" ;;
esac
