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
- `parent`: `"umbrella"` (resolve to config `umbrella_task_id`), `"none"`, an umbrella code
  declared in `containers` (`"TASK-NN"`), or an existing task id.
- `prs`: array of integers; each must NOT appear in the run's `logged-prs.txt` (dedup).
- `sp`: positive integer.

**Umbrellas (`containers`, optional).** Alongside `entries` a draft MAY carry a `containers`
array — **zero, one, or many** umbrella tasks that group the window's work by coherent effort
(NOT necessarily one-per-day). Each container is `{title, status, start, due, parent,
sp_rollup}`; `parent` is usually `"umbrella"` (the master task) and `sp_rollup` is the sum of
its children's `sp`. Children point back with `parent: "<container TASK-code>"`. `validate-draft.sh`
sums **only `entries[].sp`** — `sp_rollup` is display-only and is NOT double-counted. The same
date/voice rules apply to a container by its own `status` (an umbrella with any unfinished child
is `in progress` → no `due`). See *Structure* below for when to use one.

### 2. Human block (what the user reviews)

Below the machine block, plain markdown the user reads. **Pick the template by `status`** — the
prose must match the state, never describe unfinished work as if shipped:

**`done`** — past tense; the outcome is real, concrete facts and the closed date are correct:

```
## 🎯 Story Points: N

**↳ Umbrella:** [★ Master task](UMBRELLA_URL)   ← standalone
**↳ Parent:** [TASK-NN — title](PARENT_URL)     ← sub-entries

**What was done.** problem → what was delivered.
**Result.** the outcome that landed (concrete results / verification OK).

**🔗 Pull request:** [#186](URL)               ← one PR
**🔗 Pull requests:** [#180](URL), [#182](URL)  ← several
```

**`in progress`** — present/continuous tense; say what remains, claim nothing as finished:

```
## 🎯 Story Points: N · 🚧 in progress

**↳ Umbrella:** [★ Master task](UMBRELLA_URL)   ← standalone
**↳ Parent:** [TASK-NN — title](PARENT_URL)     ← sub-entries

**What we're doing.** what we're building and why it matters (present tense).
**Status.** what is in place so far and what still remains. End with an explicit
not-yet-done note. NO closed date range and NO completion claims ("done / shipped /
all checks green / in final review") — those read as finished.

**🔗 Pull request:** [#298](URL)
```

Render all headings/labels in the configured `language` (examples above are in English; a
draft in another language uses its own equivalents — keep the structure identical).

Voice-by-status rule (mirrors the Date rule): completion claims and a **closed** date period
(e.g. "Jun 25–27") belong to `done` only. For `in progress`, the period is open-ended (e.g.
"from Jun 25, in progress") and the start date lives in the field, not as a finished span.

Terminology: never use a word in the project's `terminology.avoid`; prefer its
`terminology.use` wording. Language follows config `language`.

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
  transliterate them (keep `Anti-Fingerprint`, not «анти-відбиток»; `Example Project`, `Secure
  Custom Fields`). This is the default; a project may still steer wording via its `terminology`
  config. Code identifiers belong in the PR, not the prose — if one genuinely cannot be
  paraphrased, spell it verbatim rather than translated.
- **Orthography.** Everything else follows the draft `language`, with correct spelling and
  diacritics (e.g. for Ukrainian, «беклог», not the Russian «бэклог»).

### Granularity (anti-spam)

**Don't emit one card per PR.** Group the window's PRs into a few coherent deliverables: merge
work that is genuinely a single deliverable carried across several PRs or repos into one entry,
and fold trivial polish (a one-line tweak, a short docs note) into a related entry rather than
its own card. Aim for entries a manager would recognise as **distinct results** — prefer fewer
meaningful entries over many granular ones.

### Structure (umbrellas, subtasks, standalone)

Shape the window around **coherent efforts/themes**, not around the calendar. A multi-theme or
multi-day window normally has **several umbrellas, one per theme** — do not force everything
under a single container. Decide per effort:

- **Umbrella + subtasks** — one theme that breaks into 2+ distinct pieces (e.g. a feature area
  worked across several PRs/days). Make a `containers` entry; hang the pieces off it via
  `parent`. A single large effort can be its own umbrella when it has real sub-parts.
- **Standalone task** — one cohesive deliverable (often a single PR) with no natural sub-parts.
  `parent: "umbrella"` (link to the master), no children.
- **Fold in** — trivial/related polish goes inside a related entry, never its own card. Several
  small unrelated fixes can be **compiled into one** "small fixes" task (list them in the body).

The split is a **proposal you present at the gate** — the user may prefer to merge themes,
promote one to its own umbrella, or compile small items differently. Offer the choice rather
than deciding silently. Keep genuinely unrelated deliverables distinct.

## Date rule (canonical)

- `done` → set `start_date` AND `due_date`.
- `in progress` → set `start_date` only; never set `due_date` (due = completion date).

The same split governs the **prose**, not just the date fields: see *Voice-by-status* above —
`in progress` text stays present-tense with no closed date range and no completion claims.

## Story-point calibration (default)

SP = relative delivery complexity in an AI-first process (review volume, architecture, risk,
cross-layer integration), NOT person-hours. Default calibration `~14-15 SP/active day`; the
consuming project may override via config `sp_calibration`. The agent proposes SP; the user
approves at the gate.
