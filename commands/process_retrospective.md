# Command: Process Retrospective

## MCP-First Requirement
Before executing any step in this command, consult `guides/mcp_first_tooling.md`. Enumerate available MCP servers and tools, and prefer them for discovery, validation, and execution tasks.

## Purpose
Periodically analyze the workflow **itself** — not the code — using the lock-history event log, and propose concrete improvements to IskInFlow (or the host's process configuration). The framework debugs itself with its own data.

## Cadence
Run between milestones, after any task that needed a circuit-breaker escalation, or whenever the user asks. Do not run mid-task.

## Steps

### Step 1: Gather the data (Manager)
```bash
IskInFlow/scripts/flow metrics --limit 40        # lead time, rework share, worst offenders
IskInFlow/scripts/flow validate .task-locks      # schema drift check (errors = broken locks)
ls -t .task-locks/completed/*.lock.json | head -10   # most recent tasks for qualitative reading
```

### Step 2: Read for patterns (Manager or a fresh subagent)
For the last ~10 completed tasks, read the lock histories plus review/QA artifacts and look for **process** signals:
- repeated review-round topics (same class of finding recurring across tasks → missing rule or skill)
- QA failures caused by brief/premise errors (a planning problem, not an implementation problem)
- stages where agents guessed (missing or ambiguous guidance)
- stages whose artifacts nobody read (ceremony without signal)
- escalation events: what triggered them, whether the threshold is right

Distinguish one-off incidents from patterns (a pattern is ≥3 occurrences with a shared cause).

### Step 3: Propose changes (Manager)
Produce a short retrospective note — `.task-locks/artifacts/retrospective-<YYYY-MM-DD>.md` — with at most 5 proposals, each as: **observation** (with data or file references) → **proposed change** (specific file and edit) → **expected effect**. Prefer editing the framework over adding warnings: a rule that lives in `guides/pipeline.md`, a role file, or a `scripts/flow` check outlives a verbal instruction.

Candidate levers, in order of preference:
1. A mechanical check in `scripts/flow` (validation or gate)
2. A rule in `guides/pipeline.md` or a role file
3. A new/updated host skill (via the reflector)
4. A template adjustment

### Step 4: Apply and record (Manager)
- **Confirm proposals with the user** before applying any change to IskInFlow or host process files.
- Apply approved edits, then run the pipeline changes on the IskInFlow repository itself using the standard workflow (IskInFlow is developed with IskInFlow).
- Append a one-line entry to the retrospective note recording what was applied, so the next retrospective can check whether the change worked.

## Output
- `.task-locks/artifacts/retrospective-<YYYY-MM-DD>.md` with data summary and proposals
- (After user approval) applied framework/host process changes

## Notes
- Never propose a process change from a single anecdote; require the pattern threshold.
- Metrics without a decision are waste: every retrospective ends in either a proposal or an explicit "no change needed".
- If `flow validate` reports errors on recent locks, fixing the drift takes priority over new proposals.
