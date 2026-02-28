# Git and Workflow Operations Guide

## Overview

This guide provides the definitive procedures for all git operations, task locking, and workflow mechanics in the IskInFlow development system. It is the single source of truth for how to execute lock-based workflow at the operational level.

### Key Principles

1. **Lock-First**: A task is only "taken" when the lock file is committed to `main` and pushed to remote
2. **Push-Before-Proceed**: The lock push to remote MUST succeed before implementation begins
3. **Feature Branches**: Implementation happens on feature branches named `ai/<task-id>-<description>`
4. **Single Source of Truth**: The lock file on `main` (remote) is authoritative for task status
5. **Resumable Work**: Every checkpoint is recorded so work can be resumed if interrupted
6. **Quality Gates**: Specific push points enforce code review and QA before merging
7. **Git Worktree (Required)**: All agents MUST use `git worktree` for every task to maintain isolated working copies and prevent file/artifact contamination
8. **Push Main After Merge**: The final merge to `main` MUST be pushed to remote before any branch cleanup. Task is not complete until remote `main` is updated
9. **Agent Identity**: Every agent has a fixed, human-readable name (e.g., `agent-alpha`). All lock operations record which agent performed them
10. **Cross-Agent Review**: In multi-agent mode, the implementing agent and the reviewing agent must be different. Self-review is not permitted
11. **Minimal Main Touches**: Only two commits per task touch `main` — lock acquisition and final merge+archive. All intermediate stage transitions stay on the feature branch
12. **Retry-Before-Fail**: Push rejections due to concurrent writes are resolved via fetch-rebase-push retry loops, not manual intervention

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
git worktree add ../<task-id>-worktree ai/<task-id>-<short-description>

# Navigate to worktree
cd ../<task-id>-worktree

# Verify you're in the right branch
git branch  # Should show: * ai/<task-id>-<short-description>

# Work in this isolated directory (tests, builds, etc.)
# No conflicts with other agents' work
```

### Worktree Structure

```
project-root/
├── .git/                          # Shared git repository (ONE per project)
├── main-worktree/                 # Main branch worktree (or use root)
├── ai-023-worktree/            # Agent 1: Task 023
├── ai-045-worktree/            # Agent 2: Task 045
└── ai-089-worktree/            # Agent 3: Task 089
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
git branch -d ai/<task-id>-<short-description>

# Prune stale remote-tracking branches
git fetch --prune
```

### Worktree Best Practices

1. **Create worktree per agent per task**: Don't share worktrees
2. **Create from feature branch**: `git worktree add <path> ai/<task-id>-...`
3. **Verify correct branch**: Always check `git branch` in worktree
4. **Use absolute paths**: Makes it clear which worktree you're in
5. **Delete after completion**: Clean up when task is done
6. **Don't nest worktrees**: Place sibling to main worktree, not inside
7. **CI/CD consideration**: Build systems MUST use worktrees in parallel environments

### Example: Worktree Workflow

**Single Agent (Task 023):**
```bash
# Lock acquired on main and pushed
git branch ai/023-metrics-system main
git worktree add ../task-023-metrics ai/023-metrics-system
cd ../task-023-metrics
# Work on task 023 here (isolated from main)
# Build artifacts stay in this worktree
# Tests run in this worktree only
```

**Multi-Agent (simultaneous work):**
```bash
# Agent 1 (Task 023) - in main repo
git branch ai/023-metrics-system main
git worktree add ../task-023-metrics ai/023-metrics-system
cd ../task-023-metrics
# Work on task 023 here - completely isolated

# Agent 2 (Task 045) - in same main repo (parallel, no conflicts)
git branch ai/045-user-auth main
git worktree add ../task-045-auth ai/045-user-auth
cd ../task-045-auth
# Work on task 045 here - completely isolated, no conflicts with Agent 1

