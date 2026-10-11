#!/usr/bin/env bash
# Проверка формата задач трекера: scripts/tracker-validate.sh [папка-задачи ...]
# Каноническое расположение — этот репозиторий (задача 0055); хосты вызывают
# через shim Tasks/validate.sh (или напрямую, задав TASKS_DIR).
# Без аргументов проверяет все NNNN-*/task.md (плюс глобальную гигиену Tasks/).
# С аргументами проверка ТОЧЕЧНАЯ: глобальные проверки топ-уровня и дублей
# номеров не выполняются — чужая битая папка не роняет вашу задачу.
# Аргумент — имя папки (0003-foo), путь (Tasks/0003-foo) или абсолютный
# путь; несуществующая задача — ошибка.
# Каталог трекера: TASKS_DIR из окружения → <git-toplevel>/Tasks/ →
# легаси-раскладка (скрипт лежит внутри Tasks/ рядом с задачами). Данные и
# логика разделены сознательно: pre-push-гейт хоста проверяет extracted-
# дерево пуша, запуская shim из дерева, который передаёт свой каталог через
# TASKS_DIR, — валидируется именно пушимое дерево.
# Каноническое описание формата: guides/task_tracker.md
#
# Ловит: посторонние файлы/папки в Tasks/ (имя не NNNN-slug, включая dot-файлы
# кроме .DS_Store; slug без хвостовых/двойных дефисов); посторонние файлы внутри
# папки задачи (допустимы task.md, attachments/, comments/) и внутри comments/
# (только NNN-slug.md, номера 001–999); повторы YAML-ключей; строки шапки вне
# синтаксиса «ключ:» (опечатки вроде «blocked - by:»); неизвестные ключи шапки —
# запрещены (whitelist схемы гайда: опечатки вроде blocke-by не проходят
# молча); обязательные поля; закрытую YAML-шапку (в task.md и комментариях;
# CRLF допускается); id ↔ номер папки и
# глобальную уникальность номеров; title в кавычках; значения
# type/status/priority/resolution/kind из допустимых; type×resolution;
# обязательные секции тела по типу (для не-draft/cancelled) и их непустоту
# (заглушки шаблона и содержимое fenced-блоков ```/~~~ не считаются);
# «Результат» research-типов: заголовок — с open, непустота — на review/done;
# для bug — наличие меток Фактическое/Ожидаемое поведение (текст после них не
# гейтится); при done — незачёркнутые '- [ ]' в «Критериях готовности»
# запрещены; незакрытый fenced-блок — отдельная ошибка;
# done/cancelled → closed + resolution, у незакрытых closed и resolution
# запрещены; research-типы при done требуют spec:; blocked-by (при любом
# статусе, flow- и блочный YAML, инлайн-комментарии срезаются) и relates-to —
# существующие id без самоссылок
# (сравнение числовое: [02] = самоссылка при id 2); взаимоблокировки
# (циклы blocked-by) — глобально, алгоритмом Кана; при blocked без blocked-by
# — комментарий NNN-blocked-*.md; duplicate → relates-to обязателен; env только
# у bug и непустой; даты YYYY-MM-DD (реальные календарные), порядок
# created ≤ closed ≤ updated; фронтматтер комментариев и сквозную нумерацию
# без пропусков.
# ДЕТАЛЬНЫЙ перечень проверок каноничен ЗДЕСЬ; гайд и Tasks/README.md держат
# только сводку.
set -u

# Хуки экспортируют GIT_DIR: с ним rev-parse --show-toplevel вернёт cwd.
# Снимаем переопределения — резолвим каталог обычным discovery.
unset GIT_DIR GIT_WORK_TREE

# Каталог трекера: TASKS_DIR → <git-toplevel>/Tasks/ → легаси-раскладка
tasks_dir="${TASKS_DIR:-}"
if [ -z "$tasks_dir" ] && command -v git >/dev/null 2>&1; then
  root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  [ -n "$root" ] && [ -d "$root/Tasks" ] && tasks_dir="$root/Tasks"
fi
if [ -z "$tasks_dir" ] && [ -r "${0%/*}/_template/task.md" ]; then
  tasks_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) # легаси: скрипт внутри Tasks/
fi
if [ -z "$tasks_dir" ] || [ ! -d "$tasks_dir" ]; then
  echo "Ошибка: не найден каталог трекера Tasks/ (задайте TASKS_DIR или запускайте из клона хост-репозитория)." >&2
  exit 1
