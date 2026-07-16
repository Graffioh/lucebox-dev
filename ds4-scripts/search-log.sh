#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/env.sh"

MODE=split
KIND=all
LOG_DIR="$RUN_ROOT/logs"
FILE=""
FOLLOW=0
SAVE=0
LIST=0

usage() {
  printf 'Usage: %s [split|hip|cuda|all] [--kind all|hc|timing|errors] [options]\n' "$0"
}

require_value() {
  (($# >= 2)) && [[ -n "$2" ]] || { printf '%s requires a value\n' "$1" >&2; exit 2; }
}

while (($#)); do
  case "$1" in
    split|hip|cuda|all) MODE="$1"; shift ;;
    --kind) require_value "$@"; KIND="$2"; shift 2 ;;
    --file) require_value "$@"; FILE="$2"; shift 2 ;;
    --log-dir) require_value "$@"; LOG_DIR="$2"; shift 2 ;;
    --follow|-f) FOLLOW=1; shift ;;
    --save) SAVE=1; shift ;;
    --list) LIST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$KIND" in
  hc) PATTERN='ds4-hc-debug|hc-boundary' ;;
  timing) PATTERN='deepseek4.*timing|split.*timing|target-shard.*timing' ;;
  errors) PATTERN='ERROR|Error:|error:|error=[^-[:space:]]|failed|failure|[Nn][Aa][Nn]|(^|[^[:alpha:]])[Ii][Nn][Ff]([^[:alpha:]]|$)' ;;
  all) PATTERN='ds4-hc-debug|hc-boundary|target-shard|split.*timing|deepseek4.*timing|chat (CACHE|DONE)|ERROR|Error:|error:|error=[^-[:space:]]|failed|failure|[Nn][Aa][Nn]|(^|[^[:alpha:]])[Ii][Nn][Ff]([^[:alpha:]]|$)' ;;
  *) printf 'Unknown kind: %s\n' "$KIND" >&2; exit 2 ;;
esac

case "$MODE" in
  split) GLOB='ds4-split*.log' ;;
  hip) GLOB='ds4-monolithic-hip*.log' ;;
  cuda) GLOB='ds4-monolithic-cuda*.log' ;;
  all) GLOB='*.log' ;;
esac

if [[ -z "$FILE" ]]; then
  shopt -s nullglob
  files=("$LOG_DIR"/$GLOB)
  shopt -u nullglob
  ((${#files[@]})) || { printf 'No %s logs in %s\n' "$MODE" "$LOG_DIR" >&2; exit 1; }

  if ((LIST)); then
    printf '%s\n' "${files[@]}"
    exit 0
  fi

  FILE="${files[0]}"
  for candidate in "${files[@]:1}"; do
    [[ "$candidate" -nt "$FILE" ]] && FILE="$candidate"
  done
elif [[ "$FILE" != /* ]]; then
  FILE="$LOG_DIR/$FILE"
fi

test -r "$FILE" || { printf 'Log not readable: %s\n' "$FILE" >&2; exit 1; }
printf 'LOG=%s KIND=%s\n' "$FILE" "$KIND" >&2

OUTPUT="${FILE%.log}-filtered-$KIND.txt"

if ((FOLLOW)); then
  if ((SAVE)); then
    printf 'OUTPUT=%s\n' "$OUTPUT" >&2
    tail -F "$FILE" | grep --line-buffered -E "$PATTERN" | tee -a "$OUTPUT"
  else
    tail -F "$FILE" | grep --line-buffered -E "$PATTERN"
  fi
  exit 0
fi

set +e
if ((SAVE)); then
  grep -E "$PATTERN" "$FILE" | tee "$OUTPUT"
  status=${PIPESTATUS[0]}
  printf 'OUTPUT=%s\n' "$OUTPUT" >&2
else
  grep -E "$PATTERN" "$FILE"
  status=$?
fi
set -e

if ((status == 1)); then
  printf 'No matching lines.\n' >&2
elif ((status > 1)); then
  exit "$status"
fi
