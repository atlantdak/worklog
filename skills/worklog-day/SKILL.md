---
name: worklog-day
description: Use at end of day to mirror a window of GitHub work into your task tracker — gather facts, write a review draft, and after explicit approval create/update tasks and return links. Never writes to the tracker before approval.
---

# Worklog Day

End-of-day, post-factum worklog mirror. You gather GitHub facts for a window the user names,
write a review draft, STOP for approval, then mirror approved entries into the configured
tracker and return exact links. **You never create or update a task before the user approves
the draft.**

Announce at start: "Using worklog-day to mirror <window> into <tracker>." — the tracker name
comes from the resolved config, never from a guess.

Resolve the plugin dirs once: this skill's `../../scripts` and `../../references` (i.e.
`<plugin>/scripts/`, `<plugin>/references/`). Call them `$SCRIPTS` and `$REFS` below.

## Config

Resolve the effective config with the script, never by reading a single file:
`eff=$(sh "$SCRIPTS/resolve-config.sh" .)` (run from the project root). It layers
**built-in defaults < global `$HOME/.claude/worklog.config.json` < project
`.claude/worklog.config.json`** and prints a provenance table to stderr — show that table
to the user so the source of every value (project / global / built-in / dynamic) is visible.

Identity is **dynamic, never hardcoded**:
- `github_repo` — derived from the project's `git remote` when unset.
- assignee — the **authenticated tracker user**, resolved at write time per the adapter's
  *Assignee* section; a config `assignee_id` only *overrides* this (e.g. to log on someone's
  behalf). So the skill works in any project as "log my work to my account".

The per-project bindings are whatever the resolved tracker requires — `resolve-config.sh`
prints them in its provenance table (plus the optional `umbrella_task_id`). Preferences
(`language`, `naming`, `sp_calibration`, `terminology`, `drafts_dir`) live in the global config
or built-in defaults. Treat the resolved `eff` as the only source of values — never hardcode
ids. If `resolve-config.sh` exits **3** (`NEEDS_ONBOARDING`) → run **Onboarding**; if it exits
**2** with `unknown tracker`, tell the user and stop.

## Adapter

The tracker is `eff.tracker`. Load `$REFS/adapters/<eff.tracker>.md` — that file is the ONLY
place tracker-specific knowledge lives, and you resolve it **by that key**, never by guessing
from the tools you happen to have. **Announce which adapter you loaded** before touching the
tracker. If the file does not exist, stop and tell the user the tracker is unsupported (adding
one means a file there plus a line in `resolve-config.sh`).

Read its frontmatter capabilities and let them steer you:

- `rich_text` — `markdown`: pass the human block through verbatim; `html_subset`: render it
  as the allowed HTML the adapter lists; `plain`: strip the formatting.
- `nesting` — `native`: a child carries a real parent id; `link`: create it top-level and link
  it to its parent.
- `status` — how "done" is expressed: a named status, a section, a completion flag, or the
  combination the adapter spells out.

Every call to the tracker follows the adapter's sections: *Assignee*, *Read state*, *Create*,
*Update*, *Nesting*, *Links*. Read its *Gotchas* before the first write.

## Onboarding (first run in a project, no resolvable binding)

1. `github_repo` is auto-derived (git remote) — no question needed; confirm what was detected.
2. Ask the user (AskUserQuestion) which tracker to use — the options are exactly the filenames
   in `$REFS/adapters/` — then ask only for the keys that tracker requires (they are named in
   the `NEEDS_ONBOARDING` line and in the adapter's *Config* section).
3. Write a **minimal** `.claude/worklog.config.json` (just `tracker` + its binding(s)) from
   `references/worklog.config.project.example.json`. If the user wants non-default preferences
   everywhere, offer to write/extend the global `$HOME/.claude/worklog.config.json`
   (template: `references/worklog.config.global.example.json`) instead of repeating them per
   project.
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
2. Read the current tracker state for dedup + correct linking: follow the adapter's
   *Read state* recipe. From the returned tasks, extract every `#NNN` PR number already present
   in names/descriptions and write them (one per line) to `$RUN/logged-prs.txt`. Also note
   existing task ids/codes you may extend (e.g. an in-progress task matching today's work) and
   how the board already nests its children.
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
     task. `parent` is `"root"` for a top-level entry, a container code for a child, or an
     existing task id — the draft never encodes where the board keeps its master task. Present
     the chosen split at the gate so the user can re-group it. See
     `references/format.md` → *Structure*.
   - **Voice by status:** `done` entries are past-tense (what was done + result, concrete
     results, closed dates); `in progress` entries are present-tense (what we're doing + status,
     what still remains) with no closed date range and no completion claims. Render headings in
     the configured `language`. See `references/format.md`.
2. Validate: `sh "$SCRIPTS/validate-draft.sh" <drafts_dir>/<date>.md "$RUN/logged-prs.txt"`.
   Fix any `INVALID:`/`ERROR:` until it prints `SP total: N`.
3. Present to the user: the SP total, each proposed entry (target, title, status, dates, PRs),
   and the draft path. Then **STOP and wait for explicit approval.** Do NOT call any tracker
   write tool yet.

## S3 — Write (only after approval)

Resolve the assignee once, per the adapter's *Assignee* section: `eff.assignee_id` when the
config pins it, otherwise the authenticated tracker user (`"me"`). Call it `ASSIGNEE`.

**Create the umbrellas (`containers`) FIRST**, capture each returned id, then create the
entries — a child must reference its parent's real id. For each entry:

- `target == "new"` → the adapter's *Create* call with the title, the human block rendered per
  `rich_text`, `ASSIGNEE`, the start date, the completion date ONLY when `status == "done"`,
  and the status expressed per `status`.
- Placement follows `parent` and the adapter's *Nesting* section: a container code → a child of
  that container (with `nesting: native`, a real parent id — do not also link it); `"root"` →
  top level, and when `eff.umbrella_task_id` is set, attached to that master task the way the
  adapter prescribes; an existing id → a child of it.
- `target` is an existing id → the adapter's *Update* call (description/dates/status; set the
  completion date when moving to done). Do not rename manager-owned tasks — annotate them
  instead, per the adapter.
- After each successful create, append its PR numbers to `$RUN/logged-prs.txt` (prevents
  intra-run dupes).

## S4 — Return links

List every created/updated task as `name → <task URL built per the adapter's *Links* section>`.
Report counts (created / updated / linked) and the SP total written. Done.

## Guardrails

- Never write to the tracker before S2 approval.
- Never rename/rewrite manager-owned tasks — comment only.
- Assign the work to the authenticated tracker user unless the config pins `assignee_id`;
  never hardcode a user id.
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
