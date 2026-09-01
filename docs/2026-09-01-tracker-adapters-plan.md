# Tracker adapters — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: используй
> `superpowers:subagent-driven-development` или `superpowers:executing-plans`.
> Шаги отмечены чекбоксами (`- [ ]`).

**Goal:** вынести ClickUp из ядра плагина в слой адаптеров, добавить адаптер
Asana и сделать контракт черновика независимым от устройства доски.

**Architecture:** три слоя. Ядро (`skills/worklog-day/SKILL.md`) ведёт поток
scope → gather → draft → ГЕЙТ → write → links и **не знает ни одного имени
трекера**. Контракт (`references/format.md`) — единственный интерфейс между
ядром и адаптером, описывает форму работы. Адаптер
(`references/adapters/<tracker>.md`) — документ-рецепт: frontmatter с
объявленными возможностями плюс маппинг на вызовы конкретного MCP.

**Tech Stack:** POSIX sh + jq (скрипты), Markdown (ядро, контракт, адаптеры),
MCP-серверы ClickUp и Asana (вызовы делает модель, не код).

**Spec:** `docs/2026-09-01-tracker-adapters-design.md`

## Global Constraints

- Ядро не содержит подстрок `clickup` / `asana` ни в каком регистре. Тест это
  проверяет; исключение — `commands/log-day.md`, где имена нужны в
  `allowed-tools`.
- Ровно один трекер на файл адаптера; имя из frontmatter совпадает с basename.
- Объявленные возможности — три ключа: `rich_text`, `nesting`, `status`.
  `assignees` и `cross_links` в таблицу **не** входят: они не меняют ветвление
  ядра, а живут в рецепте адаптера отдельными разделами.
- Назначение исполнителя всегда динамическое: аутентифицированный пользователь
  трекера (`"me"`), а `assignee_id` из конфига — только override. Ни один
  файл не содержит захардкоженного id пользователя.
- Обратная совместимость: конфиг без ключа `tracker`, но с `clickup_list_id`,
  считается `tracker: "clickup"` и продолжает работать без правок.
- Скрипты — POSIX sh (`#!/usr/bin/env sh`, `set -eu`), зависимости только
  `jq` и `gh`, проверяются через `wl_need`.
- `scripts/tests/run-all.sh` обязан печатать `ALL GREEN` после каждой задачи.
- Коммиты — Conventional Commits, без AI-атрибуции.
- Факты доски Asana (проверены 2026-09-01, повторно измерять не нужно):
  workspace `1209252743810964` (`trafficconnect.com`), проект
  `1217990719469934` «Dev Outsource - iGaming Site Builder»; секции
  Backlog `1217990719469935`, To Do `1217993678143973`,
  In Progress `1217993678143975`, Ready for Review `1217993678143979`,
  Done `1217988309530635`; задача в секции Done имеет `completed: false`;
  поля Story Points нет (есть Priority, Estimation Dev (h), Затрачено времени);
  permalink задачи — `https://app.asana.com/1/<workspace>/project/<project>/task/<gid>`.

---

## File Structure

| Файл | Ответственность | Действие |
| --- | --- | --- |
| `references/format.md` | контракт черновика, `parent: "root"` | modify |
| `references/adapters/clickup.md` | возможности + рецепт ClickUp | create |
| `references/adapters/asana.md` | возможности + рецепт Asana | create |
| `skills/worklog-day/SKILL.md` | нейтральное ядро + резолв адаптера | modify |
| `scripts/resolve-config.sh` | таблица «трекер → требуемые ключи» | modify |
| `scripts/validate-draft.sh` | ловит устаревшие значения `parent` | modify |
| `commands/log-day.md` | `allowed-tools` обоих трекеров, триггеры окна | modify |
| `references/worklog.config.*.example.json` | примеры с `tracker` | modify |
| `scripts/tests/test-adapters.sh` | структура адаптеров + связь с резолвером | create |
| `scripts/tests/test-skill.sh` | ядро нейтрально | rewrite |
| `scripts/tests/{test-references,test-resolve-config,test-validate-draft,test-command}.sh` | новые правила | modify |
| `scripts/tests/fixtures/draft-*.md` | `parent: "root"` + фикстура устаревшего контракта | modify/create |

---

## Task 1: Контракт черновика — `parent: "root"`

**Files:**
- Modify: `references/format.md`
- Modify: `scripts/validate-draft.sh`
- Modify: `scripts/tests/fixtures/draft-ok.md`, `draft-baddate.md`, `draft-dupe.md`, `draft-fracsp.md`
- Create: `scripts/tests/fixtures/draft-legacyparent.md`
- Test: `scripts/tests/test-validate-draft.sh`, `scripts/tests/test-references.sh`

