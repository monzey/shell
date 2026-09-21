#!/usr/bin/env bash
set -euo pipefail

select_agent() {
  local repo="$1"
  local selection_file="$2"
  local choice

  choice=$(
    printf '%-12s\t%s\n' \
      "OpenCode" "opencode" \
      "Copilot" "copilot" \
      "Claude" "claude" \
      "Agy" "agy" |
      fzf \
        --no-multi \
        --cycle \
        --layout=reverse \
        --height=100% \
        --border=rounded \
        --info=hidden \
        --delimiter=$'\t' \
        --with-nth=1 \
        --prompt='Agent > ' \
        --header="$repo"
  ) || exit 0

  printf '%s\n' "${choice##*$'\t'}" >"$selection_file"
}

if [[ "${1:-}" == "--select" ]]; then
  select_agent "${2:-}" "${3:-}"
  exit 0
fi

repo=$(realpath -- "${1:-$PWD}")
[[ -d "$repo" ]] || {
  printf 'Repository not found: %s\n' "$repo" >&2
  exit 1
}

for dependency in kitty fzf; do
  command -v "$dependency" >/dev/null || {
    printf 'Missing dependency: %s\n' "$dependency" >&2
    exit 1
  }
done

script_path=$(realpath -- "${BASH_SOURCE[0]}")
selection_file=$(mktemp "${TMPDIR:-/tmp}/openvide-agent.XXXXXX")
trap 'rm -f "$selection_file"' EXIT

if ! kitty +kitten panel \
  --edge=center-sized \
  --layer=overlay \
  --lines=10 \
  --columns=52 \
  --focus-policy=exclusive \
  --grab-keyboard \
  --hide-on-focus-loss \
  --class=openvide-agent-menu \
  bash "$script_path" --select "$repo" "$selection_file"; then
  exit 0
fi

[[ -s "$selection_file" ]] || exit 0
IFS= read -r agent <"$selection_file"

if ! command -v "$agent" >/dev/null; then
  printf 'Agent not found: %s\n' "$agent" >&2
  exit 1
fi

kitty --detach --directory "$repo" --hold "$agent"

# Keep the workspace focused until Kitty maps the new window.
sleep 0.5
