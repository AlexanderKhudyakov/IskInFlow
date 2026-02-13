# Command: Idea to Development Plan

## Purpose
Convert a raw idea into a product spec, technical spec, and detailed development plan.

## Inputs
- Idea description or idea file path
- Short name for the idea (used in filenames)

## Steps
1. **Product Manager**: Follow `roles/product_manager.md` to produce `<idea-short-name>_idea.md`.
2. **Tech Lead**: Follow `roles/tech_lead.md` to produce `<idea-short-name>_tech_spec.md` based on the product spec.
3. **Senior Engineer**: Follow `roles/senior_engineer.md` to produce `<tech-spec-name>_development_plan/` with milestones and task files.

## Output
- `<idea-short-name>_idea.md`
- `<idea-short-name>_tech_spec.md`
- `<tech-spec-name>_development_plan/` directory with milestone/task structure

## Notes
- If any required input is missing or ambiguous, ask for clarification before proceeding.
- Reuse existing files if they already exist, and only update what is necessary.
