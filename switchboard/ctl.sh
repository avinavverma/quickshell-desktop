#!/usr/bin/env bash
# Switchboard backend. Finds projects in ~/Projects and starts/stops them.
#
#   ctl.sh list                -> JSON array of {name, path, kind, running, autostart, modules}
#   ctl.sh start   <name>
#   ctl.sh stop    <name>
#   ctl.sh enable  <name>      start automatically at login
#   ctl.sh disable <name>
#   ctl.sh module  <name> <module-id> true|false   toggle a module in <name>/modules.json
#
# How a project is run (first match wins):
#   run.sh (executable)  -> "script"
#   shell.qml            -> "quickshell"  (qs -n -p <dir>)
#   otherwise            -> "none"        listed, but can't be toggled
#
# A project may also have modules.json: [{id, name, enabled}, ...]. Switchboard
# shows a switch per module and edits the file; the project watches it.
#
# Each project gets a systemd user unit, ~/.config/systemd/user/sb-<name>.service,
# tied to the graphical session. Output: `journalctl --user -u sb-<name>`.
set -uo pipefail

ROOT="${SWITCHBOARD_ROOT:-$HOME/Projects}"
SELF="$(cd "$(dirname "$0")" && pwd)"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

kind_of() {
  if [[ -x "$1/run.sh" ]]; then echo script
  elif [[ -f "$1/shell.qml" ]]; then echo quickshell
  else echo none; fi
}

unit_of() { local n; n=$(basename "$1"); printf 'sb-%s.service' "${n//[^A-Za-z0-9_-]/_}"; }

# PID of a running Quickshell instance using <dir>/shell.qml, however it was started.
qs_pid() {
  qs list --all 2>/dev/null | awk -v want="$1/shell.qml" '
    /Process ID:/  { pid = $3 }
    /Config path:/ { p = $0; sub(/^[ \t]*Config path: /, "", p); if (p == want) { print pid; exit } }'
}

is_running() {
  local dir=$1
  case "$(kind_of "$dir")" in
    quickshell) [[ -n "$(qs_pid "$dir")" ]] ;;
    script)     systemctl --user is-active --quiet "$(unit_of "$dir")" ;;
    *)          return 1 ;;
  esac
}

is_enabled() { systemctl --user is-enabled --quiet "$(unit_of "$1")" 2>/dev/null; }

dir_of() {
  local dir="$ROOT/$1"
  [[ -d "$dir" && "$dir" != "$SELF" ]] || { echo "unknown project: $1" >&2; exit 2; }
  printf '%s' "$dir"
}

# (Re)write the unit file for a project; reload systemd only if it changed.
write_unit() {
  local dir=$1 exec
  case "$(kind_of "$dir")" in
    quickshell) exec="$(command -v qs) -n -p \"$dir\"" ;;
    script)     exec="\"$dir/run.sh\"" ;;
    *)          echo "$(basename "$dir") has no run.sh or shell.qml" >&2; exit 3 ;;
  esac
  local file="$UNIT_DIR/$(unit_of "$dir")" new
  new=$(cat <<EOF
# Managed by Switchboard ($SELF). Edits will be overwritten.
[Unit]
Description=Switchboard: $(basename "$dir")
PartOf=graphical-session.target
After=graphical-session.target

[Service]
WorkingDirectory=$dir
ExecStart=$exec

[Install]
WantedBy=graphical-session.target
EOF
)
  if [[ ! -f "$file" ]] || [[ "$(cat "$file")" != "$new" ]]; then
    mkdir -p "$UNIT_DIR"
    printf '%s\n' "$new" > "$file"
    systemctl --user daemon-reload
  fi
}

start() {
  local dir; dir=$(dir_of "$1")
  is_running "$dir" && return 0
  write_unit "$dir"
  systemctl --user reset-failed "$(unit_of "$dir")" 2>/dev/null
  systemctl --user start "$(unit_of "$dir")"
}

stop() {
  local dir; dir=$(dir_of "$1")
  systemctl --user stop "$(unit_of "$dir")" 2>/dev/null
  # Also catch Quickshell instances started by hand.
  if [[ "$(kind_of "$dir")" == quickshell ]]; then
    local pid; pid=$(qs_pid "$dir")
    [[ -n "$pid" ]] && qs kill --pid "$pid" >/dev/null 2>&1
  fi
  return 0
}

enable()  { local dir; dir=$(dir_of "$1"); write_unit "$dir"; systemctl --user enable --quiet "$(unit_of "$dir")"; }
disable() { local dir; dir=$(dir_of "$1"); systemctl --user disable --quiet "$(unit_of "$dir")" 2>/dev/null; return 0; }

set_module() {
  local dir; dir=$(dir_of "$1")
  local file="$dir/modules.json"
  [[ -f "$file" ]] || { echo "$1 has no modules.json" >&2; exit 4; }
  [[ "$3" == true || "$3" == false ]] || { echo "expected true|false" >&2; exit 1; }
  local new
  new=$(jq --arg id "$2" --argjson on "$3" \
          'if any(.[]; .id == $id) then map(if .id == $id then .enabled = $on else . end)
           else error("no module \($id)") end' "$file") || exit 5
  # Write in place (same file) so the project's file watcher keeps working.
  printf '%s\n' "$new" > "$file"
}

list() {
  local out=() dir
  for dir in "$ROOT"/*/; do
    dir=${dir%/}
    [[ "$dir" == "$SELF" ]] && continue
    local running=false autostart=false
    is_running "$dir" && running=true
    is_enabled "$dir" && autostart=true
    local modules=null
    [[ -f "$dir/modules.json" ]] && modules=$(jq -c '.' "$dir/modules.json" 2>/dev/null || echo null)
    out+=("$(jq -cn --arg name "$(basename "$dir")" --arg path "$dir" \
              --arg kind "$(kind_of "$dir")" \
              --argjson running "$running" --argjson autostart "$autostart" \
              --argjson modules "$modules" \
              '{name: $name, path: $path, kind: $kind, running: $running, autostart: $autostart, modules: $modules}')")
  done
  printf '%s\n' "${out[@]}" | jq -cs 'map(select(. != null))'
}

case "${1:-}" in
  list)    list ;;
  start)   start   "${2:?name}" ;;
  stop)    stop    "${2:?name}" ;;
  enable)  enable  "${2:?name}" ;;
  disable) disable "${2:?name}" ;;
  module)  set_module "${2:?name}" "${3:?module id}" "${4:?true|false}" ;;
  *)       echo "usage: $0 list | start|stop|enable|disable <name> | module <name> <id> true|false" >&2; exit 1 ;;
esac
