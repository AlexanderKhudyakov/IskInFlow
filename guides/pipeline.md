# The IskInFlow Pipeline (canonical definition)

This is the **single source of truth** for the task pipeline: stages, gates,
loops, and artifacts. The commands (`start_or_continue_next_task.md`,
`quick_task.md`) are thin entry points that select tasks and then run THIS
pipeline with their lane's parameters. Role files describe how each role
executes its stages. The `flow` CLI (`scripts/flow`) encodes the mechanical
rules — prefer it over hand-editing lock files.

## Parameters (per lane)

| Parameter | `full` lane (`start_or_continue_next_task`) | `quick` lane (`quick_task`) |
| --- | --- | --- |
| Task IDs | `<NNN>` from a development plan | `qt-<short-name>` |
| Planning artifact | task file in the development plan | tracker task `Tasks/NNNN-<slug>/task.md` ([`task_tracker.md`](task_tracker.md)) |
| Brief cap | n/a (full task file) | ~80 lines; over cap → switch to `full` lane |
| Branch | `ai/<task-id>-<short-description>` | `ai/qt-<short-name>` |
| Stages | identical | identical |

## Change surfaces and staffing (set by the Manager)

A **surface** is a property of the task's diff: which classes of files it
touches (the host declares the path-class map per `HOST_CONTRACT.md`). The
enum is closed:

```
CODE | DOCS | MIXED | NONE
```

