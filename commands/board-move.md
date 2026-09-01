---
description: Move a plan's card to another section of the board. Realigns the local view first, shows the intent beside the card's current state, and waits for your confirmation.
argument-hint: "[plan path] [backlog|to_do|in_progress|review|done]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "AskUserQuestion", "Skill", "mcp__clickup__clickup_get_task", "mcp__clickup__clickup_filter_tasks", "mcp__clickup__clickup_create_task", "mcp__clickup__clickup_update_task", "mcp__asana__get_task", "mcp__asana__get_tasks", "mcp__asana__get_project", "mcp__asana__search_tasks", "mcp__asana__create_tasks", "mcp__asana__update_tasks"]
---

# /board-move

1. Invoke the **`worklog-board`** skill and follow it exactly.
2. Announce the adapter before acting; the calls live in `references/adapters/<tracker>.md`.
3. The card moves only after the user confirms. A card already in the requested state is
   a conflict to report, not a no-op to hide.

Arguments: $ARGUMENTS