**Interfaces:**
- Produces: значения `parent` — `"root"` | `"<код контейнера>"` | `"<id задачи>"`.
  Task 3 и Task 4 опираются ровно на этот набор.

- [ ] **Step 1: Написать падающие тесты**

В `scripts/tests/test-validate-draft.sh` добавить:

```sh
check "legacy parent umbrella fails" "! sh '$v' '$fx/draft-legacyparent.md' '$fx/logged-prs.txt'"
check "root parent passes"           "sh '$v' '$fx/draft-ok.md' '$fx/logged-prs.txt'"
```

Создать `scripts/tests/fixtures/draft-legacyparent.md`:

```
<!-- worklog:meta
{ "date":"2026-06-04",
  "entries":[
    {"target":"new","title":"legacy","sp":3,"status":"done","start":"2026-06-04","due":"2026-06-04","parent":"umbrella","prs":[301],"links":["u"]}
  ]
}
worklog:meta -->
```

В `scripts/tests/test-references.sh` добавить:

```sh
check "format.md declares parent root" "grep -q '\"root\"' '$root/references/format.md'"
check "format.md drops legacy parent values" \
  "! grep -qE 'parent.*\"(umbrella|none)\"' '$root/references/format.md'"
```

- [ ] **Step 2: Прогнать — тесты падают**

Run: `sh scripts/tests/test-validate-draft.sh; sh scripts/tests/test-references.sh`
Expected: FAIL на `legacy parent umbrella fails` и на обеих проверках format.md.

- [ ] **Step 3: Реализовать проверку в валидаторе**

В `scripts/validate-draft.sh` после блока `bad_date` добавить:

```sh
# Contract v2: parent is "root" | "<container code>" | "<task id>". The pre-adapter
# values "umbrella"/"none" leaked board layout into the draft and are now invalid.
legacy="$(printf '%s' "$meta" | jq -r '
  [ (.entries[]?, .containers[]?) | .parent? | select(. == "umbrella" or . == "none") ] | length')"
[ "$legacy" -eq 0 ] || note "legacy parent value (\"umbrella\"/\"none\"); use \"root\""
```

- [ ] **Step 4: Обновить контракт `references/format.md`**

Заменить строку правила `parent` на:

```
- `parent`: `"root"` (запись верхнего уровня), код умбреллы из `containers`
  (`"TASK-NN"`), либо id существующей задачи. Черновик не знает, есть ли на
  доске мастер-задача: если конфиг задал `umbrella_task_id`, адаптер
  дополнительно привяжет к ней записи верхнего уровня; если нет — они
  останутся верхнеуровневыми.
```

В блоке `containers` заменить «`parent` is usually `"umbrella"` (the master
task)» на «`parent` — `"root"`». В примере JSON заменить
`"parent": "umbrella"` на `"parent": "root"`. В разделе *Audience & voice*
заменить «ClickUp entries are read by a manager» на «Tracker entries are read
by a manager» (ядро и контракт трекер не называют).

- [ ] **Step 5: Обновить фикстуры**

В `draft-ok.md` заменить `"parent":"umbrella"` → `"parent":"root"`;
в `draft-baddate.md`, `draft-dupe.md`, `draft-fracsp.md` заменить
`"parent":"none"` → `"parent":"root"`.

- [ ] **Step 6: Прогнать всё**

Run: `sh scripts/tests/run-all.sh`
Expected: `ALL GREEN`.

- [ ] **Step 7: Коммит**

```bash
git add references/format.md scripts/validate-draft.sh scripts/tests
git commit -m "refactor(contract): collapse parent umbrella/none into root"
```

---

## Task 2: `resolve-config.sh` — таблица «трекер → требуемые ключи»

**Files:**
- Modify: `scripts/resolve-config.sh`
- Test: `scripts/tests/test-resolve-config.sh`

**Interfaces:**
- Produces: в эффективном конфиге всегда есть `.tracker` (строка). Exit-коды:
  `0` — резолвится, `3` — NEEDS_ONBOARDING (нет трекера или его обязательных
  ключей), `2` — неизвестный трекер / поломанный JSON. Task 3 и Task 4
  читают `eff.tracker`; `test-adapters.sh` (Task 3) опирается на разницу
  между `3` и `2`.

- [ ] **Step 1: Написать падающие тесты**

Дописать в `scripts/tests/test-resolve-config.sh` перед `rm -rf "$tmp"`:

