# DeepSeek4 Build/Run Cheat Sheet — lucebox3

## Scripts

### `env.sh`

No flags; sourced automatically. Optional overrides: `local.env`, `REPO`,
`SERVER`, `CUDA_BUILD`, `HIP_BUILD`, `RUN_ROOT`, `ROCM_PATH`, `HIP_CLANG`,
`JOBS`, `BUILD_TYPE`, `MODEL`, `MODEL_NAME`, `HOST`, `PORT`, `MAX_CTX`,
`CHUNK`, `TARGET_SPLIT`, `PROFILE`.

### `build.sh`

| Argument | Effect |
| --- | --- |
| `hip` | Build HIP monolithic server and daemon |
| `cuda` | Build CUDA monolithic server and daemon |
| `split` | Build both backends; default |
| `--fresh` | Reset generated CMake state before configuring |
| `--release` | `BUILD_TYPE=Release` |
| `--debug` | `BUILD_TYPE=RelWithDebInfo` |
| `--jobs N` | Parallel build jobs |
| `--tests` | Include `test_deepseek4_unit`; default |
| `--no-tests` | Build server and daemon only |
| `-h`, `--help` | Print usage |

### `run-server.sh`

| Argument | Effect |
| --- | --- |
| `hip` | Monolithic HIP; default port `8213`; default mode |
| `cuda` | Monolithic CUDA; default port `8213` |
| `split` | CUDA + HIP split; default port `8214` |
| `--profile hc\|default` | HC tracing or normal runtime profile |
| `--model PATH` | GGUF path |
| `--model-name NAME` | API model name |
| `--host HOST` | Bind address |
| `--port N` | Server port |
| `--max-ctx N` | Maximum context |
| `--chunk N` | Decode/prefill chunk size |
| `--target-split A,B` | CUDA,HIP layer weights |
| `-- SERVER_ARGS...` | Pass remaining flags to `dflash_server` |
| `-h`, `--help` | Print usage |

### `request.sh`

| Flag | Effect |
| --- | --- |
| `--host HOST` | Server host; default `127.0.0.1` |
| `--port N` | Server port; default `8213` |
| `--model NAME` | API model name; default `ds4-local` |
| `--prompt TEXT` | User prompt |
| `--max-tokens N` | Output-token limit; default `2` |
| `--temperature N` | Sampling temperature; default `0` |
| `--wait N` | Health-check timeout in seconds; default `60` |
| `-h`, `--help` | Print usage |

### `search-log.sh`

Searches `$RUN_ROOT/logs` with standard `grep`.

| Argument | Effect |
| --- | --- |
| `split` | Latest `ds4-split*.log`; default |
| `hip` | Latest monolithic HIP log |
| `cuda` | Latest monolithic CUDA log |
| `all` | Latest `.log` file |
| `--kind all` | HC, split, timing, completion, and error records; default |
| `--kind hc` | HC boundary records only |
| `--kind timing` | Timing records only |
| `--kind errors` | Errors, failures, `NaN`, and `Inf` only |
| `--file PATH` | Search a specific log |
| `--log-dir PATH` | Override `$RUN_ROOT/logs` |
| `--follow`, `-f` | Follow new matching lines |
| `--save` | Save filtered output beside the source log |
| `--list` | List matching log files |
| `-h`, `--help` | Print usage |

## 1. Environment — run in every new SSH shell

```bash
export REPO="$HOME/lucebox-hub"
export SERVER="$REPO/server"
export CUDA_BUILD="$SERVER/build-cuda-3090"
export HIP_BUILD="$SERVER/build-hip-halo"
export RUN_ROOT="$HOME/lucebox-runtime"

export ROCM_PATH=/opt/rocm
export HIP_PATH="$ROCM_PATH"
export HIP_CLANG="$ROCM_PATH/llvm/bin/clang++"
export PATH="$ROCM_PATH/bin:$PATH"
export LD_LIBRARY_PATH="$ROCM_PATH/lib:$ROCM_PATH/lib64:${LD_LIBRARY_PATH:-}"

export JOBS="${JOBS:-$(nproc)}"
export BUILD_TYPE=RelWithDebInfo  # Debugging; use Release for benchmarks

export MODEL="/opt/models/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix.gguf"  # REQUIRED: replace this
export MODEL_NAME=ds4-local
export HOST=127.0.0.1             # Use 0.0.0.0 only for remote access
export PORT=8213                  # Monolithic; use 8214 for split
export MAX_CTX=8192
export CHUNK=1                    # HC/debug; use 512 for normal throughput
export TARGET_SPLIT=10,33         # CUDA,HIP weights; lower CUDA share on OOM

mkdir -p "$RUN_ROOT/logs" "$RUN_ROOT/ipc"
cd "$REPO"
```

