# Command: Quick Task

## MCP-First Requirement
Before executing any step in this command, consult `guides/mcp_first_tooling.md`. Enumerate available MCP servers and tools, and prefer them for discovery, validation, and execution tasks.

## Purpose
Take a simple user request from chat and run the entire pipeline end-to-end: plan, implement, review, QA, and merge — all in one command. Supports both single-agent and multi-agent execution.

Key rules:
- **No pull requests** are used in this workflow. Everything is branch-based with direct merges.
- **Lock-first**: the lock commit must be on `main` **and pushed to remote** before any implementation begins.
- **User confirmation is required before resuming**: if an unfinished (ACTIVE) quick task is found, the agent **must ask the user** before continuing. Never auto-resume.
- The lock file on `main` (pushed to remote) is the **single source of truth** for whether a task is taken.
- **Post-merge push**: after merging, `main` must be pushed to remote before any cleanup.
- **Branch cleanup**: the feature branch may only be deleted after `main` is pushed.
- **`qt-` prefix**: all quick-task IDs, lock files, branches, and artifacts use a `qt-` prefix to avoid collision with numbered development-plan tasks.
- **Agent identity**: every agent must identify itself with its assigned `agentId` in all lock operations.
- **Cross-agent review**: in multi-agent mode, the reviewer and QA agent must differ from the implementer.

This command is intentionally strict:
- Tasks that change code or tests MUST go through code review and QA.
- Tasks with no code/test changes (docs/spec/process-only) MAY skip code review and QA after manager verification and lock-history evidence.
- A task is only considered **COMPLETED** after required quality gates are satisfied, the branch is **merged to `main`**, and `main` is **pushed to remote**.

**When to use this command vs. others:**
- Use `quick_task` for small, self-contained work items that don't need a full product spec / tech spec / development plan.
- Use `idea_to_dev_plan` + `start_or_continue_next_task` for larger features that benefit from structured planning with milestones.

## Inputs
- User's request (from chat)
- Short name for the task (derived from request or asked for)

## Steps

### Step 0: Resume-first Check (Manager)
- Pull latest `main` and check for any `.task-locks/qt-*.lock.json` with `status: ACTIVE`.
- If an ACTIVE lock exists:
  - Check if the lock's `agentId` matches this agent. Only resume tasks assigned to you.
  - Summarize prior progress: `workStage`, `agentId`, last checkpoint, completed objectives.
  - **Ask the user whether to resume**. Do not proceed without explicit confirmation.
- If ACTIVE locks exist for a **different** agent: report them but do NOT resume.
- If multiple ACTIVE locks exist for this agent, stop and ask the user how to proceed.

### Step 1: Understand and Plan (Manager)
This step condenses the Product Manager, Tech Lead, and Task Planner roles into one lightweight planning step.

1. Analyze the user's request to understand the problem and desired outcome.
2. Explore the codebase to understand the current state and identify files to modify.
3. Produce a **Quick Task Brief**: `.task-locks/qt-<short-name>-brief.md` containing:
   - **Problem Statement**: What needs to change and why.
   - **Proposed Solution**: High-level approach.
   - **Scope**: What's included and explicitly what's excluded.
   - **Acceptance Criteria**: Clear, verifiable conditions for completion.
   - **Files to Modify**: List of files to create, modify, or delete.
   - **Risks**: Anything that could go wrong or require extra care.
   - **Testing Approach**: How the changes will be verified.
4. The brief should be concise — capped at ~80 lines. If the brief grows beyond that, recommend `idea_to_dev_plan` instead and stop.
5. **Confirm the brief with the user** before proceeding. Do not continue without explicit approval.

### Step 2: Create Task File (Manager)
- Produce `.task-locks/qt-<short-name>-task.md` using the standard task file structure from `roles/task_planner.md`.
- Task ID uses the `qt-<short-name>` format (e.g., `qt-fix-login-bug`).
- The task file should be appropriately sized for the work — quick tasks don't need all 18 sections from the full template. Include at minimum: Task Header, Overview, Objectives, Implementation Details, Testing Requirements, and Acceptance Criteria.

### Step 3: Lock Task on `main` (Coder)
This step prevents multiple agents from working on the same task.