```sh
# --- Case F: legacy config (no tracker key) is inferred as clickup.
cat > "$proj/.claude/worklog.config.json" <<'JSON'
{ "clickup_list_id": "L9", "github_repo": "O/R" }
JSON
effF="$tmp/f.json"
WL_GLOBAL_CONFIG=/nonexistent sh "$rc" "$proj" > "$effF" 2>/dev/null
check "F: tracker inferred as clickup" "jq -e '.tracker==\"clickup\"' '$effF'"

# --- Case G: asana binding resolves.
cat > "$proj/.claude/worklog.config.json" <<'JSON'
{ "tracker": "asana", "github_repo": "O/R",
  "asana": { "project_gid": "1217990719469934",
             "section_map": { "done": "1217988309530635", "in progress": "1217993678143975" } } }
JSON
effG="$tmp/g.json"
WL_GLOBAL_CONFIG=/nonexistent sh "$rc" "$proj" > "$effG" 2>/dev/null
check "G: tracker is asana"          "jq -e '.tracker==\"asana\"' '$effG'"
check "G: project_gid preserved"     "jq -e '.asana.project_gid==\"1217990719469934\"' '$effG'"
check "G: exit 0 (resolvable)"       "WL_GLOBAL_CONFIG=/nonexistent sh '$rc' '$proj' >/dev/null 2>&1"

# --- Case H: asana without project_gid -> NEEDS_ONBOARDING (3), not a crash.
cat > "$proj/.claude/worklog.config.json" <<'JSON'
{ "tracker": "asana", "github_repo": "O/R" }
JSON
WL_GLOBAL_CONFIG=/nonexistent sh "$rc" "$proj" >/dev/null 2>&1; rcH=$?
check "H: missing asana binding exits 3" "[ $rcH -eq 3 ]"

# --- Case I: unknown tracker fails loudly (2), never silently onboards.
cat > "$proj/.claude/worklog.config.json" <<'JSON'
{ "tracker": "jira", "github_repo": "O/R" }
JSON
WL_GLOBAL_CONFIG=/nonexistent sh "$rc" "$proj" >/dev/null 2>&1; rcI=$?
check "I: unknown tracker exits 2" "[ $rcI -eq 2 ]"

# --- Case J: no tracker and no legacy binding -> onboarding (3).
check "J: bare project exits 3" \
  "WL_GLOBAL_CONFIG=/nonexistent sh '$rc' '$empty'; [ \$? -eq 3 ]"
```

- [ ] **Step 2: Прогнать — падает**

Run: `sh scripts/tests/test-resolve-config.sh`
Expected: FAIL на F/G/H/I (скрипт ещё не знает про `tracker`).

- [ ] **Step 3: Реализовать резолв трекера**

В `scripts/resolve-config.sh` заменить блок «Required binding» на:

```sh
# --- Tracker resolution -------------------------------------------------------
# One line per supported tracker: which config keys must resolve before we can
# write anything. Adding a tracker = adding a line here + a file in
# references/adapters/. The core never names a tracker; this table does.
tracker_required() {
  case "$1" in
    clickup) printf 'clickup_list_id\n' ;;
    asana)   printf 'asana.project_gid\n' ;;
    *)       return 1 ;;
  esac
}

tracker="$(printf '%s' "$eff" | jq -r '.tracker // ""')"
tracker_src="config"
if [ -z "$tracker" ]; then
  # Backwards compatibility: a pre-adapter config carries clickup_list_id and no tracker.
  if printf '%s' "$eff" | jq -e '.clickup_list_id != null' >/dev/null 2>&1; then
    tracker="clickup"; tracker_src="inferred (legacy clickup_list_id)"
    eff="$(printf '%s' "$eff" | jq '.tracker = "clickup"')"
  else
    tracker_src="unset"
  fi
fi

printf '  %-16s %-28s %s\n' 'tracker' "\"$tracker\"" "$tracker_src" >&2

if [ -z "$tracker" ]; then
  printf 'NEEDS_ONBOARDING: no tracker resolved (set "tracker" in %s)\n' "$project" >&2
  printf '%s' "$eff"; exit 3
fi

req="$(tracker_required "$tracker")" || wl_die "unknown tracker: $tracker (supported: clickup, asana)"

missing=""
for key in $req; do
  val="$(printf '%s' "$eff" | jq -r --arg k "$key" 'getpath($k | split(".")) // ""')"
  printf '  %-16s %-28s %s\n' "$key" "\"$val\"" "binding" >&2
  case "$val" in
    ""|"000000000000"|"PROJECT_GID") missing="$missing $key" ;;
  esac
done
if [ -n "$missing" ]; then
  printf 'NEEDS_ONBOARDING: tracker %s needs:%s (set them in %s)\n' "$tracker" "$missing" "$project" >&2
  printf '%s' "$eff"; exit 3
fi

printf '%s' "$eff"
```

Из провенанс-блока убрать строку `prov clickup_list_id clickup_list_id`
(её место занял вывод по таблице), строку `prov umbrella_task_id` оставить.
В шапке скрипта заменить упоминание ClickUp в комментарии на нейтральное:
«assignee is left to the skill (resolved to the authenticated tracker user at
write time)».

