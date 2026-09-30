# KidulWM — aig toolchain (slice)

Read only for aig work. Host core is KNOWN_CMDS.md.

## aig — the Kidul Zig toolchain (NEW DIRECTION, Aug 28 2026)

Repo: `https://codeberg.org/kidulwm/aig` (public, GPLv3 layer over upstream MIT).
Local: `/home/dad/dev/aig`. Docs: `README-AIG.md`, `BUILD-AIG.md`.

What it is: pinned fork of zig 0.16.0 RELEASE source + `a/` stdlib
extensions (`a.fs`, `a.img`, ...). Patch discipline in `patches/` —
nothing edits the tree without a patch file. No syntax changes in 0.x.

Why: the compiler was the last outside dependency deciding whether our
tree builds on any given morning (`std.fs` → `std.Io.Dir` mid-release,
an evening gone). Upstream roulette stops here. Updates to the toolchain
happen when WE pull, deliberately, never by surprise.

Status: bootstrap proven — aig builds from host zig and KidulWM built
with it is byte-identical to the in-service binary (sha 780eef98...).
Known gap: C compilation needs LLVM backend (milestone aig 0.1.1 —
cmake + clang21 at /usr/lib/llvm21 + `-Denable-llvm`). Until that lands,
host zig builds C-shim targets; aig already builds pure-Zig targets.

RULES (locked):
- No syntax changes in aig 0.x. Parser untouched.
- `a/` namespace for our additions; import `const a = @import("a");`
- Host zig is bootstrap seed exactly once; then aig builds aig.
- Resolved (Aug 29): the kidulwm-under-aig Sema panic was an upstream
  0.16.0 assert vs `[*c]` element-pointer routing, triggered by ONE
  line in files_card.zig (`&entry.*.d_name[0]` → array-decay form).
  kidulwm builds under aig now. Details: HANDOFF session 15. Policy:
  not reported upstream (in-house knowledge).
- Never track upstream master. We pull, we decide, we pin.
