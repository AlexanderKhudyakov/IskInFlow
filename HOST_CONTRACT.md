# Host Project Contract

IskInFlow is tech-stack agnostic. A **host project** adopts it by providing the
pieces below; IskInFlow never hardcodes paths, tools, or code style. If any
required piece is missing, agents must ask the user where it should live
instead of guessing.

## Required from the host

1. **Workflow locations** — where planning artifacts live (ideas, tech specs,
   development plans). Declared in the host's root instructions file
   (`CLAUDE.md` / `AGENTS.md`), e.g. a "Workflow locations" section.
2. **Skills directory** — the host's project-knowledge skills (architecture,
   conventions, how-tos) with an `_index.md` index. The reflector writes here.
   Recommended layout: a harness-neutral directory (e.g. `.agents/skills/`)
   exposed to each harness through symlinks (`.claude/skills` →
   `../.agents/skills`, `.zcode/skills` → `../.agents/skills`). IskInFlow's
   own `skills/` folder follows the same idea for workflow-level skills.
3. **Task coordination root** — `.task-locks/` at the repository root (locks,
   `completed/`, `artifacts/`). The `flow` CLI and the pre-push gate expect
   this path; override only by forking the scripts.
4. **Quality tooling declaration** — the host's root instructions must state
   the test command(s), linter, and build entry points the Coder and QA roles
   run. IskInFlow defines *who* runs them and *when*; the host defines *what*
   they are.
5. **Agent identity** — the user (or Manager) assigns stable `agentId`s
   (`agent-alpha`, `coder-opus5`, …). The `agentId` travels in every lock
   history entry.

## Harness adapters (optional but recommended)

IskInFlow is written harness-neutrally; each agent harness binds to it via its
own registration surface:

| Concern | Claude Code | ZCode |
| --- | --- | --- |
| Commands | `.claude/commands` → symlink to `IskInFlow/commands` | harness-specific command mapping |
| Guides / roles | read on demand from `IskInFlow/` | same |
| Workflow gates | `pre-push` hook (harness-independent, plain git) | same hook |
| Skills | `.claude/skills` symlink | `.zcode/skills` symlink |

The pre-push gate is harness-independent by construction: it is a git hook, so
every harness (and every human) pushing `ai/*` branches gets the same
enforcement. Install once per clone:
`ln -sf "$PWD/IskInFlow/scripts/pre-push.flow" .git/hooks/pre-push`.

## What IskInFlow provides

- `commands/` — entry points (`idea_to_dev_plan`, `start_or_continue_next_task`,
  `quick_task`, `process_retrospective`)
- `guides/` — `pipeline.md` (canonical stage/gate definition),
  `git_and_workflow_operations.md` (lock/branch/worktree mechanics),
  `mcp_first_tooling.md`
- `roles/` — manager, planner, coder, code_reviewer, qa_engineer, reflector
- `scripts/` — `flow` CLI (validate / new / transition / check-push / metrics)
  and the `pre-push.flow` git hook
- `templates/` — review, QA report, task file, review request/response
