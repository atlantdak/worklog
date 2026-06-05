# Worklog Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a private, portable Claude Code plugin `worklog` that, on a user-supplied window, gathers GitHub facts, writes `.md` drafts for review, and — only after explicit approval — mirrors them into ClickUp via MCP and returns exact task links.

**Architecture:** A generic engine (command + skill + references + scripts) reading a per-project `.claude/worklog.config.json`. Two shell scripts carry the testable machine work (`collect-window.sh` shapes GitHub facts; `validate-draft.sh` enforces the SP/date/dedup contract). The skill orchestrates the 4-stage, 2-gate flow and performs all ClickUp MCP writes itself — scripts never touch ClickUp. The draft carries a machine-readable `worklog:meta` JSON block (the contract S3 writes from) plus human markdown (what the user reviews).

**Tech Stack:** Claude Code plugin manifest, Markdown skill/command, POSIX `sh` + `jq`, `gh` CLI, ClickUp MCP tools.

**Resolved open questions (spec §10):** validator = POSIX `sh` + `jq` (portability); dedup cache = ephemeral per-run tmp files, no cross-run ledger; ClickUp time-tracking = NOT used (start_date/due_date only).

**Plugin root (and this plan/spec location, deliberately outside any shared repo):** `~/.claude/worklog/` → becomes private repo `atlantdak/worklog`.

---

## File Structure

```
~/.claude/worklog/
├── .claude-plugin/
│   ├── plugin.json              # plugin manifest
│   └── marketplace.json         # local/marketplace manifest
├── commands/
│   └── log-day.md               # /log-day entry point
├── skills/
│   └── worklog-day/
│       └── SKILL.md             # the 4-stage / 2-gate orchestration + onboarding
├── references/
│   ├── format.md                # task-description template, date rule, draft meta schema, SP calibration
│   └── worklog.config.example.json
├── scripts/
│   ├── lib.sh                   # shared sh helpers (run dir, die)
│   ├── collect-window.sh        # gh → window.json (scope→gh-args is the testable unit)
│   ├── validate-draft.sh        # SP sums + date rule + dedup contract on a draft
│   └── tests/
│       ├── test-collect-window.sh
│       ├── test-validate-draft.sh
│       └── fixtures/
│           ├── gh-stub           # fake gh for deterministic collect-window test
│           ├── draft-ok.md
│           ├── draft-baddate.md
│           ├── draft-dupe.md
│           └── logged-prs.txt
├── docs/
│   ├── 2026-06-05-worklog-plugin-design.md   # spec (exists)
│   └── 2026-06-05-worklog-plugin-plan.md     # this plan
├── .gitignore
└── README.md
```

Per-consuming-project file (NOT in this repo; created by onboarding, gitignored in that project):
`.claude/worklog.config.json` + drafts under the configured `drafts_dir`.

---

## Task 1: Plugin scaffold + manifests

**Files:**
- Create: `~/.claude/worklog/.claude-plugin/plugin.json`
- Create: `~/.claude/worklog/.claude-plugin/marketplace.json`
- Create: `~/.claude/worklog/README.md`
- Create: `~/.claude/worklog/.gitignore`
- Test: `~/.claude/worklog/scripts/tests/test-manifests.sh`

- [ ] **Step 1: Write the failing test**

```sh
# ~/.claude/worklog/scripts/tests/test-manifests.sh
#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

check "plugin.json parses"      "jq -e . '$root/.claude-plugin/plugin.json'"
check "plugin.json has name"    "jq -e '.name==\"worklog\"' '$root/.claude-plugin/plugin.json'"
check "marketplace.json parses" "jq -e . '$root/.claude-plugin/marketplace.json'"
check "marketplace lists worklog" "jq -e '.plugins[] | select(.name==\"worklog\")' '$root/.claude-plugin/marketplace.json'"
exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh ~/.claude/worklog/scripts/tests/test-manifests.sh`
Expected: FAIL (files do not exist yet; jq errors).

- [ ] **Step 3: Create the manifests, README, .gitignore**

`~/.claude/worklog/.claude-plugin/plugin.json`:
```json
{
  "name": "worklog",
  "description": "End-of-day worklog mirror: gathers GitHub facts for a user-supplied window, writes review drafts, and after approval mirrors them into ClickUp.",
  "version": "0.1.0",
  "author": {
    "name": "Dmytro Kishkin",
    "email": "atlantdak@gmail.com"
  },
  "keywords": ["worklog", "clickup", "github", "workflow"]
}
```

