# Lucebox GPU development environment

Reproducible CUDA development environment for `lucebox-hub`.

## Supported images

| GPU | CUDA arch | Docker image |
| --- | ---: | --- |
| RTX 3090 | `sm_86` | `graffioh/lucebox-dev:cuda12.4-ubuntu22.04-3090-amd64` |
| H200 | `sm_90` | `graffioh/lucebox-dev:cuda12.4-ubuntu22.04-h200-amd64` |

## First setup

```bash
git clone --recurse-submodules https://github.com/Graffioh/lucebox-dev.git
cd lucebox-dev
bash dev_lucebox.sh doctor
```

Download or link the desired GGUF under `lucebox-hub/server/models`. For the
default DeepSeek V4 Flash H200 workflow:

```bash
mkdir -p lucebox-hub/server/models/deepseek-v4-flash

hf download antirez/deepseek-v4-gguf \
  DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2.gguf \
  --local-dir lucebox-hub/server/models/deepseek-v4-flash

bash dev_lucebox.sh build
```

For another model, pass its path with `dev_lucebox.sh run --model PATH`.

## Daily workflow

Use `dev_lucebox.sh` after the initial setup. Run every command from `/lucebox-dev`.

```bash
bash dev_lucebox.sh doctor
```

(This reports the GPU and compute capability, CUDA arch, required tools, Git
branch/remotes/dirty state, storage, and model path.)

### Switch to a remote branch (optional)

```bash
bash dev_lucebox.sh switch \
  --remote origin \
  --branch codex/fix-ds4-layer-split-sampling
```

For upstream branches, configure the remote once:

```bash
git -C lucebox-hub remote add upstream https://github.com/Luce-Org/lucebox.git
```

Then:

```bash
bash dev_lucebox.sh switch \
  --remote upstream \
  --branch codex/ds4-rocmfpx-server
```

### Incremental rebuild

```bash
bash dev_lucebox.sh build
```

The default build compiles:

```text
dflash_server
test_deepseek4_unit
```

Useful variants:

```bash
bash dev_lucebox.sh build --target dflash_server
bash dev_lucebox.sh build --cuda-arch 90 --jobs 2
bash dev_lucebox.sh build --debug
```

Build parallelism defaults to two jobs because CUDA translation units can use
substantial CPU memory. Override it with `--jobs` or `BUILD_JOBS`.

### Run unit tests (to expand if needed)

```bash
bash dev_lucebox.sh test
```

(Right now this incrementally builds and runs `test_deepseek4_unit`)

```bash
bash dev_lucebox.sh test --no-build # to not rebuild
```

### Run DeepSeek V4 Flash (to expand to other models)

```bash
bash dev_lucebox.sh run
```

`run` rebuilds `dflash_server` incrementally before starting it. Common
overrides:

```bash
bash dev_lucebox.sh run \
  --model /workspace/models/deepseek-v4-flash/model.gguf \
  --max-ctx 32768 \
  --port 8000
```

Pass additional server flags after `--`:

```bash
bash dev_lucebox.sh run -- --target-device cuda:0
```

Run a symbolized build under GDB for debugging:

```bash
bash dev_lucebox.sh run --debug
```

```gdb
bt full
thread apply all bt full
```

### Update, build, and test

```bash
bash dev_lucebox.sh update-build-test \
  --remote origin \
  --branch codex/fix-ds4-layer-split-sampling
```

This performs the safe branch switch, incremental server/test build, and unit
test in one command.

## Test the HTTP server

With the server running, use a second terminal:

```bash
curl -sS http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "deepseek-v4-flash",
    "messages": [
      {"role": "user", "content": "Where the best pizza is made?"}
    ],
    "temperature": 0.01,
    "seed": 42,
    "max_tokens": 32
  }' | jq
```

## Docker image workflow

Normal C++ changes require only `dev_lucebox.sh build`; they do not require a
new Docker image. Rebuild the image only when changing the toolchain or
dependencies in `docker/Dockerfile`.

The GitHub workflow publishes both CUDA architectures when the Dockerfile or
workflow changes. Validate Dockerfile syntax locally with:

```bash
docker buildx build --check -f docker/Dockerfile .
```
