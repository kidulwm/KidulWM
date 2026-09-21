# CARD 2 — kvisd→kplayd rename (progress log, bobdotrix 2026-09-19)

Running on low credits. This file is the "where did it run out" marker.
Update it after each stage; if the session dies mid-sweep, the next one
reads this and resumes from the last DONE stage.

STAGES:
  1. Content sweep (case-preserving kvis→kplay across kmedia + KidulWM)  [DONE]
  2. git mv renamed files (7 files)                                     [DONE]
  3. Build kmedia + KidulWM (both repos)                                [DONE — clean]
  4. Deploy to ksd-reset VM (binary + user unit rename)                 [IN PROGRESS]
  5. Commit both repos (signed)                                         [DONE — kmedia f2ff36f, KidulWM efb98c6]
  6. Docs (CENSUS verdict 38, HANDOFF, SYSTEM.md §7 mark DONE)          [pending]

NOTES:
  - kmedia and KidulWM both build clean + test clean after the sweep.
  - grep gate: zero "kvis"/"Kvis"/"KVIS" in src/ or build.zig of either repo.
  - Cross-process contract verified consistent: kplay.sock, com.kidul.kplay,
    KplayClient, placeKplayWindow, classifyKplay all match across both repos.
  - Host still has /usr/local/bin/kvisd + ~/.config/systemd/user/kvisd.service
    (--user unit) — needs renaming to kplayd.
  - ksd-reset has /usr/local/bin/kvisd (not running, no unit found).
