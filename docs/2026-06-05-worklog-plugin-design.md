# Design: local `worklog` plugin (end of day -> ClickUp)

> **Status:** design approved 2026-06-05. Next step: implementation plan (`writing-plans`).
> **Intentionally outside shared project repositories:** both the plugin and this spec are local,
> because configs and draft files can contain project-specific data and should stay out of shared repositories.

## 1. Purpose

End-of-day plugin. Given a natural-language window from the user, it gathers facts from
GitHub for that window, writes `.md` drafts for review, and after explicit approval writes
tasks to ClickUp through MCP and returns exact links. **The agent never writes to ClickUp
before approval.** The user chose a retrospective mode, not morning planning.

Privacy note: configs and draft files are not committed because they contain project-specific data. ClickUp receives only the approved worklog output.

## 2. Shape And Locality

- **One portable plugin** with the neutral name `worklog` (no `project` or `ai` in the name).
  Structure follows a similar plugin: `command + skill + references + scripts`, plus
  `.claude-plugin/plugin.json` and `marketplace.json`.
- **Storage:** local GitHub repository; source path: `/path/to/worklog/`.
  Global install through `/plugin marketplace add <local-repo>` makes it available in all
  user projects.
- **Local:** plugin + project config + drafts. **Shared externally:** only ClickUp tasks.
- In each working/shared repository: `.gitignore` covers `worklog.config.json` and the drafts
  directory (`_daily/` or the configured `drafts_dir`).
- **Example Project cleanup:** remove an already committed `ClickUp/_daily/` directory from
  the shared repository (`git rm -r --cached`), keep it locally, and add it to `.gitignore`.
  Do not lose draft sources, but remove them from shared history.

## 3. Input

One command: `/log-day <scope>`. `<scope>` is ordinary wording:

- date: `yesterday`, `2026-06-04`;
- PR: `#186`, `since #180`, `#180..#186`;
- blank -> the agent asks which window to use.

The source of truth for what to include is the user's wording. There is no automatic
"since last run" mode and no local ledger.

## 4. Flow (4 Stages, 2 Gates)

- **S0 - Scope.** Expands the wording into a concrete commit/PR set through `gh`.
- **S1 - Collection.** `gh` pulls PRs/commits for the window (number, title, dates, merge
  status, link). Reads the current ClickUp list (task IDs, umbrella, already mentioned PR
  numbers) for deduplication and correct linking. Coordinates come from the project config
  (§6).
- **S2 - Draft -> Gate 1.** Writes `.md` to `drafts_dir/YYYY-MM-DD.md` in the accepted
  format (§7). Suggests where to attach the work (extend an open task vs create a new one)
  **only as a proposal**. Runs the validator (§8). Shows the summary and path, then
  **stops**. It does not write to ClickUp.
- **S3 - Write** (after explicit "ok"). MCP creates/updates tasks: dates, status, assignee,
  SP heading, native relationships, and links in the description. `in progress -> done`
  where the PR is merged.
- **S4 - Links.** Returns exact URLs for created/updated tasks.

## 5. Onboarding (First Run In A Project)

If the project does not have `worklog.config.json`, the skill performs a short init: derives
`github_repo` from `git remote`, asks for the ClickUp list / assignee / numbering scheme /
`drafts_dir`, writes the config, and adds the config plus `drafts_dir` to `.gitignore`.
Daily runs after that just read the config.

## 6. Per-Project Config - `.claude/worklog.config.json`

```json
{
  "github_repo": "OWNER/REPO",
  "clickup_list_id": "000000000000",
  "umbrella_task_id": "TASK-ROOT",
  "assignee_id": "00000000",
  "naming": { "scheme": "TASK-{n}", "sub": "TASK-{n}.{m}", "start_n": 21 },
  "sp_calibration": "~14-15 SP per active day",
  "drafts_dir": "ClickUp/_daily",
  "terminology": { "avoid": ["epic"], "use": ["task", "subtask"] },
  "language": "en"
}
```

All project-specific data belongs here, not in the plugin. A neighboring project has its own
config, list, numbering, and language.

## 7. `references/` (Generic, Inside The Plugin)

Only universal material, with no hardcoded IDs:

- `format.md` - task description template (`## Story Points: N`, `Overview:` / `Task:`
  clickable link, `Subtasks`, `Pull requests`), date rule (`done -> start+due`;
  `in progress -> start only, no due`), default SP calibration, and the terminology rule
  that avoids `epic` (or the consuming project's `terminology` config).
- `worklog.config.example.json` - config template.

## 8. `scripts/` (Machine Gates)

- `collect-window.sh` - `gh` -> JSON facts for the window (PR number, title, dates, merge
  status, URL).
- dedup-helper - list of already logged PR numbers from ClickUp for S1 checks.
- `validate-draft` (`sh`/`php`) - SP sums, date rule, and required draft headings/links.

## 9. Intentionally Not Doing (YAGNI)

- No local ledger / automatic "since last run" mode - the user defines the window in words.
- No automatic writes to ClickUp without the gate.
- No renaming/rewriting other people's manager-owned tickets - at most a comment.
- No morning planning - retrospective only.
- No project-specific implementation details in shared artifacts.

## 10. Open Questions For The Implementation Plan

- Validator language: `sh` (no dependencies) vs `php` (available in the stack) - decide in
  the plan.
- Dedup-cache storage format for a single run (session memory only vs tmp).
- Whether ClickUp time tracking (`start`/`stop`) is needed, or whether start/due dates are enough.
