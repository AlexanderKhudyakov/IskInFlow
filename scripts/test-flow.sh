#!/usr/bin/env bash
#
# test-flow.sh — behavior tests for scripts/flow (IskInFlow v2, spec §8).
#
# Coverage contract (spec iskinflow_delegation_tech_spec.md §8):
#   1. transitions   — new CODE_REVIEW_APPROVED -> QA_SKIPPED edge, surface
#                      refusals (CODE_REVIEW_SKIPPED / QA_SKIPPED), --force
#                      waivers with "forced": true, legacy locks unchanged
#   2. implementedBy — creation leaves it null; implementer transition fills it
#   3. new --surface — predicted staffing defaults per surface + override
#   4. classify      — derivation from git diff, assertion refusals, MIXED
#                      narrowing, forced widening, neutrality, tracker-only
#   5. patterns      — glob/path-class unit cases
#   6. validate      — synthetic v2 locks per surface, dual-enforced failures,
#                      --force waiver downgrade, shape errors, legacy unchanged
#   7. archive       — move + scoped archival commit, refusal off-MERGED
#   8. role          — marker write/show, log append, invalid role, non-repo
#
# Python 3 stdlib + git only. Portable bash 3.2 (no associative arrays, no
# ${var,,}); every scenario runs against throwaway mktemp fixtures.

set -u

FLOW="$(cd "$(dirname "$0")" && pwd)/flow"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/flow-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
OUT=""
ERR=""
STATUS=0
ERRFILE="$TMP/last-stderr.txt"

section() { printf '\n=== %s ===\n' "$1"; }
ok()      { PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
fail()    { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }

assert_eq() { # assert_eq <desc> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected <$2>, got <$3>)"; fi
}

assert_contains() { # assert_contains <desc> <haystack> <needle>
  case "$2" in
    *"$3"*) ok "$1" ;;
    *) fail "$1 (missing: $3)" ;;
  esac
}

assert_not_contains() { # assert_not_contains <desc> <haystack> <needle>
  case "$2" in
    *"$3"*) fail "$1 (unexpected: $3)" ;;
    *) ok "$1" ;;
  esac
}

assert_ok() { assert_eq "$1" "0" "$STATUS"; }

assert_refused() { # non-zero exit expected
  if [ "$STATUS" -ne 0 ]; then ok "$1 (exit $STATUS)"; else fail "$1 (expected refusal, exit 0)"; fi
}

run_flow() { # run_flow <args...> — sets OUT/ERR/STATUS
  OUT="$("$FLOW" "$@" 2>"$ERRFILE")"
  STATUS=$?
  ERR="$(cat "$ERRFILE")"
}

run_flow_in() { # run_flow_in <dir> <args...> — run with cwd=<dir>
  local dir="$1"
  shift
  OUT="$(cd "$dir" && "$FLOW" "$@" 2>"$ERRFILE")"
  STATUS=$?
  ERR="$(cat "$ERRFILE")"
}

assert_json() { # assert_json <desc> <lock-file> <expr-on-lock> <expected-json>
  local got
  got="$(python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    lock = json.load(fh)
try:
    val = eval(sys.argv[2], {"lock": lock})
except Exception as exc:
    val = "EVALERR: %s" % exc
print(json.dumps(val))
' "$2" "$3")"
  assert_eq "$1" "$4" "$got"
}

mod_lock() { # mod_lock <lock-file> <python-statements mutating `lock`>
  python3 -c '
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    lock = json.load(fh)
exec(sys.argv[2])
with open(path, "w", encoding="utf-8") as fh:
    json.dump(lock, fh, indent=2)
    fh.write("\n")
' "$1" "$2"
}

make_repo() { # make_repo -> prints a scratch repo path (branch main, 1 commit)
  local dir
  dir="$(mktemp -d "$TMP/repo.XXXXXX")"
  git -C "$dir" init -q
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  git -C "$dir" config commit.gpgsign false
  printf 'seed\n' >"$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -qm seed
  printf '%s\n' "$dir"
}

git_branch() { # git_branch <repo> <branch> — new branch off main
  git -C "$1" checkout -q -b "$2" main
}

feature_commit() { # feature_commit <repo> <file> <content>
  local repo="$1" file="$2"
  mkdir -p "$repo/$(dirname "$file")"
  printf '%s\n' "$3" >"$repo/$file"
  git -C "$repo" add "$file"
  git -C "$repo" commit -qm "wip: $file"
}

# Synthetic lock writer for validate cases.
MKLOCK="$TMP/mklock.py"
cat >"$MKLOCK" <<'PY'
import json, os, sys
lock = {
    "schemaVersion": 2,
    "taskId": "0000",
    "status": "COMPLETED",
    "workStage": "MERGED",
    "lockedAt": "2026-10-09T10:00:00+00:00",
    "history": [
        {"timestamp": "2026-10-09T10:00:00+00:00", "fromStage": None,
         "toStage": "IMPLEMENTATION_STARTED", "agentId": "t", "reason": "lock acquired"},
        {"timestamp": "2026-10-09T12:00:00+00:00", "fromStage": "REFLECTION_COMPLETE",
         "toStage": "MERGED", "agentId": "t", "reason": "merged"},
    ],
}
patch = json.loads(sys.argv[2])
lock.update(patch)
out = sys.argv[1]
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8") as fh:
    json.dump(lock, fh, indent=2)
    fh.write("\n")
PY

synth_lock() { # synth_lock <out-file> <patch-json>
  python3 "$MKLOCK" "$1" "$2"
}

# ---------------------------------------------------------------------------
section "1. Transitions — new edge, surface refusals, --force waivers, legacy"
# ---------------------------------------------------------------------------

