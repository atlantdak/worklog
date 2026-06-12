#!/usr/bin/env sh
# Resolve the effective worklog config for a project by layering:
#   built-in defaults  <  global ($HOME/.claude/worklog.config.json)  <  project (.claude/worklog.config.json)
# Identity is never stored: github_repo is derived from the project's git remote when
# unset, and assignee is left to the skill (resolved to the authenticated ClickUp user
# via `clickup_resolve_assignees ["me"]` at write time) unless a config pins assignee_id.
#
# Usage: resolve-config.sh [PROJECT_ROOT]    (default: current directory)
#   stdout : effective config as JSON
#   stderr : a provenance table (value <- source) — always printed
#   exit 3 : NEEDS_ONBOARDING (no resolvable clickup_list_id) — the skill onboards
#   exit 2 : usage / dependency error
# Env overrides (testing): WL_GLOBAL_CONFIG, WL_BUILTIN_LANG.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
wl_need jq

root="${1:-.}"
global="${WL_GLOBAL_CONFIG:-$HOME/.claude/worklog.config.json}"
project="$root/.claude/worklog.config.json"

# Built-in behavioural defaults (NOT the documentation example). Preferences only;
# zero bindings. language defaults to en for portability; a global config can set uk.
builtin="$(jq -n --arg lang "${WL_BUILTIN_LANG:-en}" '{
  naming:        { scheme: "TASK-{n}", sub: "TASK-{n}.{m}", start_n: 1 },
  sp_calibration:"~14-15 SP per active day",
  drafts_dir:    "ClickUp/_daily",
  terminology:   { avoid: [], use: [] },
  language:      $lang
}')"

# Read a layer file into JSON ({} if absent), then strip null-valued keys so an explicit
# null never clobbers an inherited value. Aborts on malformed JSON (fail loud, not silent).
read_layer() {
  _f="$1"
  if [ -f "$_f" ]; then
    jq -e . "$_f" >/dev/null 2>&1 || wl_die "malformed JSON: $_f"
    jq 'walk(if type=="object" then with_entries(select(.value != null)) else . end)' "$_f"
  else
    printf '{}'
  fi
}

g="$(read_layer "$global")"
p="$(read_layer "$project")"

# Merge. jq's `*` deep-merges objects key-by-key (so naming.* layers correctly) and lets
# the right operand replace arrays and scalars (so terminology arrays swap wholesale and
# scalars take the most specific layer) — exactly the field-specific semantics we want.
eff="$(printf '%s\n%s\n%s' "$builtin" "$g" "$p" | jq -s '.[0] * .[1] * .[2]')"

# github_repo: derive from the project's git remote when unset/placeholder.
repo="$(printf '%s' "$eff" | jq -r '.github_repo // ""')"
repo_src="config"
case "$repo" in
  ""|"OWNER/REPO")
    url="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
    # git@github.com:OWNER/REPO.git  |  https://github.com/OWNER/REPO(.git)
    derived="$(printf '%s' "$url" | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##')"
    [ -n "$derived" ] && { repo="$derived"; repo_src="git-remote"; } || repo_src="unset"
    eff="$(printf '%s' "$eff" | jq --arg r "$repo" '.github_repo = (if $r=="" then null else $r end)')" ;;
esac

# Provenance for the keys that matter — which layer won, per top-level key.
prov() {
  _k="$1"; _label="$2"
  if printf '%s' "$p" | jq -e --arg k "$_k" 'has($k)' >/dev/null; then _s=project
  elif printf '%s' "$g" | jq -e --arg k "$_k" 'has($k)' >/dev/null; then _s=global
  else _s=built-in; fi
  _v="$(printf '%s' "$eff" | jq -c --arg k "$_k" '.[$k] // "—"')"
  printf '  %-16s %-28s %s\n' "$_label" "$_v" "$_s" >&2
}
{
  printf 'worklog effective config (value <- source):\n' >&2
  printf '  %-16s %-28s %s\n' 'github_repo' "\"$repo\"" "$repo_src" >&2
  prov clickup_list_id  clickup_list_id
  prov umbrella_task_id umbrella_task_id
  # assignee: pinned only if a layer set it; otherwise the skill resolves "me" at write time.
  if printf '%s' "$eff" | jq -e 'has("assignee_id") and .assignee_id != null and .assignee_id != ""' >/dev/null; then
    printf '  %-16s %-28s %s\n' 'assignee_id' "$(printf '%s' "$eff" | jq -c '.assignee_id')" 'config (override)' >&2
  else
    printf '  %-16s %-28s %s\n' 'assignee_id' '"me"' 'dynamic (ClickUp authenticated user)' >&2
  fi
  prov naming         naming
  prov language       language
  prov drafts_dir     drafts_dir
}

# Required binding: a real clickup_list_id. Missing/placeholder -> onboarding.
list="$(printf '%s' "$eff" | jq -r '.clickup_list_id // ""')"
case "$list" in
  ""|"000000000000")
    printf 'NEEDS_ONBOARDING: no clickup_list_id resolved (set it in %s)\n' "$project" >&2
    printf '%s' "$eff"; exit 3 ;;
esac

printf '%s' "$eff"
