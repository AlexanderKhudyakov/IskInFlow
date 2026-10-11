# Command: Start or Continue Next Task

## MCP-First Requirement
Before executing any step in this command, consult `guides/mcp_first_tooling.md`. MCP and network tools belong to the **executor subagents**: researcher, coder, and planner profiles use them per their own role contracts. The **Manager itself must not** — network and `mcp__*` tools are denied to the manager role; it works through a mechanical allowlist and delegation only.

## Purpose
Select the next task(s) from the current milestone and run the standard task pipeline on them. Default mode is **delegation**: the Manager orchestrates, executor roles run as subagents. Multi-agent top-level parallel execution remains supported.

**Stage mechanics (gates, review/QA loops with circuit breakers, risk classes, artifacts, merge) are defined once in [`guides/pipeline.md`](../guides/pipeline.md) — this command defers to it.** Role contracts: `roles/manager.md`, `roles/researcher.md`, `roles/coder.md`, `roles/tech_writer.md`, `roles/code_reviewer.md`, `roles/qa_engineer.md`, `roles/reflector.md`.

Lane parameters for this command (**full lane**): task IDs `<NNN>` from a development plan; branch `ai/<task-id>-<short-description>`; planning artifact = the plan's task file.

Key rules:
- **Maximize parallelism**: when multiple eligible unblocked tasks exist, batch-lock them and launch one agent per task **in a single message** so they run concurrently. Each agent gets its own task, lock, worktree, and feature branch.
- **Lock-first**: the lock commit must be on `main` **and pushed** before implementation begins. The pushed lock is the single source of truth for task ownership.
- **User confirmation is required before resuming** an ACTIVE task. Never auto-resume.
- **No pull requests** — branch-based with direct merges. A task is COMPLETED only after required gates, merge to `main`, and push (enforced by `guides/pipeline.md` and the `pre-push` gate).

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
  plans, `IskInFlow/**`).

### Step 1: Resume-first Check (Manager)
- Pull latest `main` and check for any `.task-locks/<task-id>.lock.json` with `status: ACTIVE`.
- If an ACTIVE lock exists:
  - Check if the lock's `agentId` matches this agent. Only resume tasks assigned to you.
  - Summarize prior progress: `workStage`, `agentId`, last checkpoint, completed objectives.
  - **Ask the user whether to resume**. Do not proceed without explicit confirmation.
- If ACTIVE locks exist for a **different** agent: report them but do NOT resume. Those belong to another agent or require stale lock reclamation (see `guides/git_and_workflow_operations.md` Part 8).
- If multiple ACTIVE locks exist for this agent, stop and ask the user how to proceed.

### Step 1b: Check for Review/QA Work (Multi-Agent)
- Before selecting a new task to implement, check if any tasks are `AWAITING_REVIEW` or `AWAITING_QA` that this agent should pick up.
- Discovery:
  ```bash
  git fetch --all
  # Check feature branches for tasks awaiting review/QA
  git show origin/ai/<task-id>-...:.task-locks/<task-id>.lock.json
  ```
- If tasks are awaiting review/QA and this agent is the designated reviewer: perform the review/QA first, then proceed to new implementation.

### Step 2: Select Next Task(s) (Manager)
- If no ACTIVE lock exists (or user declined to resume), identify **all** eligible unblocked tasks from the current milestone. Selection criteria: `guides/git_and_workflow_operations.md` Part 9; full Manager authority: `roles/manager.md`.
- **Parallel-first**: batch-lock all eligible tasks in a single commit (Part 5: Batch Lock Acquisition), then spawn one Task-tool agent per task **in a single message**.
- **Locks are mechanical — no hand-authored lock JSON.** Predicted staffing is recorded at creation:
  ```bash
  IskInFlow/scripts/flow new <task-id> --agent <agentId> \
    --surface CODE|DOCS|MIXED|NONE [--implementers role,role] \
    [--name <name>] [--branch <branch>] [--plan <path>] [--milestone <id>]
  ```
  `flow new` writes the lock and fills `roles.predicted`; `changeSurface`
  stays null until gate classification runs
  `IskInFlow/scripts/flow classify <lock> --surface <S> --class STANDARD|CRITICAL [--docs-scope tracker-only] [--repo <path>] --agent <agentId>`
  (surface derived from `git diff --name-only main...<branch>`; mismatch
  rules: `roles/manager.md`). Surface → staffing matrix:
  `guides/pipeline.md`.