# New edge CODE_REVIEW_APPROVED -> QA_SKIPPED succeeds on a DOCS lock.
R="$TMP/tr-docs"; LK="$R/.task-locks/d1.lock.json"
run_flow --root "$R" new d1 --agent mgr --surface DOCS
run_flow transition "$LK" IMPLEMENTATION_COMPLETE --agent tw
run_flow transition "$LK" CODE_REVIEW_REQUESTED --agent tw
run_flow transition "$LK" CODE_REVIEW_APPROVED --agent rev
run_flow transition "$LK" QA_SKIPPED --agent rev --reason "docs surface"
assert_ok "new edge CODE_REVIEW_APPROVED -> QA_SKIPPED succeeds (DOCS)"

# CODE_REVIEW_SKIPPED refused on a CODE lock.
R="$TMP/tr-code"; LK="$R/.task-locks/c1.lock.json"
run_flow --root "$R" new c1 --agent mgr --surface CODE
run_flow transition "$LK" IMPLEMENTATION_COMPLETE --agent dev
run_flow transition "$LK" CODE_REVIEW_SKIPPED --agent dev
assert_refused "CODE_REVIEW_SKIPPED refused on a CODE lock"
assert_contains "  refusal names the surface" "$ERR" "CODE"

# CODE_REVIEW_SKIPPED refused on a DOCS+standard lock.
R="$TMP/tr-docs-std"; LK="$R/.task-locks/d2.lock.json"
run_flow --root "$R" new d2 --agent mgr --surface DOCS
run_flow transition "$LK" IMPLEMENTATION_COMPLETE --agent tw
run_flow transition "$LK" CODE_REVIEW_SKIPPED --agent tw
assert_refused "CODE_REVIEW_SKIPPED refused on a DOCS+standard lock"
assert_contains "  refusal names docsScope standard" "$ERR" "standard"

# CODE_REVIEW_SKIPPED allowed on DOCS+tracker-only.
R="$TMP/tr-docs-tonly"; LK="$R/.task-locks/d3.lock.json"
run_flow --root "$R" new d3 --agent mgr --surface DOCS
mod_lock "$LK" 'lock["roles"]["predicted"]["docsScope"] = "tracker-only"'
run_flow transition "$LK" IMPLEMENTATION_COMPLETE --agent tw
run_flow transition "$LK" CODE_REVIEW_SKIPPED --agent tw --reason "tracker-only"
assert_ok "CODE_REVIEW_SKIPPED allowed on DOCS+tracker-only"
run_flow transition "$LK" QA_SKIPPED --agent tw
assert_ok "  and QA_SKIPPED via CODE_REVIEW_SKIPPED -> QA_SKIPPED"

# CODE_REVIEW_SKIPPED allowed on NONE (existing skip path).
R="$TMP/tr-none"; LK="$R/.task-locks/n1.lock.json"
run_flow --root "$R" new n1 --agent mgr --surface NONE
run_flow transition "$LK" IMPLEMENTATION_COMPLETE --agent ref
run_flow transition "$LK" CODE_REVIEW_SKIPPED --agent ref --reason "skills-only"
assert_ok "CODE_REVIEW_SKIPPED allowed on NONE"
run_flow transition "$LK" QA_SKIPPED --agent ref
assert_ok "  and QA_SKIPPED on NONE"

# QA_SKIPPED refused on CODE and MIXED.
R="$TMP/tr-code-qa"; LK="$R/.task-locks/c2.lock.json"
run_flow --root "$R" new c2 --agent mgr --surface CODE
run_flow transition "$LK" IMPLEMENTATION_COMPLETE --agent dev
run_flow transition "$LK" CODE_REVIEW_REQUESTED --agent dev
run_flow transition "$LK" CODE_REVIEW_APPROVED --agent rev
run_flow transition "$LK" QA_SKIPPED --agent rev
assert_refused "QA_SKIPPED refused on a CODE lock"

R="$TMP/tr-mixed-qa"; LK="$R/.task-locks/m1.lock.json"
run_flow --root "$R" new m1 --agent mgr --surface MIXED
run_flow transition "$LK" IMPLEMENTATION_COMPLETE --agent dev
run_flow transition "$LK" CODE_REVIEW_REQUESTED --agent dev
run_flow transition "$LK" CODE_REVIEW_APPROVED --agent rev
run_flow transition "$LK" QA_SKIPPED --agent rev
assert_refused "QA_SKIPPED refused on a MIXED lock"

# --force passes both refusals and records "forced": true in history.
R="$TMP/tr-forced"; LK="$R/.task-locks/c3.lock.json"
run_flow --root "$R" new c3 --agent mgr --surface CODE
run_flow transition "$LK" IMPLEMENTATION_COMPLETE --agent dev
run_flow transition "$LK" CODE_REVIEW_SKIPPED --agent dev --force --reason "user waiver"
assert_ok "CODE_REVIEW_SKIPPED passes with --force on CODE"
assert_json "  history records forced: true" "$LK" 'lock["history"][-1]["forced"]' 'true'
run_flow transition "$LK" QA_SKIPPED --agent dev --force --reason "user waiver"
assert_ok "QA_SKIPPED passes with --force on CODE"
assert_json "  history records forced: true" "$LK" 'lock["history"][-1]["forced"]' 'true'

# Legacy lock (no surface fields) keeps today's semantics.
R="$TMP/tr-legacy"; LK="$R/.task-locks/lg1.lock.json"
run_flow --root "$R" new lg1 --agent mgr
run_flow transition "$LK" IMPLEMENTATION_COMPLETE --agent dev
run_flow transition "$LK" CODE_REVIEW_SKIPPED --agent dev
assert_ok "legacy lock: CODE_REVIEW_SKIPPED unchanged"
run_flow transition "$LK" QA_SKIPPED --agent dev
assert_ok "legacy lock: CODE_REVIEW_SKIPPED -> QA_SKIPPED unchanged"

