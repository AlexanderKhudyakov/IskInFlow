# Command: Process Retrospective

## MCP-First Requirement
Before executing any step in this command, consult `guides/mcp_first_tooling.md`. MCP and network tools belong to the **executor subagents**: the reflector and researcher profiles use them per their own role contracts. The **Manager itself must not** — network and `mcp__*` tools are denied to the manager role; it works through delegation only.

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
Read `IskInFlow/scripts/flow role log` alongside the lock histories — the role-switch and deny audit log; reviewing its false positives is a standing retrospective item. For the last ~10 completed tasks, read the lock histories plus review/QA artifacts and look for **process** signals:
- repeated review-round topics (same class of finding recurring across tasks → missing rule or skill)
- QA failures caused by brief/premise errors (a planning problem, not an implementation problem)
- stages where agents guessed (missing or ambiguous guidance)
- stages whose artifacts nobody read (ceremony without signal)
- escalation events: what triggered them, whether the threshold is right

Distinguish one-off incidents from patterns (a pattern is ≥3 occurrences with a shared cause). Substantive repo questions raised by the reading go to researcher dispatch — the Manager does not research.

### Step 3: Propose changes (reflector subagent, from the Manager's outline)
The Manager drafts the outline; a **reflector-profile subagent** authors the retrospective note — `.task-locks/artifacts/retrospective-<YYYY-MM-DD>.md` — with at most 5 proposals, each as: **observation** (with data or file references) → **proposed change** (specific file and edit) → **expected effect**. The Manager writes no files. Prefer editing the framework over adding warnings: a rule that lives in `guides/pipeline.md`, a role file, or a `scripts/flow` check outlives a verbal instruction.

Candidate levers, in order of preference:
1. A mechanical check in `scripts/flow` (validation or gate)
2. A rule in `guides/pipeline.md` or a role file
3. A new/updated host skill (via the reflector)
4. A template adjustment

### Step 4: Dispatch and record (Manager)
- **Confirm proposals with the user** before applying any change to IskInFlow or host process files.
- Dispatch approved edits to the **surface-owning role**: docs findings → tech_writer rounds, code findings → coder rounds. Framework self-development runs through the standard lock pipeline (`flow new --surface`, branch, gates) — IskInFlow is developed with IskInFlow, and the Manager applies nothing by hand.
- Have the dispatched round append a one-line entry to the retrospective note recording what was applied, so the next retrospective can check whether the change worked.

## Output
- `.task-locks/artifacts/retrospective-<YYYY-MM-DD>.md` with data summary and proposals
- (After user approval) applied framework/host process changes

## Notes
- Never propose a process change from a single anecdote; require the pattern threshold.
- Metrics without a decision are waste: every retrospective ends in either a proposal or an explicit "no change needed".
- If `flow validate` reports errors on recent locks, fixing the drift takes priority over new proposals.
