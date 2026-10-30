#!/usr/bin/env bash
set -euo pipefail

list_agents() {
  printf '%s\n' '[
    {"kind":"agent","value":"opencode","label":"OpenCode","icon":"terminal"},
    {"kind":"agent","value":"copilot","label":"Copilot","icon":"terminal"},
    {"kind":"agent","value":"claude","label":"Claude","icon":"terminal"},
    {"kind":"agent","value":"codex","label":"Codex","icon":"terminal"},
    {"kind":"agent","value":"grok","label":"Grok","icon":"terminal"},
    {"kind":"agent","value":"agy","label":"Agy","icon":"terminal"}
  ]'
}

launch_agent() {
  local repo="$1"
  local agent="$2"

  [[ -d "$repo" ]] || {
    printf 'Repository not found: %s\n' "$repo" >&2
    exit 1
  }

  case "$agent" in
  opencode | copilot | claude | codex | grok | agy) ;;
  *)
    printf 'Unknown agent: %s\n' "$agent" >&2
    exit 1
    ;;
  esac

  command -v kitty >/dev/null || {
    printf 'Missing dependency: kitty\n' >&2
    exit 1
  }

  command -v "$agent" >/dev/null || {
    printf 'Agent not found: %s\n' "$agent" >&2
    exit 1
  }

  local script_dir
  script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  bash "$script_dir/openvide.sh" --launch-agent "$repo" "$agent"
}

case "${1:-}" in
--list)
  list_agents
  exit 0
  ;;
--launch)
  launch_agent "${2:-}" "${3:-}"
  exit 0
  ;;
esac

repo=$(realpath -- "${1:-$PWD}")
[[ -d "$repo" ]] || {
  printf 'Repository not found: %s\n' "$repo" >&2
  exit 1
}

command -v caelestia-ipc >/dev/null || {
  printf 'Missing dependency: caelestia-ipc\n' >&2
  exit 1
}

caelestia-ipc openvide agent "$repo"
