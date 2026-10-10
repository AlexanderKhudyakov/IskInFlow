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
4. **Task tracker** — `Tasks/` at the repository root: one folder per task,
   format defined in [`guides/task_tracker.md`](guides/task_tracker.md). All
   new tasks (including quick-lane ones) are registered here; the host
   provides `Tasks/new.sh` + `Tasks/validate.sh` helpers and wires the
   validator into its pre-commit hook.
5. **Quality tooling declaration** — the host's root instructions must state
   the test command(s), linter, and build entry points the Coder and QA roles
   run. IskInFlow defines *who* runs them and *when*; the host defines *what*
   they are.
6. **Agent identity** — the user (or Manager) assigns stable `agentId`s
   (`agent-alpha`, `coder-opus5`, …). The `agentId` travels in every lock
   history entry.
7. **Path-class map** — the host's root instructions declare which paths
   belong to which write class (DOCS, SKILLS, surface-neutral); every path
   matched by no class is CODE, so an incomplete map fails closed (only the
   coder writes there). Mechanically the framework ships
   `DEFAULT_PATH_CLASSES` — it works both in the framework repo and in
   typical hosts — and a host may override it with
   `.task-locks/path-classes.json` using the same schema:
   `{"neutral": [...], "skills": [...], "docs": [...]}`, glob patterns
   (`**` spans path segments, `*` stays within one), `!`-prefixed
   exclusions, unmatched → CODE. Consumers: `flow classify` and the
   role-guard (which reads the matrix via `flow role matrix`).
8. **Role-guard install** — the host registers a PreToolUse hook in EACH
   harness config, pointing at a thin shim that execs
   `IskInFlow/scripts/role-guard`. Worked example (KVGA): the shared shim
   `.agents/hooks/isk-role-guard.sh` — exits 0 when the clone or the guard
   script is missing (enforcement is accident prevention, never an outage
   source) — registered in both `.zcode/config.json` and
   `.claude/settings.json` with the tool matcher
   `Edit|Write|MultiEdit|NotebookEdit|Bash|WebSearch|WebFetch|mcp__`;
   registrations must stay in sync across harness configs (KVGA's sync
   rule: `.agents/rules/shared-agent-config.md`, checked by
   `.agents/check-links.sh`). Marker mechanics: the guard reads
   `<git-common-dir>/isk-role`; an absent marker means unrestricted
   (non-workflow sessions and humans are never policed). A non-empty
   `agent_type` in the hook payload (a subagent call) bypasses enforcement
   — in delegation mode the marker governs the top-level manager session
   only. Deny protocol: exit code 2 plus a one-line stderr message naming
   the violated rule and the role to delegate to; every deny is appended to
   `<git-common-dir>/isk-role.log`. ZCode trust-gate reality: a newly
   registered workspace hook stays inert until a session restart plus UI
   trust approval (`pending_trust`) — enforcement begins after that, and
   pre-merge (the guard script exists only on the feature branch) the shim
   degrades to exit 0 everywhere.

## Harness adapters (optional but recommended)

IskInFlow is written harness-neutrally; each agent harness binds to it via its
own registration surface:

| Concern | Claude Code | ZCode |
| --- | --- | --- |
| Commands | `.claude/commands` → symlink to `IskInFlow/commands` | `.zcode/commands` → symlink to `IskInFlow/commands` |
| Guides / roles | read on demand from `IskInFlow/` | same |
| Workflow gates | `pre-push` hook (harness-independent, plain git) | same hook |
| Skills | `.claude/skills` symlink | `.zcode/skills` symlink |
| Enforcement layer | L1 role-guard (PreToolUse) + L2 `tools:` frontmatter on `.claude/agents/*.md` | L1 role-guard (PreToolUse, after the trust gate approves the hook); executors L0-by-bypass (`agent_type` in the payload skips the guard) |

The pre-push gate is harness-independent by construction: it is a git hook, so
every harness (and every human) pushing `ai/*` branches gets the same
enforcement. Install once per clone:
`ln -sf "$PWD/IskInFlow/scripts/pre-push.flow" .git/hooks/pre-push`.

Enforcement layers: **L0** prompt-only (role-file non-negotiables), **L1**
the role-guard PreToolUse hook + role marker, **L2** harness-native tool
restriction. Coverage is stated honestly, not assumed: Claude Code gets
L1 + L2; ZCode gets L1 once its trust gate approves the hook, while subagent
(executor) tool calls carry a non-empty `agent_type` and bypass the guard —
L0-by-bypass; harnesses without hooks get L0 only. The role-guard install
step is requirement 8 above; the path classes it enforces are requirement 7.

## What IskInFlow provides

- `commands/` — entry points (`idea_to_dev_plan`, `start_or_continue_next_task`,
  `quick_task`, `process_retrospective`)
- `guides/` — `pipeline.md` (canonical stage/gate definition),
  `task_tracker.md` (host task-tracker format),
  `git_and_workflow_operations.md` (lock/branch/worktree mechanics),
  `mcp_first_tooling.md`
- `roles/` — manager, planner, coder, code_reviewer, qa_engineer, reflector
- `scripts/` — `flow` CLI (validate / new / classify / transition / note /
  role / archive / check-push / metrics), the `role-guard` PreToolUse
  enforcer, and the `pre-push.flow` git hook
- `templates/` — review, QA report, task file, tracker task, review request/response
