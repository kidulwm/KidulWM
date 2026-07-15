# Workflow: consent before iterating

KidulWM changes are evaluated visually in a VM. After a code change is deployed, the user is often still studying the screenshot. Do not start another edit until the user explicitly asks for it.

## Rules

1. **Approval is per-change.** A user saying "right peek looking good" or "ok good" means that specific change is accepted, not that you should add more fixes. Lock that state with a commit and wait.
2. **"Stop" halts immediately.** Do not fire another tool call. Do not edit files. Report current file/branch/build state and wait.
3. **Do not anticipate the next step.** If the user mentions a symptom ("the background doesn't pull to the edge"), do not start coding until you have discussed the plan and the user has confirmed it.
4. **Suggest, don't modify.** It is safe to say "I think the next move is X" or "should I do X?"; it is not safe to edit files while the user is reviewing.
5. **Reboots and fresh testing are user decisions.** If a screenshot looks stale, ask the user whether to reboot rather than silently changing code.
6. **One change at a time.** If the user says "one step at a time", take it literally: deploy only the already-approved change, do not pile on additional fixes, and do not modify anything the user did not green-light. Wait for explicit direction before each next step.
7. **When the user rejects a direction, revert immediately.** If you made an unapproved change and the user objects, stop work and restore the last known-good commit before doing anything else.
8. **"Lock that in" means commit immediately.** When the user says a state is good, run `git add`/`git commit` right away. Do not wait for a second symptom or start another edit before locking it in.

## What to do when a change looks promising

- Build and deploy it.
- Capture the screenshot or ask the user for one.
- Wait for the user's verdict.
- If they say it's good, commit as the known-good fallback point and stop.
- If they report a remaining issue, ask whether they want to iterate before changing anything.
