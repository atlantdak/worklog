---
tracker: worksection
rich_text: plain
nesting: native
status: completed_flag
write: manual
---

# Worksection adapter

Everything the core must not know lives here: which tools to call, what the
board's vocabulary is, and how the neutral draft contract lands on it.

**Write mode is manual.** The connected MCP is used for reading only. Every
create, update and close is done by the user in the Worksection web UI from a
paste-ready card the agent prepares; the user then hands back the task link.
The agent never calls a Worksection tool that changes data, even when the
server exposes one (`create_task`, `update_task`, `complete_task`,
`post_comment`, …) — the account's write access is not part of this flow.

## Capabilities

| Key | Value | What it means for the core |
| --- | --- | --- |
| `rich_text` | `plain` | the human block becomes plain text: no `#`, `**`, link markup |
| `nesting` | `native` | a child is a real subtask of its parent task |
| `status` | `completed_flag` | "done" is the task's closed state (the tick) |
| `write` | `manual` | the agent prepares cards, the user creates them by hand |

## Config

| Key | Required | Meaning |
| --- | --- | --- |
| `worksection.project_id` | yes | the project every task is created in (the number after `/project/` in its URL) |
| `worksection.account_url` | no | e.g. `https://novatraff.worksection.com`; needed to build links by hand |
| `sections` | no | optional: canonical key → tag name, when the board marks stages with tags |
| `umbrella_task_id` | no | master task that top-level entries hang under as subtasks |
| `assignee_id` | no | a person to name in the card instead of the user |

## Sections

Worksection has no workflow columns of its own: a task is open or closed. The
five canonical keys land like this:

| Core key | What it is here |
| --- | --- |
| `backlog` | open task, plus the tag from `sections.backlog` if configured |
| `to_do` | open task, plus the tag from `sections.to_do` if configured |
| `in_progress` | open task, plus the tag from `sections.in_progress` if configured |
| `review` | open task, plus the tag from `sections.review` if configured |
| `done` | closed task (the user ticks it after creating) |

No tag is ever guessed: without `sections`, every open state is just "open".

## Board operations

All of them are manual: the agent prints the instruction, the user does it in
the UI and confirms.

| Operation | How | Notes |
| --- | --- | --- |
| `find` | read MCP `get_task` by id | "not found" is distinct from a network failure |
| `find_by_origin` | read MCP `search_tasks` in the project, then an exact comparison of the marker | **not verified against a live project**; until it is, this branch of the idempotency scheme is unproven and must not be implemented |
| `place` | instruction to the user: set or clear the stage tag from `sections[<key>]` | the user confirms when done |
| `close` | instruction to the user: paste the result text into the task, then tick it closed | the user confirms when done |

More than one match is a stop, never a choice.

## Assignee

Resolve once per run, before the first card:

- `eff.assignee_id` set → name that person in the card ("Відповідальний: …").
- otherwise → `"me"`: the user who creates the task. The card says nothing,
  Worksection sets the creator; the user picks themselves as responsible if
  the project's default differs. **Never hardcode an id.**

## Read state

Find the read tools with ToolSearch (`worksection get_tasks`) — the server
name is local configuration, never assumed. Then:

1. `get_tasks` for `worksection.project_id`, closed tasks included.
2. `get_subtasks` for every task that has children (the dedup must see one
   level down).

From the returned names and descriptions extract every `#NNN` PR number, one
per line, into `$RUN/logged-prs.txt`. Note task ids worth extending (an open
task covering today's work) and how existing work is nested.

**Read MCP unavailable** (not connected, auth failed): tell the user, ask them
to paste the PR numbers already logged for this window (or "none"), write
those to `logged-prs.txt`, and continue. Never skip the dedup silently.

## Create

Manual. For each entry, in order (umbrellas first, then their children), the
agent writes one card to `$RUN/manual-cards.md` and shows it in the reply:

```
Картка 2/5 · підзадача до «TASK-12 · …» (<parent link>)
Назва:       TASK-12.1 · Short clear title
Початок:     2026-11-03
Термін:      2026-11-03            ← only when status == done
Після створення: закрити (галочка) ← only when status == done
Відповідальний: <name>             ← only when assignee_id is pinned
Опис:
<the human block as plain text>
```

| Draft field | Worksection field |
| --- | --- |
| `title` | Назва |
| human block | Опис, plain text |
| `start` | Дата початку |
| `due` | Термін — **only** when `status == "done"` |
| `status` | `done` → the user closes the task after creating it; otherwise it stays open |

Plain text rendering of the human block: drop markdown markers, keep the
labels as plain lines ("Story Points: 8", "Що зроблено. …"), write each PR as
`#186 https://github.com/OWNER/REPO/pull/186` so Worksection makes the URL
clickable.

After each card the agent **stops and waits** for the user to paste the URL of
the task they created. It takes the task id from that URL (see Links), records
it as the real id of that entry or container, appends the entry's PRs to
`logged-prs.txt`, and only then shows the next card. A child card is shown only
after its parent's URL is known, because the card names the parent.

## Update

`target` is an existing id → a card titled "Оновити" with the task link, the
fields to change (description, dates) and, when moving to done, "закрити
(галочка)". Never rename a manager-owned task: give a comment text to post
instead. The user confirms when done; no URL is needed back.

## Nesting

- `parent` is a container code → the user creates the card as a subtask
  («Підзадача») inside that container's task, using the URL recorded for it.
  Native nesting is the relationship; nothing else to link.
- `parent: "root"` → a top-level task in the project. If `eff.umbrella_task_id`
  is set, it is created as a subtask of that master task instead.
- `parent` is an existing task id → a subtask of that task.
- Worksection nests two levels below a task. A draft that would need a third
  level is flattened: the deepest entries become subtasks of their grandparent,
  and their `TASK-NN.m.k` names keep the level visible.

## Links

Task URL: `<account_url>/project/<project_id>/<task_id>/`; a subtask adds its
own id: `<account_url>/project/<project_id>/<task_id>/<subtask_id>/`. When the
read MCP returns a `page` field, prefer it (prefix it with `account_url`). The
URL the user pastes back is the source of truth: the task id is its last
numeric path segment. S4 lists those URLs.

## Gotchas

- The read MCP may expose write tools. They are out of scope: never call them.
- Plain text only. Markdown pasted into the description editor stays as raw
  `**` and `#` characters.
- Story points live in the description text; there is no field for them.
- No time tracking, no costs: dates only.
- Closed tasks are left out of `get_tasks` unless asked for; without them the
  dedup misses PRs already logged in finished work.
