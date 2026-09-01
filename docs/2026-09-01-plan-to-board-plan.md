# Plan → Board: план реализации очереди 1

> **Для агентов-исполнителей:** ОБЯЗАТЕЛЬНЫЙ СУБ-СКИЛЛ — `superpowers:subagent-driven-development`
> (рекомендуется) либо `superpowers:executing-plans`. Шаги размечены чекбоксами
> `- [ ]` для отслеживания.

**Цель:** план в репозитории порождает карточку в Backlog трекера, карточка
проходит секции по мере работы, `/log-day` её закрывает вместо создания второй.

**Архитектура:** скрипты владеют всем локальным и всем, что проверяется без
сети; модель владеет вызовами трекера по рецепту адаптера; обмен идёт файлами.
Идемпотентность обеспечивается меткой происхождения в описании карточки, а не
локальным реестром.

**Технологии:** POSIX `sh` + `jq`. Никаких новых зависимостей: `sh`, `jq`, `git`
и `gh` уже требуются плагином.

**Спека:** [`2026-09-01-plan-to-board-design.md`](2026-09-01-plan-to-board-design.md)

## Глобальные ограничения

- **POSIX `sh`**, не bash. Причина — переносимость, решение принято в
  `2026-06-05-worklog-plugin-plan.md` §10.
- **Единственные внешние зависимости:** `jq`, `git`, `gh`. Проверяются через
  `wl_need`.
- **Ядро остаётся нейтральным:** ни одно имя трекера не появляется в
  `skills/worklog-day/SKILL.md` и в скриптах ядра. Трекер-специфика — только в
  `references/adapters/<tracker>.md`.
- **Тесты в стиле репозитория:** файл `scripts/tests/test-<тема>.sh`, хелпер
  `check "имя" "команда"`, `fail=0`, `exit $fail`. `run-all.sh` подхватывает
  `test-*.sh` сам.
- **Ни одна запись в трекер не идёт без подтверждения человека.**
- **Карточки никогда не удаляются автоматически.**
- **Атомарность записи в план:** только через временный файл и `mv`.
- **Пять канонических ключей секций:** `backlog`, `to_do`, `in_progress`,
  `review`, `done`. Снейк-кейс, без пробелов. Неполное отображение — ошибка
  разрешения конфигурации.

## Форматы данных

Фиксируются здесь один раз; все задачи ссылаются сюда.

**Заголовок плана.** Две строки сразу после `# Заголовок`:

```markdown
**Board:** asana:1210987654321
**Origin:** wl-7f3a9c21
```

До создания карточки `Board:` отсутствует, `Origin:` уже есть.

**Маркер единицы работы.** Единицей является заголовок задачи плана, а не шаг:
шаг длится 2–5 минут и в подзадачи не годится. Маркер дописывается в конец
строки заголовка:

```markdown
### Task 3: board-state.sh — карта подзадач #s3
```

**Карта подзадач** — `<план>.board.json`:

```json
{
  "tracker": "asana",
  "card": "1210987654321",
  "origin": "wl-7f3a9c21",
  "subtasks": { "s1": "1210987654322", "s3": "1210987654324" }
}
```

**Строка журнала** — `~/.claude/worklog/journal.ndjson`, по одной на операцию:

```json
{"ts":"2026-09-01T12:00:00Z","op":"create","plan":"docs/x-plan.md","tracker":"asana","outcome":"ok","card":"1210987654321","note":""}
```

`outcome` — `ok` либо `fail`. Отказ пишется тоже: журнал существует, чтобы
находить ошибки задним числом.

**Отпечаток плана** — sha256 содержимого файла, из которого удалены строки
`**Board:**` и `**Origin:**`. Число в отпечаток не входит: оно появляется между
показом предпросмотра и записью.

## Структура файлов

| Файл | Ответственность |
| --- | --- |
| `scripts/plan-file.sh` | чтение плана и атомарные правки в нём |
| `scripts/board-state.sh` | карта подзадач и положение файла плана |
| `scripts/board-preview.sh` | построение предпросмотра и проверка отпечатка |
| `scripts/board-journal.sh` | дозапись строки журнала |
| `scripts/resolve-config.sh` | *(правка)* `plans_dir` и `sections` |
| `scripts/lib.sh` | *(правка)* `wl_atomic_write`, `wl_sha256` |
| `references/adapters/*.md` | *(правка)* четыре операции, пять ключей секций |
| `skills/worklog-day/SKILL.md` | *(правка)* закрытие существующей карточки |
| `commands/*.md` | *(новое)* четыре команды |

---

### Task 1: lib.sh — атомарная запись и хеш

**Файлы:**
- Изменить: `scripts/lib.sh`
- Тест: `scripts/tests/test-lib.sh`

**Интерфейсы:**
- Отдаёт: `wl_atomic_write <путь>` — читает stdin, пишет во временный файл
  рядом с целевым и переименовывает. `wl_sha256 <путь>` — печатает хеш одной
  строкой без имени файла.

- [ ] **Шаг 1: Написать падающий тест**

Дописать в конец `scripts/tests/test-lib.sh` перед `exit $fail`:

```sh
t="$(mktemp -d)"
printf 'старое\n' > "$t/f"
printf 'новое\n' | wl_atomic_write "$t/f"
check "atomic write replaces content" "grep -q '^новое$' \"$t/f\""
check "atomic write leaves no temp"   "[ \"\$(ls \"$t\" | wc -l | tr -d ' ')\" = 1 ]"
check "sha256 prints bare hash"       "printf '%s' \"\$(wl_sha256 \"$t/f\")\" | grep -Eq '^[0-9a-f]{64}$'"
check "sha256 is stable"              "[ \"\$(wl_sha256 \"$t/f\")\" = \"\$(wl_sha256 \"$t/f\")\" ]"
rm -rf "$t"
```

- [ ] **Шаг 2: Убедиться, что тест падает**

```
sh scripts/tests/test-lib.sh
```

Ожидается: `FAIL: atomic write replaces content` и далее — функции не определены.

- [ ] **Шаг 3: Реализовать**

Дописать в `scripts/lib.sh`:

```sh
# Atomic file write: stdin -> temp beside the target -> rename.
# A torn write is the one path back to a duplicate card, and rename closes it.
wl_atomic_write() {
    _dst="${1:?destination required}"
    _dir="$(dirname "$_dst")"
    [ -d "$_dir" ] || wl_die "no such directory: $_dir"
    _tmp="$(mktemp "$_dir/.wl.XXXXXX")" || wl_die "cannot create temp in $_dir"
    cat > "$_tmp" || { rm -f "$_tmp"; wl_die "write failed: $_tmp"; }
    mv -f "$_tmp" "$_dst" || { rm -f "$_tmp"; wl_die "rename failed: $_dst"; }
}

# Bare sha256 of a file (no filename in the output). macOS ships shasum, Linux sha256sum.
wl_sha256() {
    _f="${1:?file required}"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$_f" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$_f" | cut -d' ' -f1
    else
        wl_die "missing dependency: sha256sum or shasum"
    fi
}
```

