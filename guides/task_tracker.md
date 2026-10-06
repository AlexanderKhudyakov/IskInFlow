# Task Tracker Format

Canonical definition of the host task tracker: the registry where all work
items (bugs, features, improvements, research) are described and tracked.
The default host location is `Tasks/` at the repository root (declared in the
host's root instructions per `HOST_CONTRACT.md`); this guide is the single
source of truth for the format. The host's `Tasks/README.md` is an operational
cheat sheet that links here.

## Division of responsibilities

| System | Owns | Linked from a task via |
| --- | --- | --- |
| Task tracker (`Tasks/`) | Registry + description of every task: **what** and **why** | — |
| `.task-locks/` | **Execution**: lock files (stages, ownership, merge) and pipeline execution artifacts — review/QA/reflection reports | `lock:` |
| Host docs (e.g. `Docs/packages/`) | Specs: ideas, tech specs, development plans | `spec:` |

The tracker status is high-level: while a task is being executed it is simply
`in-progress`; lock-internal stages (review gate, QA gate) are never duplicated
into `task.md`.

### Coexistence with the pipeline

- **All new tasks live in the tracker** — including small ones that previously
  existed only as `qt-` briefs. Tasks are never created directly in
  `.task-locks/`.
- The **quick lane** (`commands/quick_task.md`) plans work as a tracker task
  (`Tasks/NNNN-<slug>/task.md` is the planning artifact). Locks and pipeline
  artifacts (review, QA, reflection) still live in `.task-locks/`. When work
  starts, the task's `branch:` and `lock:` fields are filled in.
- The **full lane** (`start_or_continue_next_task`) keeps its planning
  artifacts in development plans; the tracker task holds the registry entry
  and links the plan via `spec:`. The registry entry is created at task
  selection, set `in-progress` at lock acquisition, `review` at final merge,
  and `done` when the user accepts the result.
- Historical `qt-` briefs and numbered plan tasks are legacy; they are not
  migrated forcibly.

## Layout

```
Tasks/
├── README.md            ← host cheat sheet (links here)
├── new.sh               ← create a task (next id + template)
├── validate.sh          ← format validation (run by hand and from pre-commit)
├── _template/task.md    ← template
├── 0001-<slug>/         ← one task = one folder
│   ├── task.md          ← the only mandatory file
│   ├── attachments/     ← optional, created when needed
│   └── comments/        ← optional, one file per comment
│       └── 001-<slug>.md
└── 0002-<slug>/…
```

Naming rules:

- Folder: `NNNN-slug` — a 4-digit zero-padded number plus a slug of lowercase
  latin letters, digits, and hyphens.
- `id` = the folder number: zero-padded in the **folder name** (`0008`),
  plain in the **`id` field** (`8` — leading zeros can parse as octal in
  YAML 1.1, e.g. `0010` → 8).
- Ids are sequential, monotonically growing, **never reused**. Next id =
  max existing + 1 (`new.sh` does this). Tracker ids are independent of any
  historical numbering (plan-task locks, `qt-` names).
- Task folders are **never deleted**: finished or abandoned work closes via
  `done` / `cancelled` (deleting a folder silently frees its id for reuse —
  `new.sh` takes max-existing + 1). Archival needs are met by the task's own
  record, not by removal.
- Field values (`type`, `status`, …) are latin (grep-friendly); free text
  (title, description, comments) follows the host's language convention.
- `task.md` is the only mandatory file; `attachments/` and `comments/` are
  created only when there is material for them.

## `task.md` schema

Required frontmatter fields:

| Field | Type | Notes |
| --- | --- | --- |
| `id` | int | Unique, equals the folder number (no leading zeros) |
| `title` | string | One line, quoted (double `'` inside single-quoted YAML) |
| `type` | enum | See types below |
| `status` | enum | See statuses below |
| `created` | date | `YYYY-MM-DD` |
| `updated` | date | bumped on any change to the task (fields, body, comment) |

Optional fields:

| Field | Type | Notes |
| --- | --- | --- |
| `priority` | `P0..P3` | Default `P2`. Always uncommented in the template — otherwise grep overviews lose it |
| `closed` | date | Set at `done` / `cancelled` |
| `resolution` | enum | `fixed` \| `done` at `done`; `wont-fix` \| `duplicate` \| `obsolete` at `cancelled`. Forbidden otherwise. For `duplicate`, link the original in `relates-to` |
| `assignee` | string | Owner |
| `tags` | [string] | Topics for queries |
| `blocked-by` | [int] | Task ids this task waits on |
| `relates-to` | [int] | Related tasks (duplicates, prior history) |
| `branch` | string | Execution branch — always the lane's pattern: `ai/qt-<short-name>` (quick lane) or `ai/<NNN>-<desc>` with the plan-task number (full lane) |
| `lock` | string | Lock path — real patterns: `.task-locks/qt-<name>.lock.json` (quick lane) or `.task-locks/<NNN>.lock.json` (plan tasks). Completed locks move to `.task-locks/completed/`; the field records the lock at execution time and need not be updated |
| `spec` | string | Path to the spec/plan in host docs (the output of research tasks). Points at the **current** spec location — completed work graduates to the docs archive, update the link then |
| `env` | map | Bugs only: reproduction environment |

`env` example:

```yaml
env:
  os: iOS 26.1
  build: 1.4.2 (318)
  device: iPhone 16 Pro (simulator)
```

## Types

| Type | Meaning | Mandatory body output |
| --- | --- | --- |
| `bug` | Wrong existing behavior | `## Шаги воспроизведения` + actual/expected |
| `feature` | New user-facing functionality | `## Критерии готовности` |
| `improvement` | Polishing existing behavior (UX, performance), nothing new | `## Критерии готовности` |
| `task` | Other work: infrastructure, refactoring, organization | `## Критерии готовности` |
| `product-research` | Do we need this, and how should it work | `## Открытые вопросы` + `## Результат`; spec in host ideas docs (`spec:`) |
| `tech-research` | How to implement it | `## Открытые вопросы` + `## Результат`; tech spec (`spec:`) |

`## Описание` is mandatory for every type. There is **no** attachments
section: files from `attachments/` are referenced in place with relative
links.

Adding a new type means editing **three places**: this guide, the host's
`new.sh` (type whitelist), and the host's `validate.sh` (enum + per-type body
sections) — plus the host's template if new body sections appear.

