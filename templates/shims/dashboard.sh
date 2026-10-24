#!/bin/sh
#
# Tracker entry-point shim. Canonical source: IskInFlow/templates/shims/dashboard.sh,
# deployed into the host by `flow shims sync` — do not hand-edit; re-run sync
# after pulling the framework. The canonical progress-dashboard server lives at
# IskInFlow/scripts/tracker-dashboard.py; this tracked executable keeps the
# stable Tasks/ entry point: it serves the local read-only web dashboard over
# this tracker (global progress, kanban by status, per-task pipeline timelines
# from .task-locks/).
#
# Resolution (first executable wins):
#   1. <git-toplevel>/IskInFlow/scripts/tracker-dashboard.py   (the nested clone)
#   2. <git-toplevel>/Tools/hooks/lib/tracker-dashboard.py     (optional tracked
#      vendored mirror — hosts that keep one get coverage in every clone)
#
# No silent degrade: an interactive tool must fail loud (exit 1).

set -u
# Hooks run with GIT_DIR (and sometimes GIT_WORK_TREE) exported; with GIT_DIR
# set, `git rev-parse --show-toplevel` reports the CWD, not the repo root.
# This shim must discover the enclosing checkout, so drop the overrides and
# let git walk up from the script location.
unset GIT_DIR GIT_WORK_TREE
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
script=tracker-dashboard.py
real=""
root=""
if command -v git >/dev/null 2>&1; then
    root=$(git -C "$here" rev-parse --show-toplevel 2>/dev/null) || root=""
    if [ -z "$root" ]; then
        root=$(git rev-parse --show-toplevel 2>/dev/null) || root=""
    fi
fi
for c in \
    "${root:+$root/IskInFlow/scripts/$script}" \
    "${root:+$root/Tools/hooks/lib/$script}"; do
    [ -n "$c" ] && [ -f "$c" ] && { real="$c"; break; }
done
if [ -z "$real" ]; then
    echo "dashboard.sh shim: canonical tracker-dashboard.py not found" >&2
    echo "            (IskInFlow/scripts/$script and Tools/hooks/lib/$script both absent)" >&2
    echo "            -- run from the main checkout (with the nested IskInFlow" >&2
    echo "            clone) or restore the tracked Tools/hooks/lib mirror" >&2
    exit 1
fi
exec env TASKS_DIR="$here" python3 "$real" "$@"
