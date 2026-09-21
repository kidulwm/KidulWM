# TASK CARD — Phase A item 1: knet settings (verification + gap closure)

Status: DRAFT 2026-09-04, bobdotrix. Law: docs/law/daily-driver.md (LOCKED).
Delegation: attended, per standing workflow. Harness: this card.

## Framing (why this is small)

knetd is PROVEN on this host: live since Aug 31, replaces
NM/wpa_supplicant/dhcpcd, this session rides it. The network slide is
knetd-native (ksignals 60007fd): live avail rows, PSK entry, saved switch,
connect verb, flow ticker, L2 watcher markers. The backoff-ratchet wart is
already fixed (knetd 2435d79). Settings exist for the BAD DAY, not the
good one — so this card is: prove the good day, rehearse the bad day.

## Work items

  1. Good-day end-to-end, on the host, from inside a KSD session:
       - boot → knetd auto-connects saved SSID with no interaction
       - ksignals network slide shows correct state throughout
       - manual scan → avail rows land → join NEW ssid with PSK entry
         (use a phone hotspot as the sacrificial AP — do NOT touch the
         home AP config)
       - saved-conn switch back to home SSID
  2. Bad-day rehearsal (controlled):
       - kill carrier (rfkill block / AP off) → watch recovery path
       - confirm backoff resets to 5s after link returns (2435d79 path)
       - confirm slide shows disconnected → recovering → connected with
         honest state at each step (no silent stuck)
  3. Gap closure — only what the rehearsals actually expose. Known
     candidates from HANDOFF (verify before building any):
       - SSIDs with spaces unreachable via cmd verb (App.zig:585 comment)
       - connect-failure feedback into the slide (wrong PSK today = ?)
       - DNS field still placeholder (= gw) in network.detail
  4. KSD-session wiring check: knetd.service enabled + starts before the
     session; ksignals starts in the KSD session and finds
     /tmp/kidul-signals/network.detail with correct perms for the kidul
     session user.

## Explicitly out of scope

  - Security trigger ACTING layer (whitelist window, flood) — VM-first,
    per Barticus ruling 2026-08-20.
  - VPN anything beyond what the slide already shows.
  - kiduldm/kidul-init (product-side, law §6).

## Acceptance

  - All of item 1 + 2 pass on the host, in a KSD session, evidence in
    the timeline record.
  - Every gap in item 3 either fixed + signed, or written into the card
    as a documented known-limitation with Barticus's ruling.
  - HANDOFF.md (knetd) and timeline updated; B&B signed commit(s).

## First move

Item 1 boot check requires a KSD session that launches — which is Phase A
item 2 territory. So the practical first move is the DM session-entry for
KidulWM on the host (small), then run this card inside it. Sequence the
two cards together.