- [ ] **Шаг 4: Убедиться, что тест проходит**

```
sh scripts/tests/test-lib.sh
```

Ожидается: все `PASS`, выход 0.

- [ ] **Шаг 5: Коммит**

```bash
git add scripts/lib.sh scripts/tests/test-lib.sh
git commit -m "feat(lib): atomic write and bare sha256"
```

---

### Task 2: plan-file.sh — чтение плана

**Файлы:**
- Создать: `scripts/plan-file.sh`
- Создать: `scripts/tests/test-plan-file.sh`
- Создать: `scripts/tests/fixtures/plan-fresh.md`
- Создать: `scripts/tests/fixtures/plan-linked.md`

**Интерфейсы:**
- Потребляет: `wl_sha256` из Task 1.
- Отдаёт: `plan-file.sh read <план>` — печатает в stdout JSON вида
  `{"path":…,"tracker":…,"card":…,"origin":…,"fingerprint":…,"units":[{"id":…,"title":…}]}`.
  `card` и `origin` равны `null`, когда строк нет. `id` равен `null` у единицы
  без маркера.

- [ ] **Шаг 1: Написать фикстуры**

`scripts/tests/fixtures/plan-fresh.md`:

```markdown
# Тестовый план

**Origin:** wl-aaaa1111

### Task 1: Первая единица

- [ ] Шаг

### Task 2: Вторая единица

- [ ] Шаг
```

`scripts/tests/fixtures/plan-linked.md`:

```markdown
# Связанный план

**Board:** asana:1210987654321
**Origin:** wl-bbbb2222

### Task 1: Первая единица #s1

- [ ] Шаг

### Task 2: Вторая единица #s2

- [ ] Шаг
```

- [ ] **Шаг 2: Написать падающий тест**

`scripts/tests/test-plan-file.sh`:

```sh
#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
pf="$root/scripts/plan-file.sh"
fx="$root/scripts/tests/fixtures"

fresh="$(sh "$pf" read "$fx/plan-fresh.md")"
check "fresh: card is null"        "printf '%s' '$fresh' | jq -e '.card == null'"
check "fresh: origin parsed"       "printf '%s' '$fresh' | jq -e '.origin == \"wl-aaaa1111\"'"
check "fresh: two units"           "printf '%s' '$fresh' | jq -e '.units | length == 2'"
check "fresh: unit ids are null"   "printf '%s' '$fresh' | jq -e '[.units[].id] == [null, null]'"
check "fresh: titles carried"      "printf '%s' '$fresh' | jq -e '.units[0].title == \"Первая единица\"'"
check "fresh: fingerprint is sha"  "printf '%s' '$fresh' | jq -re '.fingerprint' | grep -Eq '^[0-9a-f]{64}$'"

linked="$(sh "$pf" read "$fx/plan-linked.md")"
check "linked: tracker parsed"     "printf '%s' '$linked' | jq -e '.tracker == \"asana\"'"
check "linked: card parsed"        "printf '%s' '$linked' | jq -e '.card == \"1210987654321\"'"
check "linked: ids parsed"         "printf '%s' '$linked' | jq -e '[.units[].id] == [\"s1\", \"s2\"]'"
check "linked: marker off title"   "printf '%s' '$linked' | jq -e '.units[0].title == \"Первая единица\"'"

check "missing file exits 2"       "! sh '$pf' read /nonexistent/x.md 2>/dev/null"
exit $fail
```

- [ ] **Шаг 3: Убедиться, что тест падает**

```
sh scripts/tests/test-plan-file.sh
```

Ожидается: все `FAIL` — скрипта нет.

- [ ] **Шаг 4: Реализовать**

`scripts/plan-file.sh`:

```sh
#!/usr/bin/env sh
# Read and mutate a plan file. The plan is the source of the card link, and
# every write here is atomic: a torn write is the one path back to a duplicate.
#
# Usage:
#   plan-file.sh read <plan>          -> JSON on stdout
#   exit 2 : usage / missing file
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
wl_need jq

cmd="${1:?usage: plan-file.sh read <plan>}"
plan="${2:?plan path required}"
[ -f "$plan" ] || wl_die "no such plan: $plan"

# Fingerprint covers the substantive plan only: the link lines are stripped, so
# writing the nonce does not invalidate a preview the human already read.
plan_fingerprint() {
    _t="$(mktemp)"
    grep -v -e '^\*\*Board:\*\*' -e '^\*\*Origin:\*\*' "$plan" > "$_t"
    wl_sha256 "$_t"
    rm -f "$_t"
}

read_plan() {
    _board="$(sed -n 's/^\*\*Board:\*\* *//p' "$plan" | head -n1)"
    _origin="$(sed -n 's/^\*\*Origin:\*\* *//p' "$plan" | head -n1)"
    _tracker="${_board%%:*}"
    _card="${_board#*:}"
    [ -n "$_board" ] || { _tracker=""; _card=""; }

    # One unit per task heading. A trailing #sN is the marker; the title is what
    # remains once the marker is taken off.
    _units="$(grep -n '^### ' "$plan" | sed 's/^\([0-9]*\):### /\1\t/' | jq -R -s '
      [ splits("\n") | select(length > 0) | split("\t") | .[1] as $h |
        ($h | capture("^(?<label>.*?)(?: +#(?<id>s[0-9]+))?$")) |
        { id: (.id // null),
          title: (.label | sub("^Task [0-9]+: *"; "")) } ]')"

    jq -n --arg path "$plan" --arg tracker "$_tracker" --arg card "$_card" \
          --arg origin "$_origin" --arg fp "$(plan_fingerprint)" \
          --argjson units "$_units" '{
      path: $path,
      tracker: (if $tracker == "" then null else $tracker end),
      card:    (if $card    == "" then null else $card    end),
      origin:  (if $origin  == "" then null else $origin  end),
      fingerprint: $fp,
      units: $units
    }'
}

case "$cmd" in
  read) read_plan ;;
  *)    wl_die "unknown command: $cmd" ;;
esac
```

- [ ] **Шаг 5: Убедиться, что тест проходит**

```
sh scripts/tests/test-plan-file.sh
```

Ожидается: все `PASS`.

- [ ] **Шаг 6: Коммит**

```bash
git add scripts/plan-file.sh scripts/tests/test-plan-file.sh scripts/tests/fixtures/plan-fresh.md scripts/tests/fixtures/plan-linked.md
git commit -m "feat(plan-file): read a plan into JSON"
```