fi
cd "$tasks_dir"

TYPES="bug feature improvement task product-research tech-research"
STATUSES="draft open in-progress blocked review done cancelled"
PRIORITIES="P0 P1 P2 P3"
RES_DONE="fixed done"
RES_CANCELLED="wont-fix duplicate obsolete"
KINDS="comment decision"
TASK_FIELDS="id title type status created updated priority closed resolution assignee tags blocked-by relates-to branch lock spec env"
COMMENT_FIELDS="author date kind"

errors=0
tasks=0

fail() { echo "ОШИБКА [$cur]: $1" >&2; errors=$((errors + 1)); }

in_list() { # <значение> <список через пробел>
  printf '%s\n' "$2" | tr ' ' '\n' | grep -qx -- "$1"
}

is_date() { # YYYY-MM-DD: формат + реальная календарная дата (2026-02-31 — нет)
  printf '%s\n' "$1" | grep -Eq '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$' || return 1
  local norm
  norm=$(date -j -f '%Y-%m-%d' "$1" '+%Y-%m-%d' 2>/dev/null) \
    || norm=$(date -d "$1" '+%Y-%m-%d' 2>/dev/null) \
    || return 0 # date без нормализации — остаёмся на regex-проверке
  [ "$norm" = "$1" ]
}

# YAML-шапка: строки между первым и вторым '---'; без закрывающей черты — не
# шапка; CRLF допускается (\r срезается)
frontmatter_of() {
  awk '
    { sub(/\r$/, "") }
    NR==1 { if ($0 != "---") exit 1 }
    NR>1  { if ($0 == "---") { closed = 1; exit } print }
    END   { if (!closed) exit 1 }
  ' "$1"
}

# структура шапки корректна (обе черты на месте), даже если она пустая, —
# чтобы отличить «шапка пуста» от «шапки нет»
fm_is_closed() {
  awk '
    { sub(/\r$/, "") }
    NR==1 { if ($0 != "---") exit 1 }
    NR>1 && $0 == "---" { ok = 1; exit }
    END { exit (ok ? 0 : 1) }
  ' "$1"
}

# значение поля из шапки: без инлайн-комментария (« # …») и краевых пробелов
fm_get() { # <текст-шапки> <поле>
  printf '%s\n' "$1" | grep -m1 "^$2:" \
    | sed "s/^$2:[[:space:]]*//" | sed 's/[[:space:]]#.*$//' | sed 's/[[:space:]]*$//'
}

# повторяющиеся ключи шапки (YAML такое отвергает)
fm_dup_keys() { # <текст-шапки>
  printf '%s\n' "$1" | grep -oE '^[A-Za-z0-9_-]+:' | sort | uniq -d
}

# все ключи шапки (для whitelist-проверки неизвестных полей)
fm_keys() { # <текст-шапки>
  printf '%s\n' "$1" | grep -oE '^[A-Za-z0-9_-]+:' | sed 's/://'
}

