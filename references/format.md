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

### Audience & voice (titles + descriptions)

ClickUp entries are read by a **manager assessing delivered value**, not by engineers. Write
every title and description in plain language a non-engineer understands: state the **problem →
the outcome** and why it matters for the product or user. The implementation detail lives in
the code and the linked PR — the prose carries the value, the PR link carries the trail.

- **Keep out of titles/descriptions:** internal decision refs (`ADR-1234`), code identifiers
  (function / class / file / option names), and mechanism jargon (`PCRE`, `Jaccard`,
  `presence-gate`, `--ed-*`, `namespace`). If a mechanism must be mentioned, name its **effect**
  ("unique service names per site"), not its internals ("per-site `--ed-*` token rename").
- **Brand & proper nouns stay verbatim.** Product, plugin, tool, and theme names are proper
  nouns: keep their canonical spelling **regardless of `language`** — never translate or
  transliterate them (keep `Anti-Fingerprint`, not «анти-відбиток»; `AlterPoka`, `Secure
  Custom Fields`). This is the default; a project may still steer wording via its `terminology`
  config. Code identifiers belong in the PR, not the prose — if one genuinely cannot be
  paraphrased, spell it verbatim rather than translated.
- **Orthography.** Everything else follows the draft `language`, with correct spelling and
  diacritics (e.g. for Ukrainian, «беклог», not the Russian «бэклог»).

### Granularity (anti-spam)

**Don't emit one card per PR.** Group the day's PRs into a few coherent deliverables
(subtasks): merge work that is genuinely a single deliverable carried across several PRs or
repos into one entry, and fold trivial polish (a one-line tweak, a short docs note) into a
related entry rather than its own card. The common-case default is one container task per
active day, but keep genuinely unrelated deliverables distinct. Aim for entries a manager
would recognise as **distinct results** — prefer fewer meaningful entries over many granular
ones.

## Date rule (canonical)

- `done` → set `start_date` AND `due_date`.
- `in progress` → set `start_date` only; never set `due_date` (due = completion date).

## Story-point calibration (default)

SP = relative delivery complexity in an AI-first process (review volume, architecture, risk,
cross-layer integration), NOT person-hours. Default calibration `~14-15 SP/active day`; the
consuming project may override via config `sp_calibration`. The agent proposes SP; the user
approves at the gate.
