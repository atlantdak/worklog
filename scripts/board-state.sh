#!/usr/bin/env sh
# Local state about a plan's card: the subtask map beside the plan, and which
# section directory the plan currently sits in.
#
# The map is versioned on purpose — its diff is the evidence of what ran.
# Neither the map nor the directory is authoritative: the tracker is. Both are
# a reflection, realigned before any operation touches the card.
#
# Usage:
#   board-state.sh map-read <plan>
#   board-state.sh map-init <plan> <tracker> <card> <origin>
#   board-state.sh map-set  <plan> <key> <gid>
#   board-state.sh dir-of   <section-key>
#   board-state.sh place    <plan> <section-key>
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
wl_need jq

cmd="${1:?usage: board-state.sh <command> <plan|key> ...}"
# For every command but dir-of this is a path; dir-of passes a section key here.
plan="${2:?plan path or section key required}"
map="${plan%.md}.board.json"

map_read() { if [ -f "$map" ]; then cat "$map"; else printf '{}\n'; fi; }

# The canonical key is the identity; the directory name is only its spelling on
# disk. Both are fixed here so nothing downstream has to guess either one.
dir_of() {
    case "${1:?section key required}" in
        backlog)     printf 'backlog\n' ;;
        to_do)       printf 'to-do\n' ;;
        in_progress) printf 'in-progress\n' ;;
        review)      printf 'review\n' ;;
        done)        printf 'done\n' ;;
        *) wl_die "unknown section key: $1 (expected backlog|to_do|in_progress|review|done)" ;;
    esac
}

move_one() {
    _src="$1"; _dst="$2"
    [ -e "$_src" ] || return 0
    if git -C "$(dirname "$_src")" rev-parse --git-dir >/dev/null 2>&1; then
        git mv -f "$_src" "$_dst" 2>/dev/null || mv -f "$_src" "$_dst"
    else
        mv -f "$_src" "$_dst"
    fi
}

place() {
    _key="${1:?section key required}"
    _dir="$(dir_of "$_key")"
    _parent="$(cd "$(dirname "$plan")/.." && pwd)"
    _target="$_parent/$_dir"
    _new="$_target/$(basename "$plan")"
    if [ "$plan" = "$_new" ]; then printf '%s\n' "$_new"; return 0; fi
    mkdir -p "$_target" || wl_die "cannot create $_target"
    move_one "$plan" "$_new"
    move_one "$map" "${_new%.md}.board.json"
    printf '%s\n' "$_new"
}

case "$cmd" in
  map-read)
    map_read ;;
  map-init)
    jq -n --arg t "${3:?tracker required}" --arg c "${4:?card required}" \
          --arg o "${5:?origin required}" \
      '{tracker:$t, card:$c, origin:$o, subtasks:{}}' | wl_atomic_write "$map"
    map_read ;;
  map-set)
    _k="${3:?key required}"; _g="${4:?gid required}"
    _cur="$(map_read | jq -r --arg k "$_k" '.subtasks[$k] // ""')"
    # Rebinding a key would silently point a unit at a different subtask.
    [ -z "$_cur" ] || [ "$_cur" = "$_g" ] \
      || wl_die "$_k is already bound to $_cur, refusing to rebind to $_g"
    map_read | jq --arg k "$_k" --arg g "$_g" '.subtasks[$k] = $g' | wl_atomic_write "$map"
    map_read ;;
  dir-of) dir_of "$plan" ;;
  place)  place "${3:?section key required}" ;;
  *) wl_die "unknown command: $cmd" ;;
esac
