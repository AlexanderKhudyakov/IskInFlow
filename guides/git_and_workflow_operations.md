# Git and Workflow Operations Guide

## Overview

This guide provides the definitive procedures for all git operations, task locking, and workflow mechanics in the IskInFlow development system. It is the single source of truth for how to execute lock-based workflow at the operational level.

### Key Principles

1. **Lock-First**: A task is only "taken" when the lock file is committed to `main` and pushed to remote
2. **Push-Before-Proceed**: The lock push to remote MUST succeed before implementation begins
3. **Feature Branches**: Implementation happens on feature branches named `codex/<task-id>-<description>`
4. **Single Source of Truth**: The lock file on `main` (remote) is authoritative for task status
5. **Resumable Work**: Every checkpoint is recorded so work can be resumed if interrupted
6. **Quality Gates**: Specific push points enforce code review and QA before merging
7. **Git Worktree (Required)**: All agents MUST use `git worktree` for every task to maintain isolated working copies and prevent file/artifact contamination
8. **Push Main After Merge**: The final merge to `main` MUST be pushed to remote before any branch cleanup. Task is not complete until remote `main` is updated

---

## Git Worktree Requirement

**CRITICAL**: All agents MUST use `git worktree` for each task, regardless of whether working alone or in parallel. This requirement applies to all scenarios and ensures:
- Isolated working copies for each task
- Clean build/test artifacts per task
- Prevention of file conflicts and state corruption
- Clear separation between work on different tasks
- Ability to parallelize work in the future without changing workflow

### Why Git Worktree is Required

Git assumes a single working copy per repository. When agents work on different branches, even sequentially:
- They may leave build artifacts, temporary files, or uncommitted changes
- Switching branches in a shared directory causes:
  - File conflicts and overwrites
  - Lost work and dangling test artifacts
  - Build system failures
  - State inconsistency between branches

Using `git worktree` for every task:
- Guarantees isolated file state per branch
- Keeps build artifacts and dependencies separate
- Prevents accidental contamination from previous tasks
- Enables future parallelization without workflow changes

### Git Worktree Setup

Each agent should create a separate worktree for each task:

```bash
# List existing worktrees
git worktree list

# Create new worktree for a task (from main)
git worktree add ../<task-id>-worktree codex/<task-id>-<short-description>

# Navigate to worktree
cd ../<task-id>-worktree

# Verify you're in the right branch
git branch  # Should show: * codex/<task-id>-<short-description>

# Work in this isolated directory (tests, builds, etc.)
# No conflicts with other agents' work
```

### Worktree Structure

```
project-root/
├── .git/                          # Shared git repository (ONE per project)
├── main-worktree/                 # Main branch worktree (or use root)
├── codex-023-worktree/            # Agent 1: Task 023
├── codex-045-worktree/            # Agent 2: Task 045
└── codex-089-worktree/            # Agent 3: Task 089
```

Each worktree has its own:
- Working directory (isolated file state)
- `.git/index` (staging area)
- Build artifacts (separate `build/`, `dist/`, etc.)
- Local branch tracking

But they share:
- `.git/` repository (commits, branches, remotes)
- Object database
- Lock files in `.task-locks/`

### Worktree Cleanup

After task completion and **only after final merge is pushed to remote**, delete the worktree:

```bash
# From main (or another worktree), verify push succeeded
git fetch origin
git status  # Should show "Your branch is up to date with 'origin/main'"

# Remove the completed worktree
git worktree remove ../<task-id>-worktree

# Prune worktree references
git worktree prune

# Delete the local branch
git branch -d codex/<task-id>-<short-description>

# Prune stale remote-tracking branches
git fetch --prune
```

### Worktree Best Practices

1. **Create worktree per agent per task**: Don't share worktrees
2. **Create from feature branch**: `git worktree add <path> codex/<task-id>-...`
3. **Verify correct branch**: Always check `git branch` in worktree
4. **Use absolute paths**: Makes it clear which worktree you're in
5. **Delete after completion**: Clean up when task is done
6. **Don't nest worktrees**: Place sibling to main worktree, not inside
7. **CI/CD consideration**: Build systems MUST use worktrees in parallel environments