---

### Task 3: plan-file.sh — атомарные правки

**Файлы:**
- Изменить: `scripts/plan-file.sh`
- Изменить: `scripts/tests/test-plan-file.sh`

**Интерфейсы:**
- Потребляет: `wl_atomic_write` из Task 1, `read` из Task 2.
- Отдаёт три подкоманды, каждая пишет атомарно и печатает обновлённый JSON:
  `plan-file.sh set-origin <план> <nonce>`,
  `plan-file.sh set-board <план> <tracker> <gid>`,
  `plan-file.sh set-marker <план> <номер-единицы> <id>` (нумерация с 1).

- [ ] **Шаг 1: Написать падающий тест**

Дописать в `scripts/tests/test-plan-file.sh` перед `exit $fail`:

```sh
t="$(mktemp -d)"; cp "$fx/plan-fresh.md" "$t/p.md"
before="$(sh "$pf" read "$t/p.md" | jq -r .fingerprint)"

sh "$pf" set-board "$t/p.md" asana 999 >/dev/null
check "set-board writes the line"   "grep -q '^\*\*Board:\*\* asana:999$' \"$t/p.md\""
check "set-board is readable back"  "sh '$pf' read \"$t/p.md\" | jq -e '.card == \"999\"'"
check "set-board keeps fingerprint" "[ \"\$(sh '$pf' read \"$t/p.md\" | jq -r .fingerprint)\" = \"$before\" ]"

sh "$pf" set-marker "$t/p.md" 2 s7 >/dev/null
check "set-marker tags the unit"    "grep -q '^### Task 2: Вторая единица #s7$' \"$t/p.md\""
check "set-marker leaves others"    "grep -q '^### Task 1: Первая единица$' \"$t/p.md\""

sh "$pf" set-origin "$t/p.md" wl-cccc3333 >/dev/null
check "set-origin replaces, not adds" "[ \"\$(grep -c '^\*\*Origin:\*\*' \"$t/p.md\")\" = 1 ]"
check "set-origin value applied"      "grep -q '^\*\*Origin:\*\* wl-cccc3333$' \"$t/p.md\""
check "no temp files left"            "! ls \"$t\"/.wl.* >/dev/null 2>&1"
check "set-marker out of range fails" "! sh '$pf' set-marker \"$t/p.md\" 99 s9 2>/dev/null"
rm -rf "$t"
```

- [ ] **Шаг 2: Убедиться, что тест падает**

```
sh scripts/tests/test-plan-file.sh
```

Ожидается: `FAIL` на каждой новой проверке — подкоманд нет.

- [ ] **Шаг 3: Реализовать**

Заменить блок `case` в `scripts/plan-file.sh` на:

```sh
# Replace a header line, or insert it right after the H1 when absent.
set_header() {
    _key="$1"; _val="$2"
    if grep -q "^\*\*$_key:\*\*" "$plan"; then
        sed "s|^\*\*$_key:\*\* .*|**$_key:** $_val|" "$plan" | wl_atomic_write "$plan"
    else
        awk -v line="**$_key:** $_val" '
            NR == 1 { print; print ""; print line; next }
            NR == 2 && $0 == "" { next }
            { print }' "$plan" | wl_atomic_write "$plan"
    fi
}

set_marker() {
    _n="${1:?unit number required}"; _id="${2:?marker required}"
    _total="$(grep -c '^### ' "$plan" || true)"
    [ "$_n" -ge 1 ] 2>/dev/null && [ "$_n" -le "$_total" ] \
        || wl_die "unit $_n out of range (plan has $_total)"
    awk -v n="$_n" -v id="$_id" '
        /^### / { c++; if (c == n) { sub(/ +#s[0-9]+$/, ""); print $0 " #" id; next } }
        { print }' "$plan" | wl_atomic_write "$plan"
}

case "$cmd" in
  read)       read_plan ;;
  set-origin) set_header Origin "${3:?nonce required}"; read_plan ;;
  set-board)  set_header Board "${3:?tracker required}:${4:?gid required}"; read_plan ;;
  set-marker) set_marker "${3:-}" "${4:-}"; read_plan ;;
  *)          wl_die "unknown command: $cmd" ;;
esac
```

- [ ] **Шаг 4: Убедиться, что тест проходит**

```
sh scripts/tests/test-plan-file.sh && sh scripts/tests/run-all.sh
```

Ожидается: все `PASS`, `ALL GREEN`.

- [ ] **Шаг 5: Коммит**

```bash
git add scripts/plan-file.sh scripts/tests/test-plan-file.sh
git commit -m "feat(plan-file): atomic header and marker writes"
```

---

### Task 4: board-state.sh — карта подзадач

**Файлы:**
- Создать: `scripts/board-state.sh`
- Создать: `scripts/tests/test-board-state.sh`

**Интерфейсы:**
- Потребляет: `wl_atomic_write` из Task 1.
- Отдаёт: `board-state.sh map-read <план>` — печатает карту (`{}`, если файла
  нет). `board-state.sh map-set <план> <ключ> <gid>` — дозаписывает связь
  атомарно. `board-state.sh map-init <план> <tracker> <card> <origin>` — создаёт
  карту. Файл карты — `<план без .md>.board.json`.

- [ ] **Шаг 1: Написать падающий тест**

`scripts/tests/test-board-state.sh`:

```sh
#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
bs="$root/scripts/board-state.sh"
t="$(mktemp -d)"; printf '# p\n' > "$t/p.md"

check "empty map reads as {}"   "[ \"\$(sh '$bs' map-read \"$t/p.md\")\" = '{}' ]"
sh "$bs" map-init "$t/p.md" asana 111 wl-dddd4444 >/dev/null
check "map file is beside plan"  "[ -f \"$t/p.board.json\" ]"
check "map-init stores card"     "sh '$bs' map-read \"$t/p.md\" | jq -e '.card == \"111\"'"
check "map-init stores origin"   "sh '$bs' map-read \"$t/p.md\" | jq -e '.origin == \"wl-dddd4444\"'"
check "subtasks start empty"     "sh '$bs' map-read \"$t/p.md\" | jq -e '.subtasks == {}'"

sh "$bs" map-set "$t/p.md" s1 222 >/dev/null
sh "$bs" map-set "$t/p.md" s2 333 >/dev/null
check "map-set accumulates"      "sh '$bs' map-read \"$t/p.md\" | jq -e '.subtasks | length == 2'"
check "map-set keeps card"       "sh '$bs' map-read \"$t/p.md\" | jq -e '.card == \"111\"'"
check "map-set is idempotent"    "sh '$bs' map-set \"$t/p.md\" s1 222 >/dev/null && sh '$bs' map-read \"$t/p.md\" | jq -e '.subtasks | length == 2'"
check "map-set refuses rebind"   "! sh '$bs' map-set \"$t/p.md\" s1 999 2>/dev/null"
check "no temp files left"       "! ls \"$t\"/.wl.* >/dev/null 2>&1"
rm -rf "$t"
exit $fail
```

