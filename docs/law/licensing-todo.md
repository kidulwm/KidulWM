# Barticus todo — brand & licensing (research further, this is Bob's map)

Ordered by what has an external clock first.

## 1. Namesearch (soon — the only time-sensitive item)
Someone else filing "Kidul" first is the one thing we can't un-do cheaply.
- [ ] IP Australia trademark search: "Kidul", "KidulWM", "KSD" —
      classes 9 (software, TV/display hardware) and 42 (software services).
      https://search.ipaustralia.gov.au/trademarks/search/quick
- [ ] USPTO TESS (uspto.gov), EUIPO eSearch (euipo.europa.eu) — same names.
      We ship TVs internationally eventually; a squatter in either is pain.
- [ ] Also sanity-check: domain names, Codeberg/GitHub org names.
      Not legal issues, but brand consistency costs nothing to check now.
- [ ] If CLEAR: proceed as planned, file at public flip.
      If CONFLICT in class 9: renaming now is free; renaming after TVs ship
      is not. Escalate to Bob before any panic.

## 2. At public flip (gate 4, already in law)
- [ ] File AU wordmark application: "Kidul" (and/or "KidulWM" — decide which
      is THE mark; wordmark covers the word in any font/style).
      ~AU$250-400/class, no lawyer needed for a clean mark. IP Australia
      eServices, headstart service optional.
      Class 9 MUST include display hardware (TVs), class 42 for software.
- [ ] From filing day: use ™ on the name. (® is illegal-ish before grant.)
- [ ] Trademark policy page: forks may say "based on KidulWM", may not call
      themselves KidulWM or ship the pill badge. (Model: Mozilla's policy.)

## 3. At TV production
- [ ] Register the pill logo as a device mark (separate application).
- [ ] Madrid Protocol international registration (one filing, many
      countries) if shipping outside AU.
- [ ] GPLv3 installation-information readiness: TV buyers must be able to
      reinstall modified OS. This is an engineering requirement (unlockable
      bootloader path for owners), not just legal.

## 4. Ongoing, zero cost
- [ ] Every commit B&B-authored or DCO-signed. Never accept code without
      a Signed-off-by line. This is what keeps re-licensing/brand options
      open and the GPL enforceable.
- [ ] Keep knet/kinit/specs Apache-2.0 discipline — resist the urge to GPL
      them later; protocols win by adoption, not walls.
- [ ] WM -> SD rename (KidulWM -> SlideDeck as the public name): schedule
      ONE flag-day commit when the flip gets inside ~100 commits. Later is
      correct — every law doc/skill/keybind reference that hardcodes the
      old name raises the cost — but it must land BEFORE public flip and
      BEFORE the trademark filing (file the mark on the FINAL name, never
      file twice).

## What Bob already did (2026-09-15)
- docs/law/licensing.md LOCKED, homed at KidulWM/docs/law/ (the root repo;
  same pattern as kmedia/docs/law — simple path, easy to find)
- GPL-3.0 LICENSE files dropped into all app repos (KidulWM MIT->GPL swap
  legal: sole B&B authorship), Apache-2.0 into knetd
- /tmp/license_sweep.py ready to header every source file (GPL header,
  Bison-exception for kslide-template) — run per-repo as each tree commits
  clean, one licensing commit per repo
