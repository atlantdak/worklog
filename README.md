# worklog

End-of-day worklog plugin. From a window you name (`yesterday`, `#180..#186`), it gathers
GitHub facts, writes a review draft, and — only after you approve — mirrors the work into
ClickUp and returns the exact task links.

## Install (global)

    gh repo create atlantdak/worklog --source /path/to/worklog --push
    # in Claude Code:
    /plugin marketplace add atlantdak/worklog
    /plugin install worklog@worklog

## Use

In any project that has `.claude/worklog.config.json` (created on first run):

    /log-day yesterday
    /log-day #180..#186

The plugin never writes to ClickUp until you approve the draft.

## Privacy

Config files and draft directories are not committed because they can contain project-specific data. The onboarding step adds them to the consuming project's `.gitignore`.
