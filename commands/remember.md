# Command: Remember Session Memory

## Purpose
Manually capture the current (or just-finished) session's outcomes into the
project's memsearch episodic memory (`.memsearch/memory/<date>.md`). Complements
the automatic writers (Claude Code memsearch plugin's Stop hook; ZCode
`memsearch-zcode-stop.sh` adapter) — use it when a turn mattered and you want a
guaranteed, curated record: after heavy debugging, before closing a long task,
or when the automatic summary would miss the point.

## Procedure

1. Resolve the memory target: the **main worktree's** root `.memsearch/memory/`
   (`git rev-parse --path-format=absolute --git-common-dir` → dirname). Never
   write into nested `.memsearch/` dirs — they are gitignored strays by
   contract (only the root `.memsearch/` is tracked).
2. Append to `<today>.md` (create if missing), following the established
   on-disk format:

   ```
   ### HH:MM
   <!-- session:<session-id-or-short-handle> source:manual -->
   - <2–6 third-person bullets: what the user asked, what was done — files,
     commands, commit hashes, key findings. Same language as the user.>
   ```

3. Re-index so the record is searchable:
   `memsearch index <root>/.memsearch/memory -c <collection>` — derive the
   collection with the memsearch plugin's `derive-collection.sh` (`ms_<sanitized
   basename>_<8-char sha256 of the absolute project path>`), or read it from
   `.memsearch/.index-state.json`.
4. Do **not** `git add`/commit `.memsearch/` yourself — `commit-memsearch.sh`
   (registered on SessionEnd/SessionStart/Stop) owns the `chore(memsearch)`
   commit and its coalescing (see AGENTS.md: never stage, commit, squash, or
   rewrite `.memsearch` by hand).

## Notes
- If `memsearch` is unavailable or indexing fails, still write the markdown —
  the next successful `memsearch index` picks it up.
- Keep bullets factual and specific; the memory is read by future agents via
  `memsearch search "<query>" --collection <collection>`.
