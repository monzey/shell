#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
project_root="$HOME"
max_depth="4"
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
agent_menu="$script_dir/agent-menu.sh"
project_state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/caelestia/openvide"

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

monitor_count() {
  hyprctl monitors -j | jq 'length'
}

has_three_monitors() {
  (($(monitor_count) >= 3))
}

lua_string() {
  jq -cn --arg value "$1" '$value'
}

launch_on_workspace() {
  local workspace="$1"
  shift
  local command
  printf -v command '%q ' "$@"
  hyprctl dispatch "hl.dsp.exec_cmd($(lua_string "$command"), { workspace = $(lua_string "$workspace") })"
}

# Keep the graph and push commands in a drawer toggled by openvide's Git shortcut.
# Worktrees and remotes stay visible; Neovim remains the diff viewer.
launch_lazygit_special() {
  ensure_lazygit "$1" "$2" "special:$1-lazygit"
}

ensure_lazygit() {
  local proj="$1" dir="$2" workspace="$3"
  mkdir -p "$project_state_dir"
  # All launch paths share this lock, including creation of a new project set.
  # Hold it until the compositor sees the window, so rapid calls cannot race.
  (
    flock -w 15 9 || return 1
    if hyprctl clients -j | jq -e --arg ws "$workspace" --arg class "openvide-lazygit-$proj" \
      'any(.[]; .workspace.name == $ws and (.class == $class or ((.class | ascii_downcase) == "kitty" and .title == "lazygit")))' >/dev/null; then
      return 0
    fi
    local executable="$script_dir/bin/lazygit" configs="${LG_CONFIG_FILE:-}"
    [[ -x "$executable" ]] || executable="lazygit"
    if [[ -z "$configs" ]]; then
      local config_dir
      config_dir=$("$executable" --print-config-dir)
      [[ ! -f "$config_dir/config.yml" ]] || configs="$config_dir/config.yml"
    fi
    configs="${configs:+$configs,}$script_dir/openvide-lazygit.yml"
    if [[ "$workspace" == special:* ]]; then
      launch_on_workspace "$workspace silent" kitty --class "openvide-lazygit-$proj" --title lazygit --directory "$dir" \
        env "LG_CONFIG_FILE=$configs" OPENVIDE_GIT_OVERVIEW=1 "$executable" --screen-mode normal log
    else
      launch_on_workspace "name:$workspace" kitty --class "openvide-lazygit-$proj" --title lazygit --directory "$dir" \
        env "LG_CONFIG_FILE=$configs" OPENVIDE_GIT_OVERVIEW=1 "$executable" --screen-mode normal log
    fi
    wait_for_window "$workspace" "openvide-lazygit-$proj" >/dev/null
  ) 9>"$project_state_dir/$proj.git.lock"
}

remember_project() {
  mkdir -p "$project_state_dir"
  jq -n --arg directory "$2" '{directory: $directory}' > "$project_state_dir/$1.json"
}

project_directory() {
  local directory
  directory=$(git -C "$2" rev-parse --show-toplevel 2>/dev/null) || return 1
  [[ $(get_proj "$directory") == "$1" ]] || return 1
  printf '%s\n' "$directory"
}

