#!/usr/bin/env bash
# Регрессионные тесты валидатора формата задач (scripts/tracker-validate.sh).
# Каждый кейс — сценарий из аудитов формата: ожидаем exit-код и подстроку
# сообщения. Гоняется в песочнице (mktemp), реальный Tasks/ не трогается.
# Песочница повторяет раскладку репозитория (scripts/ + templates/ + Tasks/):
# канонический резолв шаблона в new.sh и TASKS_DIR работают как в бою.
# Запуск: scripts/tracker-tests.sh — сводка в конце, exit 1 при любом провале.
set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

SBOX=$(mktemp -d)
PATCH="$SBOX-patch.py"
trap 'rm -rf "$SBOX" "$SBOX-wtrepo" "$PATCH"' EXIT
# Источник шаблона — тем же резолвом, что и в tracker-new.sh: канонический
# templates/ этого репозитория, затем копия из вендоренного зеркала (шаблон
# рядом со скриптом — раскладка Tools/hooks/lib).
template_src="${TASKS_TEMPLATE:-}"
if [ -z "$template_src" ]; then
  for c in \
      "$script_dir/../templates/tracker-task-template.md" \
      "$script_dir/tracker-task-template.md"; do
    [ -r "$c" ] && { template_src="$c"; break; }
  done
fi
if [ -z "$template_src" ] || [ ! -r "$template_src" ]; then
  echo "Ошибка: не найден шаблон задачи (TASKS_TEMPLATE, templates/ от скрипта или копия из вендоренного зеркала)." >&2
  exit 1
fi
mkdir -p "$SBOX/scripts" "$SBOX/templates" "$SBOX/Tasks"
cp "$script_dir/tracker-validate.sh" "$script_dir/tracker-new.sh" "$SBOX/scripts/"
cp "$template_src" "$SBOX/templates/tracker-task-template.md"
chmod +x "$SBOX/scripts/tracker-validate.sh" "$SBOX/scripts/tracker-new.sh"
RUN=(env TASKS_DIR="$SBOX/Tasks")
VAL="$SBOX/scripts/tracker-validate.sh"
NEW="$SBOX/scripts/tracker-new.sh"
cd "$SBOX/Tasks"

cat > "$PATCH" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
args = [a.replace('\\n', '\n') for a in sys.argv[2:]]
for a, b in zip(args[0::2], args[1::2]):
    s = s.replace(a, b)
open(p, 'w').write(s)
PYEOF

