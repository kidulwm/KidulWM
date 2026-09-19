# CARD 2 — kvisd→kplayd rename (progress log, bobdotrix 2026-09-19)

Running on low credits. This file is the "where did it run out" marker.
Update it after each stage; if the session dies mid-sweep, the next one
reads this and resumes from the last DONE stage.

STAGES:
  1. Content sweep (case-preserving kvis→kplay across kmedia + KidulWM)
  2. git mv renamed files (7 files)
  3. Build kmedia + KidulWM (both repos)
  4. Deploy to ksd-reset VM (binary + user unit rename)
  5. Commit both repos (signed)
  6. Docs (CENSUS verdict 38, HANDOFF, SYSTEM.md §7 mark DONE)

STATUS: starting.
