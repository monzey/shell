#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
project_root="$HOME"
max_depth="4"

mkdir -p "$HOME/.cache/nvim"

json_list() {
  jq -Rn '[inputs | split("\t") | select(length >= 3) | select(.[0] != "") | {kind: .[0], value: .[1], label: .[2]}]'
}

get_proj() {
  local dir="$1"
  if [[ "$dir" == *".worktrees/"* ]]; then
    local branch repo_name
    branch=$(basename "$dir")
    repo_name=$(basename "$(dirname "$dir")" | sed 's/\.worktrees$//')
    echo "$repo_name-$branch"
  else
    basename "$dir"
  fi
}

has_three_monitors() {
  (( $(hyprctl monitors -j | jq 'length') >= 3 ))
}

switch_set() {
  local proj="$1"
  [[ -n "$proj" ]] || exit 0

  if ! has_three_monitors; then
    hyprctl dispatch "hl.dsp.focus({ workspace = \"name:$proj-code\" })"
    return
  fi

  hyprctl dispatch "hl.dsp.workspace.move({ workspace = \"name:$proj-lazygit\",  monitor = \"DP-6\" })"
  hyprctl dispatch "hl.dsp.workspace.move({ workspace = \"name:$proj-code\",     monitor = \"DP-7\" })"
  hyprctl dispatch "hl.dsp.workspace.move({ workspace = \"name:$proj-opencode\", monitor = \"DP-5\" })"
  hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-6" })'
  hyprctl dispatch "hl.dsp.focus({ workspace = \"name:$proj-lazygit\" })"
  hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-5" })'
  hyprctl dispatch "hl.dsp.focus({ workspace = \"name:$proj-opencode\" })"
  hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-7" })'
  hyprctl dispatch "hl.dsp.focus({ workspace = \"name:$proj-code\" })"
}

create_set() {
  local proj="$1"
  local dir="$2"
  local socket="$HOME/.cache/nvim/$proj.pipe"

  rm -f "$socket"

  if ! has_three_monitors; then
    hyprctl dispatch "hl.dsp.focus({ workspace = \"name:$proj-code\" })"
    hyprctl dispatch "hl.dsp.exec_cmd(\"kitty -d $dir --hold zsh -c 'lazygit'\")"
    hyprctl dispatch "hl.dsp.exec_cmd(\"kitty -d $dir --hold zsh -c 'opencode-fhs'\")"
    hyprctl dispatch "hl.dsp.exec_cmd(\"bash -c 'cd $dir && neovide -- --listen $socket'\")"
    return
  fi

  hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-6" })'
  hyprctl dispatch "hl.dsp.focus({ workspace = \"name:$proj-lazygit\" })"
  hyprctl dispatch "hl.dsp.exec_cmd(\"kitty -d $dir --hold zsh -c 'lazygit'\")"

  hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-5" })'
  hyprctl dispatch "hl.dsp.focus({ workspace = \"name:$proj-opencode\" })"
  hyprctl dispatch "hl.dsp.exec_cmd(\"kitty -d $dir --hold zsh -c 'opencode-fhs'\")"

  hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-7" })'
  hyprctl dispatch "hl.dsp.focus({ workspace = \"name:$proj-code\" })"
  hyprctl dispatch "hl.dsp.exec_cmd(\"bash -c 'cd $dir && neovide -- --listen $socket'\")"

  sleep 0.5
  switch_set "$proj"
}

list_projects() {
  {
    printf 'action\t__new_worktree__\t[nouveau worktree]\n'
    find "$project_root" -maxdepth "$max_depth" -name ".git" -not -path "*/node_modules/*" 2>/dev/null \
      | sed 's|/.git$||' \
      | sed "s|^$HOME/||" \
      | sort \
      | while IFS= read -r repo; do printf 'project\t%s\t%s\n' "$repo" "$repo"; done
  } | json_list
}

list_repos() {
  find "$project_root" -maxdepth "$max_depth" -name ".git" -type d -not -path "*/node_modules/*" 2>/dev/null \
    | sed 's|/.git$||' \
    | sed "s|^$HOME/||" \
    | sort \
    | while IFS= read -r repo; do printf 'repo\t%s\t%s\n' "$repo" "$repo"; done \
    | json_list
}

list_branches() {
  local repo="$1"
  local repo_path="$HOME/$repo"
  {
    printf 'action\t__new_branch__\t[nouvelle branche]\n'
    git -C "$repo_path" branch -r 2>/dev/null \
      | grep -v 'HEAD' \
      | sed 's|.*origin/||' \
      | sed 's/^[[:space:]]*//' \
      | sort \
      | while IFS= read -r branch; do printf 'branch\t%s\t%s\n' "$branch" "$branch"; done \
      || true
  } | json_list
}

list_sets() {
  hyprctl workspaces -j \
    | jq -r '.[] | select(.name | endswith("-code")) | .name[:-5]' \
    | sort \
    | while IFS= read -r proj; do printf 'set\t%s\t%s\n' "$proj" "$proj"; done \
    | json_list
}

open_project() {
  local rel="$1"
  local dir
  dir=$(realpath "$HOME/$rel")
  [[ -d "$dir" ]] || exit 0

  local proj
  proj=$(get_proj "$dir")
  if hyprctl workspaces -j | jq -e --arg n "$proj-code" '.[] | select(.name == $n)' > /dev/null 2>&1; then
    switch_set "$proj"
  else
    create_set "$proj" "$dir"
  fi
}

create_worktree() {
  local repo="$1"
  local branch="$2"
  local wt_name="${3:-$2}"
  local repo_path="$HOME/$repo"
  local repo_parent repo_name wt_dir wt_path base

  [[ -d "$repo_path" && -n "$branch" ]] || exit 0

  repo_parent=$(dirname "$repo_path")
  repo_name=$(basename "$repo_path")
  if [[ "$repo_parent" == *".worktrees" ]]; then
    wt_dir="$repo_parent"
  else
    wt_dir="$repo_parent/$repo_name.worktrees"
  fi

  wt_path="$wt_dir/$wt_name"
  mkdir -p "$wt_dir"

  base=$(git -C "$repo_path" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||' || true)
  [[ -z "$base" ]] && base=$(git -C "$repo_path" branch --show-current 2>/dev/null || true)
  [[ -z "$base" ]] && base="main"

  if git -C "$repo_path" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$repo_path" worktree add "$wt_path" "$branch"
  elif git -C "$repo_path" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    git -C "$repo_path" worktree add --track -b "$branch" "$wt_path" "origin/$branch"
  else
    git -C "$repo_path" worktree add -b "$branch" "$wt_path" "$base"
  fi

  open_project "${wt_path#$HOME/}"
}

case "$mode" in
  --list-projects) list_projects ;;
  --list-repos) list_repos ;;
  --list-branches) list_branches "${2:-}" ;;
  --list-sets) list_sets ;;
  --open-project) open_project "${2:-}" ;;
  --switch-set) switch_set "${2:-}" ;;
  --create-worktree) create_worktree "${2:-}" "${3:-}" "${4:-${3:-}}" ;;
  *)
    echo "Usage: openvide.sh --list-projects|--list-repos|--list-branches|--list-sets|--open-project|--switch-set|--create-worktree" >&2
    exit 1
    ;;
esac
