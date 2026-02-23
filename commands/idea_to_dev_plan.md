# Command: Idea to Development Plan

## MCP-First Requirement
Before executing any step in this command, consult `guides/mcp_first_tooling.md`. Enumerate available MCP servers and tools, and prefer them for discovery, validation, and execution tasks.

## Purpose
Convert a raw idea into a product spec, technical spec, and detailed development plan.

## Inputs
- Idea description or idea file path
- Short name for the idea (used in filenames)

## Steps
1. **Product Manager**: Follow `roles/product_manager.md` to produce `<idea-short-name>_idea.md`.
2. **Tech Lead**: Follow `roles/tech_lead.md` to produce `<idea-short-name>_tech_spec.md` based on the product spec.
3. **Task Planner**: Follow `roles/task_planner.md` to produce `<tech-spec-name>_development_plan/` with milestones and task files.

## Output Location
All artifacts **must** be placed in the repository's `docs/` folder, following the established structure:

```
docs/
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

- **Product specs** → `docs/ideas/`
- **Technical specs** → `docs/tech-specs/`
- **Development plans** → `docs/<tech-spec-name>_development_plan/`

Never place these artifacts in the repository root.

## Output
- `docs/ideas/<idea-short-name>_idea.md`
- `docs/tech-specs/<idea-short-name>_tech_spec.md`
- `docs/<tech-spec-name>_development_plan/` directory with milestone/task structure

## Notes
- If any required input is missing or ambiguous, ask for clarification before proceeding.
- Reuse existing files if they already exist, and only update what is necessary.
- Check the existing `docs/` folder structure before creating files to stay consistent with the repository conventions.