- [ ] **Шаг 2: Убедиться, что тест падает**

```
sh scripts/tests/test-board-state.sh
```

Ожидается: все `FAIL` — скрипта нет.

- [ ] **Шаг 3: Реализовать**

`scripts/board-state.sh`:

```sh
#!/usr/bin/env sh
# Local state about a plan's card: the subtask map beside the plan.
# The map is versioned on purpose — its diff is the evidence of what ran.
#
# Usage:
#   board-state.sh map-read <plan>
#   board-state.sh map-init <plan> <tracker> <card> <origin>
#   board-state.sh map-set  <plan> <key> <gid>
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
wl_need jq

cmd="${1:?usage: board-state.sh <command> <plan> ...}"
plan="${2:?plan path required}"
map="${plan%.md}.board.json"

map_read() { [ -f "$map" ] && cat "$map" || printf '{}\n'; }

case "$cmd" in
  map-read)
    map_read ;;
  map-init)
    jq -n --arg t "${3:?tracker}" --arg c "${4:?card}" --arg o "${5:?origin}" \
      '{tracker:$t, card:$c, origin:$o, subtasks:{}}' | wl_atomic_write "$map"
    map_read ;;
  map-set)
    _k="${3:?key}"; _g="${4:?gid}"
    _cur="$(map_read | jq -r --arg k "$_k" '.subtasks[$k] // ""')"
    # Rebinding a key would silently point a step at a different subtask.
    [ -z "$_cur" ] || [ "$_cur" = "$_g" ] \
      || wl_die "$_k is already bound to $_cur, refusing to rebind to $_g"
    map_read | jq --arg k "$_k" --arg g "$_g" '.subtasks[$k] = $g' | wl_atomic_write "$map"
    map_read ;;
  *) wl_die "unknown command: $cmd" ;;
esac
```

- [ ] **Шаг 4: Убедиться, что тест проходит**

```
sh scripts/tests/test-board-state.sh
```

Ожидается: все `PASS`.

- [ ] **Шаг 5: Коммит**

```bash
git add scripts/board-state.sh scripts/tests/test-board-state.sh
git commit -m "feat(board-state): subtask map beside the plan"
```

---

### Task 5: board-state.sh — перенос файла между папками секций

**Файлы:**
- Изменить: `scripts/board-state.sh`
- Изменить: `scripts/tests/test-board-state.sh`

**Интерфейсы:**
- Потребляет: `map-read` из Task 4.
- Отдаёт: `board-state.sh dir-of <ключ>` — печатает имя каталога для
  канонического ключа. `board-state.sh place <план> <ключ>` — переносит файл
  плана и его карту в каталог ключа через `git mv` (или `mv`, если файл вне
  git), печатает новый путь. Перенос идемпотентен: файл уже там — успех без
  действия.

- [ ] **Шаг 1: Написать падающий тест**

Дописать в `scripts/tests/test-board-state.sh` перед `exit $fail`:

```sh
check "dir-of maps in_progress" "[ \"\$(sh '$bs' dir-of in_progress)\" = 'in-progress' ]"
check "dir-of maps to_do"       "[ \"\$(sh '$bs' dir-of to_do)\" = 'to-do' ]"
check "dir-of maps done"        "[ \"\$(sh '$bs' dir-of done)\" = 'done' ]"
check "dir-of rejects unknown"  "! sh '$bs' dir-of nonsense 2>/dev/null"

u="$(mktemp -d)"; mkdir -p "$u/backlog"; printf '# p\n' > "$u/backlog/p.md"
sh "$bs" map-init "$u/backlog/p.md" asana 111 wl-e5 >/dev/null
new="$(sh "$bs" place "$u/backlog/p.md" in_progress)"
check "place moves the plan"    "[ -f \"$u/in-progress/p.md\" ]"
check "place moves the map"     "[ -f \"$u/in-progress/p.board.json\" ]"
check "place clears the source" "[ ! -f \"$u/backlog/p.md\" ]"
check "place prints new path"   "[ \"$new\" = \"$u/in-progress/p.md\" ]"
check "place is idempotent"     "sh '$bs' place \"$u/in-progress/p.md\" in_progress >/dev/null"
rm -rf "$u"
```

- [ ] **Шаг 2: Убедиться, что тест падает**

```
sh scripts/tests/test-board-state.sh
```

Ожидается: `FAIL` на всех новых проверках.

- [ ] **Шаг 3: Реализовать**

Вставить в `scripts/board-state.sh` перед блоком `case` :

```sh
# The canonical key is the identity; the directory name is its spelling on disk.
# Both are fixed here so nothing downstream guesses either one.
dir_of() {
    case "${1:?key required}" in
        backlog)     printf 'backlog\n' ;;
        to_do)       printf 'to-do\n' ;;
        in_progress) printf 'in-progress\n' ;;
        review)      printf 'review\n' ;;
        done)        printf 'done\n' ;;
        *) wl_die "unknown section key: $1 (expected backlog|to_do|in_progress|review|done)" ;;
    esac
}

# Move the plan and its map into the directory of a section key.
move_one() {
    _src="$1"; _dst="$2"
    [ -e "$_src" ] || return 0
    if git -C "$(dirname "$_src")" rev-parse --git-dir >/dev/null 2>&1; then
        git mv -f "$_src" "$_dst" 2>/dev/null || mv -f "$_src" "$_dst"
    else
        mv -f "$_src" "$_dst"
    fi
}

place() {
    _key="${1:?section key required}"
    _dir="$(dir_of "$_key")"
    _parent="$(cd "$(dirname "$plan")/.." && pwd)"
    _target="$_parent/$_dir"
    _new="$_target/$(basename "$plan")"
    if [ "$plan" = "$_new" ]; then printf '%s\n' "$_new"; return 0; fi
    mkdir -p "$_target" || wl_die "cannot create $_target"
    move_one "$plan" "$_new"
    move_one "$map" "${_new%.md}.board.json"
    printf '%s\n' "$_new"
}
```

И добавить две ветки в `case`, перед `*)`:

```sh
  dir-of) dir_of "$plan" ;;
  place)  place "${3:?section key required}" ;;
```

Замечание для исполнителя: у `dir-of` второй аргумент — это ключ, а не путь.
Общая переменная `plan` здесь просто несёт его значение; переименовывать её не
нужно, но и трактовать как файл нельзя.

