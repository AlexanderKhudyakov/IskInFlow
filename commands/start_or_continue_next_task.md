# Command: Start or Continue Next Task

## MCP-First Requirement
Before executing any step in this command, consult `guides/mcp_first_tooling.md`. Enumerate available MCP servers and tools, and prefer them for discovery, validation, and execution tasks.

## Purpose
Select the next task(s) from the current milestone and run the standard task pipeline on them. Supports single-agent and multi-agent parallel execution.

**Stage mechanics (gates, review/QA loops with circuit breakers, risk classes, artifacts, merge) are defined once in [`guides/pipeline.md`](../guides/pipeline.md) — this command defers to it.** Role contracts: `roles/manager.md`, `roles/coder.md`, `roles/code_reviewer.md`, `roles/qa_engineer.md`, `roles/reflector.md`.

Lane parameters for this command (**full lane**): task IDs `<NNN>` from a development plan; branch `ai/<task-id>-<short-description>`; planning artifact = the plan's task file.

Key rules:
- **Maximize parallelism**: when multiple eligible unblocked tasks exist, batch-lock them and launch one agent per task **in a single message** so they run concurrently. Each agent gets its own task, lock, worktree, and feature branch.
- **Lock-first**: the lock commit must be on `main` **and pushed** before implementation begins. The pushed lock is the single source of truth for task ownership.
- **User confirmation is required before resuming** an ACTIVE task. Never auto-resume.
- **No pull requests** — branch-based with direct merges. A task is COMPLETED only after required gates, merge to `main`, and push (enforced by `guides/pipeline.md` and the `pre-push` gate).

## Steps

### Step 0: Resume-first Check (Manager)
- Pull latest `main` and check for any `.task-locks/<task-id>.lock.json` with `status: ACTIVE`.
- If an ACTIVE lock exists:
  - Check if the lock's `agentId` matches this agent. Only resume tasks assigned to you.
  - Summarize prior progress: `workStage`, `agentId`, last checkpoint, completed objectives.
  - **Ask the user whether to resume**. Do not proceed without explicit confirmation.
- If ACTIVE locks exist for a **different** agent: report them but do NOT resume. Those belong to another agent or require stale lock reclamation (see `guides/git_and_workflow_operations.md` Part 8).
- If multiple ACTIVE locks exist for this agent, stop and ask the user how to proceed.

### Step 0b: Check for Review/QA Work (Multi-Agent)
- Before selecting a new task to implement, check if any tasks are `AWAITING_REVIEW` or `AWAITING_QA` that this agent should pick up.
- Discovery:
  ```bash
  git fetch --all
  # Check feature branches for tasks awaiting review/QA
  git show origin/ai/<task-id>-...:task-locks/<task-id>.lock.json
  ```
- If tasks are awaiting review/QA and this agent is the designated reviewer: perform the review/QA first, then proceed to new implementation.

### Step 1: Select Next Task(s) (Manager)
- If no ACTIVE lock exists (or user declined to resume), identify **all** eligible unblocked tasks from the current milestone. Selection criteria: `guides/git_and_workflow_operations.md` Part 9; full Manager authority: `roles/manager.md`.
- **Parallel-first**: batch-lock all eligible tasks in a single commit (Part 5: Batch Lock Acquisition), then spawn one Task-tool agent per task **in a single message**.

### Steps 2–8: Run the pipeline (all roles)
Run [`guides/pipeline.md`](../guides/pipeline.md) with **lane = full**: lock acquisition and TDD implementation on a worktree feature branch (Coder), gate classification (Manager), read-only cross-context review, QA on the approved commit, mandatory reflection, final merge and push with lock archival. Observe the circuit breakers (2 review rounds / 2 QA rounds → escalate to the user) and the coordination-commit batching discipline defined there.

## Output
- Task selection summary
- Lock file committed to `main` **and pushed** when the task starts (with `agentId`)
- Feature branch `ai/...` created after the lock is on remote
- Pipeline artifacts per `guides/pipeline.md` (review / QA report for code tasks; reflection always)
- New/updated skills in the host skills directory (if any)
- Final merge includes lock archival; `main` pushed; cleanup only after push confirmed

## Multi-Agent Notes

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
- **Reflection is mandatory for ALL tasks**, including `DOCS_ONLY`.
- In multi-agent mode, check for review/QA work before starting a new implementation task.
