# worklog

Private end-of-day plugin. From a window you name (`вчера`, `#180..#186`), it gathers
GitHub facts, writes a review draft, and — only after you approve — mirrors the work into
ClickUp and returns the exact task links.

## Install (global)

    gh repo create atlantdak/worklog --private --source ~/.claude/worklog --push
    # in Claude Code:
    /plugin marketplace add atlantdak/worklog
    /plugin install worklog@worklog-dev

## Use

In any project that has `.claude/worklog.config.json` (created on first run):

    /log-day вчера
    /log-day #180..#186

The plugin never writes to ClickUp until you approve the draft.

## Privacy

This plugin, each project's `worklog.config.json`, and the drafts dir are private. Keep them
out of shared repositories (the onboarding step gitignores them in the consuming project).
