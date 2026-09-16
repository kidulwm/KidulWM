# Licensing & Brand Law

Status: LOCKED (Barticus, 2026-09-15)

## The split

1. **KSD application code** — kidulwm, kbrowser, kfiles, CFC, compositor,
   shell daemons, satellites: **GPL-3.0-or-later**.
   Every source file carries the GPL header (see templates/ below).
   Anyone may see, hack, fork, build on it. Nobody may take it
   proprietary: shipped derivatives carry the same freedoms, source
   included. This is the big-tech repellent AND the community promise —
   even B&B cannot close it later.

2. **Protocols & specs** — knet, kinit, wire formats, protocol docs:
   **Apache-2.0**. Maximum adoption; router vendors and phone OSes must
   be able to implement without a lawyer. Open the road, GPL the car.

3. **Documentation**: **CC-BY-4.0**.

## No CLA, ever

- No contributor license agreement, no copyright assignment.
- Contributors keep their copyright; the project can NEVER be relicensed
  or closed by anyone, including B&B. This is deliberate.
- Contributions need only a DCO sign-off (`Signed-off-by:` line,
  certifying they have the right to contribute the code).

## Template exception (kslide-template, future plugin SDKs)

Templates/SDKs that third parties build slides or plugins FROM carry
GPL-3.0-or-later **plus a Bison-style usage exception**: the template
itself is GPL, but works produced by using it (third-party slides,
plugins) may be distributed under any terms, proprietary included.
Rationale: the GPL wall protects KSD; it must NOT strangle the slide
ecosystem the TV play depends on. SlideDeck itself, living inside
KidulWM, is plain GPL-3.0-or-later with no exception — the layout model
is a crown jewel, the template is a door.

## Brand law

- "Kidul", "KidulWM", "KSD", and the pill logo are B&B trademarks.
- Trademarks are NOT licensed with the code. Forks get all code
  freedoms and ZERO brand rights.
- Forks MAY say "based on KidulWM" / "fork of KidulWM" (nominative,
  truthful). Forks may NOT call themselves KidulWM, ship the badge,
  or imply endorsement. Trademark policy page to be written at flip.
- Wordmark first (the word in any form), pill device mark second.

## Anti-tivoization (GPLv3 §6)

Kidul TVs MUST let owners reinstall a modified OS. Installation
information stays available to buyers. Law, not policy.

## Public-flip gates (extends the existing 3 — secrets sweep,
AI-slop cleanse, dual approval)

Gate 4: licensing sweep —
- [ ] COPYING/LICENSE files in every public repo (GPL-3.0 in code repos,
      Apache-2.0 in protocol repos)
- [ ] GPL header in every source file
- [ ] DCO note in CONTRIBUTING
- [ ] AU trademark APPLICATION filed (class 9 incl. display hardware,
      class 42), ™ in use on the name from this point
- [ ] Brand/trademark page drafted

## Trademark sequence (Barticus research list)

1. Namesearch IP Australia + USPTO + EUIPO for "Kidul"/"KidulWM"
   (classes 9, 42) BEFORE flip. Clear = proceed; conflict = rename now,
   not after launch.
2. File AU wordmark application AT flip (application date is what
   matters; grant can trail).
3. Pill device mark + Madrid Protocol international extension at TV
   production time.
4. ™ from first use/filing; ® only after registration grants.
