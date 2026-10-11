# Command: Quick Task

## MCP-First Requirement
Before executing any step in this command, consult `guides/mcp_first_tooling.md`. MCP and network tools belong to the **executor subagents**: researcher, coder, tech_writer, and other executor profiles use them per their own role contracts. The **Manager itself must not** — network and `mcp__*` tools are denied to the manager role; it works through a mechanical allowlist and delegation only.

## Purpose
Take a simple user request from chat and run the entire pipeline end-to-end: plan, implement, review, QA, and merge — all in one command. Default mode is **delegation**: the Manager orchestrates, executor roles run as subagents. Multi-agent top-level parallel execution remains supported.

**Stage mechanics (gates, review/QA loops with circuit breakers, risk classes, artifacts, merge) are defined once in [`guides/pipeline.md`](../guides/pipeline.md) — this command defers to it.** Role contracts: `roles/manager.md`, `roles/coder.md`, `roles/code_reviewer.md`, `roles/qa_engineer.md`, `roles/reflector.md`.

Lane parameters for this command (**quick lane**): task IDs `qt-<short-name>` (prevents collision with numbered development-plan tasks); branch `ai/qt-<short-name>`; the planning artifact is a **tracker task** — `Tasks/NNNN-<slug>/task.md`, format: [`guides/task_tracker.md`](../guides/task_tracker.md). Locks and pipeline execution artifacts (review/QA/reflection) still live in `.task-locks/`.

Key rules:
- **Lock-first**: the lock commit must be on `main` **and pushed** before implementation begins. The pushed lock is the single source of truth for task ownership.
- **User confirmation is required before resuming** an ACTIVE quick task. Never auto-resume.
- **No pull requests** — branch-based with direct merges. A task is COMPLETED only after required gates, merge to `main`, and push (enforced by `guides/pipeline.md` and the `pre-push` gate).
- **Cross-agent review**: reviewer and QA must differ from the implementer's context (a fresh subagent qualifies — see `guides/pipeline.md`).

**When to use this command vs. others:**
- `quick_task` for small, self-contained work items that don't need a full product spec / tech spec / development plan.
- `idea_to_dev_plan` + `start_or_continue_next_task` for larger features that benefit from structured planning with milestones.

## Inputs
- User's request (from chat)
- Short name for the task (derived from request or asked for)

## Steps

### Step 0: Set the Role Marker (Manager)
- At run start: `IskInFlow/scripts/flow role set manager --agent <agentId>`.
- **Delegation mode (default)**: the top-level session stays `manager` for the
  whole run — the marker is set **once and never flipped**. Every executor
  role (researcher, coder, tech_writer, code_reviewer, qa_engineer,
  reflector) runs as a **subagent** under its own role contract.
- Role switches and denials append to `isk-role.log`; audit with
  `IskInFlow/scripts/flow role log`.
- **Hat-switch fallback**: without a delegation runtime, switch hats between
  stages with `IskInFlow/scripts/flow role set <role>`.
- Absent marker = unrestricted — non-workflow sessions are unaffected.
- **Zero self-research**: every substantive question — task premises,
  codebase state, diff triage for classification — is dispatched to a
  researcher-profile subagent producing read-only, cited reports in
  `.task-locks/artifacts/<task-id>/research-*.md`. Decisions stay with the
  Manager; its own reads are limited to orchestration state (locks, tracker,
  `IskInFlow/**`).

### Step 1: Understand and Plan (Manager)
1. Analyze the user's request to understand the problem and desired outcome.
2. **Dispatch a researcher — no self-research.** All substantive questions
   (codebase state, premise checks) go to researcher-profile subagents:
   read-only, cited evidence, reports in
   `.task-locks/artifacts/qt-<short-name>/research-*.md`. Decisions stay
   with the Manager. The analysis output feeds the tracker task description
   below.