### Example: Worktree Workflow

**Single Agent (Task 023):**
```bash
# Lock acquired on main and pushed
git branch codex/023-metrics-system main
git worktree add ../task-023-metrics codex/023-metrics-system
cd ../task-023-metrics
# Work on task 023 here (isolated from main)
# Build artifacts stay in this worktree
# Tests run in this worktree only
```

**Multi-Agent (simultaneous work):**
```bash
# Agent 1 (Task 023) - in main repo
git branch codex/023-metrics-system main
git worktree add ../task-023-metrics codex/023-metrics-system
cd ../task-023-metrics
# Work on task 023 here - completely isolated

# Agent 2 (Task 045) - in same main repo (parallel, no conflicts)
git branch codex/045-user-auth main
git worktree add ../task-045-auth codex/045-user-auth
cd ../task-045-auth
# Work on task 045 here - completely isolated, no conflicts with Agent 1

# Agent 3 (Task 089) - continues pattern
git branch codex/089-perf main
git worktree add ../task-089-perf codex/089-perf
cd ../task-089-perf
# Work on task 089 here - completely isolated
```

All agents (whether working alone or parallel) use isolated worktrees, preventing file contamination and state corruption.

---

## Part 1: Lock File Management

### Lock File Format

All lock files follow this schema:

```json
{
  "taskId": "<task-id>",
  "status": "ACTIVE | COMPLETED",
  "workStage": "<current stage>",
  "branch": "codex/<task-id>-<short-description>",
  "lockedAt": "<ISO timestamp>",
  "completedAt": "<ISO timestamp | null>",
  "lockedBy": "agent",
  "history": [
    {
      "timestamp": "<ISO timestamp>",
      "fromStage": "<previous stage | null>",
      "toStage": "<new stage>",
      "reason": "<why this transition>",
      "gitState": {
        "branch": "<branch name>",
        "commit": "<commit hash>"
      }
    }
  ],
  "workState": {
    "lastCheckpoint": "<ISO timestamp>",
    "completedObjectives": ["<objective-id>"],
    "pendingObjectives": ["<objective-id>"],
    "currentPhase": "<phase name>",
    "testsWritten": "<number>",
    "testsPassing": "<number>",
    "coverage": "<percentage>",
    "notes": "<any relevant notes>"
  }
}
```

### Valid Work Stage Values

- `IMPLEMENTATION_STARTED` – Lock acquired, implementation beginning
- `IMPLEMENTATION_COMPLETE` – All code written and tested
- `CODE_REVIEW_REQUESTED` – Submitted for code review
- `CODE_REVIEW_CHANGES_REQUESTED` – Review feedback received, fixes in progress
- `CODE_REVIEW_APPROVED` – Code review approved ✅
- `QA_REQUESTED` – Submitted for QA verification
- `QA_FAILED` – QA found issues, fixes in progress
- `QA_PASSED` – QA verification passed ✅
- `MERGED` – Merged to `main` and pushed

### Lock File Directory Structure

```
.task-locks/
├── <task-id>.lock.json           # Active locks (ACTIVE status)
├── <task-id>.lock.json           # (another active task)
└── completed/
    ├── <task-id>.lock.json       # Completed locks (COMPLETED status)
    ├── <task-id>.lock.json       # (another completed task)
    └── ... (archive of all completed tasks)
```

---

## Part 2: Branch Operations

### Branch Naming Conventions

**Feature branches** follow this pattern:

```
codex/<task-id>-<short-description>
```

Where:
- `codex/` – Fixed prefix for all implementation branches
- `<task-id>` – Task identifier from task file (e.g., `023`)
- `<short-description>` – Hyphenated, lowercase, 2-4 words summarizing the feature

**Examples:**
- `codex/023-metrics-collection-system`
- `codex/045-user-authentication-flow`
- `codex/089-performance-optimization`

### Creating Feature Branches and Worktrees

Feature branches are created **only after** the lock commit is on `main` and pushed to remote.

