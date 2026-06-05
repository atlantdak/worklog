# worklog — format contract (generic)

## Draft file

Path: `<drafts_dir>/YYYY-MM-DD.md`. Two parts.

### 1. Machine block (the contract S3 writes from)

A single HTML-comment block. `validate-draft.sh` and the skill parse the JSON between the
markers with `jq`:

```
<!-- worklog:meta
{
  "date": "2026-06-04",
  "entries": [
    {
      "target": "new",
      "title": "TASK-43 · Short clear title",
      "sp": 8,
      "status": "done",
      "start": "2026-06-04",
      "due": "2026-06-04",
      "parent": "umbrella",
      "prs": [186],
      "links": ["https://github.com/OWNER/REPO/pull/186"]
    }
  ]
}
worklog:meta -->
```

Field rules:
- `target`: `"new"` (create) or an existing task id/code (`"TASK-34"`) to extend/close.
- `status`: exactly `"done"` or `"in progress"`.
- Date rule: `status=="done"` ⇒ both `start` and `due` present. `status=="in progress"` ⇒
  `start` present, `due` MUST be absent or null.
- `parent`: `"umbrella"` (resolve to config `umbrella_task_id`), `"none"`, or a task id.
- `prs`: array of integers; each must NOT appear in the run's `logged-prs.txt` (dedup).
- `sp`: positive integer.

### 2. Human block (what the user reviews)

Below the machine block, plain markdown the user reads. Per entry use the description
template:

```
## 🎯 Story Points: N

**↳ Огляд:** [★ Umbrella](UMBRELLA_URL)        ← epics/standalone
**↳ Задача:** [TASK-NN — title](PARENT_URL)    ← sub-entries

**Що зроблено.** …
**Результат.** …

**🔗 Pull request:** [#186](URL)               ← one PR
**🔗 Pull requests:** [#180](URL), [#182](URL)  ← several
```

Terminology: never the word «епік»; use «задача»/«під-задача» (or the consuming project's
`terminology` config). Language follows config `language`.

## Date rule (canonical)

- `done` → set `start_date` AND `due_date`.
- `in progress` → set `start_date` only; never set `due_date` (due = completion date).

## Story-point calibration (default)

SP = relative delivery complexity in an AI-first process (review volume, architecture, risk,
cross-layer integration), NOT person-hours. Default calibration `~14-15 SP/active day`; the
consuming project may override via config `sp_calibration`. The agent proposes SP; the user
approves at the gate.
