#!/usr/bin/env bash
# Создание новой задачи трекера: scripts/tracker-new.sh <type> <slug> ["Заголовок"]
# Каноническое расположение — этот репозиторий (задача 0055); хосты вызывают
# через shim Tasks/new.sh (или напрямую, задав TASKS_DIR).
# Пример: scripts/tracker-new.sh bug crash-on-word-search "Крэш при поиске по словам"
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Хуки экспортируют GIT_DIR: с ним rev-parse --show-toplevel вернёт cwd.
# Снимаем переопределения — резолвим каталог обычным discovery.
unset GIT_DIR GIT_WORK_TREE

# Каталог трекера: TASKS_DIR → <git-toplevel>/Tasks/ → легаси-раскладка
tasks_dir="${TASKS_DIR:-}"
if [ -z "$tasks_dir" ] && command -v git >/dev/null 2>&1; then
  root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  [ -n "$root" ] && [ -d "$root/Tasks" ] && tasks_dir="$root/Tasks"
fi
if [ -z "$tasks_dir" ] && compgen -G "${0%/*}/[0-9][0-9][0-9][0-9]-*" >/dev/null; then
  tasks_dir="$script_dir" # легаси: скрипт внутри Tasks/
fi
if [ -z "$tasks_dir" ] || [ ! -d "$tasks_dir" ]; then
  echo "Ошибка: не найден каталог трекера Tasks/ (задайте TASKS_DIR или запускайте из клона хост-репозитория)." >&2
  exit 1
fi

# Шаблон: TASKS_TEMPLATE → канонический templates/tracker-task-template.md
# (этот же репозиторий, рядом со скриптом) → копия из вендоренного зеркала
# (раскладка Tools/hooks/lib: шаблон лежит рядом со скриптом) → легаси-копия
# _template/task.md
template="${TASKS_TEMPLATE:-}"
if [ -z "$template" ]; then
  if [ -r "$script_dir/../templates/tracker-task-template.md" ]; then
    template="$script_dir/../templates/tracker-task-template.md"
  elif [ -r "$script_dir/tracker-task-template.md" ]; then
    template="$script_dir/tracker-task-template.md"
  elif [ -r "$tasks_dir/_template/task.md" ]; then
    template="$tasks_dir/_template/task.md"
  fi
fi
if [ -z "$template" ] || [ ! -r "$template" ]; then
  echo "Ошибка: не найден шаблон задачи (TASKS_TEMPLATE, templates/tracker-task-template.md от скрипта или \$TASKS_DIR/_template/task.md)." >&2
  exit 1
fi

cd "$tasks_dir"

# Критическая секция: два параллельных агента с РАЗНЫМИ слэгами вычислят
# одинаковый next-id и молча создадут дубли 0001-a/0001-b (atomic mkdir не
# помогает — имена разные). Инцидент 0055: ключ лока в /tmp по пути Tasks
# текущего checkout'а оставлял гонку МЕЖДУ linked worktrees одного репо —
# у каждого свой ключ и свой устаревший листинг. Ключ теперь — общий
# git-каталог репозитория (git rev-parse --git-common-dir): он один на все
# worktrees клона, лок в нём сериализует аллокацию repo-глобально. Вне git —
# легаси-ключ по пути Tasks (песочницы тестов, невендоренные раскладки).
# Ожидание ограничено: устаревший после сбоя лок убирается вручную.
common_dir=""
if command -v git >/dev/null 2>&1; then
  if c=$(git rev-parse --git-common-dir 2>/dev/null) && [ -n "$c" ]; then
    c=$(CDPATH= cd -- "$c" 2>/dev/null && pwd) || c=""
    common_dir=$c
  fi
fi
if [ -n "$common_dir" ]; then
  lock="$common_dir/tracker-new.lock"
else
  lock="/tmp/kvga-tasks-new.$(pwd | cksum | tr -d ' ').lock"
fi
tries=0
until mkdir "$lock" 2>/dev/null; do
  tries=$((tries + 1))
  if [ "$tries" -gt 100 ]; then
    echo "Ошибка: блокировка создания недоступна: $lock (возможно, устарела после сбоя — проверьте и удалите вручную)." >&2
    exit 1
  fi
  sleep 0.1
