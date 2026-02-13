# Command: Start or Continue Next Task

## Purpose
Select the next available task and start or resume implementation using the manager workflow.

## Steps
1. **Manager**: Follow `roles/manager.md` to:
   - Load the current milestone task list.
   - Select the first eligible unblocked task.
   - Check for existing lock file; resume if present, otherwise lock the task.
   - Create a feature branch using the required prefix `codex/`.
2. **Implementation**: Delegate to the coder workflow as described in `roles/manager.md`.
3. **Progress Tracking**: Update the lock file with checkpoints and work state.
4. **Quality Gates**: Ensure tests, review, and QA steps are followed per the manager workflow.

## Output
- Task selection summary
- `.task-locks/<task-id>.lock.json` updated/created
- Feature branch with implemented changes (if work performed)

## Notes
- If no eligible task is found, report blockers and recommend the next action.
- If resuming, summarize prior progress before continuing.
