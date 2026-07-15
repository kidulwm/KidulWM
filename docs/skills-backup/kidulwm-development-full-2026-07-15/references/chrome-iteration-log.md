# KidulWM chrome / border iteration log

Session template. Copy the section below for each new attempt and append to this file.

## YYYY-MM-DD — commit <hash> — <short description>

- **Branch:**
- **Commit / tree:**
- **Working tree clean?** yes / no (attach `git status`)
- **Symptom tested:**
- **Expected fix:**
- **Screenshot path:**
- **Observed result:**
- **Regressions:**
- **Next suspected cause:**

---

## 2026-07-12 — bisect from e6da1ab backwards — stray focused left border / missing borders

- **Branch:** chrome-2x
- **Commit / tree:** e6da1ab + uncommitted window.zig/chrome.zig changes; later reset to 83e1fc8, then to 29b8c55
- **Working tree clean?** no — had uncommitted changes
- **Symptom tested:** focused window shows only a stray left-edge line; rest of chrome border missing/displaced
- **Expected fix:** reverting to earlier stable commit
- **Screenshot path:** /tmp/screenshot38.png
- **Observed result:** revert to 83e1fc8 and then 29b8c55 both still showed the defect; "last good commit" cannot be trusted without fresh verification
- **Regressions:** lost working-tree clip/offset experiment after `git checkout` without stashing
- **Next suspected cause:** recent chrome overlay clip/offset changes (e6da1ab) detached the surface clip from the wrapper, and the previous commits were already broken or the binary was not cleanly rebuilt

---

## 2026-07-13 — reset to 29b8c55 — CSD shadows bleeding through chamfer corners

- **Branch:** chrome-2x
- **Commit / tree:** 29b8c55 working tree clean
- **Working tree clean?** yes
- **Symptom tested:** client rounded corners / CSD shadows visible past the chamfered chrome border, especially around corners; also dark artifact in seam between left peek and focused slide
- **Expected fix:** restore clean geometry first, then fix only masking/clipping of surface content without touching `corner_style` or placement
- **Screenshot paths:** /tmp/screenshot40.png, /tmp/screenshot41.png
- **Observed result:** geometry good at 29b8c55; clip attempts broke geometry; pure mask-inset tweak deployed and awaiting visual check
- **Regressions:** temporary geometry breaks from naive `subsurfaceTreeSetClip` calls; none remaining after reset
- **Next suspected cause:** if mask-inset does not stop it, either client buffer extends outside wrapper and needs per-edge content clip, or hidden-edge `DEST_OUT` strips expose leaked surface at seam
