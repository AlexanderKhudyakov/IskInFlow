# Command: Idea to Development Plan

## MCP-First Requirement
Before executing any step in this command, consult `guides/mcp_first_tooling.md`. The rule binds the **planner subagent** — it runs the technology-selection lookups. The **Manager itself must not** use network or `mcp__*` tools at all: they are denied to the manager role; it orchestrates and verifies through delegation only.

## Purpose
Convert a raw idea into a product spec, technical spec, and detailed development plan.

## Session Shape (Manager)
This session runs as the **Manager**: set the role marker once at start with
`IskInFlow/scripts/flow role set manager --agent <agentId>` — delegation mode,
with hat-switch fallback (`IskInFlow/scripts/flow role set <role>`) when no
delegation runtime exists; absent marker = unrestricted. Phases 1–3 execute
as **planner-profile subagents** (per `roles/planner.md`); a planner may
dispatch researcher-profile subagents for large codebase surveys and keeps
small direct lookups itself. The Manager orchestrates and verifies — it never
authors the specs or plans itself. **The user approval gate between Phase 2
and Phase 3 is unchanged**: the Manager presents the specs; the user decides.

## Inputs
- Idea description or idea file path
- Short name for the idea (used in filenames)

## Steps
1. **Phase 1 — Product Analysis**: Follow `roles/planner.md` Phase 1 to produce `<idea-short-name>_idea.md`.
2. **Phase 2 — Technical Specification**: Follow `roles/planner.md` Phase 2 to produce `<idea-short-name>_tech_spec.md` based on the product spec.
3. **Approval gate (user)**: present the product spec and tech spec (executive summaries plus key decisions) to the user and **wait for explicit approval**. Do not start task breakdown on an unapproved spec; incorporate requested changes and re-confirm.
4. **Phase 3 — Task Breakdown**: Follow `roles/planner.md` Phase 3 to produce `<tech-spec-name>_development_plan/` with milestones and task files.

## Output Location
All artifacts **must** be placed in the host project's documented workflow locations. **The host project defines these locations in its root instructions file** (`CLAUDE.md` / `AGENTS.md` — look for a "Workflow locations" or similar section; see `HOST_CONTRACT.md`); read it before creating any files. The artifacts follow this structure, rooted wherever the host project keeps them (`<docs-root>` below):

```
<docs-root>/
├── ideas/
│   └── <idea-short-name>_idea.md
├── tech-specs/
│   └── <idea-short-name>_tech_spec.md
└── <tech-spec-name>_development_plan/
    ├── 01_<milestone>/
    │   ├── <NNN>_<task>.md
    │   └── ...
    ├── 02_<milestone>/
    │   └── ...
    └── ...
```

Never place these artifacts in the repository root. If the host's root instructions do not define the locations, ask the user where they should live before proceeding.

## Output
- `<docs-root>/ideas/<idea-short-name>_idea.md`
- `<docs-root>/tech-specs/<idea-short-name>_tech_spec.md`
- `<docs-root>/<tech-spec-name>_development_plan/` directory with milestone/task structure

## Notes
- If any required input is missing or ambiguous, ask for clarification before proceeding.
- Reuse existing files if they already exist, and only update what is necessary.
- Check the host project's existing docs folder structure before creating files to stay consistent with the repository conventions.