`~/.claude/worklog/.claude-plugin/marketplace.json`:
```json
{
  "name": "worklog-dev",
  "description": "Private marketplace for the worklog end-of-day plugin.",
  "owner": {
    "name": "Dmytro Kishkin",
    "email": "atlantdak@gmail.com"
  },
  "plugins": [
    {
      "name": "worklog",
      "source": "./",
      "version": "0.1.0",
      "description": "End-of-day worklog mirror into ClickUp from GitHub facts.",
      "author": {
        "name": "Dmytro Kishkin",
        "email": "atlantdak@gmail.com"
      }
    }
  ]
}
```

`~/.claude/worklog/README.md`:
```markdown
# worklog

Private end-of-day plugin. From a window you name (`вчера`, `#180..#186`), it gathers
GitHub facts, writes a review draft, and — only after you approve — mirrors the work into
ClickUp and returns the exact task links.

## Install (global)

    gh repo create atlantdak/worklog --private --source ~/.claude/worklog --push
    # in Claude Code:
    /plugin marketplace add atlantdak/worklog
    /plugin install worklog@worklog-dev

## Use

In any project that has `.claude/worklog.config.json` (created on first run):

    /log-day вчера
    /log-day #180..#186

The plugin never writes to ClickUp until you approve the draft.

## Privacy

This plugin, each project's `worklog.config.json`, and the drafts dir are private. Keep them
out of shared repositories (the onboarding step gitignores them in the consuming project).
```

`~/.claude/worklog/.gitignore`:
```
*.local
.DS_Store
```

- [ ] **Step 4: Run test to verify it passes**

Run: `sh ~/.claude/worklog/scripts/tests/test-manifests.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/.claude/worklog && git init -q 2>/dev/null; git add .claude-plugin README.md .gitignore scripts/tests/test-manifests.sh
git commit -m "feat: plugin scaffold and manifests"
```

---

## Task 2: references — format.md + config example

**Files:**
- Create: `~/.claude/worklog/references/worklog.config.example.json`
- Create: `~/.claude/worklog/references/format.md`
- Test: `~/.claude/worklog/scripts/tests/test-references.sh`

- [ ] **Step 1: Write the failing test**

```sh
# ~/.claude/worklog/scripts/tests/test-references.sh
#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

check "config example parses" "jq -e . '$root/references/worklog.config.example.json'"
check "config has clickup_list_id key" "jq -e 'has(\"clickup_list_id\")' '$root/references/worklog.config.example.json'"
check "config has naming.scheme" "jq -e '.naming.scheme' '$root/references/worklog.config.example.json'"
check "format.md has meta-schema anchor" "grep -q 'worklog:meta' '$root/references/format.md'"
check "format.md states date rule" "grep -q 'done' '$root/references/format.md' && grep -q 'in progress' '$root/references/format.md'"
exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh ~/.claude/worklog/scripts/tests/test-references.sh`
Expected: FAIL (files absent).

- [ ] **Step 3: Create the reference files**

`~/.claude/worklog/references/worklog.config.example.json`:
```json
{
  "github_repo": "OWNER/REPO",
  "clickup_list_id": "000000000000",
  "umbrella_task_id": "",
  "assignee_id": "00000000",
  "naming": { "scheme": "TASK-{n}", "sub": "TASK-{n}.{m}", "start_n": 1 },
  "sp_calibration": "~14-15 SP per active day",
  "drafts_dir": "ClickUp/_daily",
  "terminology": { "avoid": ["епік"], "use": ["задача", "під-задача"] },
  "language": "uk"
}
```

`~/.claude/worklog/references/format.md`:
````markdown
# worklog — format contract (generic)

## Draft file

Path: `<drafts_dir>/YYYY-MM-DD.md`. Two parts.

### 1. Machine block (the contract S3 writes from)

A single HTML-comment block. `validate-draft.sh` and the skill parse the JSON between the
markers with `jq`:

```
<!-- worklog:meta
{
  "date": "2026-06-04",
  "entries": [
    {
      "target": "new",
      "title": "TASK-43 · Short clear title",
      "sp": 8,
      "status": "done",
      "start": "2026-06-04",
      "due": "2026-06-04",
      "parent": "umbrella",
      "prs": [186],
      "links": ["https://github.com/OWNER/REPO/pull/186"]
    }
  ]
}
worklog:meta -->
```

Field rules:
- `target`: `"new"` (create) or an existing task id/code (`"TASK-34"`) to extend/close.
- `status`: exactly `"done"` or `"in progress"`.
- Date rule: `status=="done"` ⇒ both `start` and `due` present. `status=="in progress"` ⇒
  `start` present, `due` MUST be absent or null.
- `parent`: `"umbrella"` (resolve to config `umbrella_task_id`), `"none"`, or a task id.
- `prs`: array of integers; each must NOT appear in the run's `logged-prs.txt` (dedup).
- `sp`: positive integer.

### 2. Human block (what the user reviews)

Below the machine block, plain markdown the user reads. Per entry use the description
template:

```
## 🎯 Story Points: N

