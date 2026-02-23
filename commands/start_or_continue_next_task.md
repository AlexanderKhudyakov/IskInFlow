# Command: Start or Continue Next Task

## MCP-First Requirement
Before executing any step in this command, consult `guides/mcp_first_tooling.md`. Enumerate available MCP servers and tools, and prefer them for discovery, validation, and execution tasks.

## Purpose
This command selects the next task using a strict, lock-based workflow. Supports both single-agent and multi-agent parallel execution.

Key rules:
- **Maximize parallelism**: when multiple eligible unblocked tasks exist, launch as many agents as possible in parallel using the Task tool with multiple concurrent tool calls. Do not work tasks sequentially when they can be parallelized. Each agent gets its own task, lock, worktree, and feature branch.
- **No pull requests** are used in this workflow. Everything is branch-based with direct merges.
- **Lock-first**: the lock commit must be on `main` **and pushed to remote** before any implementation begins.
- **User confirmation is required before resuming**: if an unfinished (ACTIVE) task is found, the agent **must ask the user** before continuing. Never auto-resume.
- The lock file on `main` (pushed to remote) is the **single source of truth** for whether a task is taken.
- **Post-merge push**: after merging, `main` must be pushed to remote before any cleanup.
- **Branch cleanup**: the feature branch may only be deleted after `main` is pushed.
- **Agent identity**: every agent must identify itself with its assigned `agentId` in all lock operations.
- **Cross-agent review**: in multi-agent mode, the reviewer and QA agent must differ from the implementer.

This command is intentionally strict:
- Tasks that change code or tests MUST go through code review and QA.
- Tasks with no code/test changes (docs/spec/process-only) MAY skip code review and QA after manager verification and lock-history evidence.
- A task is only considered **COMPLETED** after required quality gates are satisfied, the branch is **merged to `main`**, and `main` is **pushed to remote**.

## Steps

### Step 0: Resume-first Check (Manager)
- Pull latest `main` and check for any `.task-locks/<task-id>.lock.json` with `status: ACTIVE`.
- If an ACTIVE lock exists:
  - Check if the lock's `agentId` matches this agent. Only resume tasks assigned to you.
  - Summarize prior progress: `workStage`, `agentId`, last checkpoint, completed objectives.
  - **Ask the user whether to resume**. Do not proceed without explicit confirmation.
- If ACTIVE locks exist for a **different** agent: report them but do NOT resume. Those belong to another agent or require stale lock reclamation (see `roles/manager.md`).
- If multiple ACTIVE locks exist for this agent, stop and ask the user how to proceed.

### Step 0b: Check for Review/QA Work (Multi-Agent)
- Before selecting a new task to implement, check if any tasks are `AWAITING_REVIEW` or `AWAITING_QA` that this agent should pick up.
- Discovery:
  ```bash
  git fetch --all
  # Check feature branches for tasks awaiting review/QA
  git show origin/codex/<task-id>-...:task-locks/<task-id>.lock.json
  ```
- If tasks are awaiting review/QA and this agent is the designated reviewer: perform the review/QA first, then proceed to new implementation.

### Step 1: Select Next Task(s) (Manager)
- If no ACTIVE lock exists (or user declined to resume), identify **all** eligible unblocked tasks from the current milestone.
- See `roles/manager.md` for task selection criteria.
- **Parallel-first**: if multiple tasks are eligible, batch-lock them all and launch a separate agent (via the Task tool) for each task **in a single message** so they run concurrently. Do not serialize tasks that have no dependency on each other.
- **Multi-agent batch assignment:** The Manager should batch-assign in a single commit (see `guides/git_and_workflow_operations.md` Part 5: Batch Lock Acquisition), then spawn one Task-tool agent per task.

### Step 2: Lock Task on `main` (Coder)
This step prevents multiple agents from working on the same task.