pass_n=0
fail_n=0
ok() { # <папка> <описание>
  if out=$("${RUN[@]}" "$VAL" "$1" 2>&1); then
    pass_n=$((pass_n + 1))
  else
    fail_n=$((fail_n + 1)); printf 'FAIL(ok) %s\n%s\n' "$2" "$out"
  fi
}
err() { # <папка> <описание> <подстрока сообщения>
  out=$("${RUN[@]}" "$VAL" "$1" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then
    fail_n=$((fail_n + 1)); printf 'FAIL(err) %s — ошибки не было\n' "$2"
  elif ! printf '%s' "$out" | grep -qF "$3"; then
    fail_n=$((fail_n + 1)); printf 'FAIL(msg) %s — нет «%s»:\n%s\n' "$2" "$3" "$out"
  else
    pass_n=$((pass_n + 1))
  fi
}
err_full() { # <описание> <подстрока>
  out=$("${RUN[@]}" "$VAL" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then
    fail_n=$((fail_n + 1)); printf 'FAIL(err) %s — ошибки не было\n' "$1"
  elif ! printf '%s' "$out" | grep -qF "$2"; then
    fail_n=$((fail_n + 1)); printf 'FAIL(msg) %s — нет «%s»:\n%s\n' "$1" "$2" "$out"
  else
    pass_n=$((pass_n + 1))
  fi
}
ok_full() { # <описание>
  if out=$("${RUN[@]}" "$VAL" 2>&1); then
    pass_n=$((pass_n + 1))
  else
    fail_n=$((fail_n + 1)); printf 'FAIL(ok) %s\n%s\n' "$1" "$out"
  fi
}
nt() { "${RUN[@]}" "$NEW" "$1" "$2" "${3:-Заголовок}" | head -1 | grep -oE '[0-9]{4}-[a-z0-9-]+/task\.md' | head -1 | sed 's|/task\.md||'; }
patch() { python3 "$PATCH" "$@"; }
setf() { # <task.md> <status> [доп-поля шапки, строки через \n]
  patch "$1" 'status: draft' "status: $2"
  if [ $# -gt 2 ]; then
    python3 - "$1" "$3" <<'PYEOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
extra = sys.argv[2].replace('\\n', '\n')
s = re.sub(r'(?m)^(updated: .*)$', lambda m: m.group(1) + '\n' + extra, s, count=1)
open(p, 'w').write(s)
PYEOF
  fi
}
clear_block() { # убрать блокировку — вернуть в open без blocked-by
  python3 - "$1" <<'PYEOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'(?m)^blocked-by:.*\n?', '', s)
s = s.replace('status: blocked', 'status: open')
open(p, 'w').write(s)
PYEOF
}
fdate() { sed -n 's/^created: //p' "$1" | head -1; } # дата фикстуры, не литерал — иначе набор протухает на следующий день
DESC_OLD='<!-- Что происходит / чего не хватает / что исследуем и зачем. -->'
DESC_NEW='Реальная проблема с контекстом.'
READY_OLD='<!-- feature / improvement / task — обязательно; для bug — опционально. -->\n\n- [ ]'
READY_NEW='- [ ] Пункт готовности.'
STEPS_OLD='1.\n2.\n\n**Фактическое поведение:**\n\n**Ожидаемое поведение:**'
STEPS_NEW='1. Открыть поиск.\n\n**Фактическое поведение:** крэш.\n\n**Ожидаемое поведение:** результат.'
QUEST_OLD='<!-- Только product-research / tech-research — обязательно. -->\n\n-'
QUEST_NEW='- Что исследуем и зачем?'
RES_OLD='<!-- product-research / tech-research — обязательно: итог проработки и решение.\n     Результат проработки также фиксируется спекой (поле spec выше). -->'
RES_NEW='Итог: решение.'
fill_desc()  { patch "$1/task.md" "$DESC_OLD" "$DESC_NEW"; }
fill_ready() { patch "$1/task.md" "$READY_OLD" "$READY_NEW"; }
fill_steps() { patch "$1/task.md" "$STEPS_OLD" "$STEPS_NEW"; }
fill_quest() { patch "$1/task.md" "$QUEST_OLD" "$QUEST_NEW"; }
fill_result() { patch "$1/task.md" "$RES_OLD" "$RES_NEW"; }

# --- структура и шапка -------------------------------------------------------
d=$(nt task t01); ok "$d" 'черновик из шаблона валиден (YAML-комментарии легальны)'
d=$(nt task t02); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" open; ok "$d" 'open с заполненными секциями'
d=$(nt feature t03); fill_desc "$d"; setf "$d/task.md" open
err "$d" 'пустые «Критерии готовности»' 'раздел'
d=$(nt task t04); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" open
patch "$d/task.md" '## Описание' '## Описания'
err "$d" 'заголовок-опечатка' "раздел '## Описание' отсутствует"
d=$(nt task t05); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" open 'blocke-by: [1]'
err "$d" 'неизвестное поле' 'неизвестное поле'
d=$(nt task t06); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" open 'blocked - by: [3]'
err "$d" 'строка шапки вне «ключ:»' 'не вида «ключ: значение»'
d=$(nt task t07); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" open 'assignee: a'
patch "$d/task.md" 'priority: P2' 'priority: P2\nstatus: draft'
err "$d" 'дубль ключа' 'дважды'
d=$(nt task t08); fill_desc "$d"; fill_ready "$d"
patch "$d/task.md" 'status: draft' 'status: inprogres'
err "$d" 'плохой enum' 'вне enum'
d=$(nt task t09); printf -- '---\nid: 9\ntitle: x\ntype: task\nstatus: draft\ncreated: 2026-10-07\nupdated: 2026-10-07\n---\n\n## Описание\n\nтекст\n' > "$d/task.md"
err "$d" 'title без кавычек' 'в кавычках'
d=$(nt task t10); printf -- '---\n---\n' > "$d/task.md"
err "$d" 'пустая закрытая шапка' 'YAML-шапка пуста'

# --- даты --------------------------------------------------------------------
# все правки дат — от фактической даты фикстуры (fdate), а не от литерала:
# new.sh проставляет date +%F, литерал протух бы уже на следующий день
d=$(nt task t11); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" open
patch "$d/task.md" "created: $(fdate "$d/task.md")" 'created: 2026-10-00'
err "$d" 'день 00' 'не в формате YYYY-MM-DD'
d=$(nt task t12); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" open
patch "$d/task.md" "created: $(fdate "$d/task.md")" 'created: 2026-02-31'
err "$d" '31 февраля' 'не в формате YYYY-MM-DD'
d=$(nt task t13); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" open
patch "$d/task.md" "created: $(fdate "$d/task.md")" 'created: 2099-01-01'
err "$d" 'updated раньше created' 'раньше created'
d=$(nt task t14); fill_desc "$d"; fill_ready "$d"
setf "$d/task.md" done 'closed: 2099-01-01\nresolution: done'
err "$d" 'updated раньше closed' 'раньше closed'

# --- закрытие и типы ---------------------------------------------------------
d=$(nt bug t15); fill_desc "$d"; fill_steps "$d"
setf "$d/task.md" done 'closed: 2026-10-07\nresolution: done'
err "$d" 'bug + resolution done' 'не соответствует type=bug'
d=$(nt task t16); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" open 'resolution: fixed'
err "$d" 'resolution у незакрытой' 'только при done/cancelled'
d=$(nt tech-research t17); fill_desc "$d"; fill_quest "$d"; fill_result "$d"
setf "$d/task.md" done 'closed: 2026-10-07\nresolution: done'
err "$d" 'research done без spec' 'требуется spec'
d=$(nt product-research t18); fill_desc "$d"; fill_quest "$d"; setf "$d/task.md" open
ok "$d" 'research open: «Результат» только заголовком'
patch "$d/task.md" 'status: open' 'status: review'
err "$d" 'research review: «Результат» пуст' 'итог проработки'

# --- секции тела -------------------------------------------------------------
d=$(nt bug t19); fill_desc "$d"
patch "$d/task.md" "$STEPS_OLD" '1. Открыть поиск.'
setf "$d/task.md" open
err "$d" 'bug без меток' 'нет метки'
d=$(nt task t20); fill_desc "$d"; setf "$d/task.md" open
patch "$d/task.md" "$READY_OLD" '<!--\n  критерии:\n  сначала одно,\n  потом другое\n-->\n\n- [ ]'
err "$d" 'многострочный HTML-комментарий' 'пуст'
d=$(nt task t21); fill_desc "$d"; setf "$d/task.md" open
patch "$d/task.md" "$READY_OLD" '    ```swift\n    let x = 1\n    ```'
err "$d" 'только fenced-контент' 'пуст'
d=$(nt task t22); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" open
printf '```swift\nlet x = 1\n' >> "$d/task.md"
err "$d" 'незакрытый fence' 'незакрытый fenced-блок'

# --- блокировки и ссылки (после каждого негативного кейса — clear_block) ------
base=$(nt task t23); fill_desc "$base"; fill_ready "$base"; setf "$base/task.md" open
bn=$((10#${base%%-*}))
d=$(nt task t24); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" blocked 'blocked-by: [99]'
err "$d" 'висячий blocked-by' 'несуществующую задачу'
clear_block "$d/task.md"
d=$(nt task t25); fill_desc "$d"; fill_ready "$d"
n=$((10#${d%%-*})); setf "$d/task.md" blocked "blocked-by: [0$n]"
err "$d" 'самоссылка с ведущим нулём' 'саму себя'
clear_block "$d/task.md"
d=$(nt task t26); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" blocked 'blocked-by: [v3]'
err "$d" 'не-id в blocked-by' 'только id-числа'
clear_block "$d/task.md"
d=$(nt task t27); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" blocked
err "$d" 'внешний блокер без комментария' 'внешний блокер'
mkdir -p "$d/comments"
printf -- '---\nauthor: a\ndate: 2026-10-07\nkind: comment\n---\nЖдём лицензиара.\n' > "$d/comments/001-blocked-license.md"
ok "$d" 'внешний блокер с NNN-blocked-комментарием'
d=$(nt task t28); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" blocked "blocked-by:\n  - $bn"
ok "$d" 'блочный YAML в blocked-by'

# --- комментарии -------------------------------------------------------------
d=$(nt task t29); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" open
mkdir -p "$d/comments"
printf -- '---\nauthor: a\ndate: 2026-10-07\n---\nБез kind.\n' > "$d/comments/001-a.md"
err "$d" 'комментарий без kind' 'без kind'
rm "$d/comments/001-a.md"
printf -- '---\nauthor: a\ndate: 2026-10-07\nkind: comment\n---\nОдин.\n' > "$d/comments/001-a.md"
printf -- '---\nauthor: a\ndate: 2026-10-07\nkind: comment\n---\nТри.\n' > "$d/comments/003-c.md"
err "$d" 'пропуск в нумерации' 'нумерация'
rm "$d/comments/003-c.md"
printf -- '---\nauthor: a\ndate: 2026-10-07\nkind: comment\n---\nНоль.\n' > "$d/comments/000-zero.md"
err "$d" 'комментарий 000' 'посторонний файл в comments'
rm "$d/comments/000-zero.md" "$d/comments/001-a.md"
rmdir "$d/comments"

# --- содержимое папки задачи -------------------------------------------------
d=$(nt task t30); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" open
touch "$d/scratch.txt"
err "$d" 'посторонний файл в папке' 'посторонний файл в папке задачи'
rm "$d/scratch.txt"

# --- глобальные проверки (полный режим) --------------------------------------
rm -rf [0-9][0-9][0-9][0-9]-*/
ok_full 'пустой трекер — exit 0'
v1=$(nt task g01); fill_desc "$v1"; fill_ready "$v1"; setf "$v1/task.md" open
v2=$(nt bug g02); fill_desc "$v2"; fill_steps "$v2"; setf "$v2/task.md" open
ok_full 'полный прогон на валидном наборе'
mkdir -p 12-badnum
err_full 'папка вне нумерации' 'вне нумерации'
rmdir 12-badnum
v1n=$((10#${v1%%-*})); cp -R "$v1" "$(printf '%04d' $v1n)-dup"
err_full 'дубликат номера' 'более чем одной папкой'
rm -rf "$(printf '%04d' $v1n)-dup"
x=$(nt task g03); fill_desc "$x"; fill_ready "$x"
y=$(nt task g04); fill_desc "$y"; fill_ready "$y"
xn=$((10#${x%%-*})); yn=$((10#${y%%-*}))
setf "$x/task.md" open "blocked-by: [$yn]"
setf "$y/task.md" open "blocked-by: [$xn]"
err_full 'взаимная блокировка' 'циклическая блокировка'
python3 - "$x/task.md" <<'PYEOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
open(p, 'w').write(re.sub(r'(?m)^blocked-by:.*\n?', '', s))
PYEOF
ok_full 'цикл разорван'
mkdir -p junk-stray
ok "$x" 'точечный режим не падает от чужого мусора'
rmdir junk-stray

# --- чекбоксы критериев и CRLF ----------------------------------------------
d=$(nt task t31); fill_desc "$d"
patch "$d/task.md" "$READY_OLD" '- [x] Сделано.'
setf "$d/task.md" done "closed: $(fdate "$d/task.md")\nresolution: done"
ok "$d" 'done с зачёркнутыми критериями'
patch "$d/task.md" '- [x] Сделано.' '- [x] Сделано.\n\n- [ ] Забытый пункт.'
err "$d" 'done с незачёркнутым пунктом' 'незачёркнут'
python3 - "$d/task.md" <<'PYEOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'(?m)^(closed|resolution):.*\n?', '', s)
open(p, 'w').write(s.replace('status: done', 'status: open'))
PYEOF
ok "$d" 'незачёркнутый пункт легален до done'
d=$(nt task t32); fill_desc "$d"; fill_ready "$d"; setf "$d/task.md" open
python3 - "$d/task.md" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, newline='').read().replace('\n', '\r\n')
open(p, 'w', newline='').write(s)
PYEOF
ok "$d" 'CRLF-файл валиден'
d=$(nt task t33); fill_desc "$d"
patch "$d/task.md" "$READY_OLD" '- [x] Сделано.\n\n<!--\n- [ ] закомментированный черновик пункта\n-->'
setf "$d/task.md" done "closed: $(fdate "$d/task.md")\nresolution: done"
ok "$d" 'закомментированный чекбокс при done — не считается'

# --- гонка параллельного создания: номера уникальны ---------------------------
for i in 1 2 3 4 5 6; do "${RUN[@]}" "$NEW" task race-$i "R" >/dev/null 2>&1 & done
wait
race_dirs=$(ls -d [0-9][0-9][0-9][0-9]-race-* 2>/dev/null | wc -l | tr -d ' ')
race_nums=$(ls -d [0-9][0-9][0-9][0-9]-race-* 2>/dev/null | sed 's/-race.*//' | sort -u | wc -l | tr -d ' ')
if [ "$race_dirs" = 6 ] && [ "$race_nums" = "$race_dirs" ]; then
  pass_n=$((pass_n + 1))
else
  fail_n=$((fail_n + 1))
  printf 'FAIL(race) параллельное создание: папок %s, уникальных номеров %s\n' "$race_dirs" "$race_nums"
fi

# --- гонка МЕЖДУ worktrees одного репо: общий git-каталог сериализует ----------
# Инцидент 0055: у каждого linked worktree свой каталог Tasks и свой ключ
# /tmp-лока — два агента считали next-id по локальному листингу и оба
# аллоцировали один номер. Механизм (0066): лок в общем git-каталоге репозитория
# (git rev-parse --git-common-dir) + перечитывание листингов всех worktrees
# (git worktree list) внутри лока. Сценарии гоняются в песочнице-git-репо,
# реальный трекер не трогается.
if command -v git >/dev/null 2>&1; then
  # Песочница обязана быть изолирована от git-окружения вызывающего процесса:
  # pre-commit хук экспортирует GIT_DIR (иногда GIT_WORK_TREE) — с ними
  # `git -C <sandbox>` уходит в ЧУЖОЙ репозиторий. Снимаем переопределения.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
  WTS="$SBOX-wtrepo"
  git init -q "$WTS/repo"
  git -C "$WTS/repo" config user.email test@example.com
  git -C "$WTS/repo" config user.name test
  mkdir -p "$WTS/repo/Tasks/0001-seed"
  printf 'seed\n' > "$WTS/repo/Tasks/0001-seed/task.md"
  git -C "$WTS/repo" add Tasks >/dev/null 2>&1
  git -C "$WTS/repo" commit -qm seed >/dev/null 2>&1
  git -C "$WTS/repo" worktree add "$WTS/wa" -b wt-a >/dev/null 2>&1
  git -C "$WTS/repo" worktree add "$WTS/wb" -b wt-b >/dev/null 2>&1
  wtenv() { local d="$1"; shift; env TASKS_DIR="$d/Tasks" TASKS_TEMPLATE="$template_src" "$NEW" "$@"; }
  wt_nums() { ls -d "$WTS/wa/Tasks"/[0-9][0-9][0-9][0-9]-*/ "$WTS/wb/Tasks"/[0-9][0-9][0-9][0-9]-*/ 2>/dev/null | sed 's|.*/\([0-9][0-9][0-9][0-9]\)-.*|\1|' | sort -u; }
  # два параллельных аллокатора из РАЗНЫХ worktrees — номера обязаны разойтись
  wtenv "$WTS/wa" task wt-a A >/dev/null 2>&1 &
  wtenv "$WTS/wb" task wt-b B >/dev/null 2>&1 &
  wait
  wt_u=$(wt_nums | grep -c .)
  wt_d=$(ls -d "$WTS/wa/Tasks"/[0-9][0-9][0-9][0-9]-*/ "$WTS/wb/Tasks"/[0-9][0-9][0-9][0-9]-*/ 2>/dev/null | wc -l | tr -d ' ')
  # 4 строки ls: сид 0001 лежит в ОБЕИХ worktrees + по одной новой папке в каждой
  if [ "$wt_d" = 4 ] && [ "$wt_u" = 3 ] && wt_nums | grep -qx 0003; then
    pass_n=$((pass_n + 1))
  else
    fail_n=$((fail_n + 1))
    printf 'FAIL(wtree) меж-worktree гонка: папок %s, уникальных номеров %s [%s]\n' "$wt_d" "$wt_u" "$(wt_nums | tr '\n' ' ')"
  fi
  if [ ! -e "$WTS/repo/.git/tracker-new.lock" ]; then
    pass_n=$((pass_n + 1))
  else
    fail_n=$((fail_n + 1)); printf 'FAIL(wtree) общий лок не снят после аллокации\n'
  fi
  # устаревший локальный максимум: регистрация в sibling-worktree видна из лока
  mkdir -p "$WTS/wb/Tasks/0009-late"; printf 'x\n' > "$WTS/wb/Tasks/0009-late/task.md"
  wt_c=$(wtenv "$WTS/wa" task wt-c C | head -1 | grep -oE '[0-9]{4}-[a-z0-9-]+/task\.md' | head -1 | sed 's|/task\.md||')
  if [ "$wt_c" = 0010-wt-c ]; then
    pass_n=$((pass_n + 1))
  else
    fail_n=$((fail_n + 1)); printf 'FAIL(wtree) чужая регистрация не видна: %s (ожидался 0010-wt-c)\n' "$wt_c"
  fi
  # путь worktree с пробелами: -z парсинг сканирует литеральные пути без
  # C-квотинга — регистрация в «неудобном» worktree тоже видна
  git -C "$WTS/repo" worktree add "$WTS/w sp ace" -b wt-sp >/dev/null 2>&1
  mkdir -p "$WTS/w sp ace/Tasks/0012-sp"; printf 'x\n' > "$WTS/w sp ace/Tasks/0012-sp/task.md"
  wt_s=$(wtenv "$WTS/wa" task wt-sp S | head -1 | grep -oE '[0-9]{4}-[a-z0-9-]+/task\.md' | head -1 | sed 's|/task\.md||')
  if [ "$wt_s" = 0013-wt-sp ]; then
    pass_n=$((pass_n + 1))
  else
    fail_n=$((fail_n + 1)); printf 'FAIL(wtree) путь с пробелами не виден: %s (ожидался 0013-wt-sp)\n' "$wt_s"
  fi
  # холодный старт: свежий клон без linked worktrees сохраняет max+1
  git clone -q "$WTS/repo" "$WTS/fresh" 2>/dev/null
  mkdir -p "$WTS/fresh/Tasks/0007-gap"; printf 'x\n' > "$WTS/fresh/Tasks/0007-gap/task.md"
  wt_f=$(wtenv "$WTS/fresh" task fresh F | head -1 | grep -oE '[0-9]{4}-[a-z0-9-]+/task\.md' | head -1 | sed 's|/task\.md||')
  if [ "$wt_f" = 0008-fresh ]; then
    pass_n=$((pass_n + 1))
  else
    fail_n=$((fail_n + 1)); printf 'FAIL(wtree) свежий клон: %s (ожидался 0008-fresh)\n' "$wt_f"
  fi
  unset -f wtenv wt_nums
else
  printf 'SKIP: git недоступен — меж-worktree кейсы пропущены\n'
fi

printf '\nПройдено: %d, провалено: %d\n' "$pass_n" "$fail_n"
[ "$fail_n" -eq 0 ] || exit 1
echo 'Все регрессионные тесты зелёные.'