- [ ] **Шаг 4: Убедиться, что тест проходит**

```
sh scripts/tests/test-board-state.sh && sh scripts/tests/run-all.sh
```

Ожидается: все `PASS`, `ALL GREEN`.

- [ ] **Шаг 5: Коммит**

```bash
git add scripts/board-state.sh scripts/tests/test-board-state.sh
git commit -m "feat(board-state): move a plan into its section directory"
```

---

### Task 6: resolve-config.sh — plans_dir и sections

**Файлы:**
- Изменить: `scripts/resolve-config.sh`
- Изменить: `scripts/tests/test-resolve-config.sh`
- Изменить: `references/worklog.config.example.json`
- Изменить: `references/worklog.config.project.example.json`

**Интерфейсы:**
- Отдаёт: в эффективном конфиге появляются `plans_dir` (строка, по умолчанию
  `docs/superpowers/plans`) и `sections` (объект из пяти ключей). Неполный
  `sections` — выход 3, тем же кодом, что и `NEEDS_ONBOARDING`: и то и другое
  означает «конфигурация не готова к работе».

- [ ] **Шаг 1: Написать падающий тест**

Дописать в `scripts/tests/test-resolve-config.sh` перед `rm -rf "$tmp"`:

```sh
# --- Case F: plans_dir has a built-in default.
cat > "$proj/.claude/worklog.config.json" <<'JSON'
{ "clickup_list_id": "L1", "github_repo": "O/R" }
JSON
effF="$tmp/f.json"
WL_GLOBAL_CONFIG=/nonexistent sh "$rc" "$proj" > "$effF" 2>/dev/null
check "F: plans_dir default" "jq -e '.plans_dir==\"docs/superpowers/plans\"' '$effF'"

# --- Case G: a complete five-key sections map resolves.
cat > "$proj/.claude/worklog.config.json" <<'JSON'
{ "clickup_list_id": "L1", "github_repo": "O/R",
  "sections": { "backlog":"b", "to_do":"t", "in_progress":"i", "review":"r", "done":"d" } }
JSON
effG="$tmp/g.json"
WL_GLOBAL_CONFIG=/nonexistent sh "$rc" "$proj" > "$effG" 2>/dev/null
check "G: five keys survive" "jq -e '.sections | length == 5' '$effG'"

# --- Case H: an incomplete sections map is a configuration error, not a guess.
cat > "$proj/.claude/worklog.config.json" <<'JSON'
{ "clickup_list_id": "L1", "github_repo": "O/R",
  "sections": { "done":"d", "in_progress":"i" } }
JSON
check "H: incomplete sections exits 3" \
  "WL_GLOBAL_CONFIG=/nonexistent sh '$rc' '$proj' >/dev/null 2>&1; [ \$? -eq 3 ]"
check "H: the missing keys are named" \
  "WL_GLOBAL_CONFIG=/nonexistent sh '$rc' '$proj' 2>&1 >/dev/null | grep -q backlog"
```

- [ ] **Шаг 2: Убедиться, что тест падает**

```
sh scripts/tests/test-resolve-config.sh
```

Ожидается: `FAIL: F`, `FAIL: G`, `FAIL: H` — ключей нет.

- [ ] **Шаг 3: Реализовать**

В `scripts/resolve-config.sh` добавить `plans_dir` во встроенные значения:

```sh
  drafts_dir:    "worklog/_daily",
  plans_dir:     "docs/superpowers/plans",
```

И перед выводом эффективного конфига вставить проверку:

```sh
# sections: either absent (the board flow is unused) or complete. A half-filled
# map would fail mid-write, and the write is the expensive half.
if printf '%s' "$eff" | jq -e 'has("sections")' >/dev/null 2>&1; then
  missing="$(printf '%s' "$eff" | jq -r '
    ["backlog","to_do","in_progress","review","done"]
    - (.sections | keys) | join(", ")')"
  if [ -n "$missing" ]; then
    printf 'NEEDS_ONBOARDING: sections is missing: %s\n' "$missing" >&2
    exit 3
  fi
fi
```

Дописать в оба примера конфигурации полный блок:

```json
"sections": {
  "backlog": "<gid>", "to_do": "<gid>", "in_progress": "<gid>",
  "review": "<gid>", "done": "<gid>"
}
```

- [ ] **Шаг 4: Убедиться, что тест проходит**

```
sh scripts/tests/test-resolve-config.sh && sh scripts/tests/test-references.sh
```

Ожидается: все `PASS` в обоих.

- [ ] **Шаг 5: Коммит**

```bash
git add scripts/resolve-config.sh scripts/tests/test-resolve-config.sh references/worklog.config.example.json references/worklog.config.project.example.json
git commit -m "feat(config): plans_dir and a complete five-key sections map"
```

---

### Task 7: board-preview.sh — предпросмотр и отпечаток

**Файлы:**
- Создать: `scripts/board-preview.sh`
- Создать: `scripts/tests/test-board-preview.sh`

**Интерфейсы:**
- Потребляет: `plan-file.sh read` из Task 2.
- Отдаёт: `board-preview.sh build <план> <секция>` — пишет
  `<план без .md>.board-preview.md` и печатает путь. Первая строка файла —
  `<!-- fingerprint: <sha> -->`. `board-preview.sh verify <план>` — выход 0,
  если отпечаток в предпросмотре совпадает с текущим планом; выход 4, если
  разошёлся; выход 2, если предпросмотра нет.

Код 4 отдельный: «план изменился после показа» — не ошибка использования, а
штатный отказ, и вызывающий обязан отличать его от отсутствия файла.

- [ ] **Шаг 1: Написать падающий тест**

`scripts/tests/test-board-preview.sh`:

```sh
#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
bp="$root/scripts/board-preview.sh"
pf="$root/scripts/plan-file.sh"
t="$(mktemp -d)"; cp "$root/scripts/tests/fixtures/plan-fresh.md" "$t/p.md"

out="$(sh "$bp" build "$t/p.md" backlog)"
check "build prints the path"      "[ \"$out\" = \"$t/p.board-preview.md\" ]"
check "preview exists"             "[ -f \"$t/p.board-preview.md\" ]"
check "preview carries fingerprint" "head -n1 \"$t/p.board-preview.md\" | grep -Eq 'fingerprint: [0-9a-f]{64}'"
check "preview names the section"  "grep -q 'backlog' \"$t/p.board-preview.md\""
check "preview lists both units"   "[ \"\$(grep -c '^- ' \"$t/p.board-preview.md\")\" = 2 ]"
check "verify passes when unchanged" "sh '$bp' verify \"$t/p.md\""

# Writing the nonce must NOT invalidate a preview the human already read.
sh "$pf" set-origin "$t/p.md" wl-ffff6666 >/dev/null
check "verify survives a nonce write" "sh '$bp' verify \"$t/p.md\""

printf '\n### Task 3: Третья единица\n' >> "$t/p.md"
check "verify refuses after an edit" "sh '$bp' verify \"$t/p.md\"; [ \$? -eq 4 ]"

rm -f "$t/p.board-preview.md"
check "verify without preview exits 2" "sh '$bp' verify \"$t/p.md\"; [ \$? -eq 2 ]"
rm -rf "$t"
exit $fail
```