- [ ] **Step 4: Прогнать**

Run: `sh scripts/tests/test-resolve-config.sh && sh scripts/tests/run-all.sh`
Expected: все PASS, `ALL GREEN`.

- [ ] **Step 5: Коммит**

```bash
git add scripts/resolve-config.sh scripts/tests/test-resolve-config.sh
git commit -m "feat(config): resolve tracker by table, infer clickup from legacy binding"
```

---

## Task 3: Адаптеры ClickUp и Asana

**Files:**
- Create: `references/adapters/clickup.md`, `references/adapters/asana.md`
- Create: `scripts/tests/test-adapters.sh`

**Interfaces:**
- Produces: frontmatter-контракт адаптера — ключи `tracker`, `rich_text`
  (`markdown|html_subset|plain`), `nesting` (`native|link`), `status`
  (`named|section|completed_flag`); обязательные разделы `## Capabilities`,
  `## Config`, `## Assignee`, `## Read state`, `## Create`, `## Update`,
  `## Nesting`, `## Links`, `## Gotchas`. Task 4 (ядро) ссылается на разделы
  по этим именам.

- [ ] **Step 1: Написать падающий тест `scripts/tests/test-adapters.sh`**

```sh
#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

dir="$root/references/adapters"
check "adapters dir exists" "[ -d '$dir' ]"

# Frontmatter value of KEY in FILE.
fm() { sed -n '/^---$/,/^---$/p' "$2" | sed -n "s/^$1: *//p" | head -1; }

for f in "$dir"/*.md; do
  b="$(basename "$f" .md)"
  check "$b: declares tracker == filename" "[ \"\$(sed -n '/^---\$/,/^---\$/p' '$f' | sed -n 's/^tracker: *//p' | head -1)\" = '$b' ]"
  for k in rich_text nesting status; do
    check "$b: declares $k" "sed -n '/^---\$/,/^---\$/p' '$f' | grep -q '^$k: '"
  done
  check "$b: rich_text value is known" \
    "sed -n '/^---\$/,/^---\$/p' '$f' | grep -qE '^rich_text: (markdown|html_subset|plain)\$'"
  check "$b: nesting value is known" \
    "sed -n '/^---\$/,/^---\$/p' '$f' | grep -qE '^nesting: (native|link)\$'"
  check "$b: status value is known" \
    "sed -n '/^---\$/,/^---\$/p' '$f' | grep -qE '^status: (named|section|completed_flag)\$'"
  for s in Capabilities Config Assignee "Read state" Create Update Nesting Links Gotchas; do
    check "$b: has section $s" "grep -q '^## $s' '$f'"
  done
  # The assignee is always the authenticated user; no hardcoded ids anywhere.
  check "$b: assignee is dynamic (\"me\")" "grep -q '\"me\"' '$f'"
  # Exactly one tracker per file: no adapter mentions another adapter's name.
  for other in "$dir"/*.md; do
    ob="$(basename "$other" .md)"
    [ "$ob" = "$b" ] && continue
    check "$b: does not mention $ob" "! grep -qi '$ob' '$f'"
  done
  # The config resolver must know this tracker: a bare config with only the
  # tracker key exits 3 (needs binding), never 2 (unknown tracker).
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude"
  printf '{ "tracker": "%s", "github_repo": "O/R" }' "$b" > "$tmp/.claude/worklog.config.json"
  WL_GLOBAL_CONFIG=/nonexistent sh "$root/scripts/resolve-config.sh" "$tmp" >/dev/null 2>&1; rc=$?
  check "$b: resolve-config knows this tracker" "[ $rc -eq 3 ]"
  rm -rf "$tmp"
done
exit $fail
```

- [ ] **Step 2: Прогнать — падает**

Run: `sh scripts/tests/test-adapters.sh`
Expected: FAIL `adapters dir exists`.

- [ ] **Step 3: Написать `references/adapters/clickup.md`**

Frontmatter и каркас (проза переносится из нынешнего S3 ядра, без потерь):

```markdown
---
tracker: clickup
rich_text: markdown
nesting: native
status: named
---

# ClickUp adapter

## Capabilities
| Key | Value | Meaning for the core |
| --- | --- | --- |
| `rich_text` | `markdown` | the human block goes in as markdown, verbatim |
| `nesting` | `native` | a subtask carries a real `parent` id |
| `status` | `named` | "done" is a status name read off the list |

## Config
`clickup_list_id` (required binding) · `umbrella_task_id` (optional master task)
· `assignee_id` (optional override).

## Assignee
`clickup_resolve_assignees ["me"]` → the authenticated ClickUp user; pass the
returned id as `assignees`. Use `eff.assignee_id` only when the config pins it.

## Read state
`clickup_filter_tasks` with `list_ids:[clickup_list_id]`, `include_closed:true`,
`subtasks:true` → extract every `#NNN` from names/descriptions into
`logged-prs.txt`; note ids of tasks worth extending.