# ---------------------------------------------------------------------------
section "2. implementedBy lifecycle"
# ---------------------------------------------------------------------------

R="$TMP/impl"
run_flow --root "$R" new i1 --agent mgr
assert_json "flow new (no --surface) leaves implementedBy null" \
  "$R/.task-locks/i1.lock.json" 'lock["implementedBy"]' 'null'
run_flow --root "$R" new i2 --agent mgr --surface CODE
assert_json "flow new --surface leaves implementedBy null" \
  "$R/.task-locks/i2.lock.json" 'lock["implementedBy"]' 'null'
run_flow transition "$R/.task-locks/i2.lock.json" IMPLEMENTATION_COMPLETE --agent dev-nine
assert_json "IMPLEMENTATION_COMPLETE stamps implementedBy" \
  "$R/.task-locks/i2.lock.json" 'lock["implementedBy"]' '"dev-nine"'

# ---------------------------------------------------------------------------
section "3. flow new --surface — predicted staffing defaults"
# ---------------------------------------------------------------------------

R="$TMP/newsurf"

run_flow --root "$R" new s-code --agent mgr --surface CODE
assert_json "CODE predicted staffing" "$R/.task-locks/s-code.lock.json" \
  'lock["roles"]["predicted"] == {"surface": "CODE", "implementers": ["coder"], "reviewKind": "code", "qa": "full", "docsScope": None}' 'true'
assert_json "CODE: changeSurface stays null" "$R/.task-locks/s-code.lock.json" \
  'lock["changeSurface"]' 'null'
assert_json "CODE: roles.actual stays null" "$R/.task-locks/s-code.lock.json" \
  'lock["roles"]["actual"]' 'null'

run_flow --root "$R" new s-docs --agent mgr --surface DOCS
assert_json "DOCS predicted staffing" "$R/.task-locks/s-docs.lock.json" \
  'lock["roles"]["predicted"] == {"surface": "DOCS", "implementers": ["tech_writer"], "reviewKind": "docs", "qa": "skipped", "docsScope": "standard"}' 'true'

run_flow --root "$R" new s-mixed --agent mgr --surface MIXED
assert_json "MIXED predicted staffing" "$R/.task-locks/s-mixed.lock.json" \
  'lock["roles"]["predicted"] == {"surface": "MIXED", "implementers": ["coder", "tech_writer"], "reviewKind": "mixed", "qa": "code-only", "docsScope": None}' 'true'

run_flow --root "$R" new s-none --agent mgr --surface NONE
assert_json "NONE predicted staffing" "$R/.task-locks/s-none.lock.json" \
  'lock["roles"]["predicted"] == {"surface": "NONE", "implementers": [], "reviewKind": None, "qa": "skipped", "docsScope": None}' 'true'

run_flow --root "$R" new s-ovr --agent mgr --surface CODE --implementers coder,tech_writer
assert_json "--implementers overrides the derived list" "$R/.task-locks/s-ovr.lock.json" \
  'lock["roles"]["predicted"]["implementers"]' '["coder", "tech_writer"]'

run_flow --root "$R" new s-bad --agent mgr --surface CODE --implementers wizard
assert_refused "unknown --implementers role refused"
assert_contains "  refusal names the valid roles" "$ERR" "wizard"

# Legacy shape: without --surface the new keys are absent entirely.
run_flow --root "$R" new s-legacy --agent mgr
assert_json "legacy new has no changeSurface key" "$R/.task-locks/s-legacy.lock.json" \
  '"changeSurface" in lock' 'false'
assert_json "legacy new has no roles key" "$R/.task-locks/s-legacy.lock.json" \
  '"roles" in lock' 'false'

# ---------------------------------------------------------------------------
section "4. classify — derivation, assertions, narrowing, neutrality"
# ---------------------------------------------------------------------------

CR="$(make_repo)"

# Happy path: docs diff, predicted DOCS.
git_branch "$CR" feature
feature_commit "$CR" "Docs/guide.md" "hello"
run_flow --root "$CR" new 9101 --agent mgr --branch feature --surface DOCS
LK="$CR/.task-locks/9101.lock.json"
run_flow classify "$LK" --surface DOCS --class STANDARD --agent cls
assert_ok "classify happy path (docs diff)"
assert_json "  changeSurface set" "$LK" 'lock["changeSurface"]' '"DOCS"'
assert_json "  roles.actual derived" "$LK" \
  'lock["roles"]["actual"] == {"surface": "DOCS", "implementers": ["tech_writer"], "reviewKind": "docs", "qa": "skipped", "docsScope": "standard"}' 'true'
assert_json "  history classification surface" "$LK" 'lock["history"][-1]["classification"]["surface"]' '"DOCS"'
assert_json "  history docs path count" "$LK" 'lock["history"][-1]["classification"]["docsPaths"]' '1'
assert_json "  history code path count" "$LK" 'lock["history"][-1]["classification"]["codePaths"]' '0'
assert_json "  history neutral path count" "$LK" 'lock["history"][-1]["classification"]["neutralPaths"]' '0'
assert_json "  no narrowing" "$LK" 'lock["history"][-1]["classification"]["narrowing"]' 'false'
assert_json "  no waiver" "$LK" 'lock["history"][-1]["classification"]["forced"]' 'false'
assert_json "  workStage unchanged (checkpoint entry)" "$LK" \
  'lock["history"][-1]["fromStage"] == lock["history"][-1]["toStage"]' 'true'
assert_json "  workStage value unchanged" "$LK" 'lock["workStage"]' '"IMPLEMENTATION_STARTED"'

