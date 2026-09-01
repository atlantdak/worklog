---
description: Cancel a plan. Closes its card with a cancelled marker in the name and files the plan under done. Not undoable by ordinary means, so it always asks first.
argument-hint: "[path to the plan file]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "AskUserQuestion", "Skill", "mcp__clickup__clickup_get_task", "mcp__clickup__clickup_filter_tasks", "mcp__clickup__clickup_create_task", "mcp__clickup__clickup_update_task", "mcp__asana__get_task", "mcp__asana__get_tasks", "mcp__asana__get_project", "mcp__asana__search_tasks", "mcp__asana__create_tasks", "mcp__asana__update_tasks"]
---

# /board-cancel

1. Invoke the **`worklog-board`** skill and follow it exactly.
2. Confirmation is mandatory: the tracker has no cancelled state, so the card is closed
   and marked in its name instead.
3. The card is never deleted.

Plan: $ARGUMENTS
