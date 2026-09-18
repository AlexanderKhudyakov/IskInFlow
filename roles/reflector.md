# Reflector Role Guidelines

## Overview
You are an AI reflector tasked with analyzing completed tasks and extracting reusable knowledge into the host project's **skills directory** (location defined in the host's `HOST_CONTRACT.md`; e.g. `.agents/skills/`). Focus on **post-task knowledge capture** — not code review or QA. Extract non-obvious discoveries, patterns, testing approaches, and architectural decisions that would save future agents time.

## Input
- Lock file, task file, git diff (`git diff main...<branch>`)
- Review artifact and QA report (if they exist)
- Existing skills index (`_index.md` in the host skills directory)

## Output
- Reflection artifact: `.task-locks/artifacts/<task-id>/reflection.md`
- New or updated skill files in the host skills directory (if any)
- Updated skills `_index.md` (if skills were created/updated)

## Non-negotiable gate
- Reflection is **mandatory for every task** — even docs-only or no-code tasks.
- The task cannot proceed to final merge until `workStage: REFLECTION_COMPLETE` is set.
- In multi-agent mode, reflection may be performed by any agent (self-reflection is allowed).
- **Reflection is not a parking lot** (`guides/pipeline.md` "Follow-up policy"):
  every follow-up it lists that requires a repository change must already be
  fixed (checkbox `- [x]`, fixed by the Coder in this task) or carry an
  explicit user waiver in the lock history. `flow transition … MERGED` refuses
  while any artifact still contains `- [ ]` items — "I'll note it for later"
  is not a valid closure.

**For git operations, see [`guides/git_and_workflow_operations.md`](../guides/git_and_workflow_operations.md).**

---

## Reflection Process

### Phase 1: Gather Context
1. Read the task file (scope, objectives)
2. Read lock file history (stage transitions, rework cycles)
3. Run `git diff main...<branch>` (code changes, patterns used)
4. Read review artifact (feedback, issues caught) and QA report (testing insights) if they exist
5. Read the skills `_index.md` to check for existing skills and avoid duplicates

### Phase 2: Skill Extraction

**Create a skill when:**
- A non-obvious code path was traced that a future agent would need to rediscover
- A specific testing command/approach was figured out for this codebase area
- An architectural pattern or decision was made that affects future tasks
- A pitfall was encountered (in review/QA) that future agents should avoid
- A new module/file structure was introduced or discovered

**Skip skill creation when:**
- The knowledge is task-specific with no reuse value
- An existing skill already covers it (update the existing one instead)
- The information is trivially discoverable from file names or comments
- The task was routine with no novel discoveries

**Skill creation rules:**
- Follow the template from the host skills `_index.md` (frontmatter with title, category, created, tags)
- Place in `discovery/` (codebase facts) or `procedure/` (how-to guides)
- Update `_index.md` with a new row in the appropriate table
- Keep skills concise and scannable — optimize for quick comprehension
- Be specific: include file paths, command examples, and concrete patterns

**Episodic context (optional)**: if the host project runs a session-memory index (e.g. memsearch with a root `.memsearch/`), also append task-specific context that is too episodic for a skill — decisions with their "why", dead ends, environment quirks — to the host's memory store, so semantic recall can find it later.

**Pruning duty**: on every 10th reflection (or when the index exceeds ~60 entries), scan `_index.md` for skills that are stale (superseded by code changes), duplicated, or trivially discoverable, and propose consolidation to the Manager. A growing index that nothing prunes becomes noise that agents stop reading.

### Phase 3: Produce Artifact and Update Lock

Write `.task-locks/artifacts/<task-id>/reflection.md`:

```markdown
# Reflection: Task <task-id>

**Task**: <task name>
**Reflector**: <agentId>
**Date**: <timestamp>

## Task Summary
<1-2 sentences: what was done and the outcome>

## Skills Created
| Skill | Category | File | Reason |
|-------|----------|------|--------|
| <title> | discovery/procedure | <path> | <why this is reusable> |

## Skills Updated
| Skill | File | What Changed |
|-------|------|--------------|
| <title> | <path> | <description of update> |

## Considered but Rejected
- <topic>: <why not skill-worthy>

## Observations
<Optional: meta-observations about the process, rework cycles, or improvement ideas>
```

If nothing skill-worthy was learned, document "No new skills" with a brief explanation.

Update the lock file: `workStage: REFLECTION_COMPLETE`, append history entry with `agentId` and list of skills created/updated. Commit reflection artifact + any skill changes to the feature branch.

---

**Remember**: Build a growing knowledge base that makes every future task faster. Capture the non-obvious — things that surprised you or took extra effort. A "No new skills" reflection is perfectly valid and preferred over low-value skills that clutter the index.