## Create
`clickup_create_task` with `list_id`, `name`, `markdown_description`,
`assignees`, `start_date`, `due_date` (only when `status=="done"`), `status`
mapped to the list's status name (`clickup_get_list` if unsure).

## Update
`clickup_update_task` for an existing `target` (description/dates/status; set
`due_date` when moving to done). Never rename a manager-owned task — annotate
with `clickup_create_task_comment`.

## Nesting
`parent: "<container code>"` → native `parent=<container task id>`; do not also
link it. `parent: "root"` → create top-level, then, **if** `umbrella_task_id` is
set, `clickup_add_task_link` to it. Fallback when the workspace rejects native
subtasks ("Cannot make subtasks…"): create top-level and link to the parent.

## Links
Task URL: `https://app.clickup.com/t/<id>`. Cross-links between tasks:
`clickup_add_task_link`.

## Gotchas
- Status names are per-list: read them, never assume "Complete"/"Done".
- Story points live in the description text, not a custom field.
```

- [ ] **Step 4: Написать `references/adapters/asana.md`**

```markdown
---
tracker: asana
rich_text: html_subset
nesting: native
status: section
---

# Asana adapter

## Capabilities
| Key | Value | Meaning for the core |
| --- | --- | --- |
| `rich_text` | `html_subset` | the human block is rendered as `html_notes` |
| `nesting` | `native` | a subtask carries a real `parent` gid |
| `status` | `section` | "done" is a section, plus the `completed` flag |

## Config
`asana.project_gid` (required binding) · `asana.section_map`
(`{"done": "<gid>", "in progress": "<gid>"}`) · `assignee_id` (optional
override). Read the live section gids with `get_project` (`include_sections:
true`) when `section_map` is missing a status.

## Assignee
Pass `assignee: "me"` on create and update — the Asana MCP resolves it to the
authenticated user. Never hardcode a gid. Use `eff.assignee_id` only as an override.

## Read state
`get_tasks` with `project=<project_gid>`, `opt_fields=gid,name,notes,completed,parent.gid,memberships.section.name,permalink_url`
→ extract every `#NNN` from names/notes into `logged-prs.txt`. Subtasks are
members of the project (see *Nesting*), so one call covers them.

## Create
`create_tasks` with `default_project=<project_gid>` and one entry per task:
`name`, `html_notes` (single `<body>` root), `assignee: "me"`, `start_on`,
`due_on` (only when `status=="done"`), `section_id` from `section_map`, and
`completed: true` when `status=="done"`.
Allowed tags: `<body> <strong> <em> <u> <s> <code> <ol> <ul> <li> <a>
<blockquote> <pre> <h1> <h2> <hr/> <img>`. Anything else is a 400.

## Update
`update_tasks` with `task=<gid>` and the changed fields. Moving a task to
another section: `add_projects: [{project_id, section_id}]`. Closing: set the
Done section **and** `completed: true` — Done is terminal because acceptance
waits in "Ready for Review". Never rename a manager-owned task — annotate with
`add_comment` (comments allow no `<h1>/<h2>/<hr/>/<img>`).

## Nesting
`parent: "<container code>"` → `parent=<container gid>` **plus**
`project_id` + `section_id`, so the subtask shows on the board.
`parent: "root"` → top-level task in the project; if `umbrella_task_id` is set,
make it the task's `parent` instead.

## Links
Task URL: `https://app.asana.com/1/<workspace_gid>/project/<project_gid>/task/<gid>`
— or the `permalink_url` returned by the API, which is authoritative. There is
no task-link primitive: cross-references go into `html_notes` as `<a>`.

## Gotchas
- A task sitting in the Done section still reports `completed: false` — the flag
  and the section are independent, which is why we set both.
- There is no story-points field: SP go into the description text.
- `start_on` requires `due_on` on update; for an in-progress entry set
  `start_on` at create time and leave `due_on` unset.