# Re-classify appends fresh evidence (acquire + classify + re-classify).
run_flow classify "$LK" --surface DOCS --class CRITICAL --agent cls2
assert_ok "re-classify allowed"
assert_json "  fresh riskClass recorded" "$LK" 'lock["history"][-1]["classification"]["riskClass"]' '"CRITICAL"'
assert_json "  reason mentions the default diff repo" "$LK" \
  '"default" in lock["history"][-1]["reason"]' 'true'
assert_json "  history grew by one" "$LK" 'len(lock["history"])' '3'

# Assertion refusal: --surface disagrees with the diff.
run_flow --root "$CR" new 9102 --agent mgr --branch feature --surface DOCS
run_flow classify "$CR/.task-locks/9102.lock.json" --surface CODE --class STANDARD --agent cls
assert_refused "--surface flag disagreeing with the diff refuses"
assert_contains "  refusal shows the derived surface" "$ERR" "derived DOCS"
run_flow classify "$CR/.task-locks/9102.lock.json" --surface CODE --class STANDARD --agent cls --force
assert_refused "  --force does NOT escape a wrong assertion"

# Benign narrowing: predicted MIXED verifying as DOCS.
run_flow --root "$CR" new 9103 --agent mgr --branch feature --surface MIXED
LK="$CR/.task-locks/9103.lock.json"
run_flow classify "$LK" --surface DOCS --class STANDARD --agent cls
assert_ok "predicted MIXED verifying as DOCS proceeds (benign narrowing)"
assert_json "  narrowing recorded" "$LK" 'lock["history"][-1]["classification"]["narrowing"]' 'true'

# Widening refusal + --force waiver: predicted CODE verifying as DOCS.
run_flow --root "$CR" new 9104 --agent mgr --branch feature --surface CODE
LK="$CR/.task-locks/9104.lock.json"
run_flow classify "$LK" --surface DOCS --class STANDARD --agent cls
assert_refused "predicted CODE verifying as DOCS refuses"
run_flow classify "$LK" --surface DOCS --class STANDARD --agent cls --force
assert_ok "  --force proceeds with a waiver"
assert_json "  waiver recorded" "$LK" 'lock["history"][-1]["classification"]["forced"]' 'true'

# Widening refusal + --force waiver: predicted CODE verifying as MIXED.
git_branch "$CR" feature2
feature_commit "$CR" "Docs/mixed-note.md" "d"
feature_commit "$CR" "src/app.py" "print(1)"
run_flow --root "$CR" new 9105 --agent mgr --branch feature2 --surface CODE
LK="$CR/.task-locks/9105.lock.json"
run_flow classify "$LK" --surface MIXED --class STANDARD --agent cls
assert_refused "predicted CODE verifying as MIXED refuses"
run_flow classify "$LK" --surface MIXED --class STANDARD --agent cls --force
assert_ok "  --force proceeds with a waiver"
assert_json "  MIXED staffing derived" "$LK" \
  'lock["roles"]["actual"]["implementers"] == ["coder", "tech_writer"] and lock["roles"]["actual"]["qa"] == "code-only"' 'true'

# Neutrality: coordination + hook-owned + skills-only diff -> NONE.
git_branch "$CR" feat-neutral
feature_commit "$CR" ".task-locks/dummy.lock.json" "{}"
feature_commit "$CR" ".memsearch/memory/n.md" "m"
feature_commit "$CR" ".agents/skills/foo/SKILL.md" "s"
run_flow --root "$CR" new 9106 --agent mgr --branch feat-neutral --surface NONE
LK="$CR/.task-locks/9106.lock.json"
run_flow classify "$LK" --surface NONE --class STANDARD --agent cls
assert_ok "neutral-only diff classifies as NONE"
assert_json "  neutral path count" "$LK" 'lock["history"][-1]["classification"]["neutralPaths"]' '3'
assert_json "  NONE staffing: no implementers, no gates" "$LK" \
  'lock["roles"]["actual"] == {"surface": "NONE", "implementers": [], "reviewKind": None, "qa": "skipped", "docsScope": None}' 'true'

# Neutrality: neutral files + one DOCS file -> DOCS.
git_branch "$CR" feat-neutral-docs
feature_commit "$CR" ".task-locks/dummy2.lock.json" "{}"
feature_commit "$CR" ".memsearch/memory/n2.md" "m"
feature_commit "$CR" "Docs/a.md" "d"
run_flow --root "$CR" new 9107 --agent mgr --branch feat-neutral-docs --surface DOCS
LK="$CR/.task-locks/9107.lock.json"
run_flow classify "$LK" --surface DOCS --class STANDARD --agent cls
assert_ok "neutral files + one Docs/ file classifies as DOCS"
assert_json "  docs path count" "$LK" 'lock["history"][-1]["classification"]["docsPaths"]' '1'
assert_json "  neutral path count" "$LK" 'lock["history"][-1]["classification"]["neutralPaths"]' '2'

# tracker-only accepted when the whole DOCS diff is under Tasks/.
git_branch "$CR" feat-tasks
feature_commit "$CR" "Tasks/9001/task.md" "task"
run_flow --root "$CR" new 9108 --agent mgr --branch feat-tasks --surface DOCS
LK="$CR/.task-locks/9108.lock.json"
run_flow classify "$LK" --surface DOCS --class STANDARD --docs-scope tracker-only --agent cls
assert_ok "tracker-only accepted for an all-Tasks/ DOCS diff"
assert_json "  docsScope persists in roles.actual" "$LK" 'lock["roles"]["actual"]["docsScope"]' '"tracker-only"'

