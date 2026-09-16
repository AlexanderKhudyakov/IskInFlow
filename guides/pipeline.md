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
| Planning artifact | task file in the development plan | `.task-locks/qt-<name>-brief.md` + `-task.md` |
| Brief cap | n/a (full task file) | ~80 lines; over cap → switch to `full` lane |
| Branch | `ai/<task-id>-<short-description>` | `ai/qt-<short-name>` |
| Stages | identical | identical |

## Risk classes (set by the Manager at gate classification)

| Class | Definition | Review | QA depth |
| --- | --- | --- | --- |
| `DOCS_ONLY` | diff touches no code/test files (`git diff --name-only main...` proves it) | skip (record evidence) | skip (record evidence) |
| `STANDARD` | default for code/test changes | full | Phases 1–3 + risk-based slice of Phase 4 |
| `CRITICAL` | concurrency, persistence/migrations, security, data loss, cross-component contracts | full | all QA phases incl. exploratory |

The class is recorded in the lock history with diff evidence. When in doubt,
classify up (STANDARD → CRITICAL), never down.

## Stages and gates

```
IMPLEMENTATION_STARTED ──► IMPLEMENTATION_COMPLETE
        │ (gate: TDD suite green, linter clean, self-review checklist done)
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

`flow transition` refuses illegal gate transitions (use plain history entries
for checkpoints — progress notes, corrections, round bookkeeping — without
moving `workStage`). A `pre-push` hook (`scripts/pre-push.flow`) blocks pushes
of `ai/*` branches whose lock is missing, has an unknown stage, or lacks
required artifacts.

## Roles per stage

- **Lock + plan**: Manager classifies risk, Coder acquires the lock (lock-first,
  pushed to `main` before any implementation — see
  `git_and_workflow_operations.md` Part 5).
- **Implementation**: Coder (TDD; `roles/coder.md`).
- **Review**: Code Reviewer — **never the implementation context**
  (`roles/code_reviewer.md`).
- **QA**: QA Engineer — **never the implementation context**; runs after review
  approval (`roles/qa_engineer.md`).
- **Reflection**: any agent, mandatory for every task (`roles/reflector.md`).
- **Merge + push**: Manager (or Coder on Manager's instruction) — only after
  all required gates.

## Review loop (with circuit breaker)

```
IMPLEMENTATION_COMPLETE → review → APPROVED → proceed to QA
                        → CHANGES_REQUESTED → coder fixes all feedback → re-review
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

Coordination data (locks, briefs, artifacts) rides on `main`. To keep history
readable:

- Batch: one commit per stage burst, not per file (e.g. lock transition +
  its artifact together; final archival rides with the merge commit's branch
  preparation).
- Batch lock acquisition across tasks is mandatory in multi-agent mode
  (Part 5) and preferred in single-agent mode.
- Never push `main` more than once per stage transition burst.
- Known direction for a future major version: move coordination data out of
  `main` commits into dedicated refs (`refs/locks/*`) so `main` carries code
  only. Until then, batching is the discipline.

## Artifacts

| Stage | Artifact | Path |
| --- | --- | --- |
| Plan (quick lane) | brief + task file | `.task-locks/qt-<name>-brief.md`, `-task.md` |
| Review | review report (round-numbered) | `.task-locks/artifacts/<task-id>/review.md` |
| QA | QA report | `.task-locks/artifacts/<task-id>/qa-report.md` |
| Reflection | reflection summary | `.task-locks/artifacts/<task-id>/reflection.md` |
| Merge | lock archived with `status: COMPLETED`, `workStage: MERGED` | `.task-locks/completed/<task-id>.lock.json` |

Completion rule (unchanged): a task is COMPLETED only after required gates,
merge to `main`, and push to remote. The `pre-push` gate and `flow validate`
are the mechanical enforcers; this document is the definition.