# значение поля-списка: inline-значение ([1, 2]) плюс блочные продолжения
# «- N» на следующих строках (валидный блочный YAML); инлайн-комментарии
# « # …» срезаются и в значении, и в продолжениях — как в fm_get
fm_get_list() { # <текст-шапки> <поле>
  printf '%s\n' "$1" | awk -v f="$2" '
    { sub(/\r$/, "") }
    !started && index($0, f ":") == 1 {
      started = 1
      val = substr($0, length(f) + 2)
      sub(/[[:space:]]#.*$/, "", val)
      next
    }
    started && /^[[:space:]]*-[[:space:]]/ {
      line = $0
      sub(/[[:space:]]#.*$/, "", line)
      val = val " " line
      next
    }
    started && /^[[:space:]]*$/ { next }
    started { exit }
    END { printf "%s\n", val }
  '
}

validate_comment() { # <файл комментария>
  local c="$1" fm author date kind dk k bl
  cur="$1"
  fm=$(frontmatter_of "$c") || fm=""
  [ -n "$fm" ] || {
    if fm_is_closed "$c"; then
      fail "YAML-шапка комментария пуста — нет полей"
    else
      fail "комментарий без YAML-шапки"
    fi
    return
  }
  dk=$(fm_dup_keys "$fm")
  [ -z "$dk" ] || for k in $dk; do fail "поле '$k' указано в шапке дважды"; done
  bl=$(printf '%s\n' "$fm" | grep -vE '^[A-Za-z0-9_-]+:|^[[:space:]]|^#' | head -1)
  [ -z "$bl" ] || fail "строка шапки не вида «ключ: значение»: '$bl'"
  for k in $(fm_keys "$fm"); do
    in_list "$k" "$COMMENT_FIELDS" || fail "неизвестное поле '$k' в комментарии (допустимы: $COMMENT_FIELDS)"
  done
  author=$(fm_get "$fm" author)
  date=$(fm_get "$fm" date)
  kind=$(fm_get "$fm" kind)
  [ -n "$author" ] || fail "комментарий без author"
  [ -n "$date" ] || fail "комментарий без date"
  [ -z "$date" ] || is_date "$date" || fail "date '$date' не в формате YYYY-MM-DD"
  [ -n "$kind" ] || fail "комментарий без kind (comment|decision)"
  [ -z "$kind" ] || in_list "$kind" "$KINDS" || fail "kind '$kind' вне enum ($KINDS)"
}

shopt -s nullglob
all_dirs=( [0-9][0-9][0-9][0-9]-*/ )
shopt -u nullglob

# реестр существующих id — нужен и точечной проверке (проверка ссылок)
existing_ids=" $(printf '%s\n' ${all_dirs[@]+"${all_dirs[@]}"} | sed 's/-.*//' | tr '\n' ' ')"
id_exists() { # <id задачи>
  case "$1" in *[!0-9]*) return 1 ;; esac # не число — такого id быть не может
  [ "$1" -le 9999 ] || return 1           # вне диапазона нумерации формата
  case "$existing_ids" in *" $(printf '%04d' "$((10#$1))") "*) return 0 ;; *) return 1 ;; esac
}

# Гигиена всего Tasks/ (топ-уровень + дубли номеров) — только в полном режиме:
# точечная проверка с аргументами не должна падать из-за чужих битых папок.
# Посторонние записи: каждая — служебный файл или папка NNNN-slug; папка с
# «неправильным» номером иначе невидима (глоб нумерации её не найдёт);
# dot-файлы сканируем тоже, .DS_Store — задокументированное исключение (шум Finder)
global_checks() {
  local e n dups
  shopt -s dotglob nullglob
  local top_entries=( * )
  shopt -u dotglob nullglob
  for e in ${top_entries[@]+"${top_entries[@]}"}; do
    case "$e" in
      README.md | new.sh | validate.sh | tests.sh | _template | .DS_Store) continue ;;
    esac
    cur="$e"
    if [ -d "$e" ]; then
      printf '%s\n' "$e" | grep -Eq '^[0-9]{4}-[a-z0-9]+(-[a-z0-9]+)*$' \
        || fail "имя папки не NNNN-slug — она вне нумерации и проверок (переименуйте или удалите)"
    else
      fail "посторонний файл в Tasks/ (не задача NNNN-slug и не служебный файл)"
    fi
  done
  dups=$(printf '%s\n' ${all_dirs[@]+"${all_dirs[@]}"} | sed 's/-.*//' | sort | uniq -d)
  if [ -n "$dups" ]; then
    cur="(глобально)"
    for n in $dups; do
      fail "номер $n использован более чем одной папкой"
    done
  fi

  # Циклические блокировки (алгоритм Кана): убираем задачи без неразрешённых
  # blocked-by внутри оставшихся; непустой остаток — взаимоблокировка
  local -a bdeps=()
  local d id r remaining changed unresolved
  for d in ${all_dirs[@]+"${all_dirs[@]}"}; do
    d="${d%/}"
    id=$((10#${d%%-*}))
    for r in $(fm_get_list "$(frontmatter_of "${d}/task.md" 2>/dev/null)" blocked-by | grep -oE '[0-9]+'); do
      bdeps[$id]="${bdeps[$id]:-} $((10#$r))"
    done
  done
  remaining=""
  for id in ${!bdeps[@]}; do remaining="$remaining $id"; done
  remaining=" $remaining "
  changed=1
  while [ "$changed" = 1 ]; do
    changed=0
    for id in $remaining; do
      unresolved=""
      for r in ${bdeps[$id]}; do
        case "$remaining" in *" $r "*) unresolved=1 ;; esac
      done
      if [ -z "$unresolved" ]; then
        remaining="${remaining/ $id / }"
        changed=1
      fi
    done
  done
  if [ -n "$(printf '%s' "$remaining" | tr -d ' ')" ]; then
    cur="(глобально)"
    fail "циклическая блокировка (mutual blocked-by) — задачи в цикле или транзитивно заблокированы им:$(printf ' %s' $remaining)"
  fi
}

validate_task() { # <имя папки задачи>
  local dir="$1"
  cur="$dir"

  if ! printf '%s\n' "$dir" | grep -Eq '^[0-9]{4}-[a-z0-9]+(-[a-z0-9]+)*$'; then
    fail "имя папки не соответствует NNNN-slug"
    return
  fi
  if [ ! -f "$dir/task.md" ]; then
    fail "нет task.md"
    return
  fi
  tasks=$((tasks + 1))

  # посторонние записи внутри папки: только task.md, attachments/, comments/
  local inner e b
  shopt -s dotglob nullglob
  inner=( "$dir"/* )
  shopt -u dotglob nullglob
  for e in ${inner[@]+"${inner[@]}"}; do
    b=$(basename "$e")
    [ "$b" = ".DS_Store" ] && continue
    case "$b" in
      task.md) ;;
      attachments | comments)
        [ -d "$e" ] || fail "$b должен быть папкой, не файлом"
        ;;
      *)
        fail "посторонний файл в папке задачи: $b (допустимы task.md, attachments/, comments/)"
        ;;
    esac
  done

  local fm dk bl
  fm=$(frontmatter_of "$dir/task.md") || fm=""
  if [ -z "$fm" ]; then
    if fm_is_closed "$dir/task.md"; then
      fail "YAML-шапка пуста — нет ни одного поля"
    else
      fail "нет YAML-шапки (первая строка '---' … закрывающая '---')"
    fi
    return
  fi
  dk=$(fm_dup_keys "$fm")
  [ -z "$dk" ] || for k in $dk; do fail "поле '$k' указано в шапке дважды"; done
  bl=$(printf '%s\n' "$fm" | grep -vE '^[A-Za-z0-9_-]+:|^[[:space:]]|^#' | head -1)
  [ -z "$bl" ] || fail "строка шапки не вида «ключ: значение»: '$bl'"
  for k in $(fm_keys "$fm"); do
    in_list "$k" "$TASK_FIELDS" || fail "неизвестное поле '$k' (опечатка? схема — в IskInFlow/guides/task_tracker.md)"
  done

  local f
  for f in id title type status created updated; do
    printf '%s\n' "$fm" | grep -q "^$f:" || fail "нет обязательного поля '$f'"
  done

  # id: число без ведущих нулей, совпадает с номером папки
  local id num id_num=""
  id=$(fm_get "$fm" id)
  num="${dir%%-*}"
  if printf '%s\n' "$id" | grep -qx '[1-9][0-9]*'; then
    id_num=$((10#$id))
    [ "$num" = "$(printf '%04d' $id_num)" ] || fail "id '$id' не совпадает с номером папки '$num'"
  else
    fail "id '$id' — должно быть число без ведущих нулей"
  fi

  # title: непустой, в кавычках (инлайн-комментарий после значения допустим)
  printf '%s\n' "$fm" | grep -Eq "^title: ['\"].+['\"]([[:space:]]+#.*)?$" \
    || fail "title — непустая строка в кавычках (апострофы внутри удваивать)"

  local type status priority resolution closed created updated refs r
  type=$(fm_get "$fm" type)
  status=$(fm_get "$fm" status)
  priority=$(fm_get "$fm" priority)
  closed=$(fm_get "$fm" closed)
  resolution=$(fm_get "$fm" resolution)
  in_list "$type" "$TYPES" || fail "type '$type' вне enum ($TYPES)"
  in_list "$status" "$STATUSES" || fail "status '$status' вне enum ($STATUSES)"
  [ -z "$priority" ] || in_list "$priority" "$PRIORITIES" || fail "priority '$priority' вне enum ($PRIORITIES)"

  # env только у bug и непустой (вложенные ключи ищем ТОЛЬКО под env: —
  # не по всей шапке, чтобы будущие блочные поля не маскировали пустой env)
  if printf '%s\n' "$fm" | grep -q '^env:'; then
    if [ "$type" != bug ]; then
      fail "env допустим только для type=bug"
    elif [ -z "$(fm_get "$fm" env)" ]; then
      printf '%s\n' "$fm" | awk '
        /^env:/ { seen = 1; next }
        seen && /^[A-Za-z0-9_-]+:/ { exit }
        seen && /^[[:space:]]+[A-Za-z_-]+:/ { found = 1; exit }
        END { exit (found ? 0 : 1) }
      ' || fail "env пуст — укажите os/build/device или уберите поле"
    fi
  fi

  # relates-to: существующие id, без ссылок на себя (сравнение числовое:
  # [02] и id 2 — одна и та же задача; список — flow- или блочный YAML)
  refs=$(fm_get_list "$fm" relates-to)
  if [ -n "$refs" ]; then
    # список должен состоять только из id-чисел («[v3]» — не ссылка на 3)
    if printf '%s\n' "$refs" | grep -q '[0-9]' \
       && ! printf '%s\n' "$refs" | tr -d '[], -' | grep -qxE '[0-9]+'; then
      fail "relates-to: ожидаются только id-числа"
    fi
    for r in $(printf '%s\n' "$refs" | grep -oE '[0-9]+'); do
      if ! id_exists "$r"; then
        fail "relates-to ссылается на несуществующую задачу $r"
        continue
      fi
      if [ -n "$id_num" ] && [ "$((10#$r))" = "$id_num" ]; then
        fail "relates-to ссылается на саму себя"
      fi
    done
  fi

  # blocked-by: существующие id без самоссылок — при ЛЮБОМ статусе
  # (застарелое поле после разблокировки остаётся записью о причине);
  # пустой blocked-by допустим только при status=blocked с внешним блокером
  local bb has_ext="" c
  bb=$(fm_get_list "$fm" blocked-by)
  if printf '%s\n' "$bb" | grep -q '[0-9]'; then
    if ! printf '%s\n' "$bb" | tr -d '[], -' | grep -qxE '[0-9]+'; then
      fail "blocked-by: ожидаются только id-числа"
    fi
    for r in $(printf '%s\n' "$bb" | grep -oE '[0-9]+'); do
      if ! id_exists "$r"; then
        fail "blocked-by ссылается на несуществующую задачу $r"
        continue
      fi
      if [ -n "$id_num" ] && [ "$((10#$r))" = "$id_num" ]; then
        fail "blocked-by ссылается на саму себя"
      fi
    done
  elif [ "$status" = blocked ]; then
    for c in "$dir"/comments/*.md; do
      if [ -f "$c" ] && printf '%s\n' "$(basename "$c")" | grep -Eq '^(00[1-9]|0[1-9][0-9]|[1-9][0-9][0-9])-blocked-[a-z0-9]+(-[a-z0-9]+)*\.md$'; then
        has_ext=1
        break
      fi
    done
    [ -n "$has_ext" ] \
      || fail "внешний блокер оформляется комментарием comments/NNN-blocked-<slug>.md (либо заполните blocked-by id задач)"
  fi

  case "$status" in
    done)
      [ -n "$closed" ] || fail "done требует closed"
      case "$type" in
        product-research | tech-research)
          [ -n "$(fm_get "$fm" spec)" ] || fail "для $type при done требуется spec: (ссылка на созданную спеку)"
          ;;
      esac
      if [ -n "$resolution" ]; then
        local expected
        if [ "$type" = bug ]; then expected=fixed; else expected=done; fi
        in_list "$resolution" "$RES_DONE" || fail "resolution '$resolution' вне ($RES_DONE)"
        [ "$resolution" = "$expected" ] || fail "resolution '$resolution' не соответствует type=$type (ожидается '$expected')"
      else
        fail "done требует resolution (fixed|done)"
      fi
      ;;
    cancelled)
      [ -n "$closed" ] || fail "cancelled требует closed"
      if [ -n "$resolution" ]; then
        in_list "$resolution" "$RES_CANCELLED" || fail "resolution '$resolution' вне ($RES_CANCELLED)"
      else
        fail "cancelled требует resolution (wont-fix|duplicate|obsolete)"
      fi
      if [ "$resolution" = duplicate ]; then
        printf '%s\n' "$refs" | grep -q '[0-9]' || fail "resolution duplicate требует relates-to с оригиналом"
      fi
      ;;
    *)
      [ -z "$closed" ] || fail "closed допустим только при done/cancelled"
      [ -z "$resolution" ] || fail "resolution допустим только при done/cancelled"
      ;;
  esac

  created=$(fm_get "$fm" created)
  updated=$(fm_get "$fm" updated)
  # формат дат: лексические сравнения ниже рассчитывают на YYYY-MM-DD;
  # при провале формата сравнения пропускаются — без вторичных ошибок
  local dates_ok=1
  [ -z "$created" ] || is_date "$created" || { fail "created '$created' не в формате YYYY-MM-DD"; dates_ok=0; }
  [ -z "$updated" ] || is_date "$updated" || { fail "updated '$updated' не в формате YYYY-MM-DD"; dates_ok=0; }
  [ -z "$closed" ] || is_date "$closed" || { fail "closed '$closed' не в формате YYYY-MM-DD"; dates_ok=0; }
  if [ "$dates_ok" = 1 ]; then
    if [ -n "$created" ] && [ -n "$updated" ] && [ "$updated" \< "$created" ]; then
      fail "updated ($updated) раньше created ($created)"
    fi
    if [ -n "$created" ] && [ -n "$closed" ] && [ "$closed" \< "$created" ]; then
      fail "closed ($closed) раньше created ($created)"
    fi
    if [ -n "$updated" ] && [ -n "$closed" ] && [ "$updated" \< "$closed" ]; then
      fail "updated ($updated) раньше closed ($closed) — закрытие тоже бампает updated (updated > closed легально: комментарии после закрытия)"
    fi
  fi

  # обязательные секции тела: Описание всем + секции по типу; каждая непуста
  # (заглушки шаблона — «1.», «-», пустые чекбоксы, метки, HTML-комментарии —
  # содержимым не считаются). draft и cancelled освобождены.
  # Тело без fenced-блоков: заголовки и содержимое внутри ```/~~~ не
  # считаются ни секцией, ни её наполнением. Fence может быть индуцирован
  # (код внутри списка); незакрытый fence — отдельная ошибка, иначе хвост
  # файла молча выпадает из проверок и диагностика уводит от причины
  local body_clean fence_count
  body_clean=$(awk '/^[[:space:]]*```/ || /^[[:space:]]*~~~/ { fence = !fence; next } !fence' "$dir/task.md")
  fence_count=$(grep -cE '^[[:space:]]*(```|~~~)' "$dir/task.md" || true)
  if [ $((fence_count % 2)) -ne 0 ]; then
    fail 'незакрытый fenced-блок (```/~~~) — всё после него выпадает из проверок секций'
  fi
  # заголовок секции — точное совпадение (с допуском хвостовых пробелов):
  # «## Результаты» не должно матчиться как секция «Результат»
  has_sec() { printf '%s\n' "$body_clean" | grep -qE "^## $1[[:space:]]*$"; }
  sec_has_label() { # <секция> <подстрока> — метка внутри секции (не контент)
    printf '%s\n' "$body_clean" | awk -v h="^## $1[[:space:]]*$" -v lbl="$2" '
      $0 ~ h { insec = 1; next }
      insec && /^## / { insec = 0 }
      insec && index($0, lbl) > 0 { found = 1; exit }
      END { exit (found ? 0 : 1) }
    '
  }
  sec_nonempty() { # <имя секции> → 0, если есть хоть одна содержательная строка
    printf '%s\n' "$body_clean" | awk -v hdr="^## $1[[:space:]]*$" '
      $0 ~ hdr { insec = 1; next }
      insec && /^## / { insec = 0 }
      insec {
        line = $0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line == "") next
        # многострочные HTML-комментарии: строки МЕЖДУ <!-- и --> — не контент
        if (incomment) {
          if (line ~ /-->/) incomment = 0
          next
        }
        if (line ~ /<!--/) {
          if (line !~ /-->/) incomment = 1
          next
        }
        if (line ~ /^(-|\*|[0-9]+\.)$/) next
        if (line ~ /^- \[.\]$/) next
        if (line == "**Фактическое поведение:**" || line == "**Ожидаемое поведение:**") next
        n++
      }
      END { exit (n > 0 ? 0 : 1) }
    '
  }
  need_sec() {
    has_sec "$1" || { fail "обязательный раздел '## $1' отсутствует"; return; }
    sec_nonempty "$1" || fail "раздел '## $1' пуст (заполните вместо заглушек шаблона)"
  }
  # заголовок обязателен с open; непустота — только на review/done
  # (для «Результата»: итог проработки нечем заполнить на старте)
  need_sec_hdr() {
    has_sec "$1" || { fail "обязательный раздел '## $1' отсутствует"; return; }
    case "$status" in
      review | done)
        sec_nonempty "$1" || fail "раздел '## $1' пуст (итог проработки заполняется к приёмке)"
        ;;
    esac
  }
  case "$status" in
    draft | cancelled) ;;
    *)
      need_sec "Описание"
      case "$type" in
        bug)
          need_sec "Шаги воспроизведения"
          sec_has_label "Шаги воспроизведения" '**Фактическое поведение:**' \
            || fail "в '## Шаги воспроизведения' нет метки 'Фактическое поведение:' (текст после меток не гейтится)"
          sec_has_label "Шаги воспроизведения" '**Ожидаемое поведение:**' \
            || fail "в '## Шаги воспроизведения' нет метки 'Ожидаемое поведение:' (текст после меток не гейтится)"
          ;;
        feature | improvement | task)
          need_sec "Критерии готовности"
          ;;
        product-research | tech-research)
          need_sec "Открытые вопросы"
          need_sec_hdr "Результат"
          ;;
      esac
      # done с незачёркнутыми критериями — ошибка (переходы статусов не
      # гейтятся, но это закрытие с невыполненными пунктами собственного же
      # плана); многострочные HTML-комментарии пропускаем — как в sec_nonempty
      if [ "$status" = done ] && has_sec "Критерии готовности" \
         && printf '%s\n' "$body_clean" | awk -v h="^## Критерии готовности[[:space:]]*$" '
              $0 ~ h { insec = 1; next }
              insec && /^## / { insec = 0 }
              insec {
                if (incomment) { if ($0 ~ /-->/) incomment = 0; next }
                if ($0 ~ /<!--/) { if ($0 !~ /-->/) incomment = 1; next }
                if ($0 ~ /- \[ \]/) { found = 1; exit }
              }
              END { exit (found ? 0 : 1) }
            '; then
        fail "done с незачёркнутыми пунктами в '## Критерии готовности'"
      fi
      ;;
  esac

  # комментарии: в comments/ допустимы только NNN-slug.md — прочие файлы
  # отклоняются (заметки и материалы — в attachments/)
  shopt -s dotglob nullglob
  local centries=( "$dir"/comments/* )
  shopt -u dotglob nullglob
  for e in ${centries[@]+"${centries[@]}"}; do
    b=$(basename "$e")
    [ "$b" = ".DS_Store" ] && continue
    printf '%s\n' "$b" | grep -Eq '^(00[1-9]|0[1-9][0-9]|[1-9][0-9][0-9])-[a-z0-9]+(-[a-z0-9]+)*\.md$' \
      || { cur="$dir"; fail "посторонний файл в comments/: $b (комментарий — NNN-slug.md, номера 001–999; прочее — attachments/)"; }
  done
  # фронтматтер комментариев и сквозная нумерация без пропусков
  local c nums k i numbering_ok=1
  for c in "$dir"/comments/*.md; do
    [ -f "$c" ] || continue
    cur="$dir"
    validate_comment "$c"
  done
  nums=$(for c in "$dir"/comments/*.md; do [ -f "$c" ] && basename "$c" | sed 's/-.*//' | sed 's/^0*//'; done | sort -n)
  k=0
  for i in $nums; do
    k=$((k + 1))
    [ "$i" = "$k" ] || numbering_ok=0
  done
  [ "$numbering_ok" = 1 ] || { cur="$dir"; fail "нумерация комментариев с пропусками или дублями (ожидается 001, 002, … подряд)"; }
}

if [ $# -gt 0 ]; then
  for arg in "$@"; do
    d="${arg%/}"
    case "$d" in
      */*) d="${d##*/}" ;; # Tasks/0003-x или абсолютный путь → имя папки
    esac
    if [ ! -d "$d" ]; then
      cur="$arg"
      fail "задача не найдена: $arg"
      continue
    fi
    validate_task "$d"
  done
else
  global_checks
  if [ ${#all_dirs[@]} -eq 0 ]; then
    if [ "$errors" -gt 0 ]; then
      echo "Формат нарушен: $errors ошибок." >&2
      exit 1
    fi
    echo "Задач нет — проверять нечего."
    exit 0
  fi
  for d in "${all_dirs[@]}"; do validate_task "${d%/}"; done
fi

if [ "$errors" -gt 0 ]; then
  echo "Формат нарушен: $errors ошибок." >&2
  exit 1
fi
echo "OK: $tasks задач(и) соответствуют формату."