- [ ] **Шаг 2: Убедиться, что тест падает**

```
sh scripts/tests/test-board-preview.sh
```

Ожидается: все `FAIL` — скрипта нет.

- [ ] **Шаг 3: Реализовать**

`scripts/board-preview.sh`:

```sh
#!/usr/bin/env sh
# Build the preview a human reads before anything is written to the tracker,
# and refuse a confirmation that no longer matches what was read.
#
# Usage:
#   board-preview.sh build  <plan> <section-key>   -> path on stdout
#   board-preview.sh verify <plan>
# exit 4 : the plan changed after the preview was built
# exit 2 : usage, missing plan, or missing preview
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
wl_need jq

cmd="${1:?usage: board-preview.sh <build|verify> <plan> [section]}"
plan="${2:?plan path required}"
[ -f "$plan" ] || wl_die "no such plan: $plan"
preview="${plan%.md}.board-preview.md"

current_fp() { sh "$here/plan-file.sh" read "$plan" | jq -r .fingerprint; }

build() {
    _section="${1:?section key required}"
    _json="$(sh "$here/plan-file.sh" read "$plan")"
    _title="$(head -n1 "$plan" | sed 's/^# *//')"
    {
        printf '<!-- fingerprint: %s -->\n\n' "$(printf '%s' "$_json" | jq -r .fingerprint)"
        printf '# Будет создано\n\n'
        printf '**Карточка:** %s\n\n' "$_title"
        printf '**Секция:** %s\n\n' "$_section"
        printf '**Подзадачи:**\n\n'
        printf '%s' "$_json" | jq -r '.units[] | "- " + .title'
        printf '\nПодтверди, чтобы записать. Отмена — просто не подтверждай.\n'
    } | wl_atomic_write "$preview"
    printf '%s\n' "$preview"
}

verify() {
    [ -f "$preview" ] || { printf 'no preview for %s\n' "$plan" >&2; exit 2; }
    _was="$(sed -n '1s/.*fingerprint: \([0-9a-f]*\).*/\1/p' "$preview")"
    _now="$(current_fp)"
    [ "$_was" = "$_now" ] || {
        printf 'plan changed after the preview was built\n' >&2
        exit 4
    }
}

case "$cmd" in
  build)  build "${3:-}" ;;
  verify) verify ;;
  *)      wl_die "unknown command: $cmd" ;;
esac
```

- [ ] **Шаг 4: Убедиться, что тест проходит**

```
sh scripts/tests/test-board-preview.sh
```

Ожидается: все `PASS`. Особенно проверка «verify переживает запись числа» —
она доказывает, что отпечаток считается по содержательной части.

- [ ] **Шаг 5: Коммит**

```bash
git add scripts/board-preview.sh scripts/tests/test-board-preview.sh
git commit -m "feat(board-preview): preview with a fingerprint gate"
```

---

### Task 8: board-journal.sh — след для человека

**Файлы:**
- Создать: `scripts/board-journal.sh`
- Создать: `scripts/tests/test-board-journal.sh`

**Интерфейсы:**
- Отдаёт: `board-journal.sh append <op> <plan> <tracker> <outcome> [card] [note]`
  — дозаписывает одну строку ndjson. `outcome` принимает только `ok` и `fail`;
  что угодно ещё — выход 2. Путь журнала берётся из `WL_JOURNAL`, по умолчанию
  `$HOME/.claude/worklog/journal.ndjson`.

Журнал — наблюдение, а не состояние: его удаление не меняет поведения системы.
Ни один скрипт не читает его, чтобы принять решение.

- [ ] **Шаг 1: Написать падающий тест**

`scripts/tests/test-board-journal.sh`:

```sh
#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
bj="$root/scripts/board-journal.sh"
t="$(mktemp -d)"; j="$t/journal.ndjson"

WL_JOURNAL="$j" sh "$bj" append create docs/p.md asana ok 111 ""
check "journal file created"    "[ -f '$j' ]"
check "one line written"        "[ \"\$(wc -l < '$j' | tr -d ' ')\" = 1 ]"
check "line is valid json"      "jq -e . '$j'"
check "outcome recorded"        "jq -e '.outcome == \"ok\"' '$j'"
check "card recorded"           "jq -e '.card == \"111\"' '$j'"
check "timestamp is utc"        "jq -re '.ts' '$j' | grep -q 'Z$'"

WL_JOURNAL="$j" sh "$bj" append create docs/p.md asana fail "" "network refused"
check "failures are recorded"   "[ \"\$(wc -l < '$j' | tr -d ' ')\" = 2 ]"
check "failure carries a note"  "tail -n1 '$j' | jq -e '.outcome == \"fail\" and .note == \"network refused\"'"
check "bad outcome rejected"    "! ( WL_JOURNAL='$j' sh '$bj' append create docs/p.md asana maybe 2>/dev/null )"
check "bad outcome writes nothing" "[ \"\$(wc -l < '$j' | tr -d ' ')\" = 2 ]"
rm -rf "$t"
exit $fail
```

- [ ] **Шаг 2: Убедиться, что тест падает**

```
sh scripts/tests/test-board-journal.sh
```

Ожидается: все `FAIL` — скрипта нет.

- [ ] **Шаг 3: Реализовать**

`scripts/board-journal.sh`:

```sh
#!/usr/bin/env sh
# One line per finished operation, successes and failures alike. This is a trail
# for a human looking back, not state: nothing reads it to decide anything, and
# deleting it changes no behaviour.
#
# Usage: board-journal.sh append <op> <plan> <tracker> <ok|fail> [card] [note]
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
wl_need jq

[ "${1:-}" = "append" ] || wl_die "usage: board-journal.sh append <op> <plan> <tracker> <ok|fail> [card] [note]"
op="${2:?op required}"; plan="${3:?plan required}"
tracker="${4:?tracker required}"; outcome="${5:?outcome required}"
card="${6:-}"; note="${7:-}"

case "$outcome" in
  ok|fail) ;;
  *) wl_die "outcome must be ok or fail (got: $outcome)" ;;
esac

journal="${WL_JOURNAL:-$HOME/.claude/worklog/journal.ndjson}"
mkdir -p "$(dirname "$journal")" || wl_die "cannot create journal directory"

jq -c -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg op "$op" \
  --arg plan "$plan" --arg tracker "$tracker" --arg outcome "$outcome" \
  --arg card "$card" --arg note "$note" \
  '{ts:$ts, op:$op, plan:$plan, tracker:$tracker, outcome:$outcome, card:$card, note:$note}' \
  >> "$journal"
```

