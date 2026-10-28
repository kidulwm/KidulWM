# KidulWM — aig toolchain (slice)

Read only for aig work. Host core is KNOWN_CMDS.md.

## aig — the Kidul Zig toolchain (NEW DIRECTION, Aug 28 2026; re-based to 0.17.0 Oct 28 2026)

Repo: `https://codeberg.org/kidulwm/aig` (public, GPLv3 layer over upstream MIT).
Local: `/home/dad/dev/aig`. Docs: `BUILD-AIG.md`.

What it is: pinned fork of zig 0.17.0 RELEASE source (tag `0.17.0`, commit
`afee422535…`, re-based 2026-10-28 from the 0.16.0 fork) + `a/` stdlib
extensions (`a.fs`, `a.img`, ...). Version 0.17.1 (fork guard in BOTH
CMakeLists.txt + build.zig). Patch discipline in `patches/` — nothing
edits the tree without a patch file. No syntax changes in 0.x.

Why: the compiler was the last outside dependency deciding whether our
tree builds on any given morning (`std.fs` → `std.Io.Dir` mid-release,
an evening gone). Upstream roulette stops here. Updates to the toolchain
happen when WE pull, deliberately, never by surprise. "0.17.0 is where we
take over" (Barticus) — fork number 17, one toolchain ends version sprawl.

Status: re-based + LLVM-enabled (Zig 0.17 requires LLVM 22; system
`/usr/bin/llvm-config` → 22.1.8). Binary `/home/dad/dev/aig/zig-out/bin/zig`
reports `0.17.1-dev.3+55c57cb4f`. Drop-in verified: kfiles + libc link
test build clean under aig. Lives on branch `aig-0.17.0` (NOT merged to
main) until VM-proven under aig + drop-in verified across all repos.

Toolchain swap (2026-10-28): `/usr/local/bin/zig` → symlink
`/home/dad/dev/tools/zig-0.17.0/zig` (official interim, sha 7c61539a…).
Pacman `/usr/bin/zig` (0.16.0) UNTOUCHED; revert = `rm /usr/local/bin/zig`.

RULES (locked):
- No syntax changes in aig 0.x. Parser untouched.
- `a/` namespace for our additions; import `const a = @import("a");`
- Host zig is bootstrap seed exactly once; then aig builds aig.
- The kidulwm-under-aig Sema panic was a 0.16.0-only upstream assert
  (`Sema.elemPtrArray` vs `[*c]` element-pointer routing, triggered by
  ONE line in files_card.zig `&entry.*.d_name[0]` → array-decay form).
  Fixed in kidulwm, NOT aig; 0.17 does not have the assert. Details:
  HANDOFF session 15. Policy: not reported upstream (in-house knowledge).
- 0002 LLD .sframe workaround = OBSOLETE (0.17 linker links glibc 2.44
  clean, verified).
- Never track upstream master. We pull, we decide, we pin.