**For all scenarios (REQUIRED):**

```bash
# Step 1: Verify lock is on main (should already be pushed)
git checkout main
git pull origin main
ls .task-locks/<task-id>.lock.json  # Should exist

# Step 2: Create feature branch from main
git branch codex/<task-id>-<short-description> main

# Step 3: Create WORKTREE for this branch (REQUIRED for all agents)
git worktree add ../<task-id>-worktree codex/<task-id>-<short-description>

# Step 4: Navigate to worktree
cd ../<task-id>-worktree

# Step 5: Verify you're on the correct branch
git branch  # Should show * codex/<task-id>-<short-description>
```

**Critical**: All agents MUST use `git worktree` for every task. This ensures isolated working copies regardless of whether working alone or in parallel, and prevents file/artifact contamination between tasks (see "Git Worktree Requirement" section above).

### Branch Deletion (Cleanup)

Branches and worktrees are deleted **only after** the final merge is pushed to remote.

**If using worktree (multi-agent scenario):**

```bash
# Step 1: Verify main was pushed
git fetch origin
git status  # Should show "Your branch is up to date with 'origin/main'"

# Step 2: Exit the worktree (navigate away from it)
cd /path/to/original/repo

# Step 3: Delete the worktree
git worktree remove ../<task-id>-worktree

# Step 4: Prune worktree references
git worktree prune

# Step 5: Delete the branch reference (local)
git branch -d codex/<task-id>-<short-description>

# Step 6: Prune stale remote-tracking branches
git fetch --prune
```

**If using shared checkout (single-agent/sequential scenario):**

```bash
# Step 1: Verify main was pushed
git fetch origin
git status  # Should show "Your branch is up to date with 'origin/main'"

# Step 2: Delete local feature branch
git branch -d codex/<task-id>-<short-description>

# Step 3: Prune stale remote-tracking branches
git fetch --prune
```

---

## Part 3: Git Workflow (Detailed)

### Push Timing & Requirements

**Push timing is critical** to the workflow. There are specific points where pushes are mandatory:

#### Push 1: Lock Acquisition (MANDATORY)
- **When**: After lock file is committed to `main` but before creating feature branch
- **What**: The `.task-locks/<task-id>.lock.json` commit on `main`
- **Requirement**: MUST succeed before any implementation begins
- **Why**: Prevents multiple agents from claiming the same task

```bash
git push origin main
```

#### Push 2: Final Merge (MANDATORY)
- **When**: After merging feature branch to `main` with final lock update
- **What**: All commits from feature branch + final lock archival
- **Requirement**: MUST succeed before any branch cleanup
- **Why**: Confirms completed task is recorded on remote and ensures other agents/CI see the work

**CRITICAL: This push is non-negotiable. Task is not complete until main is pushed to remote.**

```bash
git push origin main
```

After this push succeeds:
- Only then proceed with worktree cleanup
- Only then delete feature branch
- Only then archive lock file metadata

### Merge Strategy

The workflow uses **fast-forward merge** for clean history:

```bash
# Switch to main and pull latest
git checkout main
git pull origin main

# Merge with fast-forward (keeps linear history)
git merge --ff-only codex/<task-id>-<short-description>

# If fast-forward fails, main has diverged and needs rebase
```

### Handling Merge Conflicts

```bash
# On feature branch, rebase on main
git checkout codex/<task-id>-<short-description>
git rebase main

# Resolve conflicts in the files that appear
# After resolving each conflict:
git add <resolved-file>

# Continue rebase
git rebase --continue

# Run tests to ensure nothing broke
# Then try merge again
```

---

## Part 4: Resume Protocol

### Finding Existing Locks

When starting work, always check for existing locks:

```bash
# Update local main
git checkout main
git pull origin main

# List all active locks
ls .task-locks/*.lock.json 2>/dev/null
```

### User Confirmation (Required)

**CRITICAL:** Never auto-resume without explicit user confirmation.

```
Found ACTIVE lock for task <task-id>.

Current Status:
- Stage: <workStage>
- Locked At: <timestamp>
- Completed: <objectives>
- Pending: <objectives>

Do you want to resume this task? (yes/no)
```

