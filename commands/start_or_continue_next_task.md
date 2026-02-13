# Command: Start or Continue Next Task

## Purpose
Prefer continuing unfinished work: **if any task is already in progress (an ACTIVE lock exists), the agent MUST resume it rather than starting a new task**.

Otherwise, select the next available task and start implementation using the manager workflow.

This command is intentionally strict: **every task MUST go through code review and QA**. A task is only considered **COMPLETED** after the reviewed+QA-verified branch is **merged to `main`**.

## Steps
0. **Manager: Resume-first rule (mandatory)**
   - Look for any existing `.task-locks/<task-id>.lock.json` with `status: ACTIVE`.
   - If one exists, **resume that task** (summarize progress + current `workStage`) and do not start a new task.
   - If multiple ACTIVE locks exist, stop and ask for clarification (or resolve according to an explicit project policy) before proceeding.
1. **Manager: Select & lock** (see `roles/manager.md`)
   - Load the current milestone task list.
   - Select the first eligible unblocked task.
   - Check for existing lock file; resume if present, otherwise lock the task.
   - Create a feature branch using the required prefix `codex/`.
   - Initialize lock file state (`status: ACTIVE`, `workStage: IMPLEMENTATION_STARTED`).
2. **Coder: Implement with TDD** (see `roles/coder.md`)
   - Implement the task using TDD.
   - Keep tests green and update the lock file with checkpoints.
   - When ready, transition lock file to `workStage: CODE_REVIEW_REQUESTED`.
3. **Code Review (mandatory, never skip)** (see `roles/code_reviewer.md`)
   - Produce a review artifact: `<output-folder>/<task-number>-review.md`.
   - If review requests changes, coder must fix and re-request review.
   - Only when review status is **APPROVED** can the task proceed.
   - Transition lock file to `workStage: CODE_REVIEW_APPROVED`.
4. **QA Verification (mandatory, never skip)** (see `roles/qa_engineer.md`)
   - QA MUST be run only on the **refined branch/commit that incorporates all review feedback**.
   - QA produces: `<output-folder>/<task-number>-qa-report.md`.
   - QA failures loop back to coder (and may require re-review).
   - Transition lock file to `workStage: QA_PASSED` only on PASS.
5. **Merge (mandatory gate)** (see `roles/manager.md`)
   - Only merge when `CODE_REVIEW_APPROVED` and `QA_PASSED` are both true.
   - Transition lock file to `workStage: MERGED` and record merge commit.
6. **Mark task completed (only after merge)**
   - Only after merge to `main`, set `status: COMPLETED` and archive/release the lock file.

## Output
- Task selection summary
- `.task-locks/<task-id>.lock.json` updated/created (with append-only transition history)
- Feature branch with implemented changes
- Code review report (mandatory)
- QA report (mandatory)
- Merge info recorded in lock file

## Notes
- If no eligible task is found, report blockers and recommend the next action.
- If resuming, summarize prior progress **and current workStage** before continuing.
- **Never** mark a task completed based on “implementation finished”. Completion requires: review ✅ + QA ✅ + merge ✅.
