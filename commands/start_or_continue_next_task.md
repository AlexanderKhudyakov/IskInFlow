# Command: Start or Continue Next Task

## MCP-First Requirement
Before executing any step in this command, consult `guides/mcp_first_tooling.md`. Enumerate available MCP servers and tools, and prefer them for discovery, validation, and execution tasks.

## Purpose
This command selects the next task using a strict, lock-based workflow.

Key rules:
- **No pull requests** are used in this workflow. Everything is branch-based with direct merges.
- **Lock-first**: the lock commit must be on `main` **and pushed to remote** before any implementation begins.
- **User confirmation is required before resuming**: if an unfinished (ACTIVE) task is found, the agent **must ask the user** before continuing. Never auto-resume.
- The lock file on `main` (pushed to remote) is the **single source of truth** for whether a task is taken.
- **Post-merge push**: after merging, `main` must be pushed to remote before any cleanup.
- **Branch cleanup**: the feature branch may only be deleted after `main` is pushed.

This command is intentionally strict:
- Tasks that change code or tests MUST go through code review and QA.
- Tasks with no code/test changes (docs/spec/process-only) MAY skip code review and QA after manager verification and lock-history evidence.
- A task is only considered **COMPLETED** after required quality gates are satisfied, the branch is **merged to `main`**, and `main` is **pushed to remote**.

## Steps

### Step 0: Resume-first Check (Manager)
- Pull latest `main` and check for any `.task-locks/<task-id>.lock.json` with `status: ACTIVE`.
- If an ACTIVE lock exists:
  - Summarize prior progress: `workStage`, last checkpoint, completed objectives.
  - **Ask the user whether to resume**. Do not proceed without explicit confirmation.
- If multiple ACTIVE locks exist, stop and ask the user how to proceed.

### Step 1: Select Next Task (Manager)
- If no ACTIVE lock exists (or user declined to resume), select the first eligible unblocked task from the current milestone.
- See `roles/manager.md` for task selection criteria.

### Step 2: Lock Task on `main` (Coder)
This step prevents multiple agents from working on the same task.

**For complete step-by-step procedures, see [`guides/git_and_workflow_operations.md#part-5-command-reference`](../guides/git_and_workflow_operations.md#part-5-command-reference).**

Summary:
1. Create `.task-locks/<task-id>.lock.json` with `status: ACTIVE`, `workStage: IMPLEMENTATION_STARTED`.
2. Commit the lock file on `main`.
3. **Push `main` to remote** — this is mandatory before proceeding.
4. Only after push succeeds: create the feature branch `codex/<task-id>-<short-description>` from `main`.

### Step 3: Implement with TDD (Coder)
- Implement the task using TDD on the feature branch.
- Periodically update the lock file with progress checkpoints.
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
  - Produce review artifact: `.task-locks/artifacts/<task-number>-review.md`.
  - Only when review status is **APPROVED** can the task proceed.
  - Transition lock to `workStage: CODE_REVIEW_APPROVED`.
  - See `roles/code_reviewer.md`.
- If task has no code/test changes:
  - Skip code review and set `workStage: CODE_REVIEW_SKIPPED`.
  - Record skip reason + diff evidence in lock history.

### Step 6: QA Verification (Conditional)
- If task changes code/tests:
  - QA runs only on the branch/commit that incorporates review feedback.
  - QA produces: `.task-locks/artifacts/<task-number>-qa-report.md`.
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
3. **Push `main` to remote** — mandatory before any cleanup.
4. Only after push succeeds: optionally delete the local feature branch.

## Output
- Task selection summary
- Lock file committed to `main` **and pushed to remote** when task starts
- Feature branch `codex/...` created after lock is on remote
- Code review artifact (required only when code/tests changed)
- QA report (required only when code/tests changed)
- For no-code/test tasks: lock history entry documenting approved review/QA skip with diff evidence
- Final merge includes lock archival; `main` pushed to remote
- Branch cleanup only after remote push confirmed

## Notes
- If no eligible task is found, report blockers and recommend next action.
- **Never** mark a task completed based on "implementation finished". Completion requires: required quality gates ✅ + merge ✅ + push ✅.
- **Always ask the user** before resuming unfinished work. Never auto-resume.
