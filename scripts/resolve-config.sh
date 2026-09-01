#!/usr/bin/env sh
# Resolve the effective worklog config for a project by layering:
#   built-in defaults  <  global ($HOME/.claude/worklog.config.json)  <  project (.claude/worklog.config.json)
# Identity is never stored: github_repo is derived from the project's git remote when
# unset, and assignee is left to the skill (resolved to the authenticated tracker user
# at write time, per the adapter) unless a config pins assignee_id.
#
# Usage: resolve-config.sh [PROJECT_ROOT]    (default: current directory)
#   stdout : effective config as JSON
#   stderr : a provenance table (value <- source) — always printed
#   exit 3 : NEEDS_ONBOARDING (no tracker, or its required bindings are missing)
#   exit 2 : usage / dependency error, including an unknown tracker
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
  drafts_dir:    "worklog/_daily",
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
# --- Tracker resolution -------------------------------------------------------
# One line per supported tracker: which config keys must resolve before anything can
# be written. Adding a tracker = a line here + a file in references/adapters/. The
# skill itself never names a tracker; this table and the adapters do.
tracker_required() {
  case "$1" in
    clickup) printf 'clickup_list_id\n' ;;
    asana)   printf 'asana.project_gid\n' ;;
    *)       return 1 ;;
  esac
}

tracker="$(printf '%s' "$eff" | jq -r '.tracker // ""')"
tracker_src="config"
if [ -z "$tracker" ]; then
  # Backwards compatibility: a pre-adapter config carries clickup_list_id and no tracker.
  if printf '%s' "$eff" | jq -e '.clickup_list_id != null' >/dev/null 2>&1; then
    tracker="clickup"; tracker_src="inferred (legacy clickup_list_id)"
    eff="$(printf '%s' "$eff" | jq '.tracker = "clickup"')"
  else
    tracker_src="unset"
  fi
fi
req=""
[ -z "$tracker" ] || req="$(tracker_required "$tracker")" \
  || wl_die "unknown tracker: $tracker (supported: clickup, asana)"

{
  printf 'worklog effective config (value <- source):\n' >&2
  printf '  %-16s %-28s %s\n' 'github_repo' "\"$repo\"" "$repo_src" >&2
  printf '  %-16s %-28s %s\n' 'tracker' "\"$tracker\"" "$tracker_src" >&2
  for key in $req; do
    val="$(printf '%s' "$eff" | jq -r --arg k "$key" 'getpath($k | split(".")) // ""')"
    printf '  %-16s %-28s %s\n' "$key" "\"$val\"" 'binding' >&2
  done
  prov umbrella_task_id umbrella_task_id
  # assignee: pinned only if a layer set it; otherwise the skill resolves "me" at write time.
  if printf '%s' "$eff" | jq -e 'has("assignee_id") and .assignee_id != null and .assignee_id != ""' >/dev/null; then
    printf '  %-16s %-28s %s\n' 'assignee_id' "$(printf '%s' "$eff" | jq -c '.assignee_id')" 'config (override)' >&2
  else
    printf '  %-16s %-28s %s\n' 'assignee_id' '"me"' 'dynamic (authenticated tracker user)' >&2
  fi
  prov naming         naming
  prov language       language
  prov drafts_dir     drafts_dir
}

# Required bindings must resolve before the skill may write anything.
if [ -z "$tracker" ]; then
  printf 'NEEDS_ONBOARDING: no tracker resolved (set "tracker" in %s)\n' "$project" >&2
  printf '%s' "$eff"; exit 3
fi

missing=""
for key in $req; do
  val="$(printf '%s' "$eff" | jq -r --arg k "$key" 'getpath($k | split(".")) // ""')"
  case "$val" in
    ""|"000000000000"|"PROJECT_GID") missing="$missing $key" ;;
  esac
done
if [ -n "$missing" ]; then
  printf 'NEEDS_ONBOARDING: tracker %s needs:%s (set them in %s)\n' "$tracker" "$missing" "$project" >&2
  printf '%s' "$eff"; exit 3
fi

printf '%s' "$eff"