- [ ] **Шаг 4: Убедиться, что тест проходит**

```
sh scripts/tests/test-board-journal.sh && sh scripts/tests/run-all.sh
```

Ожидается: все `PASS`, `ALL GREEN`.

- [ ] **Шаг 5: Коммит**

```bash
git add scripts/board-journal.sh scripts/tests/test-board-journal.sh
git commit -m "feat(board-journal): append-only trail including failures"
```

---

### Task 9: адаптеры — четыре операции и пять ключей секций

**Файлы:**
- Изменить: `references/adapters/asana.md`
- Изменить: `references/adapters/clickup.md`
- Изменить: `scripts/tests/test-adapters.sh`

**Интерфейсы:**
- Отдаёт: у каждого адаптера появляется раздел `## Board operations` с четырьмя
  операциями — `find`, `find_by_origin`, `place`, `close` — и раздел
  `## Sections`, отображающий пять канонических ключей на понятие трекера.

Причина, по которой это отдельная задача: нынешние адаптеры **противоречат**
канонической схеме, а не просто её не содержат. У Asana размечены два ключа
вместо пяти, карта необязательна, ключ записан как `in progress` с пробелом, и
разрешён подбор секции по названию. У ClickUp секций нет вовсе — там статусы
списка.

- [ ] **Шаг 1: Написать падающий тест**

Дописать в `scripts/tests/test-adapters.sh` внутрь цикла `for f in "$dir"/*.md`,
сразу после проверки существующих разделов:

```sh
  for s in "Board operations" Sections; do
    check "$b: has section $s" "grep -q '^## $s' '$f'"
  done

  for op in find find_by_origin place close; do
    check "$b: documents operation $op" "grep -q '\`$op\`' '$f'"
  done

  # Five canonical keys, snake_case, no spaces. A key spelled with a space is
  # exactly the defect this task exists to remove.
  for k in backlog to_do in_progress review done; do
    check "$b: maps section key $k" "grep -q '\`$k\`' '$f'"
  done
  check "$b: no space-spelled section key" "! grep -q '\"in progress\"' '$f'"

  # Guessing a section by display name is removed: matching names are a
  # coincidence, not a guarantee.
  check "$b: does not guess sections by name" \
    "! grep -qi 'whose name matches' '$f'"
```

- [ ] **Шаг 2: Убедиться, что тест падает**

```
sh scripts/tests/test-adapters.sh
```

Ожидается: `FAIL` на разделах `Board operations` и `Sections`, на четырёх
операциях, на ключах `backlog`, `to_do`, `review`, на `no space-spelled` и на
`does not guess sections by name` — у Asana.

- [ ] **Шаг 3: Реализовать — Asana**

В `references/adapters/asana.md` заменить строку про `section_map` в таблице
конфигурации на:

```markdown
| `sections` | yes | все пять канонических ключей → gid секции |
```

Удалить абзац, начинающийся с «When `section_map` lacks a status», целиком.

Добавить два раздела:

```markdown
## Sections

Пять канонических ключей ядра отображаются на gid секций проекта. Отображение
обязательно и полно: недостающий ключ — ошибка разрешения конфигурации, а не
повод подобрать секцию по названию. Совпадение названий — совпадение, а не
гарантия.

| Ключ ядра | Что это в Asana |
| --- | --- |
| `backlog` | секция проекта |
| `to_do` | секция проекта |
| `in_progress` | секция проекта |
| `review` | секция проекта |
| `done` | секция проекта **и** флаг `completed` |

Список gid читается один раз через `get_project` с `include_sections: true` и
закрепляется в конфигурации пользователем.

## Board operations

| Операция | Вызов | Замечания |
| --- | --- | --- |
| `find` | `get_task` с `task_id` | «не найдено» — это ошибка вызова, отличай её от сетевой |
| `find_by_origin` | `search_tasks` с `text` = метка и `projects_any` = проект | проверено живым запросом 2026-09-01: находит по фразе, встречающейся только в описании, и возвращает в том числе закрытые задачи |
| `place` | `add_projects` с `section_id` из `sections[<ключ>]` | для `done` дополнительно `completed: true` |
| `close` | `update_tasks`: `completed: true`, текст в `html_notes` | story points идут текстом внутри описания |

Ноль совпадений у `find_by_origin` означает «карточки нет, создавай». Больше
одного — остановка: метка перестала быть уникальной, и выбирать первую попавшуюся
нельзя.
```

- [ ] **Шаг 4: Реализовать — ClickUp**

В `references/adapters/clickup.md` добавить те же два раздела, с поправкой на
устройство трекера:

```markdown
## Sections

Секций у ClickUp нет — есть статусы списка, и задаёт их пользователь. Поэтому
ядро ничего не гарантирует, а требует: пять канонических ключей отображаются на
существующие статусы списка, и если статуса под ключ нет, пользователь его
заводит.

| Ключ ядра | Что это в ClickUp |
| --- | --- |
| `backlog` | статус списка |
| `to_do` | статус списка |
| `in_progress` | статус списка |
| `review` | статус списка |
| `done` | статус списка, закрывающий задачу |

## Board operations

| Операция | Вызов | Замечания |
| --- | --- | --- |
| `find` | `clickup_get_task` по id | «не найдено» отличается от сетевой ошибки |
| `find_by_origin` | `clickup_filter_tasks` по списку с последующим точным сравнением метки | **не проверено живым запросом.** До проверки ClickUp-ветка идемпотентности считается недоказанной |
| `place` | `clickup_update_task` со статусом из `sections[<ключ>]` | |
| `close` | `clickup_update_task` со статусом `sections.done` | |
```

- [ ] **Шаг 5: Убедиться, что тест проходит**

```
sh scripts/tests/test-adapters.sh && sh scripts/tests/run-all.sh
```

Ожидается: все `PASS`, `ALL GREEN`. Проверка «один трекер на файл» должна
остаться зелёной: в разделах выше не упоминается чужой трекер.

- [ ] **Шаг 6: Коммит**

```bash
git add references/adapters/asana.md references/adapters/clickup.md scripts/tests/test-adapters.sh
git commit -m "feat(adapters): board operations and five canonical section keys"
```

---

### Task 10: команды и ядро