# Agent 3 (Task 089) - continues pattern
git branch ai/089-perf main
git worktree add ../task-089-perf ai/089-perf
cd ../task-089-perf
# Work on task 089 here - completely isolated
```

All agents (whether working alone or parallel) use isolated worktrees, preventing file contamination and state corruption.

---

## Part 1: Lock File Management

### Lock File Format (Schema v2)

All lock files follow this schema. Fields marked *(v2)* are new for multi-agent support and are optional for backward compatibility with existing locks.

```json
{
  "schemaVersion": 2,
  "taskId": "<task-id>",
  "taskName": "<human-readable task name>",
  "status": "ACTIVE | COMPLETED",
  "workStage": "<current stage>",
  "branch": "ai/<task-id>-<short-description>",
  "milestone": "<milestone name>",
  "planFile": "<path to task plan file>",
  "lockedAt": "<ISO timestamp>",
  "completedAt": "<ISO timestamp | null>",
  "agentId": "<agent-alpha | agent-beta | agent-gamma | ...>",
  "agentSession": "<random hex string per session>",
  "implementedBy": "<agentId of implementing agent>",
  "reviewedBy": "<agentId of reviewing agent | null>",
  "qaBy": "<agentId of QA agent | null>",
  "history": [
    {
      "timestamp": "<ISO timestamp>",
      "fromStage": "<previous stage | null>",
      "toStage": "<new stage>",
      "agentId": "<which agent performed this transition>",
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

#### Agent Identity Fields *(v2)*

| Field | Description |
|---|---|
| `agentId` | Fixed human-readable name assigned by user or Manager: `agent-alpha`, `agent-beta`, `agent-gamma`, etc. |
| `agentSession` | Short random hex (e.g., `a1b2c3d4`) generated at session startup. Distinguishes agent restarts from the same slot. |
| `implementedBy` | `agentId` of the agent that performed implementation. Set when implementation starts. |
| `reviewedBy` | `agentId` of the agent that performed code review. Set when review starts. **Must differ from `implementedBy`** in multi-agent mode. |
| `qaBy` | `agentId` of the agent that performed QA. Set when QA starts. **Must differ from `implementedBy`** in multi-agent mode. |

### Valid Work Stage Values

Implementation stages:
- `IMPLEMENTATION_STARTED` – Lock acquired, implementation beginning
- `IMPLEMENTATION_COMPLETE` – All code written and tested

Review stages:
- `AWAITING_REVIEW` – *(v2)* Implementation complete, pushed to remote, waiting for a different agent to review
- `CODE_REVIEW_REQUESTED` – Submitted for code review (same agent or assigned reviewer)
- `CODE_REVIEW_CHANGES_REQUESTED` – Review feedback received, fixes in progress
- `CODE_REVIEW_APPROVED` – Code review approved ✅
- `CODE_REVIEW_SKIPPED` – No code/test changes, review skipped with evidence

QA stages:
- `AWAITING_QA` – *(v2)* Review approved, waiting for a different agent to QA
- `QA_REQUESTED` – Submitted for QA verification
- `QA_FAILED` – QA found issues, fixes in progress
- `QA_PASSED` – QA verification passed ✅
- `QA_SKIPPED` – No code/test changes, QA skipped with evidence

Reflection stages:
- `REFLECTION_COMPLETE` – Reflection analysis done, skills extracted/updated

Completion:
- `MERGED` – Merged to `main` and pushed

#### Stage Transitions in Multi-Agent Mode

```
IMPLEMENTATION_STARTED
    ↓ (implementing agent)
IMPLEMENTATION_COMPLETE
    ↓ (implementing agent pushes feature branch)
AWAITING_REVIEW ─────────────────────── implementing agent moves to next task
    ↓ (reviewing agent picks up)
CODE_REVIEW_REQUESTED
    ↓
CODE_REVIEW_APPROVED (or CHANGES_REQUESTED → fix loop)
    ↓
AWAITING_QA ─────────────────────────── reviewing agent moves to next review
    ↓ (QA agent picks up)
QA_REQUESTED
    ↓
QA_PASSED (or QA_FAILED → fix loop)
    ↓
REFLECTION_COMPLETE ──────────────── skills extracted, artifact created
    ↓
MERGED
```

### Lock File Directory Structure

```
.task-locks/
├── <task-id>.lock.json              # Active locks (ACTIVE status)
├── <task-id>.lock.json              # (another active task)
├── completed/                       # Archive of completed locks
│   ├── <task-id>.lock.json
│   └── ...
└── artifacts/                       # Review and QA artifacts
    ├── <task-id>/                   # Per-task subdirectory (v2)
    │   ├── review.md
    │   └── qa-report.md
    ├── <old-task-id>-review.md      # Legacy flat files (pre-v2, read-only)
    └── <old-task-id>-qa-report.md
```

**Artifact path convention (v2):** New tasks use per-task subdirectories:
- Review: `.task-locks/artifacts/<task-id>/review.md`
- QA report: `.task-locks/artifacts/<task-id>/qa-report.md`

Legacy flat files (`<task-id>-review.md`) remain in place for backward compatibility and are read-only.

---

## Part 2: Branch Operations

### Branch Naming Conventions

**Feature branches** follow this pattern:

```
ai/<task-id>-<short-description>
```

Where:
- `ai/` – Fixed prefix for all implementation branches
- `<task-id>` – Task identifier from task file (e.g., `023`)
- `<short-description>` – Hyphenated, lowercase, 2-4 words summarizing the feature

**Examples:**
- `ai/023-metrics-collection-system`
- `ai/045-user-authentication-flow`
- `ai/089-performance-optimization`

### Creating Feature Branches and Worktrees

Feature branches are created **only after** the lock commit is on `main` and pushed to remote.

**For all scenarios (REQUIRED):**

```bash
# Step 1: Verify lock is on main (should already be pushed)
git checkout main
git pull origin main
ls .task-locks/<task-id>.lock.json  # Should exist

# Step 2: Create feature branch from main
git branch ai/<task-id>-<short-description> main

# Step 3: Create WORKTREE for this branch (REQUIRED for all agents)
git worktree add ../<task-id>-worktree ai/<task-id>-<short-description>

# Step 4: Navigate to worktree
cd ../<task-id>-worktree

# Step 5: Verify you're on the correct branch
git branch  # Should show * ai/<task-id>-<short-description>
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
git branch -d ai/<task-id>-<short-description>

# Step 6: Prune stale remote-tracking branches
git fetch --prune
```

**If using shared checkout (single-agent/sequential scenario):**

```bash
# Step 1: Verify main was pushed
git fetch origin
git status  # Should show "Your branch is up to date with 'origin/main'"

# Step 2: Delete local feature branch
git branch -d ai/<task-id>-<short-description>

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
- **Multi-agent**: If push is rejected (another agent pushed first), use the retry loop (see [Multi-Agent Coordination](#part-7-multi-agent-coordination))

```bash
git push origin main
```

#### Push 2: Final Merge (MANDATORY)
- **When**: After merging feature branch to `main` with final lock update
- **What**: All commits from feature branch + final lock archival
- **Requirement**: MUST succeed before any branch cleanup
- **Why**: Confirms completed task is recorded on remote and ensures other agents/CI see the work
- **Multi-agent**: If push is rejected (another agent merged first), use the merge retry loop (see [Multi-Agent Coordination](#part-7-multi-agent-coordination))

**CRITICAL: This push is non-negotiable. Task is not complete until main is pushed to remote.**

```bash
git push origin main
```

After this push succeeds:
- Only then proceed with worktree cleanup
- Only then delete feature branch
- Only then archive lock file metadata

#### Intermediate Stage Transitions — Feature Branch Only

**IMPORTANT (v2):** All intermediate lock updates (`IMPLEMENTATION_COMPLETE`, `CODE_REVIEW_APPROVED`, `QA_PASSED`, etc.) are committed on the **feature branch**, NOT on `main`. They reach `main` automatically when the feature branch is merged at completion.

This reduces main-branch contention from ~6 commits per task to exactly 2:
1. Lock acquisition commit (Push 1)
2. Merge commit + archive (Push 2)

The only exception: if the lock needs to be updated on `main` for cross-agent visibility (e.g., transitioning to `AWAITING_REVIEW` so another agent can discover it), push the feature branch to remote and update the lock file in the feature branch. Other agents read the lock from the feature branch via `git show origin/ai/<task-id>-...:path/to/lock.json`.

### Merge Strategy

The workflow uses **non-fast-forward merge** (`--no-ff`) to always produce a merge commit, preserving a clear record of when each feature branch landed on `main`:

```bash
# Switch to main and pull latest
git checkout main
git pull origin main

# Merge with no-fast-forward (always creates a merge commit)
git merge --no-ff ai/<task-id>-<short-description>
```

### Handling Merge Conflicts

```bash
# On feature branch, rebase on main
git checkout ai/<task-id>-<short-description>
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

## Part 4: Resume Protocol (Multi-Agent Aware)

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
Found ACTIVE lock(s):

Task <task-id-1>:
- Agent: <agentId>
- Stage: <workStage>
- Locked At: <timestamp>
- Completed: <objectives>
- Pending: <objectives>

Task <task-id-2>:
- Agent: <agentId>
- Stage: <workStage>
...

Do you want to resume any of these tasks? (specify task ID or "no")
```

Only proceed with resume if user explicitly confirms.

**Multi-agent consideration:** When multiple agents are active, each agent should only resume tasks assigned to it (matching `agentId`). If an agent finds a lock with a different `agentId`, it should report the lock but NOT attempt to resume it — that is handled by the stale lock reclamation protocol (see [Part 8](#part-8-stale-lock-detection--reclamation)).

### Resuming Implementation

After user confirmation:

```bash
# Step 1: Restore local state
git checkout main
git pull origin main
git checkout ai/<task-id>-<short-description>
git pull origin ai/<task-id>-<short-description> 2>/dev/null || true

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

# 2. Create lock file with agentId
# (see Lock File Format for full schema)

# 3. Commit lock file
git add .task-locks/<task-id>.lock.json
git commit -m "chore(lock): acquire <task-id>"

# 4. Push to remote (MANDATORY) — with retry loop for multi-agent
git push origin main
# If push rejected: see "Lock Acquisition Retry Loop" in Part 7

# 5. Create feature branch and worktree
git branch ai/<task-id>-<short-description> main
git worktree add ../<task-id>-worktree ai/<task-id>-<short-description>
cd ../<task-id>-worktree
```

### Batch Lock Acquisition (Multi-Agent)

When the Manager pre-assigns tasks to multiple agents:

```bash
# 1. Update main
git checkout main && git pull origin main

# 2. Create ALL lock files in a single commit
# .task-locks/<task-id-1>.lock.json  (agentId: "agent-alpha")
# .task-locks/<task-id-2>.lock.json  (agentId: "agent-beta")
# .task-locks/<task-id-3>.lock.json  (agentId: "agent-gamma")

# 3. Commit all locks at once
git add .task-locks/*.lock.json
git commit -m "chore(lock): acquire tasks <id-1>, <id-2>, <id-3> for parallel execution"

# 4. Push (single push — no contention)
git push origin main

# 5. Each agent creates their own feature branch and worktree
```

### Final Merge (Complete Sequence)

```bash
# 1. On the feature branch: prepare final lock update
#    - Move lock to .task-locks/completed/<task-id>.lock.json
#    - Set status: COMPLETED, workStage: MERGED
#    - Commit

# 2. Merge to main (with retry for multi-agent)
git checkout main && git pull origin main
git merge --no-ff ai/<task-id>-<short-description>

# 3. Push to remote (MANDATORY - DO NOT SKIP)
git push origin main
# If push rejected: see "Merge Retry Loop" in Part 7
# *** CRITICAL: This push MUST succeed before proceeding ***

# 4. Verify push succeeded
git fetch origin
git status  # Should show "Your branch is up to date with 'origin/main'"

# 5. Cleanup worktree (only after push succeeds)
cd /path/to/main/repo  # Navigate away from worktree
git worktree remove ../<task-id>-worktree
git worktree prune

# 6. Cleanup branch references
git branch -d ai/<task-id>-<short-description>
git fetch --prune
```

---

## Part 6: Quality Gates & Checkpoints

### Required Push Points on Main

Only two push points touch `main`:

1. **Lock Acquisition**: Lock commit on `main` (before feature branch creation)
2. **Final Merge**: Feature branch merged to `main` with `--no-ff` with lock moved to `completed/` (before branch cleanup)

All intermediate lock updates (stage transitions, review/QA results) are committed on the feature branch and reach `main` via the final merge.

### Artifact Commit Checklist

**All task artifacts must be committed before merging.** At the end of a task, run `git status` and ensure no `.task-locks/` files are untracked. Required artifacts per task:

- `qt-<name>-brief.md` and `qt-<name>-task.md` (or `<task-id>` equivalents) — committed when locking
- `.task-locks/artifacts/qt-<name>/review.md` — committed after code review
- `.task-locks/artifacts/qt-<name>/qa-report.md` — committed after QA
- `.task-locks/artifacts/qt-<name>/reflection.md` — committed after reflection
- Any intermediate implementation notes or summaries

Forgetting to commit artifacts leaves orphaned untracked files and breaks the audit trail. Always stage everything in `.task-locks/` before the final merge commit.

### Pre-Merge Validation

Before final merge, validate (reading from the feature branch):

```bash
# Verify lock file shows REFLECTION_COMPLETE (on feature branch)
cat .task-locks/<task-id>.lock.json | grep workStage
# Must show: REFLECTION_COMPLETE

# Verify review artifact exists
ls .task-locks/artifacts/<task-id>/review.md

# Verify QA report exists
ls .task-locks/artifacts/<task-id>/qa-report.md

# Verify all tests pass
# (Run project test suite)

# Verify no uncommitted changes — especially in .task-locks/
git status
```

---

## Part 7: Multi-Agent Coordination

This section covers the protocols that enable 2-5 agents to work in parallel safely.

### Agent Naming Convention

Each agent gets a fixed, human-readable name:

| Agent | Name |
|---|---|
| First agent | `agent-alpha` |
| Second agent | `agent-beta` |
| Third agent | `agent-gamma` |
| Fourth agent | `agent-delta` |
| Fifth agent | `agent-epsilon` |

The user or Manager assigns agent names before work begins. Every lock operation must include the `agentId` in the history entry.

At session startup, each agent generates a random 8-character hex `agentSession` string to distinguish restarts.

### Lock Acquisition Retry Loop

When multiple agents acquire locks simultaneously, push rejections are expected. Since each agent creates a **unique** file (`<task-id>.lock.json`), rebase always succeeds cleanly (no content conflicts).

```bash
# Retry loop for lock acquisition push
MAX_RETRIES=3
RETRY=0

while [ $RETRY -lt $MAX_RETRIES ]; do
  git push origin main && break  # Success — exit loop

  RETRY=$((RETRY + 1))
  echo "Push rejected (attempt $RETRY/$MAX_RETRIES). Retrying..."

  # Random jitter: sleep 0.1-0.5 seconds
  sleep $(echo "scale=2; $RANDOM / 32768 * 0.4 + 0.1" | bc)

  # Fetch and rebase (single-file-add onto different single-file-add = always clean)
  git fetch origin main
  git rebase origin/main
done

if [ $RETRY -eq $MAX_RETRIES ]; then
  echo "ABORT: Lock acquisition failed after $MAX_RETRIES retries."
  echo "Another agent may be performing a large merge. Wait 30s and try again."
fi
```

**Why this works:** Each agent creates a unique lock file. Rebasing one unique file addition onto a different unique file addition never produces conflicts. The only failure mode is a race on push timing, which the retry handles.

### Merge Retry Loop

When multiple agents finish tasks simultaneously and try to merge:

```bash
MAX_RETRIES=3
RETRY=0

while [ $RETRY -lt $MAX_RETRIES ]; do
  # Step 1: Rebase feature branch on latest main
  git checkout ai/<task-id>-<short-description>
  git fetch origin main
  git rebase origin/main

  # Step 2: Run tests AFTER rebase (critical — catches integration breaks)
  # <run project test suite>
  # If tests fail: STOP. Fix the issue before retrying.

  # Step 3: Merge to main (no-ff — always creates a merge commit)
  git checkout main
  git merge --no-ff ai/<task-id>-<short-description>

  # Step 4: Push
  git push origin main && break  # Success — exit loop

  RETRY=$((RETRY + 1))
  echo "Push rejected (attempt $RETRY/$MAX_RETRIES). Another agent merged first."

  # Reset main to match remote (abandon our local merge)
  git fetch origin main
  git reset --hard origin/main

  # Wait with jitter before retrying
  sleep $(echo "scale=0; $RANDOM % 10 + 5" | bc)
done
```

**Critical:** The test-after-rebase step is mandatory. If Agent A's merge changed code that Agent B depends on, Agent B must catch this before pushing.

### Merge Queue (Optional — for 4+ Agents)

For 4+ agents, merge collisions become frequent. Introduce a claim-based merge queue:

**File:** `.task-locks/merge-queue.json`
```json
{
  "currentlyMerging": {
    "taskId": "057",
    "agentId": "agent-alpha",
    "claimedAt": "2026-02-22T14:00:00Z"
  },
  "waiting": [
    { "taskId": "058", "agentId": "agent-beta", "requestedAt": "2026-02-22T14:00:05Z" }
  ]
}
```

**Protocol:**
1. Agent sets `currentlyMerging` to itself (commit + push to main, using retry loop for contention)
2. If `currentlyMerging` is already set by another agent, add self to `waiting` list
3. Perform merge + push
4. Clear `currentlyMerging`, notify next in queue (they detect on next poll)
5. Timeout: if `currentlyMerging` is stale (>5 minutes), reclaim

**For 2-3 agents:** Skip the merge queue. The retry loop is sufficient.

### Cross-Agent Task Handoff

When Agent A finishes implementation, it can hand off review to Agent B:

```
1. Agent A: Commit all implementation + lock update to feature branch
2. Agent A: Push feature branch to remote
   git push origin ai/<task-id>-<short-description>
3. Agent A: Update lock on feature branch:
   - workStage: AWAITING_REVIEW
   - implementedBy: "agent-alpha"
   - reviewedBy: null (available for pickup)
4. Agent A: Move on to next task

5. Agent B: Discover tasks awaiting review:
   - Fetch all remote branches
   - Read lock files from feature branches for AWAITING_REVIEW status
   git show origin/ai/<task-id>-...:task-locks/<task-id>.lock.json
6. Agent B: Perform review on the feature branch (read-only — no worktree needed)
7. Agent B: Commit review artifact + lock update on the feature branch
   - workStage: CODE_REVIEW_APPROVED (or CHANGES_REQUESTED)
   - reviewedBy: "agent-beta"
8. Agent B: Push feature branch
```

**Same pattern for QA:** After review approval, set `AWAITING_QA`. QA agent picks it up.

**Who merges?** Any agent can perform the final merge after QA passes. In the 3-agent configuration, a dedicated reviewer/QA agent handles all merges.

### Agent Configurations

#### 2-Agent Pipeline
```
agent-alpha: implement task A → implement task C → ...
agent-beta:  implement task B → implement task D → ...
               ↕ cross-review ↕
agent-alpha: review task B      review task D
agent-beta:  review task A      review task C
```

#### 3-Agent with Dedicated Reviewer
```
agent-alpha:  implement tasks (only)
agent-beta:   implement tasks (only)
agent-gamma:  review all → QA all → merge all (dedicated quality gate agent)
```

This is the **recommended** configuration for 3 agents. It eliminates merge contention (only gamma merges) and provides genuine independent review.

#### 4-5 Agents with Merge Queue
```
agent-alpha through agent-delta: implement tasks
agent-epsilon: dedicated reviewer/QA/merge coordinator
Merge queue: required to serialize merges
```

---

## Part 8: Stale Lock Detection & Reclamation

### Liveness Detection

Since all agents run on the same machine and use worktrees, use filesystem timestamps for liveness:

```bash
# Check when a worktree was last modified
stat -f "%m" /path/to/<task-id>-worktree/

# Or check for recent git activity on the feature branch
git log -1 --format="%ci" origin/ai/<task-id>-<short-description>
```

**An agent is presumed dead if:**
- Its worktree directory has not been modified in 15+ minutes, AND
- No new commits on its feature branch in 15+ minutes

### Lock Reclamation Protocol

**Only the Manager (or the user) may reclaim locks.** Worker agents never reclaim each other's locks.

```
1. Verify agent is dead (liveness check above)
2. Inspect the lock file for current workStage:

   If workStage == REFLECTION_COMPLETE:
     → Skip to final merge (Step 8).
     → Lowest risk — all quality gates and reflection are done.

   If workStage >= QA_PASSED:
     → Perform reflection, then final merge.
     → Low risk — work is complete and verified.

   If workStage >= CODE_REVIEW_APPROVED:
     → Assign QA to a different agent.
     → Update lock: agentId = new agent, append history entry.

   If workStage >= IMPLEMENTATION_COMPLETE:
     → Assign review to a different agent.
     → Update lock: agentId = new agent, append history entry.

   If workStage == IMPLEMENTATION_STARTED:
     → Assess partial work on the feature branch.
     → Option A: Reassign to a new agent who continues from the checkpoint.
     → Option B: Abandon the branch, remove the lock, start fresh.

3. Push updated lock to main.
4. New agent picks up from the reassigned stage.
```

### Stale Lock Cleanup

If a lock is reclaimed and the original work is abandoned:

```bash
# Remove the stale worktree (if it exists)
git worktree remove ../<task-id>-worktree 2>/dev/null || true
git worktree prune

# Delete the stale feature branch
git branch -D ai/<task-id>-<short-description> 2>/dev/null || true

# Remove or update the lock file on main
# (Manager decides: reassign or delete)
```

---

## Quick Reference: Common Commands

### Basic Operations
```bash
# Check for active locks
ls .task-locks/*.lock.json

# View lock file
cat .task-locks/<task-id>.lock.json

# Push lock acquisition (with retry)
git add .task-locks/<task-id>.lock.json && \
git commit -m "chore(lock): acquire <task-id>" && \
git push origin main
# If rejected: git fetch origin main && git rebase origin/main && git push origin main

# Create feature branch + worktree
git branch ai/<task-id>-<short-description> main && \
git worktree add ../<task-id>-worktree ai/<task-id>-<short-description> && \
cd ../<task-id>-worktree
```

### Multi-Agent Operations
```bash
# Discover tasks awaiting review (from any agent)
for branch in $(git branch -r | grep 'origin/ai/'); do
  git show "$branch":.task-locks/*.lock.json 2>/dev/null | grep -l AWAITING_REVIEW
done

# Check all active worktrees
git worktree list

# Check liveness of another agent's worktree
stat -f "%Sm" -t "%Y-%m-%d %H:%M" /path/to/<task-id>-worktree/

# Batch lock acquisition (Manager)
git add .task-locks/*.lock.json && \
git commit -m "chore(lock): acquire tasks <ids> for parallel execution" && \
git push origin main
```

### Worktree Operations (Required for All Agents)
```bash
# List all worktrees
git worktree list

# Create feature branch and worktree (after lock is pushed)
git branch ai/<task-id>-<short-description> main && \
git worktree add ../<task-id>-worktree ai/<task-id>-<short-description> && \
cd ../<task-id>-worktree

# Verify correct branch
git branch

# Clean up worktree after merge and push to remote
cd /path/to/main/repo && \
git fetch origin && \
git worktree remove ../<task-id>-worktree && \
git worktree prune && \
git branch -d ai/<task-id>-<short-description> && \
git fetch --prune
```

---

## Part 9: Manager Responsibilities

The Manager (human or AI agent orchestrating the workflow) has exclusive authority over these decisions:

- **Only the Manager may mark a task as COMPLETED** — and only after required quality gates are satisfied and the branch is merged to `main`.
- **Strict role delegation**: The Manager must never write code or perform code reviews itself. All code changes go to the **Coder** role; all reviews go to the **Code Reviewer** role.
- **Only the Manager (or the user) may reclaim stale locks.** Worker agents never reclaim each other's locks (see [Part 8](#part-8-stale-lock-detection--reclamation)).
- **Task selection**: Select the first eligible unblocked task — not completed, not locked, all prerequisites satisfied, belongs to current milestone.
- **Quality gate classification**: Inspect the branch diff to determine if code/tests changed. Code/test changes require review + QA. No-code/test changes may skip with recorded evidence (`git diff --name-only`).
- **Error escalation**: If code review or QA fails after 3+ iterations, review feedback patterns, consider architectural review or task clarification. If no eligible tasks are available, report blockers.

---

## See Also

- **Coder Role**: `roles/coder.md` – Implementation guidelines, handoff protocol
- **Code Review**: `roles/code_reviewer.md` – Code quality assessment, cross-agent review
- **QA Role**: `roles/qa_engineer.md` – Functional verification, cross-agent QA
- **Reflector Role**: `roles/reflector.md` – Post-task knowledge capture and skill extraction
- **Start Command**: `commands/start_or_continue_next_task.md` – Workflow entry point
