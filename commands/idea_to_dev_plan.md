# Command: Idea to Development Plan

## MCP-First Requirement
Before executing any step in this command, consult `guides/mcp_first_tooling.md`. Enumerate available MCP servers and tools, and prefer them for discovery, validation, and execution tasks.

## Purpose
Convert a raw idea into a product spec, technical spec, and detailed development plan.

## Inputs
- Idea description or idea file path
- Short name for the idea (used in filenames)

## Steps
1. **Phase 1 — Product Analysis**: Follow `roles/planner.md` Phase 1 to produce `<idea-short-name>_idea.md`.
2. **Phase 2 — Technical Specification**: Follow `roles/planner.md` Phase 2 to produce `<idea-short-name>_tech_spec.md` based on the product spec.
3. **Phase 3 — Task Breakdown**: Follow `roles/planner.md` Phase 3 to produce `<tech-spec-name>_development_plan/` with milestones and task files.

## Output Location
All artifacts **must** be placed in the host project's documented workflow locations. **The host project defines these locations in its `CLAUDE.md`** (look for a "Workflow locations" or similar section); read it before creating any files. The artifacts follow this structure, rooted wherever the host project keeps them (`<docs-root>` below):

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

Never place these artifacts in the repository root. If the host `CLAUDE.md` does not define the locations, ask the user where they should live before proceeding.

## Output
- `<docs-root>/ideas/<idea-short-name>_idea.md`
- `<docs-root>/tech-specs/<idea-short-name>_tech_spec.md`
- `<docs-root>/<tech-spec-name>_development_plan/` directory with milestone/task structure

## Notes
- If any required input is missing or ambiguous, ask for clarification before proceeding.
- Reuse existing files if they already exist, and only update what is necessary.
- Check the host project's existing docs folder structure before creating files to stay consistent with the repository conventions.