**For complete step-by-step procedures, see [`guides/git_and_workflow_operations.md#part-5-command-reference`](../guides/git_and_workflow_operations.md#part-5-command-reference).**

Summary:
1. Create `.task-locks/<task-id>.lock.json` with `status: ACTIVE`, `workStage: IMPLEMENTATION_STARTED`, `agentId: "<your-agent-name>"`.
2. Commit the lock file on `main`.
3. **Push `main` to remote** — this is mandatory before proceeding. If push is rejected (another agent pushed first), use the retry loop from `guides/git_and_workflow_operations.md` Part 7.
4. Only after push succeeds: create the feature branch `codex/<task-id>-<short-description>` from `main` and set up a worktree.

### Step 3: Implement with TDD (Coder)
- Implement the task using TDD on the feature branch (in its own worktree).
- Update the lock file on the **feature branch** with progress checkpoints (NOT on main — intermediate updates stay on the feature branch).
- When implementation is complete, transition to `workStage: IMPLEMENTATION_COMPLETE`.
- See `roles/coder.md` for detailed implementation guidelines.

### Step 4: Determine Required Quality Gates (Manager)
- Inspect branch diff and classify task scope:
  - **Code/test changed**: requires code review + QA.
  - **No code/test changed**: allows skip of code review + QA.
- Record decision and evidence in lock history.
- Suggested evidence: `git diff --name-only main...<branch>` output showing only docs/spec/process files.

### Step 5: Code Review (Conditional)
- If task changes code/tests:
  - **Multi-agent**: Set `workStage: AWAITING_REVIEW`, push feature branch. A different agent performs the review. Implementing agent is free to start the next task.
  - **Single-agent**: Same agent performs review (legacy behavior).
  - Produce review artifact: `.task-locks/artifacts/<task-number>/review.md`.
  - Only when review status is **APPROVED** can the task proceed.
  - Transition lock to `workStage: CODE_REVIEW_APPROVED`.
  - See `roles/code_reviewer.md`.
- If task has no code/test changes:
  - Skip code review and set `workStage: CODE_REVIEW_SKIPPED`.
  - Record skip reason + diff evidence in lock history.

### Step 6: QA Verification (Conditional)
- If task changes code/tests:
  - **Multi-agent**: Set `workStage: AWAITING_QA`. A different agent performs QA. QA agent must differ from implementer.
  - **Single-agent**: Same agent performs QA (legacy behavior).
  - QA runs only on the branch/commit that incorporates review feedback.
  - QA produces: `.task-locks/artifacts/<task-number>/qa-report.md`.
  - Transition lock to `workStage: QA_PASSED` only on PASS.
  - See `roles/qa_engineer.md`.
- If task has no code/test changes:
  - Skip QA and set `workStage: QA_SKIPPED`.
  - Record skip reason + diff evidence in lock history.

### Step 7: Final Merge and Push (Manager + Coder)
**For complete step-by-step procedures, see [`guides/git_and_workflow_operations.md#part-5-command-reference`](../guides/git_and_workflow_operations.md#part-5-command-reference).**

Summary:
1. On the feature branch, prepare final lock update:
   - Set `status: COMPLETED`, `workStage: MERGED`.
   - Move lock to `.task-locks/completed/<task-id>.lock.json`.
   - Commit this final update.
2. Checkout `main`, pull latest, fast-forward merge the feature branch.
3. **Push `main` to remote** — mandatory before any cleanup. If push is rejected, use the merge retry loop from `guides/git_and_workflow_operations.md` Part 7.
4. Only after push succeeds: delete the worktree and local feature branch.

## Output
- Task selection summary
- Lock file committed to `main` **and pushed to remote** when task starts (with `agentId`)
- Feature branch `codex/...` created after lock is on remote
- Code review artifact (required only when code/tests changed): `.task-locks/artifacts/<task-id>/review.md`
- QA report (required only when code/tests changed): `.task-locks/artifacts/<task-id>/qa-report.md`
- For no-code/test tasks: lock history entry documenting approved review/QA skip with diff evidence
- Final merge includes lock archival; `main` pushed to remote
- Branch cleanup only after remote push confirmed

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
- **Never** mark a task completed based on "implementation finished". Completion requires: required quality gates + merge + push.
- **Always ask the user** before resuming unfinished work. Never auto-resume.
- In multi-agent mode, check for review/QA work before starting a new implementation task.
