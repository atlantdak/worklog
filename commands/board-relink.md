---
description: Repair the link after a plan was renamed or moved. Rewrites the plan path inside the card's origin marker and keeps the nonce that keys idempotency.
argument-hint: "[path to the plan file]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "AskUserQuestion", "Skill", "mcp__clickup__clickup_get_task", "mcp__clickup__clickup_filter_tasks", "mcp__clickup__clickup_create_task", "mcp__clickup__clickup_update_task", "mcp__asana__get_task", "mcp__asana__get_tasks", "mcp__asana__get_project", "mcp__asana__search_tasks", "mcp__asana__create_tasks", "mcp__asana__update_tasks"]
---

# /board-relink

1. Invoke the **`worklog-board`** skill and follow it exactly.
2. The nonce inside the marker is preserved. Replacing it would break idempotency and
   allow a duplicate card on the next run.

Plan: $ARGUMENTS
