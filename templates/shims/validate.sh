#!/bin/sh
#
# Tracker entry-point shim. Canonical source: IskInFlow/templates/shims/validate.sh,
# deployed into the host by `flow shims sync` — do not hand-edit; re-run sync
# after pulling the framework. The canonical tracker validator lives at
# IskInFlow/scripts/tracker-validate.sh; this tracked executable keeps the
# stable Tasks/ entry point — the pre-push gate relies on it being in every
# pushed tree (the nested clone is gitignored and never in a tree). The shim's
# own directory is passed as TASKS_DIR, so what gets validated is this
# directory's data (in the pre-push gate: the extracted pushed tree), never
# the caller's cwd.
#
# Resolution (first executable wins):
#   1. <git-toplevel>/IskInFlow/scripts/tracker-validate.sh   (the nested clone)
#   2. <git-toplevel>/Tools/hooks/lib/tracker-validate.sh     (optional tracked
#      vendored mirror — hosts that keep one get coverage in every clone)
#
# Degrade: if neither copy exists, WARN to stderr and exit 0 — the documented
# degrade-on-absence semantics (the pre-push tracker gate validates pushed
# trees by executing Tasks/validate.sh, so this shim must stay tracked; a
# missing validator degrades the gate to WARN, never blocks a push).
#

set -u
# Hooks run with GIT_DIR (and sometimes GIT_WORK_TREE) exported; with GIT_DIR
# set, `git rev-parse --show-toplevel` reports the CWD, not the repo root.
# This shim must discover the enclosing checkout, so drop the overrides and
# let git walk up from the script location.
unset GIT_DIR GIT_WORK_TREE
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
script=tracker-validate.sh
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
    [ -n "$c" ] && [ -x "$c" ] && { real="$c"; break; }
done
if [ -z "$real" ]; then
    echo "validate.sh shim: canonical tracker validator not found" >&2
    echo "            (IskInFlow/scripts/$script and Tools/hooks/lib/$script both absent)" >&2
    echo "            -- tracker validation skipped (run from the main checkout," >&2
    echo "            or restore the tracked Tools/hooks/lib mirror)" >&2
    exit 0
fi
exec env TASKS_DIR="$here" "$real" "$@"