open_git() {
  local proj="$1"
  shift
  [[ -n "$proj" && "$proj" != */* ]] || return 1
  local dir="" candidate pid workspace monitors
  if [[ -f "$project_state_dir/$proj.json" ]]; then
    candidate=$(jq -r '.directory // empty' "$project_state_dir/$proj.json")
    dir=$(project_directory "$proj" "$candidate") || dir=""
  fi
  # Existing sets predate the registry: inspect only processes belonging to
  # this set and accept a repository only when its project identifier matches.
  if [[ -z "$dir" ]]; then
    for pid in "$@"; do
      [[ "$pid" =~ ^[0-9]+$ ]] || continue
      candidate=$(readlink -e "/proc/$pid/cwd" 2>/dev/null) || continue
      if dir=$(project_directory "$proj" "$candidate"); then
        break
      fi
    done
  fi
  [[ -n "$dir" ]] || return 1
  remember_project "$proj" "$dir"
  monitors=$(monitor_count)
  workspace="$proj-lazygit"
  ((monitors >= 3)) || workspace="special:$workspace"
  ensure_lazygit "$proj" "$dir" "$workspace"
  if ((monitors < 3)); then
    hyprctl dispatch "hl.dsp.workspace.toggle_special($(lua_string "$proj-lazygit"))"
  else
    hyprctl dispatch "hl.dsp.focus({ workspace = $(lua_string "name:$workspace") })"
  fi
}

launch_neovide() {
  local proj="$1" dir="$2" socket="$3" compact="$4"
  launch_on_workspace "name:$proj-code" env \
    OPENVIDE_NVIM_PROFILE="$script_dir/openvide-nvim.lua" OPENVIDE_NVIM_COMPACT="$compact" \
    neovide --chdir "$dir" -- --listen "$socket" -c 'lua dofile(vim.env.OPENVIDE_NVIM_PROFILE)'
}

wait_for_window() {
  local workspace="$1" class="$2" window attempt
  for ((attempt = 0; attempt < 100; attempt++)); do
    window=$(hyprctl clients -j | jq -c --arg ws "$workspace" --arg class "$class" \
      '[.[] | select(.workspace.name == $ws and (.class | ascii_downcase) == ($class | ascii_downcase))][0] // empty')
    if [[ -n "$window" ]]; then
      printf '%s\n' "$window"
      return
    fi
    sleep 0.1
  done
  return 1
}

launch_agent_window() {
  local dir="$1" agent="$2" proj workspace editor agent_window class clients
  proj=$(get_proj "$dir")
  workspace="$proj-code"

  if [[ $(monitor_count 2>/dev/null || true) != 1 ]] ||
    ! hyprctl workspaces -j | jq -e --arg ws "$workspace" 'any(.[]; .name == $ws)' >/dev/null; then
    kitty --detach --directory "$dir" --hold "$agent"
    sleep 0.5
    return
  fi

  # Agent selection happens asynchronously, after Neovide was launched.
  if ! editor=$(wait_for_window "$workspace" neovide); then
    launch_on_workspace "name:$workspace" kitty --directory "$dir" --hold "$agent"
    return
  fi

  hyprctl dispatch "hl.dsp.focus({ window = \"address:$(jq -r '.address' <<<"$editor")\" })"
  hyprctl dispatch 'hl.dsp.layout("preselect l")'
  class="openvide-agent-$proj"
  launch_on_workspace "name:$workspace" kitty --class "$class" --directory "$dir" --hold "$agent"
  if ! agent_window=$(wait_for_window "$workspace" "$class"); then
    printf 'Openvide: timed out waiting for the agent window.\n' >&2
    return 1
  fi

  # Only arrange the initial pair, leaving additional user windows alone.
  clients=$(hyprctl clients -j | jq -c --arg ws "$workspace" \
    '[.[] | select(.workspace.name == $ws and .floating == false)]')
  [[ $(jq 'length' <<<"$clients") == 2 ]] || return 0
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$(jq -r '.address' <<<"$agent_window")\" })"
  # Correct the split if another window consumed the one-shot preselection.
  if jq -e '.[0].at[0] == .[1].at[0]' <<<"$clients" >/dev/null; then
    hyprctl dispatch 'hl.dsp.layout("togglesplit")'
    clients=$(hyprctl clients -j | jq -c --arg ws "$workspace" \
      '[.[] | select(.workspace.name == $ws and .floating == false)]')
  fi
  if jq -e --arg class "$class" \
    '(map(select(.class == $class))[0].at[0]) > (map(select(.class != $class))[0].at[0])' <<<"$clients" >/dev/null; then
    hyprctl dispatch 'hl.dsp.layout("swapsplit")'
  fi
  # Dwindle uses twice the left window's share: 1.2 gives the agent 60%.
  hyprctl dispatch 'hl.dsp.layout("splitratio 1.2 exact")'
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

  local monitors
  monitors=$(monitor_count)

  if ((monitors < 3)); then
    hyprctl dispatch "hl.dsp.focus({ workspace = \"name:$proj-code\" })"
    launch_neovide "$proj" "$dir" "$socket" 1
    launch_lazygit_special "$proj" "$dir"
    sleep 0.5
    bash "$agent_menu" "$dir"
    return
  fi

  hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-6" })'
  hyprctl dispatch "hl.dsp.focus({ workspace = \"name:$proj-lazygit\" })"
  ensure_lazygit "$proj" "$dir" "$proj-lazygit"

  hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-5" })'
  hyprctl dispatch "hl.dsp.focus({ workspace = \"name:$proj-opencode\" })"

  hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-7" })'
  hyprctl dispatch "hl.dsp.focus({ workspace = \"name:$proj-code\" })"
  launch_neovide "$proj" "$dir" "$socket" 0

  sleep 0.5
  switch_set "$proj"

  hyprctl dispatch 'hl.dsp.focus({ monitor = "DP-5" })'
  hyprctl dispatch "hl.dsp.focus({ workspace = \"name:$proj-opencode\" })"
  bash "$agent_menu" "$dir"
}

list_projects() {
  {
    printf 'action\t__new_worktree__\t[nouveau worktree]\n'
    find "$project_root" -maxdepth "$max_depth" -name ".git" -not -path "*/node_modules/*" 2>/dev/null |
      sed 's|/.git$||' |
      sed "s|^$HOME/||" |
      sort |
      while IFS= read -r repo; do printf 'project\t%s\t%s\n' "$repo" "$repo"; done
  } | json_list
}

list_repos() {
  find "$project_root" -maxdepth "$max_depth" -name ".git" -type d -not -path "*/node_modules/*" 2>/dev/null |
    sed 's|/.git$||' |
    sed "s|^$HOME/||" |
    sort |
    while IFS= read -r repo; do printf 'repo\t%s\t%s\n' "$repo" "$repo"; done |
    json_list
}

list_branches() {
  local repo="$1"
  local repo_path="$HOME/$repo"
  {
    printf 'action\t__new_branch__\t[nouvelle branche]\n'
    git -C "$repo_path" branch -r 2>/dev/null |
      grep -v 'HEAD' |
      sed 's|.*origin/||' |
      sed 's/^[[:space:]]*//' |
      sort |
      while IFS= read -r branch; do printf 'branch\t%s\t%s\n' "$branch" "$branch"; done ||
      true
  } | json_list
}

list_sets() {
  hyprctl workspaces -j |
    jq -r '.[] | select(.name | endswith("-code")) | .name[:-5]' |
    sort |
    while IFS= read -r proj; do printf 'set\t%s\t%s\n' "$proj" "$proj"; done |
    json_list
}

open_project() {
  local rel="$1"
  local dir
  dir=$(realpath "$HOME/$rel")
  [[ -d "$dir" ]] || exit 0

  local proj
  proj=$(get_proj "$dir")
  remember_project "$proj" "$dir"
  if hyprctl workspaces -j | jq -e --arg n "$proj-code" '.[] | select(.name == $n)' >/dev/null 2>&1; then
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
--open-git) open_git "${2:-}" "${@:3}" ;;
--switch-set) switch_set "${2:-}" ;;
--launch-agent) launch_agent_window "${2:-}" "${3:-}" ;;
--create-worktree) create_worktree "${2:-}" "${3:-}" "${4:-${3:-}}" ;;
*)
  echo "Usage: openvide.sh --list-projects|--list-repos|--list-branches|--list-sets|--open-project|--open-git|--switch-set|--launch-agent|--create-worktree" >&2
  exit 1
  ;;
esac
