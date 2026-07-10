# Lucebox berto dev environment

it contains:

1) github action to push custom images on docker hub (one Dockerfile, `CUDA_ARCH` build-arg picks the GPU), to run lucebox-hub on vast.ai:
   - `graffioh/lucebox-dev:cuda12.4-ubuntu22.04-amd64` — RTX 3090 / sm_86 (also tagged `-3090-amd64`)
   - `graffioh/lucebox-dev:cuda12.4-ubuntu22.04-h200-amd64` — H200 / sm_90
2) setup scripts to run when ssh'd into the GPU (as documented in lucebox-hub README):
   - `setup_qwen_dflash_3090.sh` — qwen target + dflash draft (RTX 3090)
   - `setup_deepseek_v4flash_h200.sh` — deepseek v4 flash target-only, ~102 GB (H200)
   - `setup_common.sh` — shared steps sourced by both, not run directly

just a way to simply reproduce the setup actions when i spin up a new gpu instance

## Steps

1) spend money on a 3090 (qwen) or H200 (deepseek) -> [vast.ai](https://vast.ai)
2) ssh into it
3) `git clone --recurse-submodules https://github.com/Graffioh/lucebox-dev.git`
4) `bash setup_qwen_dflash_3090.sh` (or `bash setup_deepseek_v4flash_h200.sh` for deepseek)
5) start lucebox server:

e.g. 

```sh
DFLASH27B_KV_TQ3=1 \
./lucebox-hub/server/build/dflash_server lucebox-hub/server/models/Qwen3.6-27B-Q4_K_M.gguf \
  --draft lucebox-hub/server/models/draft/dflash-draft-3.6-q4_k_m.gguf \
  --ddtree \
  --ddtree-budget 22 \
  --fa-window 2048 \
  --port 8000
```

from a 2nd terminal:

```sh
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "lucebox",
    "messages": [
      {"role": "user", "content": "In which city I can eat the best pizza?"}
    ],
    "max_tokens": 128,
    "temperature": 0
  }'
```

*optionally `gh auth login` to push changes*
