# LAW — reverse-DNS app_id namespace (com.kidulworks.*) (LOCKED 2026-11-11, Barticus present)

Every Wayland toplevel app_id we set lives under ONE root: `com.kidulworks.*`.

## The root

  com.kidulworks

The reverse of kidulworks.com — the domain we own (identity.md, distribution.md:
the native store serves from kidulworks.com). Reverse-DNS maps to a domain we
control, which is what makes an app_id a collision-proof lease on a name rather
than a guess. One root, one lease, forever.

## Why not the other candidates (each REJECTED, 2026-11-11)

  com.ksd.*        "KSD" is a short-form of the product, NOT a domain we own.
                   ksd.com belongs to a stranger. The moment KSD ships and kids
                   side-load (dev-mode, distribution.md §"Kids hack free"), a
                   com.ksd.* id collides with someone else's namespace. KSD is
                   the FACE identity (a branding axis, frozen separately) — it
                   never doubles as the reverse-DNS root.

  com.kidul.*      drift from the pre-law tree (kplayd used it). "kidul" is the
                   pre-company project name, not a held domain. Retired here.

  com.kidulwm.*    WRONG for every satellite — kidulwm is the compositor, ONE
                   component, not the brand. ktty/kmedia/kfiles are not part of
                   the compositor; they must not carry its name. (The compositor
                   itself owns no toplevel app_id — it is the server.)

  bare "kidul-browser"  no namespace at all. Always wrong; a reverse-DNS id is
                   the minimum bar for any toplevel we set.

## Rename table (old -> new)

  com.kidul.kplay             -> com.kidulworks.kplay
  com.kidul.video-slide-host  -> com.kidulworks.video-slide-host
  com.kidul.kvis              -> com.kidulworks.kvis            (retired — docs only)
  com.kidulwm.kmedia          -> com.kidulworks.kmedia
  com.kidulwm.ktty            -> com.kidulworks.ktty
  com.kidulwm.kfiles          -> com.kidulworks.kfiles
  com.kidulwm.kbrain          -> com.kidulworks.kbrain
  com.kidulwm.ksignals        -> com.kidulworks.ksignals
  com.kidulwm.kweather        -> com.kidulworks.kweather
  com.kidulwm.slide           -> com.kidulworks.slide
  "kidul-browser" (bare)      -> com.kidulworks.browser
  com.kidulwm.khostty         RETIRED (never reintroduce; ktty is the terminal)
  com.kidulwm.tray            RETIRED (the tray died with the widgets)

## The lockstep rule (do not break the match)

An app_id is TWO-SIDED: the app SETS it (xdg_toplevel_set_app_id) and the
compositor MATCHES it (server.zig / window.zig, by eql or substring). A rename
that touches only one side breaks the match SILENTLY — no error, just a window
the compositor no longer recognises as its kmedia/kplay/terminal. Every rename
in this estate must land both sides in the same cut, and both binaries rebuilt
together. Known match sites: server.zig (kmedia, kplay) and window.zig (peek
label + frametrace counter). Grep for the OLD string before cutting; if it
appears in a .zig file you are in a match or a set site.

## Never rename foreign namespaces

  com.mitchellh.ghostty, com.apple.*, com.microsoft.*, com.sun.star,
  com.cmd.*, com.canonical.*, com.adobe.*, com.redhat.*, com.mozilla.*, ...

These are upstream strings in VENDORED code (ghostty's bundle id, Apple plist
keys, media fourccs, etc.). Renaming them breaks upstream sync and serves
nothing. The sweep touches ONLY strings we authored. Test fixtures
(com.hotel.menu, com.example.*) are test data, not ours to rename.

## Relationship to existing law

  identity.md       kidulworks.com is the domain; the reverse of it is the root.
  distribution.md   native apps serve from kidulworks.com; the app_id root
                    matches the store's authority.
  ksd-vocabulary-law  naming axes: app_id (WHAT) is this law's subject; the
                    owner-class seating fact (WHERE) is kushd's, untouched.
