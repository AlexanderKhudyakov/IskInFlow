# Command: Idea to Development Plan

## MCP-First Requirement
Before executing any step in this command, consult `guides/mcp_first_tooling.md`. The rule binds the **planner subagent** — it runs the technology-selection lookups. The **Manager itself must not** use network or `mcp__*` tools at all: they are denied to the manager role; it orchestrates and verifies through delegation only.

## Purpose
Convert a raw idea into a product spec, a technical spec, and a task decomposition registered in the host task tracker. Research runs through **researcher-profile subagents**; the decomposition lands as tracker tasks with a `blocked-by:` dependency graph — **not** as a development-plan directory (planning artifacts live in the tracker per `guides/task_tracker.md`; existing `<tech-spec-name>_development_plan/` directories are legacy and are never created anew).

## Session Shape (Manager)
This session runs as the **Manager**: set the role marker once at start with
`IskInFlow/scripts/flow role set manager --agent <agentId>` — delegation mode,
with hat-switch fallback (`IskInFlow/scripts/flow role set <role>`) when no
delegation runtime exists; absent marker = unrestricted. The Manager
orchestrates and verifies — it never authors the specs itself, never
researches, and never registers the tasks by hand. **The user approval gate
between Phase 2 and Phase 3 is unchanged**: the Manager presents the specs;
the user decides.

## Inputs
- Idea description or idea file path
- Short name for the idea (used in filenames)

## Steps
1. **Phase 1 — Product Analysis (researcher → planner)**: dispatch
   **researcher-profile subagents** (per `roles/researcher.md`) to survey the
   project for the facts Phase 1 needs — current state, affected surfaces,
   prior art, users of the feature; reports carry `file:line` citations.
   Then run a **planner-profile subagent** following `roles/planner.md`
   Phase 1, consuming those reports, to produce `<idea-short-name>_idea.md`.
   The spec cites the researcher reports as its source of facts — the planner
   does not read the codebase to build the survey, and the Manager never
   does.
2. **Phase 2 — Technical Specification (researcher → planner)**: same
   research layer for the technical questions (codebase structure, existing
   patterns, technology comparison). Then run the planner-profile subagent
   following `roles/planner.md` Phase 2 to produce
   `<idea-short-name>_tech_spec.md` based on the product spec, citing the
   researcher reports for every factual claim that needed evidence.
3. **Approval gate (user)**: present the product spec and tech spec (executive summaries plus key decisions) to the user and **wait for explicit approval**. Do not start task breakdown on an unapproved spec; incorporate requested changes and re-confirm.
4. **Phase 3 — Task Breakdown (planner/tech_writer subagent)**: follow
   `roles/planner.md` Phase 3 — register the decomposition as **tasks in the
   host task tracker**. The executor is a **tech_writer- or planner-profile
   subagent** (never the Manager): one `Tasks/new.sh <type> <slug> "Title"`
   call per task; each tracker task gets `spec:` → the approved tech spec,
   `blocked-by:` from the dependency graph, `tags`, and a priority; the body
   carries `## Описание` + `## Критерии готовности` per the tracker format
   (`guides/task_tracker.md`). Validate with the host's `Tasks/validate.sh`.

## Output Location
All artifacts **must** be placed in the host project's documented workflow locations. **The host project defines these locations in its root instructions file** (`CLAUDE.md` / `AGENTS.md` — look for a "Workflow locations" or similar section; see `HOST_CONTRACT.md`); read it before creating any files. The docs artifacts follow this structure, rooted wherever the host project keeps them (`<docs-root>` below):

```
<docs-root>/
├── ideas/
│   └── <idea-short-name>_idea.md
└── tech-specs/
    └── <idea-short-name>_tech_spec.md
```

The task decomposition produces **no directory under `<docs-root>`**: it lands as tracker tasks (`Tasks/NNNN-<slug>/task.md`), with `blocked-by:` encoding the dependency graph and priorities marking the execution order. A host on older conventions may still hold `<tech-spec-name>_development_plan/` directories — those are legacy, not migrated forcibly; this command never creates new ones.

Never place these artifacts in the repository root. If the host's root instructions do not define the locations, ask the user where they should live before proceeding.

## Output
- `<docs-root>/ideas/<idea-short-name>_idea.md`
- `<docs-root>/tech-specs/<idea-short-name>_tech_spec.md`
- Tracker tasks `Tasks/NNNN-<slug>/task.md` with `spec:` → the tech spec, `blocked-by:` dependency chains, `tags`, priorities; `Tasks/validate.sh` green

## Notes
- If any required input is missing or ambiguous, ask for clarification before proceeding.
- Reuse existing files if they already exist, and only update what is necessary.
- Check the host project's existing docs folder structure before creating files to stay consistent with the repository conventions.
- Researcher reports live at `.task-locks/artifacts/<task-id>/research-*.md`
  when the pipeline runs under a task lock; pre-lock surveys return in the
  researcher's response and are cited from there (`roles/researcher.md`).