- `html_notes` must be well-formed XML with exactly one `<body>` root.
```

- [ ] **Step 5: Прогнать**

Run: `sh scripts/tests/test-adapters.sh`
Expected: все PASS.

- [ ] **Step 6: Коммит**

```bash
git add references/adapters scripts/tests/test-adapters.sh
git commit -m "feat(adapters): clickup and asana recipes with declared capabilities"
```

---

## Task 4: Нейтральное ядро

**Files:**
- Modify: `skills/worklog-day/SKILL.md`
- Test: `scripts/tests/test-skill.sh` (переписывается)

**Interfaces:**
- Consumes: `eff.tracker` (Task 2), разделы адаптера (Task 3), `parent: "root"`
  (Task 1).

- [ ] **Step 1: Переписать тест `scripts/tests/test-skill.sh`**

Заменить проверки `clickup_create_task` / `clickup_add_task_link` на:

```sh
check "core names no tracker" "! grep -qiE 'clickup|asana|jira|linear' '$f'"
check "core resolves an adapter" "grep -q 'references/adapters/' '$f'"
check "core announces the adapter" "grep -qi 'announce' '$f'"
check "core reads capabilities" "grep -q 'rich_text' '$f' && grep -q 'nesting' '$f' && grep -q 'status' '$f'"
check "core assigns the authenticated user" "grep -q '\"me\"' '$f'"
check "core uses parent root" "grep -q 'root' '$f'"
```

Остальные проверки (S0–S4, Onboarding, скрипты, containers, voice by status,
no-write-before-approval, native nesting) сохранить.

- [ ] **Step 2: Прогнать — падает**

Run: `sh scripts/tests/test-skill.sh`
Expected: FAIL `core names no tracker` (в ядре 24 упоминания ClickUp).

- [ ] **Step 3: Переписать `skills/worklog-day/SKILL.md`**

Правки по местам:

1. `description:` → «Use at end of day to mirror a window of GitHub work into
   your task tracker — gather facts, write a review draft, and after explicit
   approval create/update tasks and return links. Never writes to the tracker
   before approval.»
2. Вступление и строка Announce → «into <tracker> » берётся из `eff.tracker`:
   «Announce at start: "Using worklog-day to mirror <window> into <tracker>."»
3. Новый раздел сразу после **Config**:

```markdown
## Adapter

The tracker is `eff.tracker`. Load `references/adapters/<eff.tracker>.md` —
that file is the ONLY place tracker-specific knowledge lives, and you resolve it
by that key, never by guessing from tool names. **Announce which adapter you
loaded** before touching the tracker. If the file does not exist, stop and tell
the user the tracker is unsupported (adding one = a file there plus a line in
`resolve-config.sh`).

Read its frontmatter capabilities and let them steer you:
- `rich_text` — `markdown`: the human block goes in verbatim; `html_subset`:
  render it as the adapter's allowed HTML; `plain`: strip formatting.
- `nesting` — `native`: a child carries a real parent id; `link`: create it
  top-level and link it.
- `status` — how "done" is expressed (a named status, a section, a flag, or a
  combination the adapter spells out).

Every call to the tracker follows the adapter's sections: *Assignee*,
*Read state*, *Create*, *Update*, *Nesting*, *Links*.
```

4. Раздел **Config**: заменить «The only genuinely per-project binding is
   `clickup_list_id`…» на «Per-project bindings are whatever the resolved
   tracker requires — `resolve-config.sh` prints them in its provenance table
   (+ optional `umbrella_task_id`)». Строку про assignee — «the authenticated
   **tracker** user, resolved at write time per the adapter's *Assignee*
   section; a config `assignee_id` only overrides it».
5. **Onboarding**: п.2 — спросить `tracker` (AskUserQuestion, варианты —
   имена файлов в `references/adapters/`), затем требуемые им ключи из
   провенанс-таблицы; п.3 — писать минимальный конфиг с `tracker` + биндингом.
6. **S1** п.2 → «Read current tracker state for dedup + correct linking:
   follow the adapter's *Read state* recipe. From the returned tasks extract
   every `#NNN` … `$RUN/logged-prs.txt`.»
7. **S2** п.1 — `parent` теперь `root` / код контейнера / id; пункт про
   «`status` (merged → done…)» остаётся.
8. **S3** — переписать в нейтральный порядок:

```markdown
## S3 — Write (only after approval)

Resolve the assignee once, per the adapter's *Assignee* section: `eff.assignee_id`
when the config pins it, otherwise the authenticated tracker user ("me"). Call it
`ASSIGNEE`.

**Create the umbrellas (`containers`) FIRST**, capture each returned id, then the
entries — a child must reference its parent's real id. For each entry:
- `target=="new"` → the adapter's *Create* call with title, the human block
  rendered per `rich_text`, `ASSIGNEE`, the start date, the completion date ONLY
  when `status=="done"`, and the status expressed per `status`.
- `parent` decides placement per the adapter's *Nesting* section: a container
  code → a child of that container; `"root"` → top level (and, when
  `eff.umbrella_task_id` is set, attached to that master task the way the adapter
  prescribes); an existing id → a child of it.
- `target` is an existing id → the adapter's *Update* call. Never rename a
  manager-owned task — annotate instead.
- After each successful create, append its PR numbers to `$RUN/logged-prs.txt`.
```

9. **S4** → «List every created/updated task as `name → <task URL per the
   adapter's *Links* section>`.»