Only proceed with resume if user answers "yes".

### Resuming Implementation

After user confirmation:

```bash
# Step 1: Restore local state
git checkout main
git pull origin main
git checkout codex/<task-id>-<short-description>
git pull origin codex/<task-id>-<short-description> 2>/dev/null || true

# Step 2: Review work state
cat .task-locks/<task-id>.lock.json

# Step 3: Continue work from where you left off
```

---

## Part 5: Command Reference

### Lock Acquisition (Complete Sequence)

```bash
# 1. Update main
git checkout main && git pull origin main

# 2. Commit lock file
git add .task-locks/<task-id>.lock.json
git commit -m "chore: lock task <task-id> for implementation"

# 3. Push to remote (MANDATORY)
git push origin main

# 4. Create feature branch
git checkout -b codex/<task-id>-<short-description>
```

### Final Merge (Complete Sequence)

```bash
# 1. Feature branch should have final lock update committed

# 2. Merge to main
git checkout main && git pull origin main
git merge --ff-only codex/<task-id>-<short-description>

# 3. Push to remote (MANDATORY - DO NOT SKIP)
git push origin main
# *** CRITICAL: This push MUST succeed before proceeding ***
# *** Verify output shows: "main -> main" ***

# 4. Verify push succeeded
git fetch origin
git status  # Should show "Your branch is up to date with 'origin/main'"

# 5. Cleanup worktree (only after push succeeds)
cd /path/to/main/repo  # Navigate away from worktree
git worktree remove ../<task-id>-worktree
git worktree prune

# 6. Cleanup branch references
git branch -d codex/<task-id>-<short-description>
git fetch --prune
```

---

## Part 6: Quality Gates & Checkpoints

### Required Push Points

Only two push points are allowed:

1. **Lock Acquisition**: Lock commit on `main` (before feature branch creation)
2. **Final Merge**: Feature branch merged to `main` with final lock archival (before branch cleanup)

### Pre-Merge Validation

Before final merge, validate:

```bash
# Verify code review status
cat .task-locks/<task-id>.lock.json | grep -A 1 workStage
# Must show: CODE_REVIEW_APPROVED

# Verify QA status
cat .task-locks/artifacts/<task-id>-qa-report.md
# Must show: PASS

# Verify all tests pass
# (Run project test suite)

# Verify no uncommitted changes
git status
```

---

## Quick Reference: Common Commands

### Basic Operations (Single Agent)
```bash
# Check for active locks
ls .task-locks/*.lock.json

# View lock file
cat .task-locks/<task-id>.lock.json

# Push lock acquisition
git add .task-locks/<task-id>.lock.json && \
git commit -m "chore: lock task <task-id> for implementation" && \
git push origin main

# Create feature branch
git checkout -b codex/<task-id>-<short-description>

# Final merge and push
git checkout main && git pull origin main && \
git merge --ff-only codex/<task-id>-<short-description> && \
git push origin main && \
git branch -d codex/<task-id>-<short-description> && \
git fetch --prune
```

### Worktree Operations (Required for All Agents)
```bash
# List all worktrees
git worktree list

# Create feature branch and worktree (after lock is pushed)
git branch codex/<task-id>-<short-description> main && \
git worktree add ../<task-id>-worktree codex/<task-id>-<short-description> && \
cd ../<task-id>-worktree

# Verify correct branch
git branch

# Clean up worktree after merge and push to remote
cd /path/to/main/repo && \
git fetch origin && \
git worktree remove ../<task-id>-worktree && \
git worktree prune && \
git branch -d codex/<task-id>-<short-description> && \
git fetch --prune
```

---

## See Also

- **Manager Role**: `roles/manager.md` – Task selection, locking policy
- **Coder Role**: `roles/coder.md` – Implementation guidelines
- **Code Review**: `roles/code_reviewer.md` – Code quality assessment
- **QA Role**: `roles/qa_engineer.md` – Functional verification
- **Start Command**: `commands/start_or_continue_next_task.md` – Workflow entry point
