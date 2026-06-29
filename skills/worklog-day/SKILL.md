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

Resolve the effective config with the script, never by reading a single file:
`eff=$(sh "$SCRIPTS/resolve-config.sh" .)` (run from the project root). It layers
**built-in defaults < global `$HOME/.claude/worklog.config.json` < project
`.claude/worklog.config.json`** and prints a provenance table to stderr — show that table
to the user so the source of every value (project / global / built-in / dynamic) is visible.

Identity is **dynamic, never hardcoded**:
- `github_repo` — derived from the project's `git remote` when unset.
- assignee — the **authenticated ClickUp user**, resolved at write time via
  `clickup_resolve_assignees ["me"]`; a config `assignee_id` only *overrides* this (e.g. to
  log on someone's behalf). So the skill works in any project as "log my work to my account".

The only genuinely per-project binding is `clickup_list_id` (+ optional `umbrella_task_id`);
preferences (`language`, `naming`, `sp_calibration`, `terminology`, `drafts_dir`) live in the
global config or built-in defaults. Treat the resolved `eff` as the only source of values —
never hardcode IDs. If `resolve-config.sh` exits **3** (`NEEDS_ONBOARDING`) → run **Onboarding**.

## Onboarding (first run in a project, no resolvable `clickup_list_id`)

1. `github_repo` is auto-derived (git remote) — no question needed; confirm what was detected.
2. Ask the user (AskUserQuestion) only for the binding: `clickup_list_id` (+ optional
   `umbrella_task_id`). Do **not** ask for assignee (dynamic "me"), repo (auto), or
   preferences (global/built-in) unless the user wants a per-project override.
3. Write a **minimal** `.claude/worklog.config.json` (just the binding(s)) from
   `references/worklog.config.project.example.json`. If the user wants non-default
   preferences everywhere, offer to write/extend the global
   `$HOME/.claude/worklog.config.json` (template: `references/worklog.config.global.example.json`)
   instead of repeating them per project.
4. Ensure the consuming repo hides the fish: append `.claude/worklog.config.json` and the
   `drafts_dir` to that project's `.gitignore` (create if needed). Confirm to the user.
5. Continue to S0.

## S0 — Scope

Map the user's words / `$ARGUMENTS` to a scope kind+value for `collect-window.sh`:
- `yesterday` or a bare `YYYY-MM-DD` → `date YYYY-MM-DD` (compute "yesterday" from
  today; ask if ambiguous).
- `#N` → `pr-single N`. `#A..#B` → `pr-range A..B`. `since #N` → `since N`.
- Blank → ask which window to take. Never guess silently.

## S1 — Gather (read-only)

1. Compute the per-run dir, then gather. `lib.sh` is sourced, not executed:
   `RUN=$(. "$SCRIPTS/lib.sh"; wl_run_dir <date-or-today>)`, then
   `sh "$SCRIPTS/collect-window.sh" <github_repo-from-eff> <kind> <value> > "$RUN/window.json"`
   (use the `github_repo` from the resolved `eff`).
   The window is scoped to **your** GitHub account — resolved at runtime from
   `gh api user`, never hardcoded — so a teammate's PR merged in the same window is
   not mirrored as your work. To mirror someone else's PRs, or to include every
   author, prefix the call with `WL_AUTHOR=<login>` / `WL_AUTHOR='*'`. Each entry in
   `window.json` carries `author.login`; if you ever run with `WL_AUTHOR='*'`, surface
   any non-self PR to the user before drafting rather than logging it silently.
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
   - **Voice & granularity:** write titles/descriptions for a manager (plain-language value,
     not engineering detail) and consolidate the window's work into a few coherent deliverables
     rather than one card per PR — see `references/format.md` → *Audience & voice* and
     *Granularity (anti-spam)*, with the absolute rules in **Guardrails** below.
   - **Structure:** group by coherent theme/effort, not by calendar — a multi-theme/multi-day
     window may carry **several umbrellas** (`containers`), each with its own subtasks; a big
     single effort can be its own umbrella; trivial/related fixes fold (or compile) into one
     task. Present the chosen split at the gate so the user can re-group it. See
     `references/format.md` → *Structure*.
   - **Voice by status:** `done` entries are past-tense (what was done + result, concrete
     results, closed dates); `in progress` entries are present-tense (what we're doing + status,
     what still remains) with no closed date range and no completion claims. Render headings in
     the configured `language`. See `references/format.md`.
2. Validate: `sh "$SCRIPTS/validate-draft.sh" <drafts_dir>/<date>.md "$RUN/logged-prs.txt"`.
   Fix any `INVALID:`/`ERROR:` until it prints `SP total: N`.
3. Present to the user: the SP total, each proposed entry (target, title, status, dates, PRs),
   and the draft path. Then **STOP and wait for explicit approval.** Do NOT call any ClickUp
   write tool yet.

## S3 — Write (only after approval)

First resolve the assignee once: if `eff.assignee_id` is set use `[eff.assignee_id]`
(config override); otherwise call `clickup_resolve_assignees ["me"]` and use the returned id
— the authenticated ClickUp user. Call this `ASSIGNEE`.

**Create umbrellas (`containers`) FIRST**, capture each returned id, then create the entries —
a subtask must reference its parent's real id. For each `target=="new"` task:
- `clickup_create_task` with `list_id=eff.clickup_list_id`, `name=<title>`,
  `markdown_description=<human block for this entry>`, `assignees=ASSIGNEE`, `start_date`, and
  `due_date` ONLY if `status=="done"`, `status` mapped to the list's status name (done → the
  list's completed status; in progress → its in-progress status — read names via
  `clickup_get_list` if unsure).
