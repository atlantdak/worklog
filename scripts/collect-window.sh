#!/usr/bin/env sh
# Gather GitHub PR facts for a window. Prints a JSON array to stdout.
# Usage: collect-window.sh REPO KIND VALUE
#   KIND date       VALUE=YYYY-MM-DD        -> PRs merged on that date
#   KIND pr-single  VALUE=NUMBER            -> that one PR
#   KIND pr-range   VALUE=NUMBER..NUMBER    -> inclusive PR-number range
#   KIND since      VALUE=NUMBER            -> PRs with number >= VALUE
#
# PRs are scoped to YOUR GitHub account so a teammate's PR merged in the same
# window is never mirrored as your work. The account is derived at runtime from
# `gh api user` — no login is ever hardcoded. Override with:
#   WL_AUTHOR=<login>   mirror a specific person's PRs instead
#   WL_AUTHOR='*'       disable author scoping (every author in the window)
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
wl_need gh; wl_need jq

repo="${1:?repo required}"; kind="${2:?kind required}"; value="${3:?value required}"

# Whose work to mirror — the authenticated GitHub account by default (never hardcoded).
author="${WL_AUTHOR:-$(gh api user --jq '.login' 2>/dev/null || true)}"
[ -n "$author" ] || wl_die "could not resolve your GitHub login (run 'gh auth login', or set WL_AUTHOR=<login>)"

# Pull a generous candidate set once, then filter in jq. Fields match gh's schema.
# `author` is carried through so the draft step can spot any non-self PR at a glance.
if [ "$author" = "*" ]; then
  raw="$(gh pr list --repo "$repo" --state all --limit 200 \
          --json number,title,mergedAt,createdAt,url,state,author)"
else
  raw="$(gh pr list --repo "$repo" --state all --author "$author" --limit 200 \
          --json number,title,mergedAt,createdAt,url,state,author)"
fi

# Number-based scopes keep OPEN (→ in progress) and MERGED (→ done) PRs but drop
# CLOSED-unmerged (abandoned) ones, so they are never mirrored as real work.
# The `date` scope is immune: it matches on mergedAt, which only merged PRs carry.
case "$kind" in
  date)
    printf '%s' "$raw" | jq --arg d "$value" \
      '[ .[] | select((.mergedAt // "")[0:10] == $d) ]' ;;
  pr-single)
    printf '%s' "$raw" | jq --argjson n "$value" \
      '[ .[] | select(.number == $n and .state != "CLOSED") ]' ;;
  pr-range)
    case "$value" in *..*) : ;; *) wl_die "pr-range needs A..B (got: $value)" ;; esac
    lo="${value%%..*}"; hi="${value##*..}"
    printf '%s' "$raw" | jq --argjson lo "$lo" --argjson hi "$hi" \
      '[ .[] | select(.number >= $lo and .number <= $hi and .state != "CLOSED") ]' ;;
  since)
    printf '%s' "$raw" | jq --argjson n "$value" \
      '[ .[] | select(.number >= $n and .state != "CLOSED") ]' ;;
  *)
    wl_die "unknown scope kind: $kind (date|pr-single|pr-range|since)" ;;
esac
