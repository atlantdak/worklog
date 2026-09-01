# worklog

End-of-day worklog plugin. From a window you name (`yesterday`, `#180..#186`), it gathers
GitHub facts, writes a review draft, and — only after you approve — mirrors the work into
your tracker and returns the exact task links.

## Install (global)

    gh repo create atlantdak/worklog --source /path/to/worklog --push
    # in Claude Code:
    /plugin marketplace add atlantdak/worklog
    /plugin install worklog@worklog

## Use

In any project that has `.claude/worklog.config.json` (created on first run):

    /log-day yesterday
    /log-day #180..#186

The plugin never writes to the tracker until you approve the draft.

## Trackers

The core skill drives the flow and knows no tracker. Each tracker is one recipe file in
`references/adapters/`, declaring what it can do; the core adapts to those capabilities.

| Tracker | `rich_text` | `nesting` | `status` |
| --- | --- | --- | --- |
| `clickup` | `markdown` | `native` | `named` |
| `asana` | `html_subset` | `native` | `section` |

Pick one with the `tracker` key and give it the binding it asks for:

```json
{ "tracker": "clickup", "clickup_list_id": "000000000000" }
```

```json
{
  "tracker": "asana",
  "asana": {
    "project_gid": "PROJECT_GID",
    "section_map": { "done": "SECTION_GID", "in progress": "SECTION_GID" }
  }
}
```

A config written before adapters existed — `clickup_list_id` and no `tracker` — keeps working:
the resolver infers ClickUp from the binding.

Adding a third tracker is one file in `references/adapters/`, one line in the
`tracker_required` table in `scripts/resolve-config.sh`, and its MCP tools in the
`allowed-tools` list of `commands/log-day.md`.

## Privacy

Config files and draft directories are not committed because they can contain project-specific
data. The onboarding step adds them to the consuming project's `.gitignore`. The assignee is
never stored: tasks are assigned to the authenticated tracker user unless a config pins
`assignee_id`.