**For complete step-by-step procedures, see [`guides/git_and_workflow_operations.md#part-5-command-reference`](../guides/git_and_workflow_operations.md#part-5-command-reference).**

Summary:
1. Create `.task-locks/qt-<short-name>.lock.json` with `status: ACTIVE`, `workStage: IMPLEMENTATION_STARTED`, `agentId: "<your-agent-name>"`.
2. Commit the brief, task file, and lock file together on `main`.
3. **Push `main` to remote** — this is mandatory before proceeding. If push is rejected, use the retry loop from `guides/git_and_workflow_operations.md` Part 7.
4. Only after push succeeds: create the feature branch `codex/qt-<short-name>` from `main` and set up a worktree.

### Step 4: Implement with TDD (Coder)
- Implement the task using TDD on the feature branch (in its own worktree).
- Update the lock file on the **feature branch** with progress checkpoints (NOT on main).
- When implementation is complete, transition to `workStage: IMPLEMENTATION_COMPLETE`.
- See `roles/coder.md` for detailed implementation guidelines.

### Step 5: Code Review Loop (Code Reviewer + Coder)

```
┌──────────────────────────────────────────────────────┐
│                  CODE REVIEW LOOP                     │
├──────────────────────────────────────────────────────┤
│                                                       │
│   Implementation Complete                             │
│          ↓                                            │
│   [Multi-agent: AWAITING_REVIEW → different agent]    │
│   [Single-agent: same agent reviews]                  │
│          ↓                                            │
│   Code Review (Code Reviewer)                         │
│          ↓                                            │
│   ┌─────────────────────────────────────┐            │
│   │ Decision?                           │            │
│   │                                     │            │
│   │  APPROVED → Exit loop, proceed      │            │
│   │                                     │            │
│   │  REQUEST_CHANGES → Coder fixes      │            │
│   │       ↓                             │            │
│   │  Re-submit for review ──────────────┼──→ Loop   │
│   └─────────────────────────────────────┘            │
│                                                       │
└──────────────────────────────────────────────────────┘
```

- Code Reviewer reviews per `roles/code_reviewer.md`.
- Artifact: `.task-locks/artifacts/qt-<short-name>/review.md`.
- **If APPROVED**: transition lock to `workStage: CODE_REVIEW_APPROVED`, proceed to Step 6.
- **If REQUEST_CHANGES**: Coder fixes all issues per `roles/coder.md` ("Responding to Code Review Feedback"), then re-review. Repeat until approved.
- Track review iterations in lock history.

### Step 6: QA Verification Loop (QA Engineer + Coder)

```
┌──────────────────────────────────────────────────────┐
│                    QA LOOP                            │
├──────────────────────────────────────────────────────┤
│                                                       │
│   Branch ready for QA                                 │
│          ↓                                            │
│   [Multi-agent: AWAITING_QA → different agent]        │
│   [Single-agent: same agent QAs]                      │
│          ↓                                            │
│   QA Verification (QA Engineer)                       │
│          ↓                                            │
│   ┌─────────────────────────────────────┐            │
│   │ Decision?                           │            │
│   │                                     │            │
│   │  PASS → Exit loop, proceed to merge │            │
│   │                                     │            │
│   │  FAIL → Coder fixes issues          │            │
│   │       ↓                             │            │
│   │  [If significant changes]           │            │
│   │       ↓                             │            │
│   │  Back to Step 5 (re-review)         │            │
│   │                                     │            │
│   │  [If minor changes]                 │            │
│   │       ↓                             │            │
│   │  Re-submit for QA ──────────────────┼──→ Loop   │
│   └─────────────────────────────────────┘            │
│                                                       │
└──────────────────────────────────────────────────────┘
```

- QA Engineer verifies per `roles/qa_engineer.md`.
- Artifact: `.task-locks/artifacts/qt-<short-name>/qa-report.md`.
- **If PASS**: transition lock to `workStage: QA_PASSED`, proceed to Step 7.
- **If FAIL**: Coder fixes issues. Manager decides:
  - **Significant changes** (new logic, structural changes) → back to Step 5 for re-review.
  - **Minor changes** (typos, small adjustments) → re-QA only.
- Track QA iterations in lock history.

### Step 7: Final Merge and Push (Manager + Coder)
**For complete step-by-step procedures, see [`guides/git_and_workflow_operations.md#part-5-command-reference`](../guides/git_and_workflow_operations.md#part-5-command-reference).**

Summary:
1. On the feature branch, prepare final lock update:
   - Set `status: COMPLETED`, `workStage: MERGED`.
   - Move lock to `.task-locks/completed/qt-<short-name>.lock.json`.
   - Commit this final update.
2. Checkout `main`, pull latest, fast-forward merge the feature branch.
3. **Push `main` to remote** — mandatory before any cleanup. If push is rejected, use the merge retry loop from `guides/git_and_workflow_operations.md` Part 7.
4. Only after push succeeds: delete the worktree and local feature branch.

## Output
- Quick Task Brief: `.task-locks/qt-<short-name>-brief.md`
- Task file: `.task-locks/qt-<short-name>-task.md`
- Lock file committed to `main` **and pushed to remote** when task starts (with `agentId`)
- Feature branch `codex/qt-<short-name>` created after lock is on remote
- Code review artifact (required only when code/tests changed): `.task-locks/artifacts/qt-<short-name>/review.md`
- QA report (required only when code/tests changed): `.task-locks/artifacts/qt-<short-name>/qa-report.md`
- For no-code/test tasks: lock history entry documenting approved review/QA skip with diff evidence
- Final merge includes lock archival; `main` pushed to remote
- Branch cleanup only after remote push confirmed

## Notes
- If the user's request is too complex for a quick task (brief exceeds ~80 lines), recommend `idea_to_dev_plan` instead.
- **Never** mark a task completed based on "implementation finished". Completion requires: required quality gates passed + merge + push.
- **Always ask the user** before resuming unfinished work. Never auto-resume.
- All quick-task artifacts live in `.task-locks/` (brief, task file, lock) and `.task-locks/artifacts/qt-<short-name>/` (review, QA report) — no separate development plan directory is needed.
- The `qt-` prefix on all IDs and filenames ensures quick tasks never collide with numbered development-plan tasks.
- In multi-agent mode, check for review/QA work before starting a new quick task.