Find the model path if needed:

```bash
grep -nE 'MODEL|[.]gguf' "$HOME/dsv4f-server.sh"
find /opt/models "$HOME" -maxdepth 6 -type f -iname '*.gguf' 2>/dev/null
```

Preflight:

```bash
: "${REPO:?missing REPO}"
: "${SERVER:?missing SERVER}"
: "${CUDA_BUILD:?missing CUDA_BUILD}"
: "${HIP_BUILD:?missing HIP_BUILD}"
: "${RUN_ROOT:?missing RUN_ROOT}"
: "${MODEL:?missing MODEL}"
test -x "$HIP_CLANG" || { echo "Missing: $HIP_CLANG"; false; }
test -r "$MODEL" || { echo "Missing model: $MODEL"; false; }
printf 'REPO=%s\nMODEL=%s\nCUDA_BUILD=%s\nHIP_BUILD=%s\nRUN_ROOT=%s\n' \
  "$REPO" "$MODEL" "$CUDA_BUILD" "$HIP_BUILD" "$RUN_ROOT"
```

## 2. Fork and PR checkout

```bash
cd "$REPO"
git remote set-url origin https://github.com/Graffioh/lucebox-hub.git
git remote get-url upstream >/dev/null 2>&1 || \
  git remote add upstream https://github.com/Luce-Org/lucebox.git
git remote -v
```

```bash
export PR_NUMBER=503
git switch main
git status --short                       # Must be empty
git fetch upstream "pull/$PR_NUMBER/head"
git switch -c "pr-$PR_NUMBER" FETCH_HEAD # Use a new name if it already exists
git log -1 --oneline
```

Fork branch alternative:

```bash
git fetch --prune origin
git switch --track origin/codex/ds4-rocmfpx-server
```

## 3. Build CUDA — RTX 3090

```bash
cmake -S "$SERVER" -B "$CUDA_BUILD" \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  -DDFLASH27B_GPU_BACKEND=cuda \
  -DCMAKE_CUDA_ARCHITECTURES=86 \
  -DDFLASH27B_ENABLE_BSA=OFF

cmake --build "$CUDA_BUILD" \
  --target dflash_server backend_ipc_daemon test_dflash test_deepseek4_unit \
  -j"$JOBS"
```

## 4. Build HIP — Strix Halo

```bash
cmake -S "$SERVER" -B "$HIP_BUILD" \
  -DCMAKE_HIP_COMPILER="$HIP_CLANG" \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  -DCMAKE_HIP_FLAGS:STRING="-DDFLASH_WAVE_SIZE=32" \
  -DROCM_PATH="$ROCM_PATH" \
  -DDFLASH27B_GPU_BACKEND=hip \
  -DDFLASH27B_HIP_ARCHITECTURES=gfx1151 \
  -DDFLASH27B_HIP_SM80_EQUIV=ON

cmake --build "$HIP_BUILD" \
  --target dflash_server backend_ipc_daemon test_dflash test_deepseek4_unit \
  -j"$JOBS"
```

After a failed compiler/configure attempt, rerun the same configure command
with `cmake --fresh -S ...` instead of `cmake -S ...`.

Incremental rebuilds:

```bash
cmake --build "$CUDA_BUILD" --target dflash_server backend_ipc_daemon -j"$JOBS"
cmake --build "$HIP_BUILD"  --target dflash_server backend_ipc_daemon -j"$JOBS"
```

## 5. Runtime profile

HC correctness/debug:

```bash
unset DFLASH_DS4_FUSED_DECODE DFLASH_DS4_FUSED_STABLE_GRAPH
unset DFLASH_DS4_FFN_RAW_MMID DFLASH_DS4_FFN_FUSED_COMBINE
unset DFLASH_DS4_ROCMFPX_HC_GPU DFLASH_DS4_HC_DIRECT_NO_SYNC
export DFLASH_DS4_HC_CPU=1
export DFLASH_DS4_HC_DEBUG=1
export DFLASH_DS4_TIMING=1
export CHUNK=1
```

