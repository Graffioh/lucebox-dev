# Lucebox berto dev environment

it contains:

1) github action to push on docker hub a custom image, to run lucebox-hub in a 3090 (rented on vast.ai)
2) a setup script to run when ssh'd into the GPU (build and install qwen model + dflash, as documented in lucebox-hub README)

just a way to simply reproduce the setup actions when i spin up a new gpu instance

## Steps

1) spend money on a 3090 -> [vast.ai](https://vast.ai)
2) ssh into it
3) `git clone --recurse-submodules https://github.com/Graffioh/lucebox-dev.git`
4) `bash setup_lucebox_3090.sh`
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