**Файлы:**
- Создать: `commands/plan-to-board.md`
- Создать: `commands/board-move.md`
- Создать: `commands/board-cancel.md`
- Создать: `commands/board-relink.md`
- Создать: `skills/worklog-board/SKILL.md`
- Изменить: `skills/worklog-day/SKILL.md`
- Изменить: `scripts/tests/test-skill.sh`
- Изменить: `scripts/tests/test-command.sh`

**Интерфейсы:**
- Потребляет: все скрипты из Task 1–8 и разделы адаптеров из Task 9.
- Отдаёт: навык `worklog-board`, нейтральный к трекеру, и четыре команды,
  которые его вызывают.

- [ ] **Шаг 1: Написать падающий тест**

Дописать в `scripts/tests/test-skill.sh` перед `exit $fail`:

```sh
b="$root/skills/worklog-board/SKILL.md"
check "board skill exists"        "[ -s '$b' ]"
check "board skill has name"      "grep -q '^name: worklog-board' '$b'"
for s in plan-file.sh board-state.sh board-preview.sh board-journal.sh; do
  check "board skill uses $s"     "grep -q '$s' '$b'"
done
check "board skill is neutral"    "! grep -qiE 'asana|clickup' '$b'"
check "board skill states preview-first" "grep -qi 'предпросмотр' '$b'"
check "board skill forbids autonomous moves" "grep -qi 'подтвержд' '$b'"
check "day skill closes existing card" "grep -q 'board' '$root/skills/worklog-day/SKILL.md'"
```

И в `scripts/tests/test-command.sh` — проверку, что каждая команда существует и
объявляет инструменты:

```sh
for c in plan-to-board board-move board-cancel board-relink; do
  f="$root/commands/$c.md"
  check "$c: command file exists" "[ -s '$f' ]"
  check "$c: declares description" "grep -q '^description:' '$f'"
  check "$c: declares allowed-tools" "grep -q '^allowed-tools:' '$f'"
  check "$c: invokes the board skill" "grep -q 'worklog-board' '$f'"
done
```

- [ ] **Шаг 2: Убедиться, что тест падает**

```
sh scripts/tests/test-skill.sh; sh scripts/tests/test-command.sh
```

Ожидается: `FAIL` на всех новых проверках.

- [ ] **Шаг 3: Написать навык**

`skills/worklog-board/SKILL.md` — нейтральное ядро. Ни одного имени трекера:
какой адаптер читать, определяется ключом `tracker` из разрешённого конфига, и
навык обязан вслух назвать выбранный адаптер прежде, чем что-либо делать.

Порядок для `/plan-to-board`:

1. `resolve-config.sh` — получить конфиг. Выход 3 означает, что работать
   нельзя: сообщи, чего не хватает, и остановись.
2. Назвать вслух адаптер: «использую адаптер `<tracker>`».
3. `plan-file.sh read <план>` — прочитать план.
4. Если `card` уже есть — это дозаполнение, а не создание: перейти к шагу 8.
5. `board-preview.sh build <план> backlog` — построить предпросмотр, показать
   его человеку **целиком** и ждать подтверждения. До подтверждения не делать
   ни одного вызова трекера.
6. `board-preview.sh verify <план>` — выход 4 означает, что план изменился
   после показа: остановиться, сообщить, предложить пересобрать предпросмотр.
7. Сгенерировать одноразовое число, `plan-file.sh set-origin`, и только после
   этого обращаться к трекеру.
8. По рецепту адаптера: `find_by_origin` с меткой. Найдена одна — присвоить её
   gid, ничего не создавая. Найдено больше одной — остановиться. Не найдено —
   создать карточку и подзадачи.
9. `plan-file.sh set-board`, `set-marker` для каждой единицы,
   `board-state.sh map-init` и `map-set`.
10. `board-state.sh place <план> backlog`.
11. `board-journal.sh append create <план> <tracker> ok <card>`. При отказе на
    любом шаге — та же команда с `fail` и пояснением.

Порядок для `/board-move`: выровнять локальное представление по трекеру,
показать намерение рядом с текущим состоянием карточки, дождаться
подтверждения, выполнить `place` по рецепту адаптера, `board-state.sh place`,
запись в журнал.

Три случая расхождения — как в спеке: устаревший кэш выравнивается молча и
пишется в журнал; конфликт намерения с реальностью останавливает; исчезнувшая
карточка останавливает и предлагает снять `Board:`.

- [ ] **Шаг 4: Написать команды**

Каждая из четырёх — тонкая обёртка в стиле `commands/log-day.md`: frontmatter с
`description`, `argument-hint`, `allowed-tools` (объединение инструментов обоих
трекеров, как уже сделано для `log-day`), и тело из трёх-четырёх строк,
вызывающее навык `worklog-board`.

- [ ] **Шаг 5: Дополнить навык дня**

В `skills/worklog-day/SKILL.md`, в стадии записи: если у плана, к которому
относится работа, есть `Board:`, закрывать **существующую** карточку через
операцию `close` адаптера, а не создавать новую.

- [ ] **Шаг 6: Убедиться, что тесты проходят**

```
sh scripts/tests/run-all.sh
```

Ожидается: `ALL GREEN`.

- [ ] **Шаг 7: Коммит**

```bash
git add commands/ skills/ scripts/tests/test-skill.sh scripts/tests/test-command.sh
git commit -m "feat(board): neutral board skill and four commands"
```

---

## Самопроверка плана

**Покрытие спеки.** Пройдены разделы спеки: поток (Task 10), артефакты
(Task 2–4, 7, 8), секции и папки (Task 5, 6, 9), идемпотентность (Task 4 —
запрет перепривязки, Task 10 — `find_by_origin`), одноразовое число и его
атомарность (Task 1, 3, 10), три случая расхождения (Task 10), судьба плана
(Task 10), контракт адаптера (Task 9), конфигурация (Task 6), журнал (Task 8).

**Не покрыто намеренно.** Очередь 2 — индекс, поиск, проактивность, запасной
источник доказательства без PR. Обоснование в спеке.

**Известный разрыв.** `find_by_origin` для ClickUp не проверен живым запросом.
Task 9 фиксирует это в самом адаптере как условие готовности, а не как
допущение. Реализовывать ClickUp-ветку до проверки нельзя.

**Порядок задач.** Task 1 не зависит ни от чего. Task 2 требует Task 1
(`wl_sha256`). Task 3 требует Task 1 и 2. Task 4 требует Task 1. Task 5
требует Task 4. Task 6 независима. Task 7 требует Task 2 и 3. Task 8 требует Task 1 только в части `lib.sh`, который уже существует, — то
есть выполнима сразу. Task 9 требует Task 6 (ключи `sections`). Task 10
требует все.

Задачи 1, 6 и 8 не зависят друг от друга и могут идти параллельно. Остальные
выстраиваются в цепочку.