10. **Guardrails**: «Never write to the tracker before S2 approval», «Never
    invent SP/dates…», «No time tracking — dates only», «Assign the work to the
    authenticated tracker user unless the config pins `assignee_id`».

- [ ] **Step 4: Прогнать**

Run: `sh scripts/tests/test-skill.sh && sh scripts/tests/run-all.sh`
Expected: все PASS, `ALL GREEN`.

- [ ] **Step 5: Коммит**

```bash
git add skills/worklog-day/SKILL.md scripts/tests/test-skill.sh
git commit -m "refactor(skill): tracker-neutral core that resolves an adapter"
```

---

## Task 5: Команда, манифесты, примеры конфигов

**Files:**
- Modify: `commands/log-day.md`, `.claude-plugin/plugin.json`,
  `.claude-plugin/marketplace.json`, `README.md`,
  `references/worklog.config.example.json`,
  `references/worklog.config.project.example.json`
- Test: `scripts/tests/test-command.sh`, `scripts/tests/test-references.sh`

- [ ] **Step 1: Дописать тесты**

`test-command.sh`:

```sh
check "allows clickup write tools" "grep -q 'mcp__clickup__clickup_create_task' '$f'"
check "allows asana write tools"   "grep -q 'mcp__asana__create_tasks' '$f'"
check "allows asana update+comment" "grep -q 'mcp__asana__update_tasks' '$f' && grep -q 'mcp__asana__add_comment' '$f'"
check "description is tracker-neutral" "! grep -q '^description:.*ClickUp' '$f'"
```

`test-references.sh`:

```sh
check "example config declares tracker" "jq -e '.tracker' '$root/references/worklog.config.example.json'"
check "project example declares tracker" "jq -e '.tracker' '$root/references/worklog.config.project.example.json'"
check "adapters exist for documented trackers" \
  "[ -f '$root/references/adapters/clickup.md' ] && [ -f '$root/references/adapters/asana.md' ]"
```

- [ ] **Step 2: Прогнать — падает**

Run: `sh scripts/tests/test-command.sh; sh scripts/tests/test-references.sh`
Expected: FAIL на новых проверках.

- [ ] **Step 3: Обновить `commands/log-day.md`**

`description:` → «End-of-day worklog → your tracker. Gathers GitHub facts for a
window you name, writes a review draft, and after approval mirrors it into the
configured tracker.» `allowed-tools` — прежний список ClickUp плюс
`mcp__asana__get_project`, `mcp__asana__get_tasks`, `mcp__asana__get_task`,
`mcp__asana__search_tasks`, `mcp__asana__create_tasks`,
`mcp__asana__update_tasks`, `mcp__asana__add_comment`, `mcp__asana__get_me`.
В теле — «The skill never writes to the tracker before the user approves».

- [ ] **Step 4: Обновить примеры конфигов**

`references/worklog.config.example.json`:

```json
{
  "tracker": "clickup",
  "github_repo": "OWNER/REPO",
  "clickup_list_id": "000000000000",
  "umbrella_task_id": "",
  "assignee_id": "",
  "naming": { "scheme": "TASK-{n}", "sub": "TASK-{n}.{m}", "start_n": 1 },
  "sp_calibration": "~14-15 SP per active day",
  "drafts_dir": "worklog/_daily",
  "terminology": { "avoid": ["епік"], "use": ["задача", "під-задача"] },
  "language": "uk"
}
```

`references/worklog.config.project.example.json` — показать оба трекера:

```json
{
  "tracker": "asana",
  "asana": {
    "project_gid": "PROJECT_GID",
    "section_map": { "done": "SECTION_GID", "in progress": "SECTION_GID" }
  }
}
```

Глобальный пример не трогать: он про предпочтения, биндингов не несёт.

Дефолт `drafts_dir` — последнее упоминание трекера вне адаптеров: built-in в
`resolve-config.sh` сейчас `ClickUp/_daily`. Заменить на `worklog/_daily`
в трёх местах: built-in JSON в `resolve-config.sh`, пример
`worklog.config.example.json`, проверка `A: drafts_dir from built-in` в
`scripts/tests/test-resolve-config.sh`. Черновики эфемерны, мигрировать нечего.

- [ ] **Step 5: Обновить `plugin.json`, `marketplace.json`, `README.md`**

`description` в обоих манифестах — «…mirrors them into your tracker (ClickUp or
Asana)»; в `keywords` добавить `"asana"`, `"tracker"`. В README — раздел
«Trackers» с таблицей возможностей и примером конфига Asana.

- [ ] **Step 6: Прогнать**

Run: `sh scripts/tests/run-all.sh`
Expected: `ALL GREEN`.

- [ ] **Step 7: Коммит**

```bash
git add commands references .claude-plugin README.md scripts/tests
git commit -m "feat(command): allow both tracker MCPs and document the config"
```

---

