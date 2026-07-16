#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/env.sh"

PROMPT="Say hello in one short sentence."
MAX_TOKENS=2
TEMPERATURE=0
WAIT_SECONDS=60
PORT="${PORT:-8213}"

usage() {
  printf 'Usage: %s [--host HOST] [--port N] [--model NAME] [--prompt TEXT] [--max-tokens N] [--temperature N] [--wait N]\n' "$0"
}

require_value() {
  (($# >= 2)) && [[ -n "$2" ]] || { printf '%s requires a value\n' "$1" >&2; exit 2; }
}

while (($#)); do
  case "$1" in
    --host) require_value "$@"; HOST="$2"; shift 2 ;;
    --port) require_value "$@"; PORT="$2"; shift 2 ;;
    --model) require_value "$@"; MODEL_NAME="$2"; shift 2 ;;
    --prompt) require_value "$@"; PROMPT="$2"; shift 2 ;;
    --max-tokens) require_value "$@"; MAX_TOKENS="$2"; shift 2 ;;
    --temperature) require_value "$@"; TEMPERATURE="$2"; shift 2 ;;
    --wait) require_value "$@"; WAIT_SECONDS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

ready=0
for ((i = 0; i < WAIT_SECONDS; i++)); do
  if curl -sf "http://$HOST:$PORT/health" >/dev/null; then
    ready=1
    break
  fi
  sleep 1
done
((ready)) || { printf 'Server not ready: http://%s:%s\n' "$HOST" "$PORT" >&2; exit 1; }

PAYLOAD="$(
  PROMPT="$PROMPT" MODEL_NAME="$MODEL_NAME" MAX_TOKENS="$MAX_TOKENS" TEMPERATURE="$TEMPERATURE" \
    python3 -c 'import json, os; print(json.dumps({"model": os.environ["MODEL_NAME"], "messages": [{"role": "user", "content": os.environ["PROMPT"]}], "temperature": float(os.environ["TEMPERATURE"]), "max_tokens": int(os.environ["MAX_TOKENS"]), "stream": False}))'
)"

curl --fail-with-body -sS "http://$HOST:$PORT/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD" | python3 -m json.tool
