# LAW — the public seat & the walk-up identity

LOCKED 2026-11-12, Barticus present. Q.A/B/C resolved (rulings below).
AMENDED 2026-11-12 (later): BOSS/ADMIN -> OWNER (a standard sudo user); owner +
  public are plain Linux accounts (no custom auth code); the owner's real login
  name is a RANDOM HASH, shown as "Owner" in the face.

Lane: cross-cutting (kushd seating, kmedia, kidul-browser, kidulwm).
Related: profiles.md (the profile is the cell), kidulkey.md (presence free /
footprint owned), bill.kush (the seating chart), landing.md (the landing look).

## The public user

The TV boots into the PUBLIC seat: a dedicated, standard-Linux account —
`public`, no password, zero supplementary permissions (no audio/video/input/
tty/render). It is a seat identity, not a human login — kushd seats it as the
default profile (profiles.md: "the default profile starts at login"). Chosen
over "anonymous profile" for maintainability (a real nopasswd account is the
standard, boring, least-surprising shape).

- Media does NOT live on the immutable root. The public media tree is the
  public user's home: /home/public/Media/{Movies,TV,Music}.
- Public roster (for now): browser -> media player -> ktty. ktty is TEMPORARY
  on the public seat; it pulls into the admin account once that account lands.

## The identity tiers

- OWNER account — a standard Linux sudo user. The face shows "Owner"; the
  underlying login name is a RANDOM HASH, so the target is unguessable (an
  attacker must land BOTH the hash name and the key, not "root"/"admin").
  Grants disk space (footprint): "the Owner hands out the space upon request."
  kidulKey stays the code-signing / verified-boot root, NOT the login gate.
- WALK-UP user — anyone with their own HD + key/password seats themselves,
  borrows the stage, NO approval (they bring their own footprint). On removal
  + sign-out the user is ZEROIZED: nothing to remember.
- FAMILY user — persistent drive space, granted by the Boss on request;
  EXPANDABLE (at least for Granny).

## Relationship to existing law

- EXTENDS profiles.md: "public user" = the default profile = a dedicated
  nopasswd cell; walk-up / family / BOSS are the account tiers.
- EXTENDS kidulkey.md: BOSS = OWNER key (footprint); walk-up = PERSONAL key
  (presence free — own HD). "Presence free, footprint owned" is the base.
- GROUNDS bill.kush: the seating chart already carries the roster — public
  roster is a bill concern (browser restricted, media cued) + ktty (keybind).
- landing.md unchanged.

## Reversals

- Supersedes the earlier "media on root /media" placement (the FLAC at
  /media/Music): media lives in the public profile's home. Root is immutable.

## Rulings (this lock)

- Q.A  public user = a dedicated nopasswd account (not an anonymous profile),
  for maintainability. [Barticus 2026-11-12: "easiest to maintain"]
- Q.B  media in /home/public/Media, NOT /media on root. [Barticus: immutable
  root makes media-on-root backwards; a zero-permission nopasswd user is the
  safer place]
- Q.C  ktty temporary on the public seat. [Barticus: yes — safest; Granny/Boss
  hold the kidulKey to open the ADMIN/BOSS account]
- Q.D  owner + public are plain Linux accounts (sudo + nopasswd), no custom
  auth code. [Barticus 2026-11-12: "already standard linux settings again"]
- Q.E  the owner's real username is a random hash, displayed "Owner".
  [Barticus: makes the hacker's target unguessable — "whose files are they
  trying to hack?"]