- **Nesting — match how the board already nests** (inspect one existing subtask in S1):
  - **A subtask** (its `parent` is an umbrella code) → pass the **native** `parent=<umbrella id>`
    on `clickup_create_task`. Do NOT link it — native nesting is the relationship.
  - **An umbrella or standalone task** (`parent=="umbrella"`) → create top-level (no `parent`),
    then `clickup_add_task_link` it to `eff.umbrella_task_id` (a cross-list link, not nesting).
  - **Fallback:** if the workspace rejects native subtasks ("Cannot make subtasks…"), create the
    subtask top-level and `clickup_add_task_link` it to its parent instead (the `TASK-NN.m` name
    already encodes the level).
- `target` is an existing id → `clickup_update_task` (update description/dates/status; set
  `due_date` when moving to done). Do not rename manager-owned tasks; add a
  `clickup_create_task_comment` instead when only annotating.
- Real **cross-links** to other tickets → `clickup_add_task_link`.
- After each successful create, append its PR numbers to `$RUN/logged-prs.txt` (prevents
  intra-run dupes).

## S4 — Return links

List every created/updated task as `name → https://app.clickup.com/t/<id>`. Report counts
(created / updated / linked) and the SP total written. Done.

## Guardrails

- Never write to ClickUp before S2 approval.
- Never rename/rewrite manager-owned tasks — comment only.
- Never put a word from the project's `terminology.avoid` in any task.
- Never invent SP/dates not in the approved draft.
- No `time tracking` API — dates only.
- Write for a manager, not an engineer: plain-language value, no internal refs (`ADR-…`), code
  identifiers, or algorithm jargon in task names/descriptions — the PR links carry the detail.
- Keep product / tool / plugin / theme names verbatim — they are proper nouns and stay in
  canonical spelling regardless of `language`; never translate or transliterate. Respect the
  draft language's correct spelling and diacritics elsewhere (e.g. for uk, «беклог» not «бэклог»).
- Prefer fewer, consolidated entries (group the window's PRs into coherent deliverables) over
  many granular per-PR tasks; keep genuinely unrelated deliverables distinct.
- Match the prose to the status (mirror of the date rule): an `in progress` entry is present-
  tense (what we're doing + status), states what still remains, and carries NO closed date range
  and NO completion claim ("done / shipped / all checks green / in final review"). Concrete
  results and a closed period belong to `done` only.
- Don't force one umbrella: a multi-theme/multi-day window may need several umbrellas (or none);
  propose the structure at the gate instead of deciding silently.