# tracker-only refused when a DOCS path lies outside Tasks/.
git_branch "$CR" feat-tasks-plus
feature_commit "$CR" "Tasks/9002/task.md" "task"
feature_commit "$CR" "Docs/b.md" "d"
run_flow --root "$CR" new 9109 --agent mgr --branch feat-tasks-plus --surface DOCS
run_flow classify "$CR/.task-locks/9109.lock.json" --surface DOCS --class STANDARD --docs-scope tracker-only --agent cls
assert_refused "tracker-only refused when a Docs/ file is present"

# Lock without a branch refuses.
run_flow --root "$CR" new 9110 --agent mgr --branch feature
mod_lock "$CR/.task-locks/9110.lock.json" 'lock.pop("branch")'
run_flow classify "$CR/.task-locks/9110.lock.json" --surface DOCS --class STANDARD --agent cls
assert_refused "classify without lock.branch refuses"

# Cross-repo classify: lock in a host repo, substantive branch in an impl repo.
HR="$(make_repo)"
IR="$(make_repo)"
git_branch "$IR" feature
feature_commit "$IR" "src/app.py" "print(1)"
run_flow --root "$HR" new 9111 --agent mgr --branch feature --surface CODE
LK="$HR/.task-locks/9111.lock.json"
run_flow classify "$LK" --surface CODE --class STANDARD --agent cls
assert_refused "host-repo derivation alone refuses (branch lives in the impl repo)"
run_flow classify "$LK" --surface CODE --class STANDARD --agent cls --repo "$IR"
assert_ok "cross-repo classify derives from the --repo impl diff"
assert_json "  surface from the impl diff" "$LK" 'lock["changeSurface"]' '"CODE"'
assert_json "  impl code path counted" "$LK" 'lock["history"][-1]["classification"]["codePaths"]' '1'
assert_json "  docs paths empty" "$LK" 'lock["history"][-1]["classification"]["docsPaths"]' '0'
assert_json "  diffRepo records the impl repo toplevel" "$LK" \
  'lock["history"][-1]["classification"]["diffRepo"] == __import__("os").path.realpath("'"$IR"'")' 'true'
assert_json "  reason names the --repo override" "$LK" \
  '"--repo override" in lock["history"][-1]["reason"]' 'true'
assert_json "  workStage unchanged" "$LK" 'lock["workStage"]' '"IMPLEMENTATION_STARTED"'

# --repo refusal: path is not a git repository.
run_flow --root "$HR" new 9112 --agent mgr --branch feature --surface CODE
NR2="$TMP/nonrepo-classify"
mkdir -p "$NR2"
run_flow classify "$HR/.task-locks/9112.lock.json" --surface CODE --class STANDARD --agent cls --repo "$NR2"
assert_refused "--repo path outside a git repository refuses"
assert_contains "  refusal names the problem" "$ERR" "not inside a git repository"

# --repo refusal: branch unknown in the given repo.
run_flow --root "$HR" new 9113 --agent mgr --branch no-such-branch --surface CODE
run_flow classify "$HR/.task-locks/9113.lock.json" --surface CODE --class STANDARD --agent cls --repo "$IR"
assert_refused "unknown branch in the --repo diff repo refuses"
assert_contains "  refusal names the branch and repo" "$ERR" "not found in"

# ---------------------------------------------------------------------------
section "5. Path-class pattern semantics (unit)"
# ---------------------------------------------------------------------------

pycase() { # pycase <desc> <expr-on-module-m> <expected-json>
  local got
  got="$(PYTHONDONTWRITEBYTECODE=1 python3 -c '
import json, sys
src = open(sys.argv[1], encoding="utf-8").read()
mod = type(sys)("flowmod")
exec(compile(src, sys.argv[1], "exec"), mod.__dict__)
print(json.dumps(eval(sys.argv[2], {"m": mod})))
' "$FLOW" "$2")"
  assert_eq "$1" "$3" "$got"
}

pycase "glob: root *.md matches README.md" 'bool(m._glob_regex("*.md").match("README.md"))' 'true'
pycase "glob: root *.md does not match Docs/x.md" 'bool(m._glob_regex("*.md").match("Docs/x.md"))' 'false'
pycase "glob: ** crosses segments" 'bool(m._glob_regex("Docs/**").match("Docs/a/b.md"))' 'true'
pycase "class: IskInFlow/roles/x.md -> docs" 'm.path_class("IskInFlow/roles/x.md")' '"docs"'
pycase "class: IskInFlow/scripts/flow -> code (! exception)" 'm.path_class("IskInFlow/scripts/flow")' '"code"'
pycase "class: scripts/flow -> code (unmatched default)" 'm.path_class("scripts/flow")' '"code"'
pycase "class: .agents/skills/foo/SKILL.md -> skills" 'm.path_class(".agents/skills/foo/SKILL.md")' '"skills"'
pycase "class: .task-locks/x.lock.json -> neutral" 'm.path_class(".task-locks/x.lock.json")' '"neutral"'
pycase "class: .memsearch/memory/a.md -> neutral" 'm.path_class(".memsearch/memory/a.md")' '"neutral"'
pycase "class: README.md -> docs" 'm.path_class("README.md")' '"docs"'
pycase "class: Tasks/t.md -> docs" 'm.path_class("Tasks/t.md")' '"docs"'
pycase "class: src/app.py -> code (fail closed)" 'm.path_class("src/app.py")' '"code"'
pycase "derive: empty diff -> NONE" 'm.derive_surface([])["surface"]' '"NONE"'
pycase "derive: docs+code -> MIXED" 'm.derive_surface(["Docs/a.md", "src/a.py"])["surface"]' '"MIXED"'
pycase "derive: code+skills -> CODE" 'm.derive_surface(["src/a.py", ".agents/skills/x/SKILL.md"])["surface"]' '"CODE"'