**Derivation rule** (mechanical, over the host's path classes): a diff sets a
CODE flag when it touches any CODE-class path and a DOCS flag when it touches
any DOCS-class path; the four enum values are the four flag combinations.
**Surface-neutral** — sets neither flag: SKILLS-class paths
(`.agents/skills/**`), the coordination class `.task-locks/**` (every task
diff touches it), and hook-owned memory `.memsearch/**` (auto-committed by
session hooks onto whatever branch is checked out — never authored by a task).
So a skills-only change is `NONE` and a code+skills change is `CODE`.

**Staffing matrix** — who implements and which gates run, derived from the
surface:

| Surface | Implementation | Review | QA |
| --- | --- | --- | --- |
| `CODE` | coder | code review, `reviewKind: code` | full QA (`qa: full`), depth by risk class |
| `DOCS` | tech_writer | cross-context docs review, `reviewKind: docs` | skipped (`qa: skipped`, evidence recorded) |
| `DOCS` — tracker-only subcase (`docsScope: tracker-only`) | tech_writer | skipped with evidence (`CODE_REVIEW_SKIPPED`) — the carve-out for diffs under `Tasks/**` only | skipped |
| `MIXED` | coder first, **then** tech_writer documenting the final behavior | single review carrying both checklists, `reviewKind: mixed` | QA on the code portion (`qa: code-only`) |
| `NONE` | the role owning the touched path class (e.g. reflector for skills) | skipped with evidence (`CODE_REVIEW_SKIPPED`) | skipped |

Mixed-task ordering is mandatory: **docs are written after code is final**,
describing implemented reality rather than intent. `implementedBy` names the
primary implementer (the coder for `MIXED`); additional implementer rounds
are recorded via history entries with their `agentId`.

**Predicted vs verified.** Staffing is decided twice, symmetric to how risk
classes are recorded: **predicted** from the task's declared scope, filled
into `roles.predicted` at lock creation (`flow new --surface`); **verified**
at gate classification from `git diff --name-only main...<branch>` (`flow
classify` sets `changeSurface` and `roles.actual`, with diff evidence in lock
history). A predicted `MIXED` that verifies as `CODE` or `DOCS` is a benign
narrowing — recorded in history, no waiver needed. Any other mismatch is
treated exactly like a disproven premise: back into work or escalate to the
user — never a silent re-staff.

## Risk classes (set by the Manager at gate classification)

Two values, governing **depth only** — review depth and QA phase depth within
the surface-derived staffing. Gate **participation** (does this gate run at
all?) derives from the diff surface (staffing matrix above), never from the
risk class.

| Class | Definition | Review depth | QA depth |
| --- | --- | --- | --- |
| `STANDARD` | default for code/test changes | full | Phases 1–3 + risk-based slice of Phase 4 |
| `CRITICAL` | concurrency, persistence/migrations, security, data loss, cross-component contracts | full | all QA phases incl. exploratory |

The class is recorded in the lock history with diff evidence. When in doubt,
classify up (STANDARD → CRITICAL), never down.

## Stages and gates

```
IMPLEMENTATION_STARTED ──► IMPLEMENTATION_COMPLETE
        │ (gate: the implementer's exit checklist — code: TDD suite green,
        │  linter clean, self-review done; docs: referential verification)
        ▼
review gate ─────────────► CODE_REVIEW_APPROVED   (or CHANGES_REQUESTED fix loop)
        │ (gate: reviewer is a DIFFERENT context; review is read-only)
        ▼
QA gate ─────────────────► QA_PASSED              (or QA_FAILED fix loop)
        │ (gate: QA owns the authoritative test run on the final commit)
        ▼
REFLECTION_COMPLETE ─────► MERGED
        (gate: reflection artifact exists; merge; push main; archive lock)
```

Mechanical rules live in `scripts/flow`:

```bash
IskInFlow/scripts/flow validate  .task-locks            # schema check (run before pushing locks)
IskInFlow/scripts/flow transition <lock> <STAGE> --agent <id> --reason "…"
IskInFlow/scripts/flow metrics                           # lead time / rework statistics
```

The review artifact carries `reviewKind: code | docs | mixed`, set by the
diff surface (staffing matrix above). Gate skips reuse the `*_SKIPPED`
stages with evidence recorded in lock history; one unconditional transition
edge exists for docs-surface review — `CODE_REVIEW_APPROVED → QA_SKIPPED`.
`NONE` and tracker-only `DOCS` keep the existing
`CODE_REVIEW_SKIPPED → QA_SKIPPED` path.

`flow transition` refuses illegal gate transitions (use plain history entries
for checkpoints — progress notes, corrections, round bookkeeping — without
moving `workStage`). A `pre-push` hook (`scripts/pre-push.flow`) blocks pushes
of `ai/*` branches whose lock is missing, has an unknown stage, or lacks
required artifacts.

## Roles per stage

- **Lock + plan**: Manager acquires the lock and records predicted staffing
  (`flow new --surface`; lock-first, pushed to `main` before any
  implementation — see `git_and_workflow_operations.md` Part 5).
- **Implementation**: per the staffing matrix — coder (TDD; `roles/coder.md`),
  then tech_writer for `DOCS`/`MIXED` surfaces documenting the final behavior
  (`roles/tech_writer.md`).
- **Review**: Code Reviewer for the code surface, docs review for the docs
  surface — **never the implementation context** (`roles/code_reviewer.md`).
- **QA**: QA Engineer — **never the implementation context**; runs after
  review approval, gated by the surface (`roles/qa_engineer.md`).
- **Reflection**: any agent, mandatory for every task, on every surface
  (`roles/reflector.md`).
- **Merge + push**: Manager (or Coder on Manager's instruction) — only after
  all required gates.

## Review loop (with circuit breaker)

```
IMPLEMENTATION_COMPLETE → review → APPROVED → QA gate (or QA_SKIPPED for docs-surface review)
                        → CHANGES_REQUESTED → the surface-owning role fixes all feedback → re-review
```

- **Round limit**: after **2** `CODE_REVIEW_CHANGES_REQUESTED` rounds on the
  same task, the Manager must escalate to the user with a summary of the
  disputed points instead of starting a third round. Escalation is recorded in
  lock history. (Disputes about taste are resolved in favor of the reviewer;
  disputes about facts are settled with evidence — measured, not argued.)
- Every review artifact records its round number. Reviewers judge tests by
  reading; runtime questions are handed to QA explicitly.

## QA loop (with circuit breaker)

```
CODE_REVIEW_APPROVED → QA → PASS → reflection
                     → FAIL → coder fixes → Manager triages:
                           minor (typos, copy, test data) → re-QA only
                           significant (new logic/structure) → back to review
```

- **Round limit**: after **2** `QA_FAILED` rounds, the Manager escalates to the
  user with the failure summary rather than looping again.
- QA depth follows the task's risk class (table above).

## Follow-up policy (no deferred problems)

Findings from review, QA, or reflection that require **any repository change**
(code, tests, docs, config, workflow scripts) are *work*, not notes: the
Manager routes them by surface — docs findings return to the tech_writer,
code findings to the coder (a mixed task may need both rounds) — and the task
loops again (fix → re-review / re-QA as triage dictates) before `MERGED`.
Recording an actionable finding as a "follow-up" for a future task is not
permitted.

- Follow-ups are tracked as `- [ ]` checkboxes in the task's artifacts
  (`.task-locks/artifacts/<task-id>/*.md`); the owning role's fix commit
  flips them to `- [x]` **in the same task**.
- `flow transition … MERGED` refuses while the artifacts still contain
  unchecked `- [ ]` items. `--force` overrides; a forced merge MUST record the
  user's waiver in the lock history (`reason: "user waived: …"`).
- The only deferrals allowed without a waiver are items genuinely outside the
  repository's control (third-party bugs, product decisions requiring user
  input, environment provisioning) — and they must be phrased as such, with
  the user waiver recorded.
- Scope boundary does not exempt a finding: if a reviewer marks something
  "out of scope" but actionable, the Manager either extends the task's scope
  (with the user's approval) or the finding is fixed in a follow-up task
  **started before the current task merges** — it may not silently become
  backlog.

## Cross-agent review without a second session

"Reviewer must differ from implementer" means a **different context**, not
necessarily a different top-level session. Default in every mode: the Manager
spawns a fresh subagent (Task tool / equivalent mechanism) with the reviewer
role brief — it sees the diff and task file, not the implementation
conversation. A separate top-level agent remains the multi-agent mode.
Self-review by the implementing context is a **last-resort fallback** (no
subagent mechanism available), must be labeled `reviewedBy: self-fallback` in
the lock, and is a process smell worth recording for the retrospective.

## Coordination commit discipline (commit-noise control)

Coordination data (locks, artifacts) rides on `main`. To keep history
readable:

- On `main` itself only two commits per task are allowed (lock acquisition and
  final merge + archival — see "Final merge mechanics"); all intermediate
  transitions and artifacts are committed on the feature branch.
- Batch feature-branch coordination commits per stage burst, not per file
  (e.g. a lock transition commits together with its artifact).
- Batch lock acquisition across tasks is mandatory in multi-agent mode
  (Part 5) and preferred in single-agent mode.
- Never push `main` more than once per stage transition burst.
- Known direction for a future major version: move coordination data out of
  `main` commits into dedicated refs (`refs/locks/*`) so `main` carries code
  only. Until then, batching is the discipline.

## Artifacts

| Stage | Artifact | Path |
| --- | --- | --- |
| Any stage | researcher report (cited evidence; plain bullets, no checkbox items) | `.task-locks/artifacts/<task-id>/research-*.md` |
| Plan (quick lane) | tracker task | `Tasks/NNNN-<slug>/task.md` ([`task_tracker.md`](task_tracker.md)) |
| Merge | tracker task status → `review` (registry; both lanes) | `Tasks/NNNN-<slug>/task.md` |
| Review | review report (round-numbered) | `.task-locks/artifacts/<task-id>/review.md` |
| QA | QA report (with round + risk class) | `.task-locks/artifacts/<task-id>/qa-report.md` |
| Reflection | reflection summary | `.task-locks/artifacts/<task-id>/reflection.md` |
| Merge | lock archived with `status: COMPLETED`, `workStage: MERGED` | `.task-locks/completed/<task-id>.lock.json` |

## Final merge mechanics

The final merge uses **`git merge --no-ff`** — always a merge commit, preserving
a clear record of when the branch landed (full sequences in
`git_and_workflow_operations.md` Parts 3 and 5, including the rebase-and-retry
loop for push contention). Consistent with the batching discipline above, only
**two commits per task touch `main`**: lock acquisition (Push 1) and final
merge + archival (Push 2); every intermediate transition and artifact commit
lives on the feature branch and reaches `main` through the merge.

Completion rule (unchanged): a task is COMPLETED only after required gates,
merge to `main`, and push to remote. The `pre-push` gate and `flow validate`
are the mechanical enforcers; this document is the definition.
