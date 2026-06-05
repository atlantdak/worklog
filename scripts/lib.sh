# /path/to/worklog/scripts/lib.sh
# Shared helpers for worklog scripts. Sourced, not executed.

wl_die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

# Ephemeral per-run working dir (no persistent ledger).
# Usage: wl_run_dir YYYY-MM-DD  -> prints path, creates it.
wl_run_dir() {
    _date="${1:?date required}"
    _base="${TMPDIR:-/tmp}"
    _dir="${_base%/}/worklog-run-${_date}"
    mkdir -p "$_dir" || wl_die "cannot create run dir $_dir"
    printf '%s\n' "$_dir"
}

# Require a command on PATH.
wl_need() { command -v "$1" >/dev/null 2>&1 || wl_die "missing dependency: $1"; }
