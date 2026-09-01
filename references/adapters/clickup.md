---
tracker: clickup
rich_text: markdown
nesting: native
status: named
---

# ClickUp adapter

Everything the core must not know lives here: which tools to call, what the
board's vocabulary is, and how the neutral draft contract lands on it.

## Capabilities

| Key | Value | What it means for the core |
| --- | --- | --- |
| `rich_text` | `markdown` | the human block goes in verbatim as markdown |
| `nesting` | `native` | a child carries a real parent task id |
| `status` | `named` | "done" is a status name defined by the list |

## Config

| Key | Required | Meaning |
| --- | --- | --- |
| `clickup_list_id` | yes | the list every task is created in |
| `umbrella_task_id` | no | master task that top-level entries are linked to |
| `assignee_id` | no | pins the assignee instead of the authenticated user |

## Assignee

Resolve once per run, before the first write:

- `eff.assignee_id` set → use `[eff.assignee_id]` (an explicit override, e.g.
  logging on someone's behalf).
- otherwise → `clickup_resolve_assignees ["me"]` and use the returned id. That
  is the authenticated user of the connected account. **Never hardcode an id**
  and never carry one over from a previous run.

Pass it as `assignees` on every `clickup_create_task`; on
`clickup_update_task`, only when the task has no assignee yet.

## Read state

`clickup_filter_tasks` with `list_ids: [clickup_list_id]`, `include_closed: true`,
`subtasks: true`.

From the returned tasks extract every `#NNN` PR number found in names and
descriptions, one per line, into `$RUN/logged-prs.txt` — that file is what the
validator dedups against. Note the ids of tasks worth extending (an in-progress
task covering today's work) and inspect one existing subtask to see how the
board already nests.

## Create

`clickup_create_task`:

| Draft field | Call field |
| --- | --- |
| `title` | `name` |
| human block | `markdown_description` |
| — | `list_id` = `eff.clickup_list_id` |
| — | `assignees` = the resolved assignee |
| `start` | `start_date` |
| `due` | `due_date` — **only** when `status == "done"` |
| `status` | `status` = the list's matching status name |

Status names are per-list: read them with `clickup_get_list` rather than
assuming "Complete" or "Done". `done` → the list's completed status;
`in progress` → its in-progress status.

## Update

`target` is an existing id → `clickup_update_task` (description, dates, status;
set `due_date` when moving to done). Never rename a manager-owned task — add a
`clickup_create_task_comment` when you only need to annotate it.

## Nesting

- `parent` is a container code → pass the native `parent = <container task id>`
  on `clickup_create_task`. Do **not** also link it: native nesting is the
  relationship.
- `parent: "root"` → create top-level (no `parent`). If `eff.umbrella_task_id`
  is set, `clickup_add_task_link` the new task to it — that is a cross-list
  link, not nesting. If it is not set, the task simply stays top-level.
- `parent` is an existing task id → native `parent = <that id>`.
- Fallback: if the workspace rejects native subtasks ("Cannot make subtasks…"),
  create the task top-level and `clickup_add_task_link` it to its parent
  instead — the `TASK-NN.m` name already encodes the level.

## Links

Task URL: `https://app.clickup.com/t/<id>` — that is what S4 reports.
Real cross-references between tickets: `clickup_add_task_link`.

## Gotchas

- `clickup_filter_tasks` skips subtasks unless `subtasks: true`; without it the
  dedup file misses PRs already logged one level down.
- Story points live in the description text. The custom field is not used.
- No time tracking: dates only.
