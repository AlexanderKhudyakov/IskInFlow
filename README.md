# IskInFlow

Agentic development workflow for software teams.

## English

IskInFlow is a workflow setup for software development powered by AI agents. It provides a structured way to plan, build, and iterate on features with agent assistance, keeping collaboration clear and delivery consistent. The framework is tech-stack agnostic: project-specific paths, tools, and code-style rules live in the host project (its root instructions and skills directory), never in IskInFlow itself. What a host must provide is specified in [`HOST_CONTRACT.md`](HOST_CONTRACT.md).

### How it works

Six roles cooperate through a git-anchored state machine. Coordination state lives in lock files (`.task-locks/`), pushed to the remote **before** any implementation starts — no orchestrator service required.

```
Planner                    Coder            Code Reviewer        QA Engineer         Reflector
idea → spec → plan   →   TDD on branch   →   read-only diff   →   authoritative   →   knowledge
(CRITICAL/STANDARD/        + worktree          review, fresh        test run,         extracted to
 DOCS_ONLY lanes)                               context              functional         host skills
                                                                     verification
        Manager — orchestrates: selection, gate classification, circuit breakers, merge
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
- **Mechanical enforcement**: `scripts/flow` (validate / transition / check-push / metrics) plus a git `pre-push` gate — the invariants are code, not prose.

### Commands

| Command | Use for |
| --- | --- |
| `commands/idea_to_dev_plan.md` | idea → product spec → tech spec (user approval gate) → development plan |
| `commands/start_or_continue_next_task.md` | select and run milestone tasks (full lane, multi-agent parallel) |
| `commands/quick_task.md` | small end-to-end requests (quick lane, `qt-` prefix) |
| `commands/process_retrospective.md` | periodic workflow retrospective driven by `flow metrics` |

### Observability

Lock histories are the workflow's event log. `scripts/flow metrics` reports lead time, rework share, and worst offenders from `.task-locks/completed/` — run it between milestones, and feed persistent problems to the retrospective.

## Русский

IskInFlow — это настройка рабочего процесса разработки ПО с поддержкой ИИ-агентов. Она помогает структурировать планирование, разработку и итерации над функциями, делая совместную работу прозрачной и стабильной. Фреймворк не привязан к стеку: проектно-специфичные пути, инструменты и правила код-стайла живут в host-проекте (его корневых инструкциях и каталоге skills), а не внутри IskInFlow. Требования к host-проекту — в [`HOST_CONTRACT.md`](HOST_CONTRACT.md).

Ключевые принципы: lock-first (владение задачей подтверждается пушем lock-файла в `main`), проверка всегда «чужим контекстом» (ревью — read-only, QA владеет единственным авторитетным прогоном тестов), автоматические предохранители (2 раунда правок — эскалация к пользователю), обязательная рефлексия с извлечением знаний, и механическое исполнение инвариантов через `scripts/flow` и git `pre-push` хук.