# Host override map is honored.
OV="$TMP/override"
mkdir -p "$OV/.task-locks"
printf '{"neutral": ["vendor/**"], "skills": [], "docs": ["notes/**"]}' >"$OV/.task-locks/path-classes.json"
pycase_ov() { # pycase_ov <desc> <expr> <expected-json>
  local got
  got="$(PYTHONDONTWRITEBYTECODE=1 python3 -c '
import json, sys
src = open(sys.argv[1], encoding="utf-8").read()
mod = type(sys)("flowmod")
exec(compile(src, sys.argv[1], "exec"), mod.__dict__)
classes = mod.load_path_classes(sys.argv[2])
print(json.dumps(eval(sys.argv[3], {"m": mod, "classes": classes})))
' "$FLOW" "$OV" "$2")"
  assert_eq "$1" "$3" "$got"
}
pycase_ov "override: vendor/** neutral" 'm.path_class("vendor/lib.rs", classes)' '"neutral"'
pycase_ov "override: notes/** docs" 'm.path_class("notes/x.md", classes)' '"docs"'
pycase_ov "override: Docs/** falls to code (host map replaces built-in)" 'm.path_class("Docs/x.md", classes)' '"code"'

# ---------------------------------------------------------------------------
section "6. validate — surface-aware rules, waivers, legacy unchanged"
# ---------------------------------------------------------------------------

V="$TMP/val"
ART="$V/.task-locks/artifacts"
VLOCK="$V/.task-locks"

mkart() { # mkart <task> <review-kind-marker>
  mkdir -p "$ART/$1"
  printf '# Code Review: Task %s\n\n**Review Kind**: %s — verified\n' "$1" "$2" >"$ART/$1/review.md"
}
mkqa() { # mkqa <task>
  mkdir -p "$ART/$1"
  printf '# QA Report\n' >"$ART/$1/qa-report.md"
}
act_code='{"surface": "CODE", "implementers": ["coder"], "reviewKind": "code", "qa": "full", "docsScope": null}'

# CODE complete: review (kind code) + qa-report -> pass.
synth_lock "$VLOCK/v-code.lock.json" \
  "{\"taskId\": \"v-code\", \"changeSurface\": \"CODE\", \"roles\": {\"predicted\": null, \"actual\": $act_code}}"
mkart v-code code
mkqa v-code
run_flow validate "$VLOCK/v-code.lock.json"
assert_ok "CODE lock with review(code)+qa-report passes"
assert_not_contains "  no errors" "$OUT" "ERROR"

# CODE without review.md -> error.
synth_lock "$VLOCK/v-norvw.lock.json" \
  "{\"taskId\": \"v-norvw\", \"changeSurface\": \"CODE\", \"roles\": {\"predicted\": null, \"actual\": $act_code}}"
mkqa v-norvw
run_flow validate "$VLOCK/v-norvw.lock.json"
assert_refused "CODE lock without review.md errors"
assert_contains "  names the missing artifact" "$OUT" "review.md"

# CODE with wrong reviewKind marker -> error.
synth_lock "$VLOCK/v-wrong.lock.json" \
  "{\"taskId\": \"v-wrong\", \"changeSurface\": \"CODE\", \"roles\": {\"predicted\": null, \"actual\": $act_code}}"
mkart v-wrong docs
mkqa v-wrong
run_flow validate "$VLOCK/v-wrong.lock.json"
assert_refused "CODE lock with a docs reviewKind marker errors"
assert_contains "  names the marker problem" "$OUT" "reviewKind"

# CODE without qa-report.md -> error.
synth_lock "$VLOCK/v-noqa.lock.json" \
  "{\"taskId\": \"v-noqa\", \"changeSurface\": \"CODE\", \"roles\": {\"predicted\": null, \"actual\": $act_code}}"
mkart v-noqa code
run_flow validate "$VLOCK/v-noqa.lock.json"
assert_refused "CODE lock without qa-report.md errors"
assert_contains "  names the missing qa report" "$OUT" "qa-report.md"

# DOCS + standard: review (kind docs) required.
synth_lock "$VLOCK/v-docs.lock.json" \
  '{"taskId": "v-docs", "changeSurface": "DOCS", "roles": {"predicted": null, "actual": {"surface": "DOCS", "implementers": ["tech_writer"], "reviewKind": "docs", "qa": "skipped", "docsScope": "standard"}}}'
mkart v-docs docs
run_flow validate "$VLOCK/v-docs.lock.json"
assert_ok "DOCS standard with review(docs) passes"

synth_lock "$VLOCK/v-docs-miss.lock.json" \
  '{"taskId": "v-docs-miss", "changeSurface": "DOCS", "roles": {"predicted": null, "actual": {"surface": "DOCS", "implementers": ["tech_writer"], "reviewKind": "docs", "qa": "skipped", "docsScope": "standard"}}}'
run_flow validate "$VLOCK/v-docs-miss.lock.json"
assert_refused "DOCS standard without review.md errors"

# DOCS + tracker-only: no artifacts, but CODE_REVIEW_SKIPPED evidence required.
synth_lock "$VLOCK/v-tonly.lock.json" \
  '{"taskId": "v-tonly", "changeSurface": "DOCS", "roles": {"predicted": null, "actual": {"surface": "DOCS", "implementers": ["tech_writer"], "reviewKind": "docs", "qa": "skipped", "docsScope": "tracker-only"}}, "history": [{"timestamp": "2026-10-09T10:00:00+00:00", "fromStage": null, "toStage": "IMPLEMENTATION_STARTED", "agentId": "t", "reason": "lock acquired"}, {"timestamp": "2026-10-09T11:00:00+00:00", "fromStage": "IMPLEMENTATION_COMPLETE", "toStage": "CODE_REVIEW_SKIPPED", "agentId": "t", "reason": "tracker-only"}, {"timestamp": "2026-10-09T12:00:00+00:00", "fromStage": "QA_SKIPPED", "toStage": "MERGED", "agentId": "t", "reason": "merged"}]}'