**↳ Огляд:** [★ Umbrella](UMBRELLA_URL)        ← epics/standalone
**↳ Задача:** [TASK-NN — title](PARENT_URL)    ← sub-entries

**Що зроблено.** …
**Результат.** …

**🔗 Pull request:** [#186](URL)               ← one PR
**🔗 Pull requests:** [#180](URL), [#182](URL)  ← several
```

Terminology: never the word «епік»; use «задача»/«під-задача» (or the consuming project's
`terminology` config). Language follows config `language`.

## Date rule (canonical)

- `done` → set `start_date` AND `due_date`.
- `in progress` → set `start_date` only; never set `due_date` (due = completion date).

## Story-point calibration (default)

SP = relative delivery complexity in an AI-first process (review volume, architecture, risk,
cross-layer integration), NOT person-hours. Default calibration `~14-15 SP/active day`; the
consuming project may override via config `sp_calibration`. The agent proposes SP; the user
approves at the gate.
````

- [ ] **Step 4: Run test to verify it passes**

Run: `sh ~/.claude/worklog/scripts/tests/test-references.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/.claude/worklog && git add references scripts/tests/test-references.sh
git commit -m "feat: generic format contract and config example"
```

---

## Task 3: scripts/lib.sh — shared helpers

**Files:**
- Create: `~/.claude/worklog/scripts/lib.sh`
- Test: `~/.claude/worklog/scripts/tests/test-lib.sh`

- [ ] **Step 1: Write the failing test**

```sh
# ~/.claude/worklog/scripts/tests/test-lib.sh
#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
. "$root/scripts/lib.sh"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

d="$(wl_run_dir 2026-06-04)"
check "run dir created"      "[ -d \"$d\" ]"
check "run dir carries date" "printf '%s' \"$d\" | grep -q 'worklog-run-2026-06-04'"
check "wl_die exits nonzero" "! ( wl_die 'x' 2>/dev/null )"
exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh ~/.claude/worklog/scripts/tests/test-lib.sh`
Expected: FAIL ("lib.sh: No such file" / functions undefined).

- [ ] **Step 3: Write lib.sh**

```sh
# ~/.claude/worklog/scripts/lib.sh
# Shared helpers for worklog scripts. Sourced, not executed.

wl_die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

# Ephemeral per-run working dir (open question §10: no persistent ledger).
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `sh ~/.claude/worklog/scripts/tests/test-lib.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/.claude/worklog && git add scripts/lib.sh scripts/tests/test-lib.sh
git commit -m "feat: shared sh helpers (run dir, die, need)"
```

---

## Task 4: scripts/collect-window.sh — GitHub facts for the window

The testable unit is the scope→gh-search mapping and JSON shaping. The network `gh` call is
isolated behind a stub on PATH so the test is deterministic.

**Files:**
- Create: `~/.claude/worklog/scripts/collect-window.sh`
- Create: `~/.claude/worklog/scripts/tests/fixtures/gh-stub`
- Test: `~/.claude/worklog/scripts/tests/test-collect-window.sh`

- [ ] **Step 1: Write the failing test + gh stub fixture**

`~/.claude/worklog/scripts/tests/fixtures/gh-stub`:
```sh
#!/usr/bin/env sh
# Fake gh: ignores args, returns a fixed PR list as JSON (what `gh pr list --json` emits).
cat <<'JSON'
[
  {"number":186,"title":"feat(labels): csv import","mergedAt":"2026-06-04T10:00:00Z","createdAt":"2026-06-03T09:00:00Z","url":"https://github.com/OWNER/REPO/pull/186","state":"MERGED"},
  {"number":182,"title":"feat(labels): drag-drop modal","mergedAt":"2026-06-04T08:00:00Z","createdAt":"2026-06-03T07:00:00Z","url":"https://github.com/OWNER/REPO/pull/182","state":"MERGED"}
]
JSON
```

`~/.claude/worklog/scripts/tests/test-collect-window.sh`:
```sh
#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

# Stub gh: copy fixture to an executable `gh` on a temp PATH.
tmp="$(mktemp -d)"; cp "$root/scripts/tests/fixtures/gh-stub" "$tmp/gh"; chmod +x "$tmp/gh"
out="$(PATH="$tmp:$PATH" sh "$root/scripts/collect-window.sh" OWNER/REPO date 2026-06-04)"

check "emits valid json array"   "printf '%s' \"$out\" | jq -e 'type==\"array\"'"
check "has 2 entries"            "printf '%s' \"$out\" | jq -e 'length==2'"
check "entry has number+url"     "printf '%s' \"$out\" | jq -e '.[0].number and .[0].url'"
check "rejects unknown scope"    "! ( PATH=\"$tmp:\$PATH\" sh '$root/scripts/collect-window.sh' OWNER/REPO bogus x )"
rm -rf "$tmp"
exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh ~/.claude/worklog/scripts/tests/test-collect-window.sh`
Expected: FAIL (collect-window.sh absent).

- [ ] **Step 3: Write collect-window.sh**

```sh
#!/usr/bin/env sh
# Gather GitHub PR facts for a window. Prints a JSON array to stdout.
# Usage: collect-window.sh REPO KIND VALUE
#   KIND date       VALUE=YYYY-MM-DD        -> PRs merged on that date
#   KIND pr-single  VALUE=NUMBER            -> that one PR
#   KIND pr-range   VALUE=NUMBER..NUMBER    -> inclusive PR-number range
#   KIND since      VALUE=NUMBER            -> PRs with number >= VALUE
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
wl_need gh; wl_need jq

repo="${1:?repo required}"; kind="${2:?kind required}"; value="${3:?value required}"

# Pull a generous candidate set once, then filter in jq. Fields match gh's schema.
raw="$(gh pr list --repo "$repo" --state all --limit 200 \
        --json number,title,mergedAt,createdAt,url,state)"

case "$kind" in
  date)
    printf '%s' "$raw" | jq --arg d "$value" \
      '[ .[] | select((.mergedAt // "")[0:10] == $d) ]' ;;
  pr-single)
    printf '%s' "$raw" | jq --argjson n "$value" '[ .[] | select(.number == $n) ]' ;;
  pr-range)
    lo="${value%%..*}"; hi="${value##*..}"
    printf '%s' "$raw" | jq --argjson lo "$lo" --argjson hi "$hi" \
      '[ .[] | select(.number >= $lo and .number <= $hi) ]' ;;
  since)
    printf '%s' "$raw" | jq --argjson n "$value" '[ .[] | select(.number >= $n) ]' ;;
  *)
    wl_die "unknown scope kind: $kind (date|pr-single|pr-range|since)" ;;
esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `sh ~/.claude/worklog/scripts/tests/test-collect-window.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/.claude/worklog && git add scripts/collect-window.sh scripts/tests/test-collect-window.sh scripts/tests/fixtures/gh-stub
git commit -m "feat: collect-window gathers PR facts per scope"
```

---

## Task 5: scripts/validate-draft.sh — SP / date / dedup contract

**Files:**
- Create: `~/.claude/worklog/scripts/validate-draft.sh`
- Create fixtures: `draft-ok.md`, `draft-baddate.md`, `draft-dupe.md`, `logged-prs.txt`
- Test: `~/.claude/worklog/scripts/tests/test-validate-draft.sh`

- [ ] **Step 1: Write the failing test + fixtures**

`~/.claude/worklog/scripts/tests/fixtures/logged-prs.txt`:
```
174
181
```

`~/.claude/worklog/scripts/tests/fixtures/draft-ok.md`:
```
<!-- worklog:meta
{ "date":"2026-06-04",
  "entries":[
    {"target":"new","title":"TASK-43 · csv import","sp":8,"status":"done","start":"2026-06-04","due":"2026-06-04","parent":"umbrella","prs":[186],"links":["u"]},
    {"target":"TASK-34","title":"TASK-34.6 · anti-fp tail","sp":3,"status":"in progress","start":"2026-06-04","parent":"TASK-34","prs":[136],"links":["u"]}
  ]
}
worklog:meta -->
# Draft 2026-06-04
ok
```

`~/.claude/worklog/scripts/tests/fixtures/draft-baddate.md` (in-progress with a due date — must fail):
```
<!-- worklog:meta
{ "date":"2026-06-04",
  "entries":[
    {"target":"new","title":"bad","sp":3,"status":"in progress","start":"2026-06-04","due":"2026-06-04","parent":"none","prs":[999],"links":["u"]}
  ]
}
worklog:meta -->
```

`~/.claude/worklog/scripts/tests/fixtures/draft-dupe.md` (reuses already-logged PR 181 — must fail):
```
<!-- worklog:meta
{ "date":"2026-06-04",
  "entries":[
    {"target":"new","title":"dupe","sp":3,"status":"done","start":"2026-06-04","due":"2026-06-04","parent":"none","prs":[181],"links":["u"]}
  ]
}
worklog:meta -->
```

`~/.claude/worklog/scripts/tests/test-validate-draft.sh`:
```sh
#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fx="$root/scripts/tests/fixtures"; v="$root/scripts/validate-draft.sh"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

check "valid draft passes"          "sh '$v' '$fx/draft-ok.md' '$fx/logged-prs.txt'"
check "in-progress+due fails"       "! sh '$v' '$fx/draft-baddate.md' '$fx/logged-prs.txt'"
check "dedup violation fails"       "! sh '$v' '$fx/draft-dupe.md' '$fx/logged-prs.txt'"
check "prints SP total"             "sh '$v' '$fx/draft-ok.md' '$fx/logged-prs.txt' | grep -q 'SP total: 11'"
exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh ~/.claude/worklog/scripts/tests/test-validate-draft.sh`
Expected: FAIL (validate-draft.sh absent).

- [ ] **Step 3: Write validate-draft.sh**

```sh
#!/usr/bin/env sh
# Validate a worklog draft against the format contract.
# Usage: validate-draft.sh DRAFT_MD LOGGED_PRS_TXT
# Exits 0 if valid (prints "SP total: N"), 1 if any rule fails (prints reasons), 2 on usage error.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
wl_need jq

draft="${1:?draft path required}"; logged="${2:-/dev/null}"
[ -s "$draft" ] || wl_die "draft missing or empty: $draft"

# Extract JSON between the worklog:meta markers.
meta="$(awk '/worklog:meta -->/{f=0} f; /<!-- worklog:meta/{f=1}' "$draft")"
printf '%s' "$meta" | jq -e . >/dev/null 2>&1 || wl_die "no valid worklog:meta JSON block"

errs=0
note() { printf 'INVALID: %s\n' "$1" >&2; errs=1; }

# Per-entry structural + date rule, via jq returning offending indexes.
bad_struct="$(printf '%s' "$meta" | jq -r '
  [ .entries | to_entries[]
    | select((.value.title|type)!="string"
        or (.value.sp|type)!="number" or .value.sp <= 0
        or (.value.status|IN("done","in progress")|not)
        or (.value.start|type)!="string")
    | .key ] | join(",")')"
[ -z "$bad_struct" ] || note "entries with bad title/sp/status/start: [$bad_struct]"

bad_date="$(printf '%s' "$meta" | jq -r '
  [ .entries | to_entries[]
    | select( (.value.status=="done"   and ((.value.due|type)!="string"))
           or (.value.status=="in progress" and (.value.due!=null and (.value.due|type)=="string")) )
    | .key ] | join(",")')"
[ -z "$bad_date" ] || note "date-rule violations (done needs due; in progress must not have due): [$bad_date]"

# Dedup: any PR already in logged-prs.txt.
if [ -s "$logged" ]; then
  for pr in $(printf '%s' "$meta" | jq -r '.entries[].prs[]?'); do
    if grep -qx "$pr" "$logged"; then note "PR #$pr already logged (dedup)"; fi
  done
fi

total="$(printf '%s' "$meta" | jq '[.entries[].sp] | add // 0')"
[ "$errs" -eq 0 ] || exit 1
printf 'SP total: %s\n' "$total"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `sh ~/.claude/worklog/scripts/tests/test-validate-draft.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/.claude/worklog && git add scripts/validate-draft.sh scripts/tests/test-validate-draft.sh scripts/tests/fixtures
git commit -m "feat: validate-draft enforces sp/date/dedup contract"
```

---

## Task 6: commands/log-day.md

**Files:**
- Create: `~/.claude/worklog/commands/log-day.md`
- Test: `~/.claude/worklog/scripts/tests/test-command.sh`

- [ ] **Step 1: Write the failing test**

```sh
# ~/.claude/worklog/scripts/tests/test-command.sh
#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"; f="$root/commands/log-day.md"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
check "command file exists"        "[ -s '$f' ]"
check "has frontmatter description" "grep -q '^description:' '$f'"
check "invokes worklog-day skill"  "grep -q 'worklog-day' '$f'"
check "passes \$ARGUMENTS"          "grep -q 'ARGUMENTS' '$f'"
exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh ~/.claude/worklog/scripts/tests/test-command.sh`
Expected: FAIL (file absent).

- [ ] **Step 3: Write the command**

`~/.claude/worklog/commands/log-day.md`:
```markdown
---
description: End-of-day worklog → ClickUp. Gathers GitHub facts for a window you name, writes a review draft, and after approval mirrors it into ClickUp.
argument-hint: "[window — e.g. 'вчера', '2026-06-04', '#180..#186', blank to be asked]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "AskUserQuestion", "Skill", "mcp__clickup__clickup_get_list", "mcp__clickup__clickup_filter_tasks", "mcp__clickup__clickup_resolve_assignees", "mcp__clickup__clickup_create_task", "mcp__clickup__clickup_update_task", "mcp__clickup__clickup_add_task_link", "mcp__clickup__clickup_create_task_comment"]
---

# /log-day

1. Invoke the **`worklog-day`** skill and follow it exactly. It is the source of truth for the
   4-stage / 2-gate flow (scope → gather → draft+GATE → write → links) and the onboarding step.
2. The skill never writes to ClickUp before the user approves the draft.

Window argument: `$ARGUMENTS` (blank = the skill asks which window to take).
```

- [ ] **Step 4: Run test to verify it passes**

Run: `sh ~/.claude/worklog/scripts/tests/test-command.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/.claude/worklog && git add commands/log-day.md scripts/tests/test-command.sh
git commit -m "feat: /log-day command entry point"
```

---

## Task 7: skills/worklog-day/SKILL.md — orchestration + onboarding

**Files:**
- Create: `~/.claude/worklog/skills/worklog-day/SKILL.md`
- Test: `~/.claude/worklog/scripts/tests/test-skill.sh`

- [ ] **Step 1: Write the failing test**

```sh
# ~/.claude/worklog/scripts/tests/test-skill.sh
#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"; f="$root/skills/worklog-day/SKILL.md"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
check "skill file exists"      "[ -s '$f' ]"
check "has name frontmatter"   "grep -q '^name: worklog-day' '$f'"
check "has description"        "grep -q '^description:' '$f'"
for s in "S0" "S1" "S2" "S3" "S4" "Onboarding" "collect-window.sh" "validate-draft.sh" "worklog.config.json" "clickup_create_task" "clickup_add_task_link"; do
  check "mentions $s" "grep -q '$s' '$f'"
done
check "states no-write-before-approval" "grep -qi 'never write' '$f' || grep -qi 'не пиши' '$f'"
exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh ~/.claude/worklog/scripts/tests/test-skill.sh`
Expected: FAIL (file absent).

- [ ] **Step 3: Write the skill**

`~/.claude/worklog/skills/worklog-day/SKILL.md`:
````markdown
---
name: worklog-day
description: Use at end of day to mirror a window of GitHub work into ClickUp — gather facts, write a review draft, and after explicit approval create/update tasks and return links. Never writes to ClickUp before approval.
---

# Worklog Day

End-of-day, post-factum worklog mirror. You gather GitHub facts for a window the user names,
write a review draft, STOP for approval, then mirror approved entries into ClickUp and return
exact links. **You never create or update a ClickUp task before the user approves the draft.**

Announce at start: "Using worklog-day to mirror <window> into ClickUp."

Resolve the plugin scripts dir once: it is this skill's `../../scripts` (i.e.
`<plugin>/scripts/`). Call it `$SCRIPTS` below.

## Config

Read `.claude/worklog.config.json` from the current project root. If absent → run
**Onboarding** first. The config supplies: `github_repo`, `clickup_list_id`,
`umbrella_task_id`, `assignee_id`, `naming`, `sp_calibration`, `drafts_dir`, `terminology`,
`language`. Treat these as the only source of project-specific values — never hardcode IDs.

## Onboarding (first run in a project, no config)

1. Derive `github_repo` from `git remote get-url origin` (strip to `OWNER/REPO`).
2. Ask the user (AskUserQuestion) for: `clickup_list_id`, `assignee_id` (or "me" →
   `clickup_resolve_assignees`), numbering `scheme`/`start_n`, `drafts_dir`, `language`.
3. Copy `references/worklog.config.example.json`, fill the answers, write
   `.claude/worklog.config.json`.
4. Ensure the consuming repo hides the fish: append `.claude/worklog.config.json` and the
   `drafts_dir` to that project's `.gitignore` (create if needed). Confirm to the user.
5. Continue to S0.

## S0 — Scope

Map the user's words / `$ARGUMENTS` to a scope kind+value for `collect-window.sh`:
- `вчера`/`yesterday` or a bare `YYYY-MM-DD` → `date YYYY-MM-DD` (compute "yesterday" from
  today; ask if ambiguous).
- `#N` → `pr-single N`. `#A..#B` → `pr-range A..B`. `с #N`/`since #N` → `since N`.
- Blank → ask which window to take. Never guess silently.

## S1 — Gather (read-only)

1. `sh "$SCRIPTS/collect-window.sh" <github_repo> <kind> <value>` → save stdout to
   `$(sh "$SCRIPTS/lib.sh"...)`. Concretely: compute run dir via
   `RUN=$(. "$SCRIPTS/lib.sh"; wl_run_dir <date-or-today>)` and write to `$RUN/window.json`.
2. Read current ClickUp state for dedup + correct linking:
   `clickup_filter_tasks` with `list_ids:[clickup_list_id]`, `include_closed:true`,
   `subtasks:true`. From the returned tasks, extract every `#NNN` PR number already present in
   names/descriptions and write them (one per line) to `$RUN/logged-prs.txt`. Also note
   existing task ids/codes you may extend (e.g. an in-progress task matching today's work).
3. If `window.json` is empty → tell the user the window has no PRs and stop.

## S2 — Draft  → 🚦 GATE 1 (STOP)

1. Compose `<drafts_dir>/<date>.md` per `references/format.md`: the `worklog:meta` JSON block
   (machine contract) + the human markdown block. For each PR/cluster decide a `target`
   (`new` vs an existing task id) and propose `sp`, `status` (merged → `done`; open → `in
   progress`), dates (date rule), `parent`, `prs`, `links`. The attach-vs-new choice is a
   PROPOSAL.
2. Validate: `sh "$SCRIPTS/validate-draft.sh" <drafts_dir>/<date>.md "$RUN/logged-prs.txt"`.
   Fix any `INVALID:`/`ERROR:` until it prints `SP total: N`.
3. Present to the user: the SP total, each proposed entry (target, title, status, dates, PRs),
   and the draft path. Then **STOP and wait for explicit approval.** Do NOT call any ClickUp
   write tool yet.

## S3 — Write (only after approval)

For each entry in the approved `worklog:meta`:
- `target=="new"` → `clickup_create_task` with `list_id=clickup_list_id`,
  `name=<title>`, `markdown_description=<human block for this entry>`,
  `assignees=[assignee_id]`, `start_date`, and `due_date` ONLY if `status=="done"`,
  `status` mapped to the list's status name (done → the list's completed status; in progress →
  its in-progress status — read names via `clickup_get_list` if unsure).
- `target` is an existing id → `clickup_update_task` (update description/dates/status; set
  `due_date` when moving to done). Do not rename manager-owned tasks; add a
  `clickup_create_task_comment` instead when only annotating.
- Links: after create, `clickup_add_task_link` between the entry and its `parent`
  (resolve `"umbrella"` → `umbrella_task_id`), and any real cross-links.
- After each successful create, append its PR numbers to `$RUN/logged-prs.txt` (prevents
  intra-run dupes).

## S4 — Return links

List every created/updated task as `name → https://app.clickup.com/t/<id>`. Report counts
(created / updated / linked) and the SP total written. Done.

## Guardrails

- Never write to ClickUp before S2 approval.
- Never rename/rewrite manager-owned tasks — comment only.
- Never put the word «епік» (or the project's `terminology.avoid`) in any task.
- Never invent SP/dates not in the approved draft.
- No `time tracking` API — dates only.
````

- [ ] **Step 4: Run test to verify it passes**

Run: `sh ~/.claude/worklog/scripts/tests/test-skill.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/.claude/worklog && git add skills/worklog-day/SKILL.md scripts/tests/test-skill.sh
git commit -m "feat: worklog-day orchestration skill"
```

---

## Task 8: Full test sweep + local install smoke

**Files:**
- Create: `~/.claude/worklog/scripts/tests/run-all.sh`

- [ ] **Step 1: Write the aggregate runner**

```sh
# ~/.claude/worklog/scripts/tests/run-all.sh
#!/usr/bin/env sh
set -eu
d="$(cd "$(dirname "$0")" && pwd)"
fail=0
for t in "$d"/test-*.sh; do
  echo "== $t =="
  if ! sh "$t"; then fail=1; fi
done
[ "$fail" -eq 0 ] && echo "ALL GREEN" || echo "SOME FAILED"
exit $fail
```

- [ ] **Step 2: Run the full sweep**

Run: `sh ~/.claude/worklog/scripts/tests/run-all.sh`
Expected: `ALL GREEN`.

- [ ] **Step 3: Local install smoke (manual, no push yet)**

In Claude Code:
```
/plugin marketplace add ~/.claude/worklog
/plugin install worklog@worklog-dev
```
Expected: `worklog` installs; `/log-day` appears in the command list. (Do not run a real
ClickUp write here — the gate makes that safe, but this step only verifies discovery.)

- [ ] **Step 4: Commit**

```bash
cd ~/.claude/worklog && git add scripts/tests/run-all.sh
git commit -m "test: aggregate test runner"
```

---

## Task 9 (user-gated, shared repo): AlterPoka draft-tracking cleanup

> Runs in the **shared** AlterPoka repo, not the plugin. Its own `chore/` branch + PR. The
> commit message must be neutral (no mention of AI/worklog automation). Do NOT run until the
> user explicitly approves — it changes shared git tracking.

**Files:**
- Modify: `<alterpoka-repo>/.gitignore`
- Untrack: `<alterpoka-repo>/ClickUp/tasks-ua/`

- [ ] **Step 1: Confirm tasks-ua is tracked**

Run: `cd "/Users/atlantdak/Local Sites/alterpoka/app/public" && git ls-files ClickUp/tasks-ua | head`
Expected: a list of tracked files (confirms cleanup is needed). If empty, skip this task.

- [ ] **Step 2: Create chore branch**

```bash
cd "/Users/atlantdak/Local Sites/alterpoka/app/public"
git switch -c chore/untrack-local-clickup-notes origin/main
```

- [ ] **Step 3: Untrack + gitignore (keeps local files)**

```bash
git rm -r --cached ClickUp/tasks-ua
printf '\n# Local-only worklog notes\nClickUp/\n' >> .gitignore
git add .gitignore
git commit -m "chore: stop tracking local ClickUp draft notes"
```

- [ ] **Step 4: Verify local files survive + nothing tracked**

Run: `ls ClickUp/tasks-ua | head && git ls-files ClickUp/ | wc -l`
Expected: files still on disk; `0` tracked.

- [ ] **Step 5: Push + PR (user-gated)**

```bash
git push -u origin chore/untrack-local-clickup-notes
gh pr create --fill
```

---

## Task 10 (user-gated): Publish the private plugin

> Outward action. Run only when the user says go.

- [ ] **Step 1: Create the private repo and push**

```bash
gh repo create atlantdak/worklog --private --source ~/.claude/worklog --push
```
Expected: repo `atlantdak/worklog` (private) created; initial history pushed.

- [ ] **Step 2: Re-install from the remote marketplace**

In Claude Code:
```
/plugin marketplace add atlantdak/worklog
/plugin install worklog@worklog-dev
```
Expected: installs from the private remote; `/log-day` available globally.

- [ ] **Step 3: First real end-to-end run (user-supervised)**

Run `/log-day вчера` in AlterPoka, review the draft at the gate, approve, confirm the returned
ClickUp links resolve. This is the acceptance test for the whole plugin.

---

## Self-Review

**Spec coverage:**
- §1 purpose / post-factum / no-write-before-approval → Tasks 7 (skill), 6 (command). ✓
- §2 form + privacy + neutral name + gitignore + AlterPoka cleanup → Tasks 1, 7 (onboarding gitignore), 9, 10. ✓
- §3 input `/log-day <scope>` words → Task 6 + skill S0. ✓
- §4 flow S0–S4 + 2 gates → skill (Task 7) + scripts (4,5). ✓
- §5 onboarding → skill Onboarding section (Task 7). ✓
- §6 per-project config → config.example (Task 2) + onboarding (Task 7). ✓
- §7 generic references (format/date-rule/SP/example) → Task 2. ✓
- §8 scripts (collect-window, dedup, validate) → Tasks 4, 5 (dedup realized as logged-prs.txt produced in S1, consumed by validate-draft). ✓
- §9 YAGNI (no ledger / no auto-write / no rename / no time-tracking) → resolved in plan header + skill Guardrails. ✓
- §10 open questions → resolved in plan header (sh+jq / ephemeral tmp / no time-tracking). ✓

**Placeholder scan:** No "TBD"/"handle edge cases" — every script and artifact has full content. The only intentionally generic values are in `worklog.config.example.json` (OWNER/REPO, zero IDs), which is correct for a template. ✓

**Type/name consistency:** `wl_run_dir`/`wl_die`/`wl_need` defined in Task 3, used in 4/5. `worklog:meta` block + fields (`target/title/sp/status/start/due/parent/prs/links`) consistent across format.md (2), validator (5), skill (7). Scope kinds `date|pr-single|pr-range|since` consistent across command/skill/collect-window. Marketplace name `worklog-dev` consistent across manifest (1) and install steps (8,10). ✓
