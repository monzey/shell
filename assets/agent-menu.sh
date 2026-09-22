#!/usr/bin/env bash
set -euo pipefail

list_agents() {
  printf '%s\n' '[
    {"kind":"agent","value":"opencode","label":"OpenCode","icon":"terminal"},
    {"kind":"agent","value":"copilot","label":"Copilot","icon":"terminal"},
    {"kind":"agent","value":"claude","label":"Claude","icon":"terminal"},
    {"kind":"agent","value":"codex","label":"Codex","icon":"terminal"},
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
  opencode | copilot | claude | codex | agy) ;;
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

  kitty --detach --directory "$repo" --hold "$agent"

  # Keep the workspace focused until Kitty maps the new window.
  sleep 0.5
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

command -v caelestia >/dev/null || {
  printf 'Missing dependency: caelestia\n' >&2
  exit 1
}

caelestia shell openvide agent "$repo"