run_flow validate "$VLOCK/v-tonly.lock.json"
assert_ok "DOCS tracker-only with CODE_REVIEW_SKIPPED evidence passes (no artifacts)"

synth_lock "$VLOCK/v-tonly-bad.lock.json" \
  '{"taskId": "v-tonly-bad", "changeSurface": "DOCS", "roles": {"predicted": null, "actual": {"surface": "DOCS", "implementers": ["tech_writer"], "reviewKind": "docs", "qa": "skipped", "docsScope": "tracker-only"}}}'
run_flow validate "$VLOCK/v-tonly-bad.lock.json"
assert_refused "DOCS tracker-only without skip evidence errors"

# MIXED: review (kind mixed) + qa-report required.
synth_lock "$VLOCK/v-mixed.lock.json" \
  '{"taskId": "v-mixed", "changeSurface": "MIXED", "roles": {"predicted": null, "actual": {"surface": "MIXED", "implementers": ["coder", "tech_writer"], "reviewKind": "mixed", "qa": "code-only", "docsScope": null}}}'
mkart v-mixed mixed
mkqa v-mixed
run_flow validate "$VLOCK/v-mixed.lock.json"
assert_ok "MIXED lock with review(mixed)+qa-report passes"

synth_lock "$VLOCK/v-mixed-noqa.lock.json" \
  '{"taskId": "v-mixed-noqa", "changeSurface": "MIXED", "roles": {"predicted": null, "actual": {"surface": "MIXED", "implementers": ["coder", "tech_writer"], "reviewKind": "mixed", "qa": "code-only", "docsScope": null}}}'
mkart v-mixed-noqa mixed
run_flow validate "$VLOCK/v-mixed-noqa.lock.json"
assert_refused "MIXED lock without qa-report.md errors"

# NONE: neither artifact required.
synth_lock "$VLOCK/v-none.lock.json" \
  '{"taskId": "v-none", "changeSurface": "NONE", "roles": {"predicted": null, "actual": {"surface": "NONE", "implementers": [], "reviewKind": null, "qa": "skipped", "docsScope": null}}}'
run_flow validate "$VLOCK/v-none.lock.json"
assert_ok "NONE lock passes with no artifacts"

# Legacy lock unchanged at MERGED with no artifacts.
synth_lock "$VLOCK/v-legacy.lock.json" '{"taskId": "v-legacy"}'
run_flow validate "$VLOCK/v-legacy.lock.json"
assert_ok "legacy lock at MERGED without artifacts still passes"
assert_not_contains "  no surface findings for legacy" "$OUT" "ERROR"

# In-flight exemption: CODE lock before the artifact stages.
synth_lock "$VLOCK/v-inflight.lock.json" \
  "{\"taskId\": \"v-inflight\", \"status\": \"ACTIVE\", \"workStage\": \"IMPLEMENTATION_STARTED\", \"changeSurface\": \"CODE\", \"roles\": {\"predicted\": null, \"actual\": $act_code}}"
run_flow validate "$VLOCK/v-inflight.lock.json"
assert_ok "in-flight CODE lock (no artifacts yet) passes"

# Dual-enforced: CODE + QA_SKIPPED in history -> error even with artifacts.
synth_lock "$VLOCK/v-dualqa.lock.json" \
  "{\"taskId\": \"v-dualqa\", \"changeSurface\": \"CODE\", \"roles\": {\"predicted\": null, \"actual\": $act_code}, \"history\": [{\"timestamp\": \"2026-10-09T10:00:00+00:00\", \"fromStage\": null, \"toStage\": \"IMPLEMENTATION_STARTED\", \"agentId\": \"t\", \"reason\": \"lock acquired\"}, {\"timestamp\": \"2026-10-09T11:00:00+00:00\", \"fromStage\": \"CODE_REVIEW_APPROVED\", \"toStage\": \"QA_SKIPPED\", \"agentId\": \"t\", \"reason\": \"forced\"}, {\"timestamp\": \"2026-10-09T12:00:00+00:00\", \"fromStage\": \"QA_SKIPPED\", \"toStage\": \"MERGED\", \"agentId\": \"t\", \"reason\": \"merged\"}]}"
mkart v-dualqa code
mkqa v-dualqa
run_flow validate "$VLOCK/v-dualqa.lock.json"
assert_refused "CODE + QA_SKIPPED history errors (dual-enforced)"
assert_contains "  names the dual refusal" "$OUT" "QA_SKIPPED"
run_flow validate "$VLOCK/v-dualqa.lock.json" --force
assert_ok "--force downgrades the dual refusal to a warning"
assert_contains "  finding reported as WARN" "$OUT" "WARN"
assert_not_contains "  no ERROR findings remain" "$OUT" "ERROR"

# Dual-enforced: DOCS standard + CODE_REVIEW_SKIPPED + no review.md -> error.
synth_lock "$VLOCK/v-dualdocs.lock.json" \
  '{"taskId": "v-dualdocs", "changeSurface": "DOCS", "roles": {"predicted": null, "actual": {"surface": "DOCS", "implementers": ["tech_writer"], "reviewKind": "docs", "qa": "skipped", "docsScope": "standard"}}, "history": [{"timestamp": "2026-10-09T10:00:00+00:00", "fromStage": null, "toStage": "IMPLEMENTATION_STARTED", "agentId": "t", "reason": "lock acquired"}, {"timestamp": "2026-10-09T11:00:00+00:00", "fromStage": "IMPLEMENTATION_COMPLETE", "toStage": "CODE_REVIEW_SKIPPED", "agentId": "t", "reason": "forced"}, {"timestamp": "2026-10-09T12:00:00+00:00", "fromStage": "QA_SKIPPED", "toStage": "MERGED", "agentId": "t", "reason": "merged"}]}'
