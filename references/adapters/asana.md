---
tracker: asana
rich_text: html_subset
nesting: native
status: section
---

# Asana adapter

Everything the core must not know lives here: which tools to call, what the
board's vocabulary is, and how the neutral draft contract lands on it.

Measured on a live board, not assumed — the notes below reflect what the API
actually returned.

## Capabilities

| Key | Value | What it means for the core |
| --- | --- | --- |
| `rich_text` | `html_subset` | the human block is rendered as `html_notes` |
| `nesting` | `native` | a child carries a real parent task gid |
| `status` | `section` | "done" is a section **and** the `completed` flag |

## Config

| Key | Required | Meaning |
| --- | --- | --- |
| `asana.project_gid` | yes | the project every task is created in |
| `asana.workspace_gid` | no | only needed to build permalinks by hand |
| `sections` | yes | все пять канонических ключей ядра → gid секции |
| `umbrella_task_id` | no | master task that top-level entries hang under |
| `assignee_id` | no | pins the assignee instead of the authenticated user |

Section gids are read once with `get_project` (`include_sections: true`) and
pinned in the config by the user. They are never guessed at write time.

## Sections

The core's five canonical keys map onto section gids. The mapping is required
and complete: a missing key is a configuration error, not a licence to pick a
section by its display name. Matching names are a coincidence, not a guarantee,
and a wrong pick puts a card in the wrong column with nothing to show for it.

| Core key | What it is here |
| --- | --- |
| `backlog` | a project section |
| `to_do` | a project section |
| `in_progress` | a project section |
| `review` | a project section |
| `done` | a project section **and** the `completed` flag |

## Board operations

| Operation | Call | Notes |
| --- | --- | --- |
| `find` | `get_task` with `task_id` | "not found" is an error of the call — tell it apart from a network failure |
| `find_by_origin` | `search_tasks` with `text` = the marker and `projects_any` = the project | **verified live on 2026-09-01:** it matches a phrase that appears only in a task's description, and returns completed tasks too |
| `place` | `add_projects` with the `section_id` from `sections[<key>]` | for `done`, also set `completed: true` |
| `close` | `update_tasks` with `completed: true` and the text in `html_notes` | story points live inside the description text |

Zero matches from `find_by_origin` means "no card yet, create one". More than
one is a stop: the marker has stopped being unique, and picking the first is
how a second card quietly becomes the wrong one.

## Assignee

Pass `assignee: "me"` on every create and update — the MCP resolves it to the
authenticated user, so no id is ever stored in the plugin or the config. Use
`eff.assignee_id` only when the config pins it (logging on someone's behalf).
`create_tasks` also accepts `default_assignee: "me"` once for the whole batch.

## Read state

`get_tasks` with `project = asana.project_gid` and
`opt_fields = gid,name,notes,completed,parent.gid,memberships.section.name,memberships.section.gid,permalink_url`.

From the returned tasks extract every `#NNN` PR number found in names and notes,
one per line, into `$RUN/logged-prs.txt` — that file is what the validator dedups
against. Subtasks are members of the project (see *Nesting*), so one call covers
them; a subtask created elsewhere without project membership will not appear.

## Create

`create_tasks` with `default_project = asana.project_gid` and one object per task:

| Draft field | Call field |
| --- | --- |
| `title` | `name` |
| human block | `html_notes` (single `<body>` root) |
| — | `assignee` = `"me"` (or the pinned override) |
| `start` | `start_on` — **only** when `status == "done"` (see below) |
| `due` | `due_on` — **only** when `status == "done"` |
| `status` | `section_id` from `section_map` + `completed: true` when done |

Asana refuses `start_on` without `due_on` — on create just as on update. An
`in progress` entry has no completion date by contract, so it carries **no dates
at all**: put the start in the prose instead ("in progress since Sep 1"), which
is what the human block says anyway.

Allowed tags in `html_notes`: `<body> <strong> <em> <u> <s> <code> <ol> <ul>
<li> <a> <blockquote> <pre> <h1> <h2> <hr/> <img>`. Anything else — or malformed
XML, or an attribute on a non-`<a>` element — is a 400. Emoji are plain text and
pass through fine.

Closing means both moves: the Done section **and** `completed: true`. Acceptance
waits in "Ready for Review", so Done is terminal; setting only the section would
leave every report counting the work as unfinished.

## Update

`update_tasks` with `task = <gid>` and the changed fields (`name`, `html_notes`,
`due_on`, `completed`, `assignee`, …). Moving a task between sections:
`add_projects: [{ project_id, section_id }]`.

Never rename a manager-owned task — annotate with `add_comment` instead
(comments allow the same subset **minus** `<h1>`, `<h2>`, `<hr/>` and `<img>`).

## Nesting

- `parent` is a container code → pass `parent = <container gid>` **and**
  `project_id` + `section_id`, so the subtask is both a real child and visible
  on the board.
- `parent: "root"` → a top-level task in the project. If `eff.umbrella_task_id`
  is set, pass it as the task's `parent` (there is no separate link primitive);
  otherwise the task simply stays top-level.
- `parent` is an existing task gid → `parent = <that gid>`.

## Links

Task URL: the `permalink_url` returned by the API — authoritative, use it when
you have it. Built by hand it is
`https://app.asana.com/1/<workspace_gid>/project/<project_gid>/task/<gid>`.

There is no task-link primitive: cross-references go into `html_notes` as
`<a href="…">`, or as `<a data-asana-gid="…"/>` to mention another task.

## Gotchas

- A task sitting in the Done section still reports `completed: false`. The flag
  and the section are independent — that is why closing sets both.
- There is no story-points field on the board: SP go into the description text.
- `start_on` may only be set when `due_on` is present — on create too, not just
  on update (`bad_request: You must provide due_on or due_at when setting
  start_on`). Hence: dates for `done` entries only.
- `html_notes` must be well-formed XML with exactly one `<body>` root; unclosed
  tags fail the whole batch. `<p>` is **not** allowed — separate paragraphs with
  blank lines inside `<body>`.
- `add_projects` with a `section_id` does move a task that is already in the
  project — verified on the board, no `remove_projects` dance needed. Keep that
  fallback in mind only if some board ever refuses the move.
- Subtasks created with `project_id` show up in `get_tasks` for the project, so
  the *Read state* call covers them — verified.
- No time tracking API: dates only, even though the board carries hour fields.