## Statuses and transitions

| Status | Meaning |
| --- | --- |
| `draft` | Being written |
| `open` | Ready to take (description complete) |
| `in-progress` | Taken (`assignee`; `branch`/`lock` for dev work) |
| `blocked` | Blocked |
| `review` | Execution complete (merged, when run through the pipeline); result awaits **product acceptance** by the requester. This is not the lock's code review / QA — those stay in the lock |
| `done` | Finished. Terminal; a regression of a closed task is a new task with `relates-to` to the original |
| `cancelled` | Will not be done. Terminal |

Transitions:

| From | To | When |
| --- | --- | --- |
| `draft` | `open` | Description complete |
| `open` | `in-progress` | Taken |
| `draft`, `open`, `in-progress` | `blocked` | Blocker is a tracker task: non-empty `blocked-by:` with existing ids. Blocker is external (no tracker task): leave `blocked-by:` empty and add a reason comment `comments/NNN-blocked-<slug>.md` |
| `blocked` | `open` / `in-progress` / `review` | Unblocked — return to the previous status (incl. `review` for blockers found at acceptance) |
| `in-progress` | `review` | Execution complete, handed over for acceptance |
| `review` | `done` | Accepted: `closed` + `resolution` (`fixed` for bugs, `done` otherwise) |
| `review` | `in-progress` | Sent back for rework |
| `in-progress` | `open` | Executor returned the task to the queue |
| `review` | `blocked` | A blocker surfaced at acceptance |
| any but `done` | `cancelled` | `closed` + `resolution` (`wont-fix`/`duplicate`/`obsolete`; original in `relates-to` for duplicates) |

## Comments

One comment = one file `comments/NNN-<slug>.md` (`NNN` — next sequential number
in the folder, `001`, `002`, …):

```markdown
---
author: alex
date: 2026-10-06
kind: comment        # comment | decision
---

Comment text.
```

`kind: decision` records a **binding decision** (usually the user's). Decisions
are mandatory to follow and are revisited only by a new decision comment —
never by editing an old one. Comments are append-only: replies are new files.

Special naming: a comment explaining an **external blocker** is named
`NNN-blocked-<slug>.md` (see the `blocked` transition) — the validator looks
for exactly this pattern when `blocked-by:` is empty.

## Attachments

Files live in `attachments/` and are referenced with relative links from
`task.md` or comments. Videos and screenshots are the primary bug material;
files are committed. Videos heavier than ~10 MB are not committed — link them
externally (Cloud, iCloud) in the description or a comment.

## Tooling

The host provides:

- `Tasks/new.sh <type> <slug> ["Title"]` — creates the next-numbered task from
  the template;
- `Tasks/validate.sh [folder…]` — format gate: required fields, closed YAML
  frontmatter (tasks and comments), enum values, `type`×`resolution`,
  id↔folder match and global id uniqueness, no stray entries under `Tasks/`
  (every folder is `NNNN-slug`), body sections — `## Описание` for every type
  plus the per-type ones (for non-`draft`/`cancelled`) and each mandatory
  section must be non-empty (template placeholders don't count),
  `blocked-by`/`relates-to` must reference existing ids (self-references
  rejected; `resolution: duplicate` requires `relates-to`), `env` only on
  `bug`, comment numbering sequential without gaps, `closed`+`resolution` on
  closure (and forbidden
  elsewhere), non-empty `blocked-by` or a blocking comment, `YYYY-MM-DD`
  dates with `updated`/`closed` ≥ `created`, comment file names and
  frontmatter. Hosts are encouraged to wire it into the pre-commit hook
  (trigger on staged `Tasks/` paths).

## Query recipes

```bash
grep -l -E '^status: (open|in-progress|blocked|review)' Tasks/*/task.md   # open + wip
grep -l '^type: bug' Tasks/*/task.md                                        # bugs
grep -H -E '^(id|title|type|status|priority):' Tasks/*/task.md              # overview
```
