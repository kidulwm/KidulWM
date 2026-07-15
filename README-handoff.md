# Dynamic HANDOFF how-to

## Files

- `HANDOFF.md` — slim index. Run `scripts/update-handoff.sh` after a commit/branch switch.
- `DumpFile.md` (symlink to `docs/sessions/DumpFile-YYYY-MM-DD.md`) — append-only raw brain.
- `docs/sessions/YYYY-MM-DD-<topic>.md` — distilled session summaries.
- `docs/log/YYYY-MM-DD-<feature>.md` — per-feature/milestone notes.

## Workflow

1. Work as normal.
2. Append raw observations/learning to the current `DumpFile.md` as you go, or at session end.
3. When a feature lands or a lesson crystallises, create/update a file in `docs/log/`.
4. When the project state changes (branch, commit, VM, active skill), run:
   ```bash
   ./scripts/update-handoff.sh
   ```
5. Commit `HANDOFF.md`, `DumpFile.md`, `docs/log/`, `docs/sessions/` together with code changes.

## When a DumpFile gets too large

When it passes a few thousand lines, start a new dated DumpFile:
```bash
cd /home/dad/dev/KidulWM
mv docs/sessions/DumpFile-YYYY-MM-DD.md docs/sessions/DumpFile-YYYY-MM-DD-to-YYYY-MM-DD.md
# create new DumpFile-YYYY-MM-DD.md
ln -sf docs/sessions/DumpFile-YYYY-MM-DD.md DumpFile.md
```

Then update `HANDOFF.md` to point at both old and new dumps.

## For BobsBrain

Replicate the exact same pattern in the BobsBrain repo:
- `HANDOFF.md` index.
- `DumpFile.md` symlink to `docs/sessions/DumpFile-*.md`.
- `docs/log/` for distilled feature notes.
- `scripts/update-handoff.sh` for git-derived state lines.
