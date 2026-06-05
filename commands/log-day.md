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