run_flow validate "$VLOCK/v-dualdocs.lock.json"
assert_refused "DOCS standard + CODE_REVIEW_SKIPPED + no review.md errors"
run_flow validate "$VLOCK/v-dualdocs.lock.json" --force
assert_ok "  --force downgrades it to a warning"

# Shape checks: invalid enum values are errors and survive --force.
synth_lock "$VLOCK/v-shape1.lock.json" '{"taskId": "v-shape1", "changeSurface": "WRONG"}'
run_flow validate "$VLOCK/v-shape1.lock.json"
assert_refused "changeSurface: WRONG is a shape error"
synth_lock "$VLOCK/v-shape2.lock.json" \
  '{"taskId": "v-shape2", "changeSurface": null, "roles": {"predicted": {"surface": "CODE", "implementers": ["coder"], "reviewKind": "code", "qa": "maybe", "docsScope": null}, "actual": null}}'
run_flow validate "$VLOCK/v-shape2.lock.json"
assert_refused "roles.predicted.qa: maybe is a shape error"
assert_contains "  names the bad field" "$OUT" "qa"
run_flow validate "$VLOCK/v-shape2.lock.json" --force
assert_refused "  --force does NOT downgrade shape errors"

# changeSurface set but roles.actual missing -> warning only.
synth_lock "$VLOCK/v-noactual.lock.json" '{"taskId": "v-noactual", "changeSurface": "NONE"}'
run_flow validate "$VLOCK/v-noactual.lock.json"
assert_ok "changeSurface without roles.actual is only a warning"
assert_contains "  warning names roles.actual" "$OUT" "roles.actual"

# ---------------------------------------------------------------------------
section "7. archive"
# ---------------------------------------------------------------------------

AR="$(make_repo)"
run_flow --root "$AR" new 9200 --agent mgr
git -C "$AR" add .task-locks/9200.lock.json
git -C "$AR" commit -qm "lock 9200"
LK="$AR/.task-locks/9200.lock.json"
mod_lock "$LK" 'lock["workStage"] = "IMPLEMENTATION_COMPLETE"'
run_flow archive "$LK"
assert_refused "archive refuses a non-MERGED lock"
if [ -f "$LK" ]; then ok "  lock still in place"; else fail "  lock still in place (file vanished)"; fi

mod_lock "$LK" 'lock["workStage"] = "MERGED_AND_ARCHIVED"; lock["status"] = "COMPLETED"; lock["completedAt"] = "2026-10-09T12:00:00+00:00"'
run_flow archive "$LK"
assert_ok "archive accepts MERGED via legacy alias normalization"
if [ -f "$AR/.task-locks/completed/9200.lock.json" ]; then ok "  lock moved to .task-locks/completed/"; else fail "  lock moved to .task-locks/completed/ (missing)"; fi
if [ ! -f "$LK" ]; then ok "  old path gone"; else fail "  old path gone (still present)"; fi

files="$(git -C "$AR" show --name-only --no-renames --format= HEAD | sed '/^$/d' | sort | tr '\n' ' ')"
assert_eq "archival commit touches exactly the two lock paths" \
  ".task-locks/9200.lock.json .task-locks/completed/9200.lock.json " "$files"
assert_contains "commit message follows convention" "$OUT" "chore(lock): archive 9200"
if [ -z "$(git -C "$AR" status --porcelain)" ]; then ok "  tree clean after archival commit"; else fail "  tree clean after archival commit ($(git -C "$AR" status --porcelain))"; fi

run_flow archive "$AR/.task-locks/completed/9200.lock.json"
assert_refused "re-archiving an already-archived lock refuses"

NG="$TMP/nogit"
run_flow --root "$NG" new 9201 --agent mgr
mod_lock "$NG/.task-locks/9201.lock.json" 'lock["status"] = "COMPLETED"; lock["workStage"] = "MERGED"'
run_flow archive "$NG/.task-locks/9201.lock.json"
assert_refused "archive outside a git repo errors"

# ---------------------------------------------------------------------------
section "8. role set/show/log"
# ---------------------------------------------------------------------------

RR="$(make_repo)"
run_flow_in "$RR" role show
assert_ok "role show before any set"
assert_eq "  prints unrestricted" "unrestricted" "$OUT"

run_flow_in "$RR" role set coder --agent t
assert_ok "role set coder"
run_flow_in "$RR" role show
assert_eq "  show prints coder" "coder" "$OUT"
if [ -f "$RR/.git/isk-role" ]; then ok "  marker at git-common-dir"; else fail "  marker at git-common-dir (missing)"; fi
assert_eq "  marker content" "coder" "$(cat "$RR/.git/isk-role")"

run_flow_in "$RR" role set qa_engineer --agent t
run_flow_in "$RR" role log
assert_contains "log records the switch" "$OUT" "coder -> qa_engineer by t"
if [ -f "$RR/.git/isk-role.log" ]; then ok "  log file at git-common-dir"; else fail "  log file at git-common-dir (missing)"; fi

run_flow_in "$RR" role set wizard --agent t
assert_refused "invalid role refused"
run_flow_in "$RR" role show
assert_eq "  marker unchanged after invalid set" "qa_engineer" "$OUT"

NR="$TMP/nonrepo"
mkdir -p "$NR"
run_flow_in "$NR" role show
assert_refused "role show outside a git repo errors"
assert_not_contains "  no traceback" "$ERR" "Traceback"
assert_contains "  names the problem" "$ERR" "git"

# ---------------------------------------------------------------------------
printf '\n=== summary ===\n'
printf 'test-flow: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