## Task 6: Русские триггеры окна

**Files:**
- Modify: `skills/worklog-day/SKILL.md` (S0), `commands/log-day.md`
  (`argument-hint`)
- Test: `scripts/tests/test-skill.sh`

**Interfaces:**
- Consumes: S0 из Task 4. Отдельный коммит: это расширение триггеров, а не
  откат нормализации путей.

- [ ] **Step 1: Дописать тест**

```sh
check "S0 accepts russian window words" "grep -q 'вчера' '$f' && grep -q 'с #' '$f'"
check "S0 keeps english window words"   "grep -q 'yesterday' '$f' && grep -q 'since' '$f'"
```

- [ ] **Step 2: Прогнать — падает**

Run: `sh scripts/tests/test-skill.sh`
Expected: FAIL `S0 accepts russian window words`.

- [ ] **Step 3: Расширить S0**

```markdown
## S0 — Scope

Map the user's words / `$ARGUMENTS` to a scope kind+value for `collect-window.sh`.
Both English and Russian phrasings are accepted:
- `yesterday` / `вчера`, or a bare `YYYY-MM-DD` → `date YYYY-MM-DD` (compute
  "yesterday" from today; ask if ambiguous).
- `#N` → `pr-single N`. `#A..#B` → `pr-range A..B`.
  `since #N` / `с #N` / `начиная с #N` → `since N`.
- `today` / `сегодня` → `date <today>`.
- Blank → ask which window to take. Never guess silently.
```

`argument-hint` в команде → `"[window — 'yesterday' / 'вчера', '2026-06-04', '#180..#186', blank to be asked]"`.

- [ ] **Step 4: Прогнать**

Run: `sh scripts/tests/run-all.sh`
Expected: `ALL GREEN`.

- [ ] **Step 5: Коммит**

```bash
git add skills/worklog-day/SKILL.md commands/log-day.md scripts/tests/test-skill.sh
git commit -m "feat(skill): accept russian and english window phrasings"
```

---

## Task 7: Настройка kidi-builder на Asana

**Files (вне репозитория плагина):**
- Create: `<kidi-builder>/.claude/worklog.config.json`
- Modify: `<kidi-builder>/.gitignore` (если строки ещё нет)

- [ ] **Step 1: Написать конфиг проекта**

```json
{
  "tracker": "asana",
  "asana": {
    "workspace_gid": "1209252743810964",
    "project_gid": "1217990719469934",
    "section_map": {
      "done": "1217988309530635",
      "in progress": "1217993678143975"
    }
  }
}
```

- [ ] **Step 2: Проверить резолв на живом конфиге**

Run: `sh ~/.claude/plugins/marketplaces/worklog-dev/scripts/resolve-config.sh "/Users/atlantdak/Local Sites/igaming-site-builder/app/public"`
Expected: exit 0, в провенанс-таблице `tracker "asana" config` и
`asana.project_gid "1217990719469934" binding`.

- [ ] **Step 3: Убедиться, что конфиг не попадёт в git**

Run: `git -C "<kidi-builder>" check-ignore -v .claude/worklog.config.json`
Expected: строка правила; если пусто — дописать `.claude/worklog.config.json`
в `.gitignore` проекта.

- [ ] **Step 4: Обновить установленную копию (после мержа PR)**

`~/.claude/plugins/cache/worklog-dev/worklog/0.1.0` — копия, снятая с
`~/.claude/plugins/marketplaces/worklog-dev` (это git-клон репозитория). Из
шелла её не обновить: обновление делает сам Claude Code. После мержа PR
пользователь выполняет `/plugin marketplace update worklog-dev`, затем
проверяем:

```bash
ls ~/.claude/plugins/cache/worklog-dev/worklog/0.1.0/references/adapters/
grep -c asana ~/.claude/plugins/cache/worklog-dev/worklog/0.1.0/skills/worklog-day/SKILL.md
```

Expected: `asana.md clickup.md`, и `0` упоминаний трекера в ядре.

---

## Task 8: Ветка и PR

- [ ] **Step 1: Полный прогон**

Run: `sh scripts/tests/run-all.sh`
Expected: `ALL GREEN`.

- [ ] **Step 2: Push**

```bash
git push -u origin feat/tracker-adapters
```

- [ ] **Step 3: PR**

```bash
gh pr create --repo atlantdak/worklog --base main --head feat/tracker-adapters \
  --title "feat: tracker adapters (ClickUp + Asana)"
```

Тело PR: проблема (приваренность к ClickUp), решение (три слоя), ломающее
изменение контракта (`parent: "root"`, черновики эфемерны), измеренная
специфика Asana, что осталось за скобками (первый живой прогон
`/log-day` на Asana подтверждает подзадачу с `parent` + `project_id` +
`section_id` и перенос между секциями).