3. Create the **tracker task** for this work: `Tasks/new.sh <type> <slug> "Title"`
   (format: [`guides/task_tracker.md`](../guides/task_tracker.md)),
   `status: draft`, and fill (the Manager drafts the content in chat; the
   write goes through a tech_writer round or host scripts — never hand-edited):
   - `## Описание` — Problem Statement (what needs to change and why), Proposed Solution (high-level approach), Scope (what's included and explicitly excluded); for quick work, Files to Modify / Risks / Testing Approach fit here as short bullet lists.
   - `## Критерии готовности` — clear, verifiable conditions for completion.
   - For `type: bug` also `## Шаги воспроизведения` with actual/expected behavior.
4. The task description is capped at ~80 lines. If it grows beyond that, recommend `idea_to_dev_plan` instead and stop.
5. **Confirm the task with the user** before proceeding, then set `status: open`. Do not continue without explicit approval.

### Step 2: Tracker task = the task file (Manager)
- The tracker task's `task.md` **is** the task file — do NOT create a
  separate `qt-<short-name>-task.md` or `-brief.md`; delegation briefs ride
  in subagent prompts, and the tracker task description + prompts carry the
  plan. Check it covers the quick-work minimum (from `roles/planner.md`
  Phase 3, sized down): overview and objectives (in `## Описание`), testing
  requirements (short list in the description), acceptance criteria
  (`## Критерии готовности`).

### Step 3: Active Task Check and Lock on `main`
Before locking, pull latest `main` and check for `.task-locks/qt-*.lock.json` with `status: ACTIVE`:
- If an ACTIVE lock exists: only resume your own task, summarize progress, and **ask the user** whether to resume or proceed with the new one. On resume, jump to the step matching the lock's `workStage`.
- ACTIVE locks of other agents: report, do not touch.
- Multiple ACTIVE locks for this agent: stop and ask the user.

**Locks are mechanical — no hand-authored lock JSON.** Full procedure in
`guides/git_and_workflow_operations.md` Part 5. Summary — predicted staffing
is recorded at creation:

```bash
IskInFlow/scripts/flow new qt-<short-name> --agent <agentId> \
  --surface CODE|DOCS|MIXED|NONE [--implementers role,role]
```

`flow new` writes `.task-locks/qt-<short-name>.lock.json` and fills
`roles.predicted`; `changeSurface` stays null until gate classification
(Steps 4–8). Tracker fills — `branch:` (`ai/qt-<short-name>`) and `lock:` —
and `status: in-progress` go through a tech_writer round or host scripts
(`Tasks/*.sh`); the Manager triggers them and verifies the result.
**Lock-first push**: commit scoped to `.task-locks/**` + `Tasks/**` on
`main`, **push `main`** (retry loop Part 7 if rejected), then create branch
`ai/qt-<short-name>` and a worktree.

### Steps 4–8: Run the pipeline (all roles)
Run [`guides/pipeline.md`](../guides/pipeline.md) with **lane = quick**: TDD
implementation on the worktree branch per the staffing matrix (Coder for
`CODE`/`MIXED`, tech_writer for `DOCS`), read-only cross-context review
(`.task-locks/artifacts/qt-<short-name>/review.md`), QA on the approved
commit (`qa-report.md`), mandatory reflection (`reflection.md`), final merge
and push with lock archival to `.task-locks/completed/`. Observe the circuit
breakers (2 review rounds / 2 QA rounds → escalate to the user) and
coordination-commit batching defined there.

**Gate classification (Manager).** A researcher subagent reads
`git diff --name-only main...<branch>` and reports surface + risk factors
with citations; the Manager decides and records mechanically:
`IskInFlow/scripts/flow classify <lock> --surface <S> --class STANDARD|CRITICAL [--docs-scope tracker-only] [--repo <path>] --agent <agentId>`
(mismatch rules: `roles/manager.md`). Surface → staffing matrix:
`guides/pipeline.md` — `DOCS` → tech_writer + docs review, QA skipped;
tracker-only `DOCS` → review skipped too; `MIXED` → coder, then tech_writer,
QA code-only; `NONE` → review and QA both skipped.

**Briefs are prompts.** In delegation mode review, QA, and reflection are
**fresh cross-context subagents** (per `guides/pipeline.md`); multi-agent
top-level mode remains the alternative. Tracker task status along the way —
`status: review` at final merge; `status: done` + `closed`/`resolution`
after the user accepts the result — is applied by a tech_writer round or
host scripts, triggered and verified by the Manager.

QA-fail triage (Manager): minor changes (typos, small adjustments) → re-QA
only; significant changes (new logic, structural) → back to review. All
iterations tracked in lock history.

## Output
- Tracker task in `Tasks/` (description, attachments, comments; `branch`/`lock` filled; status: `in-progress` at lock, `review` at merge, `done` at user acceptance)
- Lock created via `IskInFlow/scripts/flow new`, committed to `main` **and pushed** at start (with `agentId`)
- Pipeline artifacts per `guides/pipeline.md` (researcher reports, review / QA report for code tasks; reflection always)
- New/updated skills in the host skills directory (if any)
- Final merge includes lock archival; `main` pushed; cleanup only after push confirmed

## Notes
- If the user's request is too complex for a quick task (description exceeds ~80 lines), recommend `idea_to_dev_plan` instead.
- **Never** mark a task completed based on "implementation finished" — the pipeline's gates decide.
- **Reflection is mandatory for ALL tasks, on every surface.**
- Planning lives in the tracker (`Tasks/`): the task description IS the planning artifact. Execution artifacts (lock, review, QA, reflection) live in `.task-locks/` — no development-plan directory is needed.
- In multi-agent mode, check for review/QA work before starting a new quick task.
