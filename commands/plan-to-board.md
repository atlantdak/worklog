---
description: Put an approved plan on the tracker board. Builds a preview of the card and its subtasks, and writes nothing until you have read it and confirmed.
argument-hint: "[path to the plan file]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "AskUserQuestion", "Skill", "mcp__clickup__clickup_get_task", "mcp__clickup__clickup_filter_tasks", "mcp__clickup__clickup_create_task", "mcp__clickup__clickup_update_task", "mcp__asana__get_task", "mcp__asana__get_tasks", "mcp__asana__get_project", "mcp__asana__search_tasks", "mcp__asana__create_tasks", "mcp__asana__update_tasks"]
---

# /plan-to-board

1. Invoke the **`worklog-board`** skill and follow it exactly. It is the source of truth
   for the flow, for the three kinds of divergence, and for what must never happen.
2. Which tracker is used comes from `tracker` in the resolved config; the calls for it
   live in `references/adapters/<tracker>.md`. Announce which adapter you are using.
3. Nothing is written to the tracker before the user has read the preview file and
   confirmed it.

Plan: $ARGUMENTS