done
trap 'rmdir "$lock" 2>/dev/null' EXIT

TYPES="bug feature improvement task product-research tech-research"
USAGE="Использование: scripts/tracker-new.sh <type> <slug> [\"Заголовок\"]
Типы: ${TYPES// /, }
Пример: scripts/tracker-new.sh bug crash-on-word-search \"Крэш при поиске по словам\""

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "$USAGE" >&2
  exit 1
fi

type="$1"
slug="$2"
title="${3:-$2}"

if ! echo "$TYPES" | tr ' ' '\n' | grep -qx "$type"; then
  echo "Ошибка: неизвестный тип '$type'." >&2
  echo "$USAGE" >&2
  exit 1
fi
if ! echo "$slug" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; then
  echo "Ошибка: slug '$slug' — строчная латиница/цифры, дефисы только внутри (без хвостовых и двойных)." >&2
  exit 1
fi

# next-id = максимум по Tasks-каталогам ВСЕХ worktrees репозитория + 1
# (гэки номеров допустимы, переиспользование — нет). Листинг одного
# checkout'а устаревает, как только sibling-worktree создаёт задачу
# (инцидент 0055): перечитываем git worktree list ВНУТРИ лока. Вне git —
# только локальный каталог (холодный старт сохраняет max+1).
max_seen=0
scan_tasks() { # <каталог Tasks> — поднимает max_seen до максимума номеров
  [ -d "$1" ] || return 0
  local d b n
  for d in "$1"/[0-9][0-9][0-9][0-9]-*/; do
    [ -d "$d" ] || continue
    b=${d%/}; b=${b##*/}
    n=$((10#${b:0:4}))
    if [ "$n" -gt "$max_seen" ]; then max_seen=$n; fi
  done
  return 0
}
scan_tasks "$tasks_dir"
if [ -n "$common_dir" ]; then
  # git worktree list --porcelain -z: NUL-разделение — пути без C-квотинга
  # (пробелы/кавычки/unicode сканируются как есть); старые git без -z —
  # построчный fallback (литеральные пути, ограничение то же, что до 0066).
  if git worktree list --porcelain -z >/dev/null 2>&1; then
    while IFS= read -r -d '' rec; do
      wt=${rec#worktree }
      wt=${wt%%$'\n'*}
      if [ -n "$wt" ]; then scan_tasks "$wt/Tasks"; fi
    done < <(git worktree list --porcelain -z 2>/dev/null)
  else
    while IFS= read -r wt; do
      if [ -n "$wt" ]; then scan_tasks "$wt/Tasks"; fi
    done < <(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
  fi
fi
next=$((max_seen + 1))
if [ "$next" -gt 9999 ]; then
  echo "Ошибка: исчерпан диапазон номеров трекера (максимум 9999)." >&2
  exit 1
fi
id=$(printf '%04d' "$next")
dir="${id}-${slug}"

if [ -e "$dir" ]; then
  echo "Ошибка: папка уже существует: $dir" >&2
  exit 1
fi

# Заголовок в YAML — одинарные кавычки: двойные " внутри не требуют экранирования,
# одинарные ' удваиваются (' -> '')
yaml_title=${title//"'"/"''"}
date_today=$(date +%F)

# Атомарное создание: mkdir без -p падает при существующей папке — единственный
# guard от гонки двух параллельных агентов, вычисливших одинаковый next-id
# (redirect в цикле ниже иначе молча перезаписал бы чужой task.md)
if ! mkdir "$dir" 2>/dev/null; then
  echo "Ошибка: папка уже существует или создана параллельно: $dir — перечитайте реестр во всех worktrees (git worktree list) и повторите." >&2
  exit 1
fi
while IFS= read -r line; do
  line=${line//'{{ID}}'/$next}
  line=${line//'{{DATE}}'/$date_today}
  line=${line//'{{TYPE}}'/$type}
  line=${line//'{{TITLE}}'/$yaml_title}
  printf '%s\n' "$line"
done < "$template" > "$dir/task.md"

echo "Создано: $tasks_dir/$dir/task.md (type=$type, status=draft)"
echo "Дальше: заполнить тело, затем перевести status в open."
