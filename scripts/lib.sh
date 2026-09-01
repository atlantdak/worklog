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

# Atomic file write: stdin -> temp beside the target -> rename.
# A torn write is the one path back to a duplicate card, and rename closes it.
wl_atomic_write() {
    _dst="${1:?destination required}"
    _dir="$(dirname "$_dst")"
    [ -d "$_dir" ] || wl_die "no such directory: $_dir"
    _tmp="$(mktemp "$_dir/.wl.XXXXXX")" || wl_die "cannot create temp in $_dir"
    cat > "$_tmp" || { rm -f "$_tmp"; wl_die "write failed: $_tmp"; }
    mv -f "$_tmp" "$_dst" || { rm -f "$_tmp"; wl_die "rename failed: $_dst"; }
}

# Bare sha256 of a file (no filename in the output).
# macOS ships shasum, Linux sha256sum; neither is guaranteed, so both are tried.
wl_sha256() {
    _f="${1:?file required}"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$_f" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$_f" | cut -d' ' -f1
    else
        wl_die "missing dependency: sha256sum or shasum"
    fi
}
