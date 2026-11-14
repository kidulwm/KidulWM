# LAW — the Theme (one set of colour tokens, colour = meaning, user-changable)

LOCKED 2026-10-26, Barticus present.
AMENDED 2026-11-14 (Barticus present, GSI): browser ZONE names aligned to the
cell types — the least-safe zone is now "pen" (cells.md re-cut: pen/brig/plank).
The browser zones themselves are DEPRECATED: removed in the browser redo,
replaced by browser settings + downloads at the bottom (ruling Q.D).

Lane: cross-app (kfiles, kidul-browser, kmedia + KidulWM media.zig).
Related: styles (THE PILL, CFC law), landing law, chrome law, identity law.

## Problem

Browser, media player and files each hardcoded their own pill colours and
drifted apart: browser pen/brig/plank = green/blue/rust, media movies/tv/music
= blue/green/amber, files = mono-gold. The colours carried no shared meaning,
and one was actively wrong — browser "pen" (LEAST safe) was GREEN, which reads
"safe/go". Backwards.

## Concept — colour = meaning

One set of colour TOKENS, each a FIXED meaning, delivered from a single source.
Qubes OS colours a whole VM window by security domain; KSD does it quieter — the
pill you land on carries the zone colour. The user composes their own palette
(a KISS text file they can hack) and every pill that MEANS a colour re-colours
across all three apps in one move.

## The tokens

Five pill slots, numbered left-to-right, meaning-anchored. BLUE (slot 3) is the
LANDING anchor — always the centred/default pill, the "calm ground" the user
lands on. The others radiate around it.

  1 = SHOP     "What's New" — where users BUY media. Edge-positioned (far left,
               or far right), available but NOT in the user's face (shop is
               last-resort). COLOUR TBD (open).
  2 = ORANGE   warning / least-safe.  #d9722e — the emergency-orange of the left
               signals beacon. kfiles DRIVES · media MOVIES · browser PEN.
               (media MOVIES renders a MUTED shade — "warning muted-orange".)
  3 = BLUE     calm / landing / default. #6a8fc4. kfiles HOME · media TV ·
               browser BRIG.
  4 = PURPLE   play / safe. #BD00FF — the KidulWorks sig purple (trident outer
               prongs). kfiles SETTINGS · media MUSIC · browser PLANK.
  5 = GREEN    books / status. #6b9e75. media BOOKS (ebooks, far right in the
               5-button bar) · healthy/ok signals (mounted/downloaded/family).

Chrome tokens (not pill slots):
  gold        the focus ring + active accent. #948e7b.
  border      focused + unfocused variants — the DEFAULT focused-border-colour is
              always a BRIGHTER version of the same-ish colour; unfocused =
              dimmer. One hue, two levels.
  track       #0a0a0a. text active #e8e6df, dim #6a6354.

## The law (properties)

1. ONE SOURCE, THREE APPS. The tokens live in ONE place (a KISS text file the
   user edits), delivered by kushd (the channel that already hands KIDUL_ROLE /
   KIDUL_USER to kfiles). Change slot N in one place and every pill that MEANS
   that colour re-colours across browser + media + files together. No app
   hardcodes its own pill colours.

2. BLUE LANDS. Slot 3 (blue) is the landing/default pill — always the centred
   resting state. The user lands on blue, not orange or purple.

3. SAME TEMPLATE, 3 OR 5. The 3-button bar (current: files/browser/media) is
   slots 2/3/4 (orange/blue/purple). The 5-button bar (media future) is slots
   1/2/3/4/5 (shop/orange/blue/purple/green) — books far right, shop on the far
   edge. Both use the SAME colour template, blue pinned centre.

4. ZONE COLOUR IS THE PILL COLOUR. The browser searchBar pill carries the colour
   of the pen/brig/plank zone the browser is in — the "area it is working in".
   That is the browser's safety signal (Qubes, subtler).

5. FOCUSED BORDER = BRIGHTER. The border's focused state is a brighter version of
   the same-ish colour, never a hue jump. Focus is shown by brightening, not by
   switching colour.

## Remaps this law makes

- browser zones: pen green #6b9e75 -> ORANGE #d9722e (least-safe = warning, the
  fix), brig blue #6a8fc4 (unchanged), plank rust #a8604e -> PURPLE #BD00FF.
- media: movies -> orange #d9722e (was blue #6a8fc4), tv -> blue #6a8fc4 (was
  green #6b9e75), music -> purple #BD00FF (was amber #9e7e52).
- files: DRIVES -> orange, HOME -> blue, SETTINGS -> purple (was mono-gold #34).

## Reversals

- Reverses media.zig's "house colours, never theme-fed" doctrine: pill colours
  become theme slots, not frozen per-app constants.
- Reverses the per-app hardcoded pill palettes (browser green/blue/rust, media
  blue/green/amber, files mono-gold) in favour of the shared tokens.
- Reverses nothing else against locked law.

## Rulings (this lock)

- Q.A  plank colour = PURPLE (not green). Green stays slot 5 (books/status), so
  "safe/ok" keeps green and purple owns "play". (Barticus 2026-10-26.)
- Q.B  media mapping: movies=orange, tv=blue, music=purple — a 1:1 with slots
  2/3/4, blue still the landing. (Barticus 2026-10-26.)
- Q.C  shop = "What's New" buy-media button, on the far edge, subtle; colour
  TBD. (Barticus 2026-10-26.)
- Q.D  DEPRECATION (2026-11-14, GSI): the browser pen/brig/plank zones are
  REMOVED in the browser redo. The space they occupied becomes browser SETTINGS
  (background, etc.) + DOWNLOADS at the bottom — the simpler the better. Until
  then the pen/brig/plank colour mapping (orange/blue/purple) is a temporary
  hold, and the zone names align to the cell types (pen, never "cell").
