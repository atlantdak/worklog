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
- `yesterday` or a bare `YYYY-MM-DD` → `date YYYY-MM-DD` (compute "yesterday" from
  today; ask if ambiguous).
- `#N` → `pr-single N`. `#A..#B` → `pr-range A..B`. `since #N` → `since N`.
- Blank → ask which window to take. Never guess silently.

## S1 — Gather (read-only)

1. Compute the per-run dir, then gather. `lib.sh` is sourced, not executed:
   `RUN=$(. "$SCRIPTS/lib.sh"; wl_run_dir <date-or-today>)`, then
   `sh "$SCRIPTS/collect-window.sh" <github_repo> <kind> <value> > "$RUN/window.json"`.
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