- **Lock-first push**: the Manager commits the lock scoped to
  `.task-locks/**` + `Tasks/**` and pushes `main` before implementation
  begins (Part 5: Batch Lock Acquisition).
- **Tracker registry**: for each selected task, ensure a registry entry exists in the host task tracker (`Tasks/NNNN-<slug>/task.md`, format: [`guides/task_tracker.md`](../guides/task_tracker.md)): create it if missing (`Tasks/new.sh <type> <slug> "Title"`), fill `spec:` with the development-plan path. The plan file remains the planning artifact of the full lane; the registry entry is the task's user-facing record. **The Manager never hand-edits `Tasks/**`** — entry creation runs through `Tasks/new.sh`; `branch:`/`lock:`/`spec:` fills and status flips go through a tech_writer round or host scripts (`Tasks/*.sh`); the Manager triggers them and verifies the result.

### Steps 3–9: Run the pipeline (all roles)
Run [`guides/pipeline.md`](../guides/pipeline.md) with **lane = full**: lock acquisition and TDD implementation on a worktree feature branch (Coder), gate classification (Manager), read-only cross-context review, QA on the approved commit, mandatory reflection, final merge and push with lock archival. Observe the circuit breakers (2 review rounds / 2 QA rounds → escalate to the user) and the coordination-commit batching discipline defined there.

**Briefs are prompts.** Every delegation brief — task scope, premises,
researcher citations, checklists — is passed **in the subagent prompt**;
brief files are retired. In delegation mode review, QA, and reflection are
**fresh subagents** (cross-context per `guides/pipeline.md`); multi-agent
top-level mode remains the alternative. Tracker registry updates along the
way — `branch:`/`lock:` filled and `status: in-progress` at lock
acquisition, `status: review` at final merge, `status: done` after the user
accepts the result — are applied by a tech_writer round or host scripts,
triggered and verified by the Manager.

## Output
- Task selection summary
- Lock file committed to `main` **and pushed** when the task starts (with `agentId`)
- Feature branch `ai/...` created after the lock is on remote
- Pipeline artifacts per `guides/pipeline.md` (review / QA report for code tasks; reflection always)
- New/updated skills in the host skills directory (if any)
- Tracker registry entry in `Tasks/` (`spec:` → development plan; status: `in-progress` at lock, `review` at merge, `done` at user acceptance)
- Final merge includes lock archival; `main` pushed; cleanup only after push confirmed

## Multi-Agent Notes
Alternative to delegation mode: multiple top-level agents, each switching hats
between stages (`IskInFlow/scripts/flow role set <role>`). The marker and its
audit trail are per clone, not per agent — one shared file
(`<git-common-dir>/isk-role`) and one shared `IskInFlow/scripts/flow role log`
— so per-agent role discipline in this mode is procedural (L0); parallel work
that needs per-role enforcement runs as delegation-mode subagents.

### Agent Pipeline (2 agents)
```
agent-alpha: implement A → implement C → review D → ...
agent-beta:  implement B → implement D → review C → ...
             ↕ cross-review each other's work ↕
```

### Agent Pipeline (3 agents, recommended)
```
agent-alpha:  implement only
agent-beta:   implement only
agent-gamma:  review all → QA all → merge all
```

### Handling Push Contention
If `git push origin main` is rejected because another agent pushed first:
1. `git fetch origin main`
2. `git rebase origin/main`
3. `git push origin main`
4. Retry up to 3 times with random jitter. See `guides/git_and_workflow_operations.md` Part 7.

## Notes
- If no eligible task is found, report blockers and recommend next action.
- **Never** mark a task completed based on "implementation finished" — the pipeline's gates decide.
- **Reflection is mandatory for ALL tasks, on every surface.**
- In multi-agent mode, check for review/QA work before starting a new implementation task.