Default/benchmark alternative:

```bash
unset DFLASH_DS4_HC_CPU DFLASH_DS4_HC_DEBUG DFLASH_DS4_TIMING
unset DFLASH_DS4_FUSED_DECODE DFLASH_DS4_FUSED_STABLE_GRAPH
unset DFLASH_DS4_FFN_RAW_MMID DFLASH_DS4_FFN_FUSED_COMBINE
unset DFLASH_DS4_ROCMFPX_HC_GPU DFLASH_DS4_HC_DIRECT_NO_SYNC
export BUILD_TYPE=Release
export CHUNK=512
```

## 6. Run monolithic HIP

```bash
export PORT=8213
export LOG="$RUN_ROOT/logs/ds4-monolithic-hip-$(date +%Y%m%d-%H%M%S).log"
test -x "$HIP_BUILD/dflash_server" || { echo "Missing HIP server"; false; }

HIP_VISIBLE_DEVICES=0 \
"$HIP_BUILD/dflash_server" "$MODEL" \
  --target-device hip:0 \
  --host "$HOST" --port "$PORT" \
  --max-ctx "$MAX_CTX" --chunk "$CHUNK" \
  --prefix-cache-slots 0 --prefill-cache-slots 0 \
  --disk-prefix-cache off \
  --model-name "$MODEL_NAME" \
  2>&1 | tee "$LOG"
```

## 7. Run monolithic CUDA

```bash
export PORT=8213
export LOG="$RUN_ROOT/logs/ds4-monolithic-cuda-$(date +%Y%m%d-%H%M%S).log"
test -x "$CUDA_BUILD/dflash_server" || { echo "Missing CUDA server"; false; }

CUDA_VISIBLE_DEVICES=0 \
"$CUDA_BUILD/dflash_server" "$MODEL" \
  --target-device cuda:0 \
  --host "$HOST" --port "$PORT" \
  --max-ctx "$MAX_CTX" --chunk "$CHUNK" \
  --prefix-cache-slots 0 --prefill-cache-slots 0 \
  --disk-prefix-cache off \
  --model-name "$MODEL_NAME" \
  2>&1 | tee "$LOG"
```

## 8. Run split CUDA + HIP

```bash
export PORT=8214
export IPC_DIR="$RUN_ROOT/ipc/ds4-target-$(date +%Y%m%d-%H%M%S)"
export LOG="$RUN_ROOT/logs/ds4-split-cuda-hip-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$IPC_DIR"
test -x "$CUDA_BUILD/dflash_server" || { echo "Missing CUDA server"; false; }
test -x "$HIP_BUILD/backend_ipc_daemon" || { echo "Missing HIP IPC daemon"; false; }

CUDA_VISIBLE_DEVICES=0 HIP_VISIBLE_DEVICES=0 \
"$CUDA_BUILD/dflash_server" "$MODEL" \
  --target-devices cuda:0,hip:0 \
  --target-layer-split "$TARGET_SPLIT" \
  --target-shard-ipc-bin "$HIP_BUILD/backend_ipc_daemon" \
  --target-shard-ipc-work-dir "$IPC_DIR" \
  --host "$HOST" --port "$PORT" \
  --max-ctx "$MAX_CTX" --chunk "$CHUNK" \
  --prefix-cache-slots 0 --prefill-cache-slots 0 \
  --disk-prefix-cache off \
  --model-name "$MODEL_NAME" \
  2>&1 | tee "$LOG"
```

## 9. Request and logs

```bash
until curl -sf "http://$HOST:$PORT/health" >/dev/null; do sleep 1; done

curl -sS "http://$HOST:$PORT/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL_NAME\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in one short sentence.\"}],\"temperature\":0,\"max_tokens\":2,\"stream\":false}" \
  | python3 -m json.tool
```

```bash
rg '\[ds4-hc-debug\]' "$LOG"
rg '\[deepseek4-(split-|target-)?timing\]|\[deepseek4-timing\]' "$LOG"
pgrep -af 'dflash_server|backend_ipc_daemon'
```

## 10. Unit tests

```bash
CUDA_VISIBLE_DEVICES=0 "$CUDA_BUILD/test_deepseek4_unit"
HIP_VISIBLE_DEVICES=0  "$HIP_BUILD/test_deepseek4_unit"
```
