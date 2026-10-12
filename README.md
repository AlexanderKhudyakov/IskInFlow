# IskInFlow

Agentic development workflow for software teams.

## English

IskInFlow is a workflow setup for software development powered by AI agents. It provides a structured way to plan, build, and iterate on features with agent assistance, keeping collaboration clear and delivery consistent. The framework is tech-stack agnostic: project-specific paths, tools, and code-style rules live in the host project (its root instructions and skills directory), never in IskInFlow itself. What a host must provide is specified in [`HOST_CONTRACT.md`](HOST_CONTRACT.md).

### How it works

Eight roles cooperate through a git-anchored state machine. Coordination state lives in lock files (`.task-locks/`), pushed to the remote **before** any implementation starts — no orchestrator service required.

```
Researcher — read-only evidence for every question (cited reports); feeds
             planning surveys, staffing, and gate classification

Planner                    Coder            Code Reviewer        QA Engineer         Reflector
idea → spec → plan   →   TDD on branch   →   read-only diff   →   authoritative   →   knowledge
(STANDARD/CRITICAL lanes)  + worktree          review, fresh        test run,         extracted to
                                               context; docs        functional         host skills
                                               review for DOCS
                                                                     verification
Tech Writer — owns the docs surface: implements DOCS changes; in MIXED documents
             final behavior after the coder (single mixed review, QA on the code portion)

        Manager — orchestrates: selection, staffing by change surface, gate classification, circuit breakers, merge
```

Stage machine (full definition: [`guides/pipeline.md`](guides/pipeline.md)):

```
IMPLEMENTATION_STARTED → IMPLEMENTATION_COMPLETE → review gate → QA gate
      → REFLECTION_COMPLETE → MERGED
```

- **Lock-first**: a task is owned only after its lock commit is on `main` and pushed.
- **Cross-context verification**: reviewer and QA always run in a context that did not write the code (subagent or separate agent); the reviewer is read-only, QA owns the only authoritative test run.
- **Circuit breakers**: 2 review rounds or 2 QA failures → escalate to the user, no round 3.
- **Mandatory reflection**: every task extracts reusable knowledge; skills indexes are pruned on a cadence.
- **Mechanical enforcement**: `scripts/flow` (validate / new / classify / transition / note / role / archive / check-push / metrics) plus a git `pre-push` gate — the invariants are code, not prose.

### Delegation mode

The default run since v2: one session drives the entire pipeline as the
**Manager** — the role marker is set once (`flow role set manager`) — while
implementation, review, QA, reflection, and research run as **role-profile
subagents** under their own contracts. Enforcement is layered: role contracts
(L0), the `role-guard` PreToolUse hook enforcing the active role's write
matrix from the marker (`<git-common-dir>/isk-role`; absent marker =
unrestricted; L1), and harness-native subagent tool restrictions where
supported (L2). Multi-agent top-level mode — separate named agents per role —
remains the alternative.

### Commands

| Command | Use for |
| --- | --- |
| `commands/idea_to_dev_plan.md` | idea → product spec → tech spec (user approval gate) → tracker-task decomposition (`blocked-by:` graph; no development-plan directory) |
| `commands/start_or_continue_next_task.md` | select and run tracker tasks (full lane, multi-agent parallel) |
| `commands/quick_task.md` | small end-to-end requests (quick lane, tracker ids; `qt-` names are legacy) |
| `commands/process_retrospective.md` | periodic workflow retrospective driven by `flow metrics` |

### Observability

Lock histories are the workflow's event log. `scripts/flow metrics` reports lead time, rework share, and worst offenders from `.task-locks/completed/` — run it between milestones, and feed persistent problems to the retrospective.

## Русский

IskInFlow — это настройка рабочего процесса разработки ПО с поддержкой ИИ-агентов. Она помогает структурировать планирование, разработку и итерации над функциями, делая совместную работу прозрачной и стабильной. Фреймворк не привязан к стеку: проектно-специфичные пути, инструменты и правила код-стайла живут в host-проекте (его корневых инструкциях и каталоге skills), а не внутри IskInFlow. Требования к host-проекту — в [`HOST_CONTRACT.md`](HOST_CONTRACT.md).

Ключевые принципы: lock-first (владение задачей подтверждается пушем lock-файла в `main`), проверка всегда «чужим контекстом» (ревью — read-only, QA владеет единственным авторитетным прогоном тестов), автоматические предохранители (2 раунда правок — эскалация к пользователю), обязательная рефлексия с извлечением знаний, и механическое исполнение инвариантов через `scripts/flow` и git `pre-push` хук.

С v2 ролей восемь: к Planner → Coder → Code Reviewer → QA → Reflector добавляются Researcher — read-only источник доказательств для любого вопроса (отчёты с цитатами; питает планирование, стаффинг и классификацию гейтов) — и Tech Writer, владелец docs-поверхности: реализует DOCS-изменения, в MIXED документирует итоговое поведение после кодера. Manager при укомплектовании исполнителей классифицирует поверхность изменений (DOCS → tech_writer + docs-ревью). Режим по умолчанию — **delegation**: одна сессия ведёт весь пайплайн как Manager (маркер роли ставится один раз — `flow role set manager`), а исполнение, ревью, QA, рефлексия и research выполняют ролевые сабагенты по своим контрактам; enforcement слоистый: L0 — ролевые контракты, L1 — PreToolUse-хук role-guard по маркеру роли (`<git-common-dir>/isk-role`; маркера нет — ограничений нет), L2 — штатные ограничения инструментов сабагентов, где харнесс их поддерживает. Альтернатива — multi-agent режим с отдельными именованными агентами.
