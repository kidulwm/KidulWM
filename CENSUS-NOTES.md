# KSD RESET LEDGER — live state (bobdotrix, migrated from media census 2026-09-20)
#
# SESSION WRAP-UP (bobdotrix 2026-11-13, late morning) — DEVICE REGISTRY DRAFT FROZEN (docs/design/device-registry.draft.md).
#   Barticus's "user vault access list" = the ROSTER/kpax that already exists in law, NOT a new vault. The increment:
#     wire the kidulKey-signed { attested-device-key -> role } roster into input-trust Tier 2 (PROVEN) as the source of
#     device identity. WHO=roster (global, signed once), WHAT=per-node tier+allowlist (local, revocable) — the split he
#     asked for is already law. Roster is PUBLIC signed material on the krouter; the cold vault (cold-storage.md) holds
#     SECRETS only, never the roster, never private keys. kidulKey dongle = CDC-ACM prover (2fe3:0004), NOT a keyboard —
#     the Tier 2 production device is the REMOTE (HID + kidulKey seed). So "plug in + verify" today verifies the CRYPTO
#     PRIMITIVE (challenge/response), not a live Tier 2 keyboard. Build order (5 slices) frozen in the doc; NOT code yet.
#   TESTABLE NOW (host, CachyOS): kidulkey-gate builds clean (zig 0.17.0); test-proof.py needs cryptography (have 50.0.1).
#     Plug dongle -> python3 tools/test-proof.py /dev/ttyACM0  (VERIFY: OK = proof holds)  OR
#     kidulkey-gate /dev/ttyACM0 (TRUSTED/UNTRUSTED + writes global verdict). Global verdict SUPERSEDED — don't wire Tier 2
#     to it. PITFALL: SIGN arms with NO timeout — if host times out & closes tty, dongle stays ARMED forever (blinking,
#     ignores input). Recovery: tap BUTTON1 once, or reset. Keep host tap window >= gate's 30s.
#   NOT BUILT (docket #53): roster/kpax enforcement, key-cast vault unlock, hw-attested SSH, Tier 2 wired to roster.
#
# SESSION WRAP-UP (bobdotrix 2026-11-13, morning) — INPUT-TRUST PER-DEVICE ENFORCEMENT (proper fix, seatTrusted retired).
#   SYMPTOM: fresh KSD boot -> "couldn't open anything, no keypresses work". Barticus's hunch (no global keybind
#     defaults for the public user) was WRONG — the log showed keybinds: 33 loaded (source=user config), 25 from
#     /home/public/.config/kidulwm/keybinds.conf over 8 defaults. Defaults + fallback both fine.
#   ROOT CAUSE: the post-hoc GLOBAL seatTrusted() filter. kushd is fail-CLOSED (writes UNTRUSTED at startup; the
#     temporary 2026-11-12 fail-open writeVerdict("TRUSTED") was reverted — kushd working tree clean + 00:03 binary
#     rebuilt fail-closed). The 2fe3 kidulKey dongle IS present (ttyACM0) but enumerates ~1.2s BEFORE kushd binds its
#     netlink uevent socket -> ZERO "gate fired" events -> verdict stays UNTRUSTED forever -> seatTrusted()==false ->
#     EVERY Mod4/Ctrl bind inert. Plain typing + media keys still pass (why it read as "keys dead" not "keyboard dead").
#   THE FIX (proper, per docs/law/input-trust.md ladder): retire the global seatTrusted(); kidulwm now resolves
#     wlr_libinput_get_device_trust() AT RUNTIME via dlsym (single-flight cached; the getter exists only in our patched
#     libwlroots-0.20.so on KSD, NOT stock host wlroots, so it's dlsym not link-time) and gates HARMFUL binds
#     (spawn/close/reset/browser + XF86HomePage close) on the SOURCE device's tier. INTERNAL(0)/PROVEN(2) fire;
#     USABLE(1)/UNTRUSTED(3) only type+navigate (focus/tray/overview/fullscreen/volume still work). The internal AT
#     keyboard (bustype I8042) is Tier 0 INTERNAL -> full binds, no crypto-remote needed. Planck (03a8:a4f9) = Tier 1.
#   Commits 924e1b7 (enforcement) + 21e8a90 (cache). Built ReleaseSafe, deployed /mnt/ksd/usr/local/bin/kidulwm
#     (stamp 21e8a90, size 8373112); .bak = prior 924e1b7 build. patches/README.md REMAINING updated. REBOOT-TEST
#     PENDING: boot KSD -> Mod4+Return opens ktty, Mod4+s browser, etc., all from the internal keyboard.
#   NOTE (defer): the FAIL-CLOSED kushd verdict + cold-plug gap are STILL open (Tier 2 crypto proof is the remaining
#     harden slice). This fix makes them harmless on the pc/laptop (Tier 0 keyboard self-trusts) but a keyboard-less TV
#     still needs the crypto remote proven. Also the child spawns inherit WAYLAND_DISPLAY from the compositor — verify
#     no regression there on reboot.
#
# SESSION WRAP-UP (bobdotrix 2026-11-12, evening) — PUBLIC SEAT LAW LOCKED + BOOT-QUIET DEPLOYED.
#   PUBLIC SEAT LAW (docs/law/public-seat.md, commit 5baf290, LOCKED): TV boots into a dedicated 'public' nopasswd
#     account (zero supp perms), NOT an anonymous profile (maintainability). Media does NOT live on the immutable root —
#     it lives in /home/public/Media/{Movies,TV,Music} (REVERSES the FLAC-at-/media/Music placement). Public roster for
#     now = browser -> media player -> ktty (ktty TEMPORARY, pulls to admin acct later). Identity tiers: OWNER (std
#     sudo, random-hash login name, grants footprint), WALK-UP (own HD+key, no approval, ZEROIZED on removal), FAMILY (Owner-granted,
#     expandable). Extends profiles.md + kidulkey.md ("presence free, footprint owned"). globalPillsBar + admin-user-
#     settings = TBD / deferred.
#   BOOT-QUIET DEPLOYED: limine.conf cmdline += "quiet loglevel=0" (backup limine.conf.bak-quiet). The verbose text was
#     the KERNEL printk (kboot is screen-silent — logs to files — and already drains /dev/kmsg -> /var/log/kernel.log,
#     so silencing the console loses NOTHING). Fade Predator->KSD already exists (kidulwm fades in from black) — done.
#   USERS CUT (nvme0n1p2 test bed): 'public' uid1001 (zero supp groups) + owner uid1002 w/ random-hash login
#     'bee62e237cdd37a455eeafca' GECOS 'Owner'. /home/public/Media/{Movies,TV,Music} created; FLAC moved there (now
#     1001-owned); old /media removed. seed-users.sh committed+pushed kboot e9dfe24 (idempotent, fresh random hash per install).
#     FINDING: KSD root has NO sudo/su/useradd/shadow/nologin (kernel+pacman only) -> Owner escalation = kushd CLASS
#     system, not the sudo pkg. Escalation wiring is a later slice.
#   MUSIC ROOT WIRED (item 1 DONE, 19053b2): media.zig buildMusic() += /home/public/Media/Music. Live front-end IS media.zig
#     MediaWidget (fingerprint host=109/KSD=94; sweep 5db316d NOT merged), NOT the kmedia client. Built ReleaseSafe, deployed
#     /mnt/ksd/usr/local/bin/kidulwm (sha e7f7392...). FLAC shows in Music wall on KSD reboot.
#   SEAT->PUBLIC (item 2 DONE): /etc/kushd/seat=1001 (was 1000 kidul). Config migrated /home/kidul -> /home/public
#     (.config/kidulwm{keybinds,outputs,weather} + .config/kidul-browser + Pictures), chown 1001:1001. kushd seatUid()
#     default+comment corrected 1000->1001 (kidul->public), rebuilt + deployed sha de1eee0.... kidul(1000) left legacy.
#   OWNER ESCALATION (item 3): DESIGN FROZEN (public-seat.md). Runtime re-seat + landing roster = NEXT slice (a real
#     kushd/kidulwm feature, not a one-liner). No sudo pkg -> escalation = kushd CLASS, not sudo.
#   TOMORROW TEST: boot KSD -> public seat (uid 1001); FLAC in Music wall; browser+media+ktty present; keybinds/outputs/
#     wallpaper from migrated config.
#   sda1 zero-copy server work: PARKED per Barticus ("NOT NOW").
#
# SESSION WRAP-UP (bobdotrix 2026-11-12, evening) — TTY-OWNERSHIP CUT + NETWORK IDENTITY + PII SCRUB.
#   PTMX/PTY HARDENING (the ktty insta-crash root-caused): devtmpfs makes /dev/ptmx 0600 root:root; no udev -> stays 0600 ->
#     the seat's openpty() EACCES -> ktty dies OpenptyFailed ~2 frames after map. Fix = THREE coordinated legs, all deployed:
#     (a) kboot devRules() chowns /dev/ptmx root:tty 0660 (SEAT PERMISSION, not world 0666; kidul in 'tty', no sudo), with a 0666
#     fallback if the rootfs has no tty group; (b) kboot mountEarly() mounts devpts ptmxmode=000 (kills the /dev/pts/ptmx twin,
#     ONE pty entry); (c) kushd mintSession() setgroups adds "tty" (the trap: mintSession REPLACES supp groups, so /etc/group
#     'tty' alone was silently dropped at seat-mint). Rootfs /etc/group gained tty:x:5:kidul. Layer-0: KSD kernel 7.2.14 has ZERO
#     dangerous line disciplines (n_gsm/n_hdlc/n_slcan/n_6pack/n_ppp all =n) -> no TIOCSETD ldisc LPE path; MPTCP compiled OUT ->
#     CVE-2026-98432 (TCP UAF, fixed 7.2.10) does not apply. Host is 7.2.8 pre-fix but only 127.0.0.1 listener (ollama), not
#     reachable. kboot+kushd rebuilt ReleaseSafe, sha256-identical on /mnt/ksd, pending reboot with the tty group.
#   NETWORK IDENTITY -> KSD m.2: knetd saved-network store /mnt/ksd/var/lib/knetd/networks (0600 root:root) written in knetd's
#     stanza format (network <ssid> / key / auto 1). Router+gateway are DHCP-provided (nothing to copy); KSD leases its OWN IP.
#     No MAC spoof either side. PSK never echoed to logs, file outside any git tree. Pending reboot: knetd connects at boot.
#   PII SCRUB (Barticus: "no network details or passwords of ANY type pushed"): the LIVE wifi PSK + SSID
#     were ALREADY committed to codeberg knetd (HANDOFF.md, rig/store_test.zig) from Aug/Oct test-rig drills — committed
#     UNSIGNED under the non-B&B identity "Bob Dotrix <bob@dotrix.org>" (Aug 18 2026, the WPA2 supplicant host-position
#     session). NOTE the repo is PRIVATE (anonymous access = 404), so the leak was never public — severity is contained,
#     not burned. filter-repo --replace-text rewrote full history (PSK->REDACTED, SSID->REDACTED-SSID), force-pushed; verified
#     remote clean. gitignored rig/*.log still hold the SSID on LOCAL disk only (never pushed) — flag for cleanup.
#     testlab-psk-0001 is a fictional sacrificial test-AP passphrase, kept. Pre-scrub bundle: /tmp/knetd-prescrub.bundle.
#     SEPARATE HYGIENE ITEM (still open): repo history has 39 unsigned "Bob Dotrix <bob@dotrix.org>" commits vs 22 "B&B" —
#     signing law was not applied to knetd. Rotation still recommended (cheap insurance) but NOT an emergency since private.
#   REVERTED (this session): kushd writeVerdict("TRUSTED") security-off — restored to UNTRUSTED fail-closed. Committed only the
#     tty-group leg.
#   BONUS: shamanic FLAC (The Oldest Medicine, 61min) copied to /mnt/ksd/media/Music/ for the ksound test on reboot.
#   STILL OPEN: mouth getty on ttyS0 crash-loops (needs tty0 fallback) — the one "sleeping" holdout in htop.
#
# SESSION WRAP-UP (bobdotrix 2026-11-12) — DOCKET #54 (2) DONE: PHASE-2 NETLINK HOTPLUG BUILT+DEPLOYED.
#   "next" fired the top non-DONE docket (#54 KSD input). Phase-2 (the last input blocker) is now BUILT: a
#     NETLINK_KOBJECT_UEVENT listener in the wlroots libinput backend (NEW file backend/libinput/hotplug.c) — the no-udev
#     equivalent of udevd's monitor — so the Planck (USB, ~1.4s post-scan) and any late device now admits.
#   DESIGN (Q2 LOCKED, input-path.draft.md): "hotplug home = netlink kobject-uevent listener INSIDE the backend" — the
#     WLROOTS backend (owns session + event loop), NOT libinput's path-seat.c (no loop there). The docket's "in path-seat.c"
#     was loose shorthand; corrected in DOCKETS + README.
#   MECHANISM: socket(AF_NETLINK, SOCK_DGRAM|CLOEXEC, NETLINK_KOBJECT_UEVENT) bound nl_groups=1 (non-root, proven) BEFORE the
#     cold-plug scan, registered on the event loop AFTER dispatch — buffered uevents replay and are DEDUPED by
#     libinput_device_get_sysname (no double-add). On input add/remove -> libinput_path_add_device/remove_device; the
#     four-tier ladder re-runs per device (both paths funnel through DEVICE_ADDED -> handle_device_added).
#   BUILT+DEPLOYED: wlroots 0.20.2 rebuilt clean (-Werror), DT_NEEDED IDENTICAL to stock (strict superset, no new dep — netlink
#     is libc socket()). Deployed /mnt/ksd/usr/lib/libwlroots-0.20.so (Phase-1 -> .pre-hotplug; .stock kept). kidulwm resolves
#     against it in chroot (libwlroots-0.20.so + libinput.so.10). Patch REGENERATED patches/wlroots-0.20.2-libinput-path.patch
#     (now 6 files, sha256 1d1152ea…) — `git apply --check` clean vs tag 0.20.2.
#   SMOKE PASS (host): standalone netlink listener (scratch/ksd-netlink-smoke.c) bound non-root, fired `sudo udevadm trigger
#     --subsystem-match=input --action=add`, received+parsed 18 input ADD uevents -> correct /dev/input/eventN devnodes.
#   REMAINING: RE-BOOT-TEST (Barticus BIOS-swap nvme1) to confirm the Planck admits -> real typing box. Then "harden" slices:
#     Tier-2 crypto proof (kidulKey Ed25519 per-device) + kidulwm per-device enforcement (wlr_libinput_get_device_trust exists).
#   OUT OF SCOPE HERE: Tier-2 proof, kidulwm seatTrusted()->per-device consume, mouth-ttyS0 fallback.
#
# SESSION WRAP-UP (bobdotrix 2026-11-11, evening) — APP_ID NAMESPACE REBUILT + REDEPLOYED to /mnt/ksd (11 binaries, all clean).
#   Law: docs/law/app-id-namespace.md (LOCKED, Barticus "gsi"). Root = com.kidulworks (reverse of kidulworks.com, the domain we
#     OWN). REJECTED: com.ksd.* (ksd.com is a stranger's domain — would collide the moment kids side-load), com.kidul.* (drift),
#     com.kidulwm.* (the compositor is a component, not the brand), bare "kidul-browser" (no namespace). Rename table old->new:
#     kplay, video-slide-host, kvis(retired), kmedia, ktty, kfiles, kbrain, ksignals, kweather, slide, browser. RETIRED: khostty, tray.
#   LOCKSTEP RULE: app_id is TWO-SIDED (app sets / compositor matches). Exact-eql matchers = ONLY kmedia + kplay (server.zig);
#     window.zig uses SUBSTRING ("kplay"/"ghostty") which survives the rename. Foreign namespaces NEVER renamed. Source swept in 9
#     repos (KidulWM, ktty, kmedia, kfiles, kbrain, kweather, ksignals, kslide-template, kidul-browser) + live law/build/index docs.
#   REBUILT + REDEPLOYED (DONE): all 11 binaries rebuilt ReleaseSafe and deployed to /mnt/ksd — kidulwm, kmedia, kplayd, ktty,
#     kfiles, kbrain (daemon) + kbrain-ui (face), kweather, ksignals, kslide-template, kidul-browser. VERIFIED via strings: every
#     binary carries com.kidulworks.*, ZERO old-namespace remnants. kidulwm+ktty via cp->mv atomic. Lockstep trio consistent.
#   DEPLOY GOTCHA (recorded): kbrain builds TWO binaries — kbrain (daemon, main.zig, cued by kushd bill.kush as /usr/local/bin/kbrain,
#     NO app_id) and kbrain-ui (face, ui-main.zig, app_id com.kidulworks.kbrain, keybind spawns it). Do NOT deploy kbrain-ui under the
#     name "kbrain" (clobbers the daemon). Names are distinct on disk: kbrain + kbrain-ui.
#   NEXT CUT (C5 DECOUPLING, plan drafted v2 after Barticus steer): THREE targets.
#     (1) THE CARD IS DEAD — "NO card at all any more, only the slide". The media card became the media SLIDE (the
#     placement). Compositor-owned card scene tree (MediaCard/MediaWidget/media_slide.zig) -> ZERO. "card" survives ONLY
#     for overview mini-grid + dm login — never media. (2) TEST MEDIA ZERO ON KSD — test-media.mp4 (VERIFIED already absent
#     from /mnt/ksd), Player.zig "old test player" (ALREADY deleted from kmedia/src), 12 test/probe harness binaries
#     (bench_decode/clockprobe/displaysync/driftprobe/eofprobe/liveavoff/livetest/modeltest/playertest/posprobe/walltest/
#     tvpacktest + KidulWM kmedia-test + ksoundtest) stay HOST-ONLY, never deployed. (3) app_id special-casing
#     (mediaCardToggle:2144 / handleNewXdgToplevel:4049 / classifyKplay:4070 + window.zig is_kplay) -> structural. VERIFIED:
#     kplayd already resident daemon (kplay.sock), kmedia already client (Wall.zig 3-pill = FORBIDDEN LAYER gate CLEARED).
#     PLAN: docs/design/c5-decoupling.md (DRAFT v2). Open Qs A-F; Q-A gate = is .media_player slide ever seated on real boot?
#     Q-E = harness binaries: REC keep-built-but-whitelisted. Q-F = leave Player.zig comment history.
#   BARTICUS RULINGS (2026-11-11, gsi, folded into plan v2 + vocabulary law):
#     (a) kmedia is "just another app", seated ONLY by kushd (the usher-man), never app_id sniffing. kplayd = the SYSTEM
#     player connecting the pipes (kplay.sock) that ALL apps access — kmedia borrows it like any app. Q-C CONFIRMED.
#     (b) kmedia = klibrary (LOCKED decision): the media app IS the library; binary `klibrary` + repo + app_id
#     com.kidulworks.klibrary. Executed as its OWN cut AFTER C5 (decouple first, rename second — cosmetic, zero structural risk).
#     (b2) THREE DISTINCT "LIBRARY" SURFACES (avoid a second card/slide overload): (1) PUBLIC LIBRARY = the landing/home
#     launcher, 3-button top pill bar the TV boots into (Browser / Public Library / People); (2) MY LIBRARY = user's own
#     collection title inside the app; (3) the media wall's internal pill (Movies/TV/Music) = the CATEGORY filter inside the
#     library. "People" = NOT media — it is the mesh (kweb/identity.md, OMEMO + kidulKey), a separate docket. Root-cause
#     framing corrected: the library model leaked into TWO processes (kmedia AND kidulwm's media.zig), not one; C5 removes
#     the compositor's second copy, the klibrary rename then makes the survivor's name honest.
#     (c) ART VOCABULARY LOCKED: the 2:3 fan-art picture = POSTER (art-chain.md <stem>-poster.jpg → poster.jpg → folder.jpg);
#     the 2:3 grid cell = TILE (ui.md/Wall.zig); "fan-art" = the GENRE, never the noun. "placecard" is OVERLOADED — it means
#     kfiles' file-detail card (KEEPS the name) + the empty wall placeholder (media-side, dies with C5 as "empty tile").
#     NEVER "placecard" for a poster. The art-chain.md "the card is the poster is the title" line is the card-era wording
#     that dies with C5.
#   BARTICUS RULINGS (2026-11-11, SECOND BATCH, gsi):
#     (d) PEEK RETIREMENT + GLOBAL PILL BAR (both parked as docket #56, DEFERRED — huge change, "needs real thought").
#         (d1) peeks: widget-peeks (logo/clock/network/weather/gauges) LEAVE TV+PC; widgets grow 3-4x and live on the
#         empty-slides (landing + ends of rows/columns); peeks survive ONLY for games (steam-details) + server (glass case).
#         peek-as-LAYOUT (the 3-column deck neighbour-sliver) is a DIFFERENT thing and stays. (d2) global pill bar: the
#         deck's left/right BECOMES left/right on a global pill bar (per-app "depth of last entry" per session) — deck
#         becomes a projection of the bar, deleting its own ordering logic. Open Q1 vertical (up/down = same-app rows?
#         browser/TTY only; 2D grid not bolt-on), Q2 restore-state owner, Q3 derived vs editable order, Q4 non-app
#         surfaces (dialogs/dm/fullscreen). Deck-follows-bar = docs/design/ when un-parked.
#     (e) NOTIFICATIONS = TOP MARQUEE, not a peek (docs/law/notifications.md LOCKED). Full-width, text-first, every word
#         legible from the lounge; CFC-pending is the catch-up not the default; chrome law stands (retreats + no input steal).
#     (f) ENTER = PLAY/PAUSE DURING PLAYBACK (fullscreen.md ruling 9 LOCKED). Remote centre button toggles play/pause ONLY
#         while media is playing — Granny's "set the hand" button; playback-scoped, Enter keeps "apply" elsewhere; the
#         physical XF86AudioPlay/Pause stays blind-safe. (Play/pause is the media KEY, NOT space; Mod4+Space = overview.)
#     (g) DECK VERTICAL AXIS — Q1 RULED (GSI, "smart placement" breakthrough): up/down = instances of the SAME app, stacked
#         DETERMINISTICALLY below the first. Column = app identity; every multiple opens BELOW the primary and takes focus
#         (NOT to the right). Position = fn(app identity + instance count), never free-form history — predictable = learnable.
#         Still a 2D grid (peeks need up/down neighbours). Sub-details (stack order + close-primary behaviour) deferred to
#         the design doc. Q2 (restore-state owner), Q3 (derived vs editable order), Q4 (non-app surfaces) STILL OPEN.
#   NOT DONE: KSD has NO keybinds.conf (kidulwm falls back to built-in defaults — pre-existing gap). Host ~/.config/kidulwm/
#     keybinds.conf still has stale "spawn /usr/bin/ghostty" + "spawn ~/.local/bin/kmedia" lines (host-side cosmetic cleanup).
#
# SESSION WRAP-UP (bobdotrix 2026-11-11, evening) — FACE WIRING: ktty + htop + wallpaper + fonts/terminfo deployed to /mnt/ksd.
#   Remounted /mnt/ksd rw. Deployed (all verify-clean in chroot): /usr/local/bin/ktty (fresh ReleaseSafe build, app_id
#     com.kidulwm.ktty, kidul+cairo, links wayland-client/cairo/xkbcommon/fontconfig/freetype — NO gtk/adwaita), the terminal
#     launcher /usr/local/bin/launch-kidul-terminal.sh FIXED to `exec /usr/local/bin/ktty` (was exec /usr/bin/ghostty = dead
#     path; script + tree both patched). htop + libcap.so.2 + terminfo (xterm-ghostty/xterm-256color/ghostty). Wallpaper
#     theWallpaper.png -> /home/kidul/Pictures/Wallpapers/ (kidulwm hardcodes that path). fontconfig config (/etc/fonts) +
#     monospace fonts (JetBrainsMono/DejaVuMono/LiberationMono, 40 files) -> /usr/share/fonts (KSD had ZERO fonts; ktty/kfiles
#     would render blank text without them). ktty spawns bash (KSD passwd kidul=/usr/bin/bash, present) — no fish on KSD.
#   KNOWN FOLLOW-ON (cosmetic, NOT a blocker): kidulwm window.zig computePeekLabel matches "ghostty" not "ktty" -> ktty window
#     peek-label falls through to cleaned "ktty" (fine). Add "ktty" nickname + ft_commit counter rename when kidulwm next rebuilt.
#   REMAINING (unchanged): (2) Phase-2 hotplug (netlink kobject-uevent) so the PLANCK admits -> real typing box. Trackpad
#     (pointers:0) = Fn+F2 EC toggle, NOT software. RE-BOOT-TEST due (Barticus).
#
# SESSION WRAP-UP (bobdotrix 2026-11-11) — DOCKET #54 (0)+(1) DONE. Input path UNBLOCKED past the keymap wall.
#   (0) LIBINPUT FORK LANDED (signed B&B): commit bacf8d9 (patch+docs+README+gitignore for patches/libinput-src/ — the
#       upstream build checkout is IGNORED like wlroots-src/, NOT committed) + a742cdd (census handoff). Tree clean.
#   (1) XKEYBOARD-CONFIG BAKED (GAP 1 CLOSED): copied host data tree -> /mnt/ksd/usr/share/X11/xkb (293 files, 4.0M;
#       sudo cp -a /usr/share/xkeyboard-config-2 ...). VERIFIED: KSD libxkbcommon.so.0 lists /usr/share/X11/xkb in its
#       default include path + `xkbcli compile-keymap --layout us` against the baked tree = valid keymap (EXIT 0).
#       The ADMITTED internal AT keyboard will now emit keysyms on next boot. Assembly trace recorded in input-path.draft.md.
#   REMAINING: (2) Phase-2 hotplug (netlink kobject-uevent listener) so the PLANCK admits (~1.4s post-scan) -> real
#       typing box. RE-BOOT-TEST now worth it: expect AT keyboard to type even before (2) lands.
#
# SESSION WRAP-UP (bobdotrix 2026-11-10) — BOOT DIAGNOSED (no-input) + PROFILES LAW LOCKED (wall = containment).
#   KSD BOOTS ON NVME1: clock + KSD logo + cursor + widgets render (kidulwm bootcheck verdict OK, eDP-1 1920x1080@144,
#   GLES2). NO INPUT — two gaps, NEITHER is udev (the patched no-udev stack IS deployed: libinput.so.10.13.0 +
#   libwlroots-0.20.so both present with .stock backups + 1.31.3 quirks tree). GAP 1: xkeyboard-config absent
#   (/usr/share/X11/xkb missing) -> xkbcommon "failed to create default keymap" -> even the admitted AT keyboard emits
#   zero keysyms. GAP 2: Planck not admitted ("keyboards: 5 pointers: 0") — the 5 are internal (Sleep/Power/Power/
#   VideoBus/AT); the Planck (USB) enumerates ~1.4s AFTER libinput's cold-plug scan, and Phase-2 hotplug (netlink
#   kobject-uevent listener in the backend) is not built. Added xkeyboard-config as the 4th rootfs data-tree gap in
#   input-path.draft.md (Mesa / firmware / libinput-quirks / xkeyboard-config).
#   LOCKED (f208317, signed B&B): profiles.md — the profile IS the cell; wall = CONTAINMENT NOT ARMOR (the wall keeps
#   foreign stuff AWAY from the trust core; it does not armor the cell's own contents). native/"Private" = trust core,
#   no cell, "safer than any VM, colder than Qubes at home". pen=foreign distro / brig=foreign code / plank=most-unsafe
#   guests (discard on misbehave — resolves cells.md "plank=discard" + theme "browser plank"). Escalation = classify-at-
#   seat + plank-on-threat (NOT live migration). Profiles cued (default at login + per-profile start-at-boot toggle),
#   settings tentacle owns user+profile mgmt, kidulKey (PERSONAL create/delete, OWNER gates footprint). Colours DEFERRED.
#   distribution.md (LOCKED): base=golden image no-PM / native=libalpm+our signed repo / foreign=the cell's OWN
#   package manager (pen apt, brig guest PM). C repo format=pacman's, D dev-mode gate=OWNER's key.
#   Granny Home/World profile names (tentative; Private=native locked).
#   NEXT (in order): (0) LAND the libinput fork — the prior session's uncommitted input-path work is STILL IN THE
#   TREE (git status: M docs/design/input-path.draft.md, M patches/README.md, ?? patches/libinput-1.31.3-ksd-path-
#   no-udev.patch, ?? patches/libinput-src/); commit it signed B&B BEFORE touching the rootfs. (1) bake xkeyboard-config
#   into the golden rootfs (trace ksd-golden rootfs-assembly — the 4th data-tree gap). (2) Phase-2 hotplug (netlink
#   kobject-uevent listener) -> the Planck admits -> a real typing box.
#
# SESSION WRAP-UP (bobdotrix 2026-11-10) — LIBINPUT FORK BUILT+DEPLOYED+CHROOT-PROVEN (wlroots patch was necessary-not-sufficient).
#   The wlroots path patch (below) unblocked the backend, but booting still crashed one level DEEPER: libinput 1.31.3's
#   own path backend requires udev. Two seams, both patched in our own libinput.so.10 (1.31.3):
#     path-seat.c  udev_device_from_devnode() waited 200x10ms for udev_device_get_is_initialized(), NEVER true without a
#                  resident udevd -> "udev device never initialized" -> "Invalid path". Dropped the wait; accept the sysfs
#                  device udev_device_new_from_devnum() already returns (devnode/syspath/sysname populated).
#     evdev.c      classification was driven ENTIRELY by ID_INPUT* udev properties (udev's input_id builtin + hwdb); absent
#                  -> "not tagged as supported input device". Ported udev's input_id into libinput (ksd_evdev_tags_from_evdev,
#                  reads evdev capability bits via libevdev) as a fallback in evdev_device_get_udev_tags().
#   PATCH: patches/libinput-1.31.3-ksd-path-no-udev.patch (2 files, sha256 267e60d7...). BUILT 1.31.3 with -Dlibwacom=false
#   (drops libgudev from DT_NEEDED) prefix=/usr. DEPLOYED /mnt/ksd: libinput.so.10 -> 10.13.0 (stock = .stock), quirks
#   REPLACED with the matching 1.31.3 set (rootfs had a 1.32 quirks tree -> "Unknown key ModelCircularTouchpad"; 1.32 saved
#   as usr/share/libinput.1.32.bak).
#   CHROOT-PROVEN (no udevd, /run/udev absent): 18 devices admitted — AT kb, Planck 03a8:a4f9, ELAN touchpad, lid/power/sleep,
#   MX Master 3. 10 audio devices (HDA jacks, PC speaker) correctly rejected == stock (switch support = SW_LID/TABLET_MODE/
#   KEYPAD_SLIDE only). NOTE: the earlier "host smoke test" was a FALSE GREEN — host runs udevd.
#   PURITY BOUNDARY (LOCKED): libudev.so.1 STAYS as libinput's device model (client lib, no daemon; meson dep_udev is
#   non-optional). "No udev" = no resident udevd + no database + no rules/hwdb, NOT dropping the libudev client. libgudev is
#   now orphaned in the rootfs (can remove). NEXT: re-boot-test (Barticus kboot) — expect kushd.log "seated kidulwm", NO
#   "died kidulwm" loop, AT keyboard + Planck produce input.
#
# SESSION WRAP-UP (bobdotrix 2026-11-10) — INPUT-PATH FIX BUILT+DEPLOYED: wlroots 0.20.2 patched to path-based libinput (no udev) + 4-tier admission gate.
#   ROOT CAUSE of the deck-dark boot: wlroots' libinput backend is udev-ONLY (backend.c backend_start() =
#   libinput_udev_create_context + assign_seat) — a no-udev rootfs enumerates ZERO devices -> "no input
#   devices" -> backend fails -> wlr_seat_destroy assert -> SIGABRT -> kushd respawn backoff forever. The DRM
#   backend already has a no-udev fallback; libinput had none. Fix closes that asymmetry (input-path.draft.md).
#   BUILT (KidulWM f602041, signed B&B): wlroots 0.20.2 patched — backend.c backend_start() now
#   libinput_path_create_context + glob("/dev/input/event*") + libinput_path_add_device() (open_restricted still
#   routes through wlr_session_open_file/seatd). events.c handle_device_added() classifies each device into the
#   4-tier ladder (T0 internal bustype / T1 allowlist vid:pid / T2 proven-hook / T3 unknown), stores the tier,
#   logs "[input-trust] ... tier=N". Public API added: enum wlr_libinput_trust + wlr_libinput_get_device_trust()
#   (include/wlr/backend/libinput.h). Tier 2 is a documented HOOK — no per-device crypto proof wired yet, and
#   deliberately NOT read from the global verdict (that proves the SEAT, not the device).
#   DEPLOYED to /mnt/ksd: our libwlroots-0.20.so (strict-superset ABI — identical DT_NEEDED to stock; MUST
#   install vulkan-headers or vulkan-renderer=NO silently drops libvulkan.so.1), 54 libinput quirks copied to
#   usr/share/libinput, /etc/kushd/input-allowlist (planck 03a8:a4f9). Stock .so backed up as
#   libwlroots-0.20.so.stock. chroot ld-linux --list kidulwm+kboot = CLEAN.
#   SMOKE-TESTED (host, no udev, no compositor): 20 devices enumerated via path context — AT kb/touchpad/buttons
#   TIER0, Drop Planck TIER1 (03a8:a4f9), BT MX Keys/Master TIER3. Proves the no-udev enumeration + classification
#   against real hardware. (scratch/ksd-path-smoke.c prototype.)
#   NEXT: re-boot-test (Barticus BIOS-swap nvme1) — expect kushd.log "seated kidulwm" with NO "died kidulwm" loop,
#   AT keyboard + Planck produce input. REMAINING harden: Tier-2 crypto proof + netlink hotplug + kidulwm
#   per-device enforcement (the getter already exists).
#
# SESSION WRAP-UP (bobdotrix 2026-11-10) — KIDULWM SEGFAULT FIXED + DEPLOYED; REBOOT-TEST PENDING.
#   THE FIX: kidulwm was crash-looping with a use-after-free segfault (0x0) in Environ.getPosix
#   (main.zig:41, KIDULWM_NO_BACKEND lookup). Root cause: Server.init -> applyTitleBarEnvironment ->
#   setenv() REALLOCATES libc's environ VECTOR; Init.Minimal.environ is a SNAPSHOT of that vector, so any
#   getPosix() after the realloc reads freed heap. NOT a null environ — kushd's hand-off was fine
#   (XDG_RUNTIME_DIR=/run/user/1000 resolved). Two commits, signed B&B:
#     07cbfc8  backend: unset WAYLAND_DISPLAY before autocreate (pick DRM, not nested) [recovered verbatim — was pre-existing dirty]
#     bafe895  main: read environ before Server.init reallocs it (fix boot segfault)    [XDG_RUNTIME_DIR now REQUIRED, fails NAMED]
#   Built ReleaseSafe (deployed profile), FRESH cache, stamp verified bafe895+6d0a38c, deployed
#   /mnt/ksd/usr/local/bin/kidulwm (KSD root back to ro). OLD deployed cb643e7 NOT backed up on disk
#   (cp raced the ro remount) — recoverable from git history. NEXT: reboot into KSD, confirm kidulwm
#   seats clean (kushd.log "seated kidulwm" with NO "died kidulwm" crash-loop).
#
#   FORK FLAG CLEARED 2026-11-10 09:55: the kboot logdrain/devRules/log-path work + kushd
#   log-path work are now COMMITTED (kboot a7d513f 86ins/4del, kushd 68a102d, both signed B&B).
#   Re-verified the work was ALREADY DEPLOYED — the Nov 9 binaries carry it (strings show
#   /var/log/kboot.log + "kboot: forked logdrain" + "kboot: devrule" + /dev/dri in the on-disk
#   kboot; kernel.log/kboot.log/kushd*.log all persist at /var/log). The earlier "NOT deployed"
#   note was wrong on that point. No rebuild needed before flip — binaries match source.
#
#   STILL OPEN (carried): VMD revert — host root is ALSO behind VMD, needs a plan not a flip.
#
# SESSION WRAP-UP (bobdotrix 2026-11-09) — BOOT-BLOCKER SWEEP: WIFI FW BAKED + KIDULWM BACKEND FIXED + SOUND BAKED + PIPEWIRE RUNTIME COPIED.
#   Four fixes, closes the dual-boot path past wifi, the kidulwm crash-loop, and sound. STILL UNREBOOTED — one reboot
#   validates all three together (wifi + compositor + audio).
#   1) WIFI FW BAKED: iwlwifi probe+fw-load at ~0.876s is BEFORE root mount (~1.229s); a no-initrd baked driver can't
#      see /usr/lib/firmware on root. Baked via CONFIG_EXTRA_FIRMWARE="iwlwifi-QuZ-a0-hr-b0-77.ucode regulatory.db
#      regulatory.db.p7s i915/tgl_dmc_ver2_12.bin" + CONFIG_EXTRA_FIRMWARE_DIR="firmware" (staged under
#      linux-7.2.14/firmware/, subdir i915/). `nm vmlinux | grep _fw_` = 4 symbols; bzImage 18.5->19.0MB. CAVEAT:
#      regulatory.db + .p7s baked but NOT boot-verified (CONFIG_CFG80211_REQUIRE_SIGNED_REGDB=y).
#   2) KIDULWM BACKEND FIXED: crash-loop "Could not connect to remote display" (BackendCreateFailed). Root cause =
#      kushd mintSession (main.zig ~line 233) sets WAYLAND_DISPLAY=wayland-1 for EVERY user-class child, so
#      wlr_backend_autocreate picks the NESTED wayland backend instead of DRM. FIX: one unsetenv("WAYLAND_DISPLAY")
#      in KidulWM server.zig just before wlr.Backend.autocreate. Built -Doptimize=ReleaseSafe (8,365,160B), deployed
#      /usr/local/bin/kidulwm (backup kidulwm.bak-prefw). Do NOT set WLR_BACKENDS by hand — the VM rig's
#      WLR_BACKENDS=drm,libinput is a VM-only crutch; the real host wants the env CLEANED, not forced.
#   3) SOUND BAKED =y (kernel #5): own kernel had the entire sound stack =m (SND/SND_HDA_INTEL/SND_HDA_CODEC_HDMI);
#      no initrd + no module loader = zero ALSA ever (kernel.log showed no snd/hda lines). The distro kernel had been
#      supplying sound via initramfs snd-hda-intel.ko. Baked =y: SOUND + SND + SND_TIMER/SND_PCM/SND_HWDEP + SND_HDA +
#      SND_HDA_INTEL + SND_HDA_CORE + SND_HDA_GENERIC + SND_HDA_CODEC_HDMI (+_GENERIC/_INTEL) + SND_INTEL_DSP_CONFIG.
#      GOTCHA: olddefconfig AND syncconfig silently revert SND=y back to =m unless the top-level CONFIG_SOUND=y
#      umbrella is baked too (everything sits under `if SOUND`). scripts/config wants the CONFIG_ prefix
#      (--enable CONFIG_SND, NOT --enable SND). Verified: `nm vmlinux` = azx_driver_init + snd_hda_codec_hdmi
#      initcalls, zero snd-hda*.ko; bzImage 19.0->19.3MB.
#   4) PIPEWIRE/ALSA RUNTIME COPIED to KSD-root (byte-for-byte CachyOS, no systemd daemon): root had the pipewire/
#      wireplumber/pipewire-pulse binaries (BuildID f47c5152) but was MISSING the runtime — /usr/lib/spa-0.2
#      (support/alsa/audioconvert/...), /usr/lib/pipewire-0.3 (32 modules), /usr/share/pipewire + /usr/share/wireplumber,
#      libasound.so.2, /usr/share/alsa (8.8M incl ucm2), /usr/lib/alsa-lib. All copied. ksound was failing
#      pw_main_loop_new "can't make support.system handle" because spa-0.2/support was absent. wireplumber.conf already
#      ships support.logind=disabled (no systemd needed); libudev/libdbus/libsystemd present as libs. Barticus ruling:
#      carry PipeWire byte-for-byte NOW; native AIG/ALSA is deferred (pipedream / later tinker).
#   STATE: kernel #5 (sha c5534680...) on ESP vmlinuz-ksd; vmlinuz-ksd.bak-presound(#4) / bak-prefw(#3) / bak-vmd(#2)
#   kept. KSD-root + ESP unmounted clean. WATCH ON BOOT: WirePlumber's ALSA monitor leans on udev for device discovery
#   and KSD has NO udevd — if snd_hda_intel shows in kernel.log but no sink appears, that is the culprit (fix: static
#   ALSA node or direct-card enumeration). /dev/snd = root:audio 0660 via devtmpfs; kidul is in the audio group
#   (kushd setgroups) so access should hold.
#
# SESSION WRAP-UP (bobdotrix 2026-11-09) — #54 PANIC PINNED: PSTORE WORKED, ROOT= WAS A FS-UUID. FIX DEPLOYED.
#   PSTORE-EFI PROVED LIVE. The 13:50 boot-test panicked, and this time the REAL kmsg survived in NVRAM:
#   17 dump-type0-* vars (GUID cfc8fc79-…, LINUX_EFI_CRASH_GUID) decompress (raw deflate, -MAX_WBITS) to the
#   full boot log. VMD fix CONFIRMED GOOD: both NVMe now enumerate (nvme0n1 host + nvme1n1=KSD tower, p1 p2),
#   iwlwifi/i915 firmware absent (expected, no /lib/firmware yet) but boot proceeds PAST the old VMD panic.
#   NEW PANIC (real line, no blue screen): "Kernel panic - not syncing: VFS: Unable to mount root fs on
#   unknown-block(0,0)". Root cause = the cmdline said root=UUID=89bf75b0-… which is the FILESYSTEM uuid of
#   the ext4 KSD-root. The kernel's early-boot lookup (block/early-lookup.c early_lookup_bdev) resolves ONLY
#   PARTUUID=/PARTLABEL=/dev-name/devnum — filesystem UUID= needs initrd/udev, and this boot has NO initrd
#   (init=kboot). So root= never resolved → unknown-block(0,0) → error -6. FIX (deployed + verified on-disk):
#   ESP/limine.conf cmdline now root=PARTUUID=86e26299-62b3-4fc1-9e3a-aff29097dcf2 (the GPT partition uuid the
#   kernel's own panic partition-list already showed for nvme1n1p2). Old conf saved limine.conf.bak-fsuuid.
#   LAW-LEVEL NOTE: KSD uses PARTUUID (or PARTLABEL) for root=, NEVER root=UUID=<fsuuid>, on this initrd-less
#   boot path. NEXT: reboot, KSD-root mounts, kboot runs. (kboot init path still unproven past mount.)
# SESSION WRAP-UP (bobdotrix 2026-11-09, takeover of the stuck cert-log session) — PSTORE-EFI BAKED.
#   Same #54 boot-test, still panicking past the VMD fix (second fault unseen). Fixed the "can't see the
#   panic" problem: efi-pstore was compiled-in (CONFIG_EFI_VARS_PSTORE=y) but DEFAULT_DISABLE=y turned it
#   OFF. Flipped CONFIG_EFI_VARS_PSTORE_DEFAULT_DISABLE -> n (make olddefconfig), rebuilt bzImage
#   sha cb5771f1...ca6ed, deployed /tmp/ksdesp/vmlinuz-ksd (hash-verified on-disk). Old VMD kernel
#   preserved as vmlinuz-ksd.bak-vmd. Panic kmsg now persists to NVRAM under LINUX_EFI_CRASH_GUID
#   cfc8fc79-be2e-4ddc-97f0-9f98bfe298a0 (dump-type* vars). READBACK after boot-test (from host):
#   efivarfs at /sys/firmware/efi/efivars is already mounted; vars show as dump-type*-cfc8fc79-....
#   `xxd` them (pstore header + compressed kmsg) or `mount -t pstore` on host if enabled. NEXT: boot-test,
#   then read the REAL panic line instead of the blue screen.
# SESSION WRAP-UP (bobdotrix 2026-11-09) — #54 BOOT-TEST READY: VMD PANIC FIXED + KIDULKEY GATE TRUSTED.
#   HOST = Tiger Lake i7-11800H (NOT the miniPC — 11th gen, Intel RST VMD enabled). KSD tower on
#   nvme1n1: p1=KSD-ESP, p2=KSD-root (UUID 89bf75b0-cbfc-4b22-908a-c62229df37e9). Limine 12.9 UEFI
#   -> vmlinuz-ksd, init=kboot, NO initrd, kmodd(class "tv")=zero modules.
#   FIRST BOOT PANIC (2026-11-09): blue DRM-panic screen, CONFIG_PANIC_TIMEOUT=0 => hung. Root cause
#   CONFIG_VMD=m on a VMD host: BOTH NVMe (incl 980 Pro nvme1n1) sit behind VMD domain 10000:xx,
#   invisible to a module VMD (no initrd => vmd never loads) => root=UUID unmountable. FIX:
#   CONFIG_VMD=y baked, rebuilt bzImage sha 8cd5e615 -> ESP/vmlinuz-ksd (old 86af7eb2 saved as
#   vmlinuz-ksd.bak-novmd), hash-verified + synced. Kernel was tuned for miniPC gen9/10 (no VMD).
#   NEXT BOOT EXPECTATION: NVMe enumerates, root mounts, boot proceeds PAST the panic. BUT KSD-root
#   has NO /lib/firmware yet — iwlwifi .ucode won't load (no wifi) + i915 falls back. Add
#   iwlwifi-QuZ-a0-hr-b0-77.ucode + i915/tgl_dmc_ver2_12.bin (~2MB) before wifi matters.
#   KIDULKEY #53 (parked behind #54): fw#2 Ed25519 device-proof RE-VERIFIED LIVE (tap-sign VERIFY OK,
#   pubkey 20a6b571...aabe, 2nd tap same identity). Gate slice 1 PROVEN via production binary
#   kidulkey-gate -> TRUSTED exit 0; /etc/kushd/input-trust.pub burned + matches. BUG found: fw SIGN
#   arm loop has NO timeout (blocks forever after host gives up; recover by tap or reset) — fix before
#   live seat path. Remaining #53: VM-seat functional proof (kushd NETLINK detect + gate verdict ->
#   seat admits), gated on #54 boot-test. Slices 2-3 (kushd detect, kidulwm seatTrusted) built.
#   NOW: #54 boot-test on the 980 Pro (VMD fix deployed + verified). Boot, then wire the seat proof.
# SESSION WRAP-UP (bobdotrix 2026-10-31) — DOCKET #53 KIDULKEY: SPEC FROZEN AS LAW + HARDWARE SOURCED.
#   Cue "next" -> docket #53 KIDULKEY (the signing root). Step 1 (freeze spec as law) DONE:
#   docs/law/kidulkey.md v2 LOCKED (Barticus "lock & load" GSI), commit fd3d74a pushed to Codeberg,
#   signed B&B. kidulKey is a KEY FAMILY in three tiers, not one dongle:
#     ROOT    cold, keyring, ceremonies only (signs roster + mints subordinates).
#     SYSTEM  resident, slots into its HOME box (router/TV/server/gamingPC), one per box.
#     PERSONAL fingerprint, built INTO the keyboard/remote (gates banking/personal-touch taps).
#   Resolves crypto trust-ledger 2/3/4: WYSIWYS = trusted screen + finger (personal) / ceremony
#   (root); deniability = root signs WHO never WHAT; revocation = refresh-on-associate. Personal
#   shell: dual-computer keyboard (input BLE lean / bulk WiFi switched app-SoC), HD = just an
#   encrypted networked drive (NOT the vault), screen disposable. pair-for-life + tidy-up/zeroize.
#   HARDWARE (sourcing only, NOT ordered): nRF52840 (in hand) = prototype kidulKey + BLE; production
#   kidulKey = NXP EdgeLock SE050 (EAL6+, HW Ed25519/Twisted-Edwards) + nRF52840 transport. Input =
#   ESP32-C6 (RISC-V, BLE5+WiFi6+Thread; Barticus has ESP32s for keyboard tests). Fast half =
#   SpacemiT K1 RISC-V SoM (Banana Pi BPI-CM6 / Milk-V Jupiter NX; WiFi6 + M.2 PCIe x2) or pragmatic
#   RK3566. Don't chase WiFi7 yet. NEXT = step 2: NCS/Zephyr toolchain (multi-GB).
#
# SESSION WRAP-UP (bobdotrix 2026-10-30) — KTTY M2g SCROLLBAR DOT COMPLETE (grab & drag, speed,
#   activation, resize-race fix, horizontal parity). Commits 5ab81c4 + 756da59, signed B&B.
#   The "non-scrollbar scrollbar" is DONE: right-edge Bob's Dot that fades, reveals on hover,
#   and grabs+drags to seek 1:1. Barticus live-verified "it works beautifully" + "gsi".
#   - GRAB & DRAG: wl_pointer motion/button/enter/leave wired Window -> Surface. Hover the right
#     edge reveals the dot; left-press starts a drag that seeks 1:1 onto the dot's travel track
#     (full track = full scrollback, exact); release resumes the fade. New core method
#     Surface.scrollToRow(row) — absolute seek, bypasses wheel accumulation.
#   - ACTIVATION BAND 72px (~2x): dot reveals+grabs "when the cursor is almost there", not
#     pixel-precise. Safe: dot only exists with scrollback, and every TUI needing its right edge
#     (vim/htop/less) runs alt-screen = no scrollback = no dot = no interference.
#   - SCROLL SPEED: mouse-scroll-multiplier 3/1 -> 5 discrete / 2 precision (house default in
#     kidul App.run). HORIZONTAL now mirrors vertical (756da59): same multiplier + cell-size
#     accumulation, so a horizontal tick = as many columns as a vertical tick = rows.
#   - FIX (resize race): resize() now holds device.swap_mutex across freeBuffers+allocateBuffers+
#     swapTargetLocked — kills the intermittent pixman segfault (renderer mid-draw into a freed
#     surface). This was the "cutting out" Barticus saw.
#   - NEW SKILL `bobs-dot` (house lit-crumb primitive + scrollbar interaction). styles points at it.
#   DEPLOYED /usr/local/bin/ktty (ReleaseSafe, build green). NEEDS A FULL RELOG for the running
#   terminals to pick up the new binary. REMAINING (M2g tail): CFC chrome + KSD tokens + buffer
#   margins + two-line fish prompt, <100MB resident on REAL i915, mouse/selection/paste/clipboard.
#
# SESSION WRAP-UP (bobdotrix 2026-10-29) — KTTY M2f SCROLL INPUT WIRED (commit b65d894, signed B&B).
#   wl_pointer -> core scrollCallback is LIVE. Window.zig binds wl_pointer alongside wl_keyboard,
#   accumulates axis (precise) + axis_discrete (wheel notches) per wl_pointer.frame, prefers
#   discrete for wheel devices, forwards one scrollCallback per gesture. Surface.scrollCallback +
#   App wiring complete. Build green (-Dapp-runtime=kidul -Drenderer=cairo -Doptimize=ReleaseSafe),
#   installed /usr/local/bin/ktty 22:37:33.
#   OPEN (needs Barticus's eyes): wheel UP/DOWN direction is UNVERIFIED. kfiles and kidul-browser
#   disagree on axis_discrete sign (kfiles passes it through, browser negates it); libinput's
#   discrete value is the INVERSE sign of the continuous delta, so first scroll may feel backwards.
#   If inverted: flip ONE sign in pointerFrame (or pointerAxisDiscrete) in apprt/kidul/Window.zig.
#   NOT DONE: fade-away border SCROLLBAR (right edge, dot-peek, near-cursor/auto-scroll
#   visibility; reuse house drawSlider), horizontal scroll speed parity, CFC chrome + KSD tokens +
#   buffer margins + two-line fish prompt, <100MB resident on REAL i915.
#   KEYBIND RELOG: Mod4+Return + Mod4+y -> /usr/local/bin/ktty are IN keybinds.conf, but the
#   running WM still holds the old in-memory binding. keybinds.conf is parsed ONCE at startup
#   (Keybinds.load); .reload (Mod4+r) = requestQuit ONLY, does NOT re-read the file. A full relog
#   is REQUIRED to activate the new terminal keys. Running terminals are the OLD binary until respawn.
#
# SESSION WRAP-UP (bobdotrix 2026-10-29) — KTTY M2e CORE DONE + RENAME ("we finally have a
#   system that doesn't flicker"). khostty -> ktty (Barticus). Commits fa29e3e (cursor border),
#   980e310 (rename + M2e), e78dfd5 (kawung art), 553d5cf (BUILD.md). All signed B&B, both
#   builds green, installed /usr/local/bin/ktty. The terminal is COMFORTABLE now:
#   - type-FLICKER KILLED: tear-free present (back/present wl_shm buffers + wl_surface.frame
#     pacing + Cairo swap_mutex) — the one thing that had to die before "home".
#   - key auto-REPEAT (30/s, 500ms) + server-repeat dedup; ctrl utf8 (ctrl+o='o'+ctrl not 0x0f);
#     cursor heartbeat FADE (out 1.2s/rest 1s/in 1.2s, floor 0.15); house defaults 20pt,
#     bg #141414@96%, fg #c8c8c8, padding x14/y20.
#   - cursor BORDER fixed: chamfered-octagon OUTLINE (char visible); the .off carve was a
#     src_over no-op (rendered solid), now .src erases; the 45-degree chamfer was t/sqrt(2) thin
#     (corners looked missing), now uniform t via inner_chamfer = chamfer - t*(2-sqrt2).
#   - renamed app_id com.kidulwm.ktty, title/memfd/docs; keybind Mod4+Return (primary, natural
#     "tty on Return") + Mod4+y (secondary) -> /usr/local/bin/ktty; OLD /usr/local/bin/khostty
#     binary REMOVED. ktty name is clear (kitty=Kovid's GPU term, kty=K8s dashboard,
#     KiTTY=Windows PuTTY fork). NOTE: keybind changes need Mod4+r (reload = requestQuit ->
#     full WM restart) to take effect — the running WM still held the old Mod4+y->khostty
#     binding in memory, which is why a new terminal wouldn't open mid-session.
#   NEXT (M2f, top of docket #18): NO SCROLL INPUT YET — the kidul apprt binds wl_keyboard but
#     NOT wl_pointer. Core scrollCallback is fully written; needs a wl_pointer listener feeding
#     axis/axis_discrete -> scrollCallback. Then the fade-away border SCROLLBAR (right edge,
#     dot-peek, visible only near cursor or while auto-scrolling; reuse house drawSlider) and
#     horizontal scroll speed matching vertical. Recon done: kidulwm input/pointer.zig
#     handleAxis already forwards axis/axis_discrete/source/frame via seat.pointerNotifyAxis.
#   The running terminals are STILL the old binary until Barticus respawns (Mod4+y). Golden
#   image: drop ghostty when we return to it (Barticus).
#
# SESSION WRAP-UP (bobdotrix 2026-10-29) — KHOSTTY M2d INPUT LIVE (Barticus: "gsi indeed indeed").
#   keyboard -> termio is wired and LIVE-VERIFIED by Barticus: typing works, fish talks back,
#   lsblk prints, nano opens a treat. Commit b999be2 (signed B&B). New kidul/Key.zig translates
#   xkbcommon -> input.KeyEvent (evdev scan+8 -> input.Key via input.keycodes; mods via
#   xkb_state_mod_name_is_active Shift/Control/Mod1/Mod4/Lock/Mod2; utf8 via get_utf8; unshifted
#   codepoint from level-0 keysym). Window does xkb_state_update_key per press/release + tracks
#   left/right modifier sides + forwards key/focus via callbacks; Surface keyCallback/focusCallback
#   -> core encoder -> PTY. The "hello" seed is gone (shell prompt is the real content). Fish is the
#   login shell, so khostty spawns fish by default.
#   KNOWN (M2e): (1) text FLICKERS AS YOU TYPE — wl_shm buffer swap not yet mutex-guarded/double-buffered
#   against a concurrent renderer draw (must die before khostty is "home"); (2) no key repeat (no
#   repeat_info timer); (3) no paste/clipboard/mouse/selection. Then CFC chrome + KSD tokens + buffer
#   margins + two-line fish prompt (fish_prompt in ~/.config/fish), then <100MB on REAL i915.
#
# SESSION WRAP-UP (bobdotrix 2026-10-29) — KHOSTTY M2c DONE + INSTALLED + KEYBOUND (relog pending).
#   M2c landed (commit 820809b, signed B&B, both builds green): cairo renderer is now REAL — Buffer(T)
#   retains synced cell data, Target holds the apprt cairo surface over wl_shm, Texture holds the glyph
#   atlas, RenderPass.step draws bg_color/cell_bg/cell_text via cairo_paint/rectangle+fill/mask_surface.
#   kidul apprt wires a REAL core Surface + renderer thread; seeds "hello" via Surface.printString().
#   VERIFIED LIVE (bobdotrix): ReleaseSafe binary installed to /usr/local/bin/khostty (126MB); ran 5s
#   against live wayland-1 with NO crash, log showed runtime=.kidul + renderer.generic.Renderer(renderer.Cairo)
#   + io_exec started /bin/sh. (Headless weston blocks screenshot capture, so pixels = Barticus's eyes.)
#   KEYBIND: ~/.config/kidulwm/keybinds.conf Mod4+y -> spawn /usr/local/bin/khostty (kcell VACATED mod4+y).
#   KEY FINDING: keybinds.conf is parsed ONCE at startup (Keybinds.load()); .reload (Mod4+r) = requestQuit
#   ONLY, does NOT re-read the file. A keybind CHANGE needs a full WM restart (relog) to take effect.
#   NOT DONE (M2d): termio/PTY keyboard input, double-buffered wl_shm, binary rename (still says "ghostty"),
#   Mod4+Return/open_slide -> /usr/local/bin/launch-kidul-terminal.sh is MISSING (pre-existing breakage).
#
# SESSION WRAP-UP (bobdotrix 2026-10-29) — DOCKET #50 AIG 0.17.0 MIGRATION COMPLETE ("next >>> gsi").
#   The three remaining items are done. House now builds + runs on Zig 0.17.0.
#   1) PUSH: 14 migration repos -> Codeberg (12 existing remotes + kweather/kvaultd created private,
#      default main, via API). aig-0.17.0 branch pushed (b66e8f0cd1, NOT merged to main). All ahead=0.
#   2) TOOLCHAIN SWAP: /usr/local/bin/zig -> symlink /home/dad/dev/tools/zig-0.17.0/zig (official
#      0.17.0 interim, sha 7c61539a…). Pacman /usr/bin/zig (0.16.0) UNTOUCHED. Revert = rm
#      /usr/local/bin/zig. All 14 repos build clean under 0.17.0 (verified, exit 0 each).
#   3) VM-PROVE KidulWM: cb643e7 ReleaseSafe built under 0.17.0 (8.3MB), deployed to ksd-reset
#      /usr/local/bin/kidulwm. Boots clean (NRestarts=0), Virtual-1 1920x1080, bootcheck OK,
#      IPC get_layout/get_windows OK, deck renders (sha 777c008a… matched). The wallpaper
#      "CairoError" warning is PRE-EXISTING (42x since Sep-19) — not a migration regression.
#   FOLLOW-ON (separate track, NOT #50): aig 0.17.1 -> daily toolchain (VM-prove KidulWM under aig,
#   drop-in verify all repos, merge aig-0.17.0 -> main). Interim = official 0.17.0 until then.
#
# SESSION WRAP-UP (bobdotrix 2026-10-27) — KFILES FACE COMPLETE (Barticus gsi: "very good").
#   Six signed B&B commits (69b6396..66a6acb) on codeberg, all DEPLOYED to /usr/local/bin/kfiles.
#   SHIPPED: full-screen image viewer + "Open In…" picker (#40); the left-panel depth gauge (dir
#   name + shrinking ancestor-dot rail, rail halfway to the text); details split around the right
#   card (date above, type+size below, folder icon carries item count); ONE 36px text size across
#   the whole face; title-case "Drives/Kidul/Settings" pill bar that dims at the top; border-colour
#   secondary text so the CFC'd list name is the only full-white text.
#   BUGS KILLED: Esc-quits-app; empty-folder ghost back (DOWN hard-stops); 0-byte sizes/dates
#   (stat on a non-null-terminated path).
#   NEXT (candy, Barticus): #41 key auto-repeat + smooth scroll; #36 marquee; #42 tools opening.
#   Reopen Mod4+n to eyeball the live face.
#


# PENDING HANDOFF (bobdotrix 2026-10-27) — KFILES FULL-SCREEN VIEWER + OPEN IN (docket #40, DONE + DEPLOYED).
#   Barticus relogged mid-kfiles-design-proof and could not READ the /tmp/kfiles-*.png proof cards (the
#   right-third placecard is too small at lounge distance). Built BOTH asks in kfiles (no WM change):
#   (1) "View" verb in the drawer (image files) -> full-screen contain-fit viewer, filename pinned top,
#       Esc/Enter/Left/BackSpace dismiss back to the list. The slide's OWN surface renders the image
#       edge-to-edge (3x the old card), no xdg set_fullscreen, no KidulWM wiring.
#   (2) "Open In…" verb -> one-off submenu of the file kind's candidate programs (from the settings
#       opener map; e.g. image: xdg-open/viewer/feh/qimgv/gwenview). Enter launches the pick, Left/Esc
#       back to the verb list. Does NOT change the persisted opener.
#   (3) FIX (latent bug): Wayland.zig closed the WHOLE app on any Esc press — contradicted the "Esc never
#       quits" top-nav law and would have broken the viewer. Esc now only navigates back.
#   Harness pixel+vision verified: kfiles-viewer.png = photo.jpg contain-fit blue (centre 107,143,197,
#       corners dark bg), kfiles-openin.png = 5 candidate rows (xdg-open highlighted). Commit 9f1a96f
#   (signed B&B), pushed codeberg main. Deployed /usr/local/bin/kfiles sha f7511679… == build
#   (.bak-20261027-pre-openin kept). kfiles NOT running (relog) — reopen via Mod4+n (Files), NEVER
#   hand-respawn.
#   FOLLOW-UP (same session, Barticus gsi): the dotrix-field instr proof -> refined to the LEFT-PANEL
#   "DEPTH GAUGE" — current directory name on a large lit gold dot, ancestors as shrinking (dimming)
#   dots above; NO children, NO ancestor text, NO dot-field ("both too much — the centre panel already
#   lists the folder's contents"). Implemented in Renderer.zig (drawCrumbStack -> drawDepthGauge),
#   harness pixel-verified (3 ancestor dots y~382/408/434 + lit dot y~460 + "src"). Commit 3fa3114
#   (signed B&B) pushed codeberg. Deployed /usr/local/bin/kfiles sha a7364803… (.bak-20261027-pre-gauge
#   kept). Details block (date/type/size) KEPT — the gauge replaces only the crumb stack. Reopen Mod4+n.
#   FOLLOW-UP 2 (same session, Barticus gsi): LAYOUT SPLIT + two bug fixes.
#   Left = depth gauge ONLY: name centred H+V, dots a locked shrinking rail at far-left 27px (no details).
#   Details moved to the RIGHT: date ABOVE the card (fixed, muted), type+size BELOW (files EXT+size,
#   folders "Folder"+on-disk size). Folder icon now carries the ITEM COUNT inside (72px, couch-legible).
#   BUG FIXES: (1) empty-folder ghost back — DOWN past the last entry hit a phantom .preview focus where
#   RIGHT was dead and LEFT only snapped back to .files; DOWN now hard-stops at the bottom. (2) 0-byte
#   sizes/dates — loadDirectory stat'd a non-null-terminated path (std.fs.path.join) so st_size/mtime
#   came back 0; now null-terminated first (isDir/thumbFor already were). Commit c0c587f (signed B&B),
#   pushed codeberg. Deployed sha 219b8081… (.bak-20261027-pre-layout kept). Reopen Mod4+n.
#   FOLLOW-UP 3 (same session, Barticus gsi): TWEAK PASS. Unified text size 36px EVERYWHERE (gauge
#   name, right-side date/type/size, folder-icon count, pill labels). Pill bar title-case
#   "Drives/Kidul/Settings" (user label title-cased too) + SEMI-TRANSPARENT when at the top (fill
#   34/255, ring 0.30, focused label 0.55) — only the CFC'd mainstage element reads 100%. Gauge dots
#   bigger; dot rail now sits HALFWAY between the screen edge and the text's left edge (no longer
#   pinned 27px). Right details: size stacked under the type, bigger fixed gap above/below the card.
#   Commit a78425d (signed B&B), pushed codeberg. Deployed sha 0eaea557… (.bak-20261027-pre-unify
#   kept). Reopen Mod4+n.
#   FOLLOW-UP 4 (same session, Barticus gsi): FINISH PASS. Gauge name + right date/type/size ALL in the
#   border colour (#6a6354) — the CFC'd list name is the only full-white text. More air between type &
#   size (line_h 1.5). Unified last stragglers to 36px (settings detail_size 30→36; viewer name 30→36).
#   NOTE: all main-view text was already 36px — the apparent pill-bar size diff is DESCENDERS (photo.jpg
#   has p/j/g, ~37px tall; "Kidul"/"Drives" have none, ~28px) at the same font size. Commit 66a6acb
#   (signed B&B), pushed codeberg. Deployed sha a940f84b… (.bak-20261027-pre-mute kept). Reopen Mod4+n.
#   FOLLOW-UP 5 (same session, Barticus gsi "go for it"): #41 SCROLL INPUT wired. Mouse wheel
#   (pointerAxisDiscrete -> App.scrollWheel: files/drives/settings/drawer/submenu; positive = down)
#   + hold-to-repeat Up/Down (keyDown tracks the hold; run loop ticks App.tickScroll each frame —
#   280ms dwell, then 80->30ms accelerating interval). Immediate step still flows through handleKey,
#   so edge behaviour holds (Up@top -> home, Down@bottom hard-stop). Harness SCROLL TEST PASS (n=14).
#   Commit 31732e7 (signed B&B), pushed codeberg. Deployed sha d7abb559… (.bak-20261027-pre-scroll
#   kept). LIVE-CHECK for Barticus: wheel direction (+=down) + repeat feel; flip the sign in
#   pointerAxisDiscrete/scrollWheel if it scrolls backwards. Reopen Mod4+n.
#   LOCKED (Barticus gsi "goldilocks"): speed "just so damn nice" — 280ms dwell + 80->30ms accel
#   FROZEN, no retune. Wheel direction correct (no sign flip). Fade-in = anti-flicker: moveSelection
#   resets the settle clock every step, so fast scroll never re-fades the preview (zero flicker) —
#   it fades in only once the selection stops. Nothing further to do on #41.
#   FOLLOW-UP 6 (same session — the real bug Barticus found): scroll went jerky after changing
#   folders. Root cause: thumbFor decoded the FULL-RES image synchronously (stb_image, no downscale)
#   + a full-width R<->B swap INSIDE the frame loop, so every new image step blocked a frame (home
#   has few images -> felt fine; a photo folder hitches). FIX: the placecard now shows the glyph
#   while scrolling and only decodes once the selection settles (no scroll key held + >=120ms dwell).
#   New widget.scrolling flag (set by keyDown/keyUp/tickScroll) + THUMB_SETTLE_US=120ms cover hold +
#   wheel + rapid tap. Scroll is glyph-only -> silky; image still fades in on stop. Harness
#   DEFER GATE PASS + SCROLL TEST PASS. Commit e1d1367 (signed B&B), pushed codeberg. Deployed sha
#   e60c6c62… (.bak-20261027-pre-decodefix kept). Reopen Mod4+n. Residual (docket #43): stopping on a
#   HUGE photo still decodes full-res once — downscale + disk cache to come.
#   FOLLOW-UP 7 (same session, docket #36 marquee): the marquee drew a SINGLE copy that scrolled
#   fully off-screen, leaving a ~1.7s dead panel (the gap-minus-side-inset tail of the loop) before
#   snapping back. FIX: draw a SECOND copy offset by one loop period so the scroll is seamless —
#   copy 2 enters from the right as copy 1 exits left, fixed MARQUEE_GAP between them, no blank
#   frame ever. Speed 40 -> 50 px/s (120 RACED — Barticus "calmly moving, not racing"). Harness
#   marquee-continuity test (400 samples / 40s window, pixel-checks the soft-white name is always
#   present) PASSES. Commit 3559961 (signed B&B), pushed codeberg. Deployed sha 5a0b93b1…
#   (.bak-20261027-pre-marquee kept). Reopen Mod4+n. Speed (50) is live-tunable if it feels off.
#   NETWORK NOTE: Mullvad tunnel DNS (10.64.0.1) intermittently fails to resolve codeberg.org ONLY
#   (github/google fine, egress healthy); push rescued via DoH + temp /etc/hosts pin (removed after).
#   FOLLOW-UP 8 (docket #44, 2026-10-27): "Open IS the viewer". 'View' verb renamed 'Open' — for an
#   image it opens the in-app full-screen viewer; non-image falls back to the external opener; folder
#   still navigates in. The old external xdg-open path now lives ONLY in "Open In…". Viewer is
#   NAVIGABLE: Up/Down prev/next image (wrap, skip folders), Left/BackSpace/Esc/Enter back to the list
#   (Left = the kfiles-native back-out per Barticus — Esc "feels like something else"). PLAY: Space (or
#   the Play verb) starts a slow slideshow — next image every 60s (play_interval_sec, default 60s,
#   explicit never auto), stop via Space/back. Run-loop tickPlay advances it (reuses the marquee/scroll
#   keep-alive). Harness NAV+PLAY PASS (n=3: step/wrap/interval/stop). Commit 9795ca3 (signed B&B),
#   sha 801708fa…, pushed codeberg, deployed /usr/local/bin/kfiles. Reopen Mod4+n. REMAINING: SETTINGS
#   "Play interval" row + persistence + per-panel burn-time cap (interval max < panel burn time —
#   25yr-product law, Barticus) -> docket #45 Smart Tools. #45 is the NEXT pondering item.
#
#   FOLLOW-UP 9 (docket #47, 2026-10-28): TOOLS DRAWER = HALF-SPLIT. The drawer no longer takes
#   over the centre — the focused file's art holds the LEFT half (contain-fit), the tools sit CFC'd
#   at 3w/4 in the RIGHT half (36px, same as the rest), replacing gauge+placecard+list while open.
#   Harness + PIL pixel-verified (tools centroid 1438.8 vs 1440; file 481.7 vs 480). Commit f17b3ff
#   (signed B&B), sha fb2a9e46, deployed /usr/local/bin/kfiles (.bak-20261028-pre-drawersplit kept).
#   Reopen Mod4+n. Laws committed to KidulWM (codeberg): docs/law/move-copy.md (the LIFT) +
#   docs/law/open-flow.md (RIGHT flows, LEFT backs out, Enter acts). NEXT: #45 Smart Tools (per-type
#   table LOCKED) then #46 move/copy lift.
#
#   FOLLOW-UP 10 (same session, dockets #44/#47 fix): VIEWER RESTORED in the open flow. RIGHT now
#   flows: image -> full-screen viewer -> (RIGHT again) -> tools; non-image -> drawer directly;
#   Enter (main stage) -> tools (geek shortcut). Viewer takes render+input priority only while the
#   drawer is CLOSED (viewer_open && !drawer_open). Drawer = borderless (pure black), file title
#   moved ABOVE the art on the left, "Options" labels the tool list. Commit 6ff5c19 (signed B&B),
#   sha 39bd53fe, deployed /usr/local/bin/kfiles (.bak-20261028-pre-openflow kept). Reopen Mod4+n.
#
#   FOLLOW-UP 11 (docket #45, 2026-10-28): SMART TOOLS view+play SHIPPED. (1) In-app TEXT VIEWER —
#   txt/md/log/code open IN the viewer now (openViewer reads the file up-front, renderViewer branches
#   to renderTextViewer: monospace 28px, character-wrapped, top-aligned below the filename, Up/Down
#   scrolls, Enter/Esc/Left/BackSpace closes). (2) VIDEO/AUDIO primary drawer verb is now "Play"
#   (kmedia), not "Open" — image keeps Open+Play (slideshow). (3) Guest (Granny) sees ONLY Open/Play,
#   no "Open In…"/CRUD — docs/law/grannyize.md (the "Grannyize + hidden GeekFeatures" credo) frozen
#   commit a3eca28, pushed to codeberg. Commit f518de6 (signed B&B), sha 254a6427, deployed
#   /usr/local/bin/kfiles (.bak-20261028-pre-smarttools kept). Harness: TEXT VIEWER + DRAWER VERBS
#   PASS. Install/edit stay placeholders -> #48 (kernel/brigs "Smart File System"). Reopen Mod4+n.
#   NEXT: #46 move/copy — the LIFT.
#
#   FOLLOW-UP 13 (docket #45 follow-up, 2026-10-28, visual polish): CLEAN FILE GLYPHS. Barticus: the
#   non-image type glyphs were "really ugly line drawing" — "just text in a clean border is fine".
#   drawFileGlyph no longer draws the folded-corner file icon + tiny ext; it now draws a clean rounded
#   plate (1.4:1, gold border 0.45, muted fill 0.08) with the uppercase extension centred inside (36px
#   Fantasque, text_color 0.9) — ZIP/PDF/FLAC/... fileIconPath DELETED. Video keeps the poster plate
#   (play triangle); folders keep the icon + count. Harness renderState index 5/12 + filedrawer;
#   PIL-verified: "ZIP"/"PDF" centroid x=1600.0 (card centre 5w/6), plate 395x277 centred. Commit
#   cb53ccc (signed B&B), sha 6c7665da, deployed /usr/local/bin/kfiles. Reopen Mod4+n.
#
#   FOLLOW-UP 12 (docket #45 follow-up, 2026-10-28, the KLINKS): "play in kfiles = play in kmedia".
#   Barticus's seamless-play direction. The #45 "Play -> kmedia" wiring was WRONG — it launched the
#   kmedia WALL client, which ignores the path. Fixed: kfiles "Play" now routes through the WM's
#   media_play door (`kidulwm-control media_play <path>`) -> kplayCloseAny + kplay.sock 'open' ->
#   kplayd. Music (.mp3/.flac/.ogg/.opus/.m4a/.aac/.wav) = headless background (kfiles stays); video
#   = fullscreen; NEVER the kmedia wall. FROZEN: KidulWM docs/law/play-handoff.md (commit 61ba03a).
#   kfiles commit 8afe797, sha 41be942e, deployed /usr/local/bin/kfiles. GAP: video fullscreen from
#   kfiles (media slide closed) needs deck-level fullscreen (docket #49) — media_play fullscreens
#   only while the media slide is open. Music works NOW; Barticus to reload Mod4+n and try Play on a
#   tune.

# PENDING HANDOFF (bobdotrix 2026-10-25) — KFILES PLACECARD CENTRING DONE + TOP-CHROME SPEC FROZEN.
#   CENTRING (done + deployed): three sections now TRUE EQUAL THIRDS of the full width, NOT the padded
#   inner area. Poster details (date/type/size) CENTRED in the left third (w/6); placecard image
#   centred in the right third (5w/6); CFC list dead-centre (w/2). Before: details left-ALIGNED at
#   x+8 ("way off centre to the left"), card ~25px left of centre. Harness pixel-verified: card 1599
#   vs 1600, details 324 vs 320. Deployed /usr/local/bin/kfiles (sha 6df3bcbd…, .bak kept). Commit
#   0344949 (signed B&B) in /home/dad/dev/kfiles. Barticus verdict: "very nice".
#   RESPAWN TRAP (documented in kfiles skill): after a deploy, `pkill kfiles` + raw `launch-kfiles.sh`
#   does NOT seat the slide (toplevel maps but off-focus; TV keeps showing home slide). Barticus
#   reopens via Mod4+n (Files keybind -> homeSlideLaunch). Never hand-respawn.
#   DONE 2026-10-26 (signed B&B): G/H/I BUILT + DEPLOYED (bee9b84+c01de02+c0a7888), then the
#   TOP-NAV "focus = centre stage" redesign (commit 8471b42, deploy 198d3a6b). The focused top
#   slot (crumbs/[DRIVES]/[SETTINGS]) owns the centre + the stage (true CFC); before-elements left,
#   after-elements right; no Enter-to-open/Esc-to-close views — Esc returns to files, never quits;
#   collapsed "end crumb" + NEEDS FILLER identity slot at the SETTINGS hard-stop (kidul-filler-zones
#   law). Settings LEFT/RIGHT opener cycle nested one level down, preserved. Harness pixel-verified
#   (DRIVES/SETTINGS centre 960, filler ~1469). Deployed sha 198d3a6b (.bak = c6fed8c2, reopen
#   Mod4+n). FULL CFC refinement (commit 57af09a, deploy 17abd13f): the focused slot now drops to
#   the VERTICAL centre (h/2), not the top — pill bar CENTERED or ABSENT (kmedia slide law #1). The
#   stage list trades the centre: on a slot the pill sits at h/2 with a dim preview list below; in
#   the list the pill retreats dormant to the top and the focused row centres. Fixes the pill-vs-list
#   focus ambiguity (3-level distinction). Harness pixel-verified (pill centre 540 on-slot; top 86 +
#   list centre 540 in-list). Reopen Mod4+n. UNIFIED PILL TRACK (commit 0949a08, deploy d8b6f9b8):
#   top chrome is now ONE connected stadium track (THE PILL aesthetic — separators + sliding gold-ring
#   highlight). Focus always centred; [SETTINGS] FIXED right; ancestors VARIABLE-WIDTH (fit label) push
#   [DRIVES] left; deep path hard-stops [DRIVES] at the left edge and fades the MIDDLE crumbs, holding
#   the HOME FOLDER (basename home_root) as the trail's floor. Harness pixel+vision verified. NEXT
#   docket: browser #29 (flesh out with Barticus).
#   3-BUTTON PILL REVERT (commit d89cbf5, deploy c3503612): Barticus pivot — the unified crumb track
#   welded a nav-rail onto a breadcrumb trail & broke the hard-stop (focus wandered into crumb segs).
#   Back to THREE fixed buttons (media-player PILL): [DRIVES]|[HOME]|[SETTINGS], focused centred, the
#   others flank. HOME labelled with the user's name (user_label, KIDUL_USER env) — the 'only user'
#   made visible. Crumbs moved OUT of the bar to the TOP-LEFT VOID (read-only "you are here",
#   left-truncated, never a nav target). Movement DRIVES<->HOME<->SETTINGS, hard-stops both ends.
#   Harness pixel+vision verified. NEXT docket: browser #29 (flesh out with Barticus).

# SESSION WRAP (bobdotrix 2026-10-26, 11hr) — KFILES TOP-BAR REFINEMENTS (PLANNED, not built).
#   Barticus verdict on the 3-button bar: (1) pillsBar displays almost right but lacks the COLOURS
#   + a 1px border around the WHOLE bar (read as ONE stadium, focused gold-ringed, others dim);
#   (2) crumbs are NOT GOOD at the top-left — they merge into the LEFT panel with the details as a
#   vertical "tray" (crumb buttons + date/type/size rows, auto-centring); crumbs become NAV targets
#   (tap ancestor = jump) — that is the movement the bar was missing; (3) marquee blanks for a beat
#   between loops — speed it up + a fixed gap between name-end and name-repeat (daughter's idea,
#   cinematic always-moving). Logged as dockets #34/#35/#36 (fire 'next'). Fresh session ready.
#   CORRECTIONS + LANDING + TITLE (same session, later): (a) crumbs are DISPLAY-ONLY, NEVER navable
#   (kill the "tap ancestor = jump" idea). (b) LANDING LAW: when a top pill is CFC'd, ZERO crumbs show
#   — that clean landing (pills centred + user files centred below) is the GOAL look, Barticus loves it.
#   (c) the top filler is a KISS TITLE, never an app id: kfiles -> "Folders & Files" (+ "Drives" /
#   "Settings" on those pills), browser -> "Browser", media landing -> its own title; the ENTIRE space
#   above the pillBar is usable; classy-and-clean shared text style + cinematic goddess/movie corner
#   art (kidul twist). Logged as docket #37.
# LANDING LAW LOCKED (bobdotrix 2026-10-26): the three apps' cohesive look & feel frozen as
#   docs/law/landing.md (signed B&B). Media title = "Library" (Barticus). Corner art = Batik (not
#   goddess) in the user's border colour; title CENTRED; small purple&blue KidulWorks sig above the
#   focused pill (walks the eye title->sig->pill). Extends kidul-filler-zones + kfiles-top-nav;
#   grounds styles CFC. Q.A/B/C all ruled.

# PENDING HANDOFF (bobdotrix 2026-10-25) — EMBEDDED-PLAYER FORK INCIDENT + RECONCILE (LOCKED).
#   PROB: seasons/grouping/CFC/digit-jump/Collections built into embedded src/ui/media.zig on the
#   stale _deploy_quitfix fork (forked origin/main Oct 19 — BEFORE C2 ph1 Oct 20 + MEGA ROACH sweep).
#   WRONG LAYER: media player = kmedia CLIENT (Wall.zig + Expansion.zig); media.zig is BYPASSED/
#   retiring (slide-process.md C5). The media.zig seasons work duplicates kmedia/src/Expansion.zig.
#   FIX: quitfix 3354163 cherry-picked onto main (c73c2a2). Wrong-layer work ARCHIVED (never merged,
#   never deleted): tags archive/seasons-in-mediazig-2026-10-25 (=4725c7a) + archive/roach-c2-sweep-
#   2026-10-25 (=8b88d6e). FORBIDDEN-LAYER block added to top of slide-process.md. media.zig FROZEN
#   on main until kmedia client Wall filters by category.
#   GATING: pure KSD blocked on kushd (miniPC ~1wk out). Player FROZEN this week — pivot to kfiles +
#   browser. Full brain+repos+profile copy onto miniPC BEFORE any host conversion.

# PENDING HANDOFF (bobdotrix 2026-10-14) — TV logo fanArt + sizing + ABC consolidation + button text.
#   LOGOS (~/.local/share/kmedia/logos/, in-house dirty, NOT git): channel-9.png = transparent blue
#   "9"+dots mark (main Nine only, others untouched); abc-entertains.png = pink wordmark; abc-family.png
#   = white "ABC FAMILY" mark (was solid grey box). All transparent RGBA.
#   SIZING (target ABC-TV smallest -> ABC-Kids largest): 7 = 0.560 (was 0.729), 10 = 0.487 (was 0.170).
#   10 Drama/10 Comedy were mislabelled (streams are 10bold/10peach) -> renamed 10 Bold/10 Peach with
#   correct iptv-org logos (10-bold.png red, 10-peach.png purple; render ~0.25, wide circle+wordmark).
#   M3U: removed stale "ABC Me" from au.m3u + tv.m3u (ABC Me renamed ABC Family Jun 2025; its abc-me.m3u8
#   now = ABC Entertains). ABC streams were ALREADY correct (Family=abc-tv-plus, Entertains=abc-me).
#   CODE (src/ui/media.zig, committed + signed B&B): media pill/subcategory button text font_size_s(13)
#   -> font_size_l(22). Built ReleaseSafe, installed /usr/local/bin/kidulwm (backup .bak-20261014-234909),
#   zig build + zig build test clean. ACTIVATES ON RELOG.
#   VERIFY POST-RELOG: ABC Family/Entertains transparent, 7/10 sized right, pill text bigger.
# PENDING HANDOFF (bobdotrix 2026-10-14, close-of-session) — FULL BACKUP SCENARIO DONE.
#   Road-backup clone COMPLETE + VERIFIED (raw dd nvme0n1 -> nvme1n1; GPT GUID
#   90604B7B-8EA5-4D9D-B803-A88A5BAC5509 and LUKS UUID 248d082f-47a1-4fa5-a7be-331f70ce0b5b
#   target == source). RESOLVED 2026-10-14: clone removed. nvme1n1 now = 1TB miniPC TV drive
#   (old Proxmox install to be wiped; future kboot test bunny).
#   Also DONE: Codeberg push (27 commits), Apocalypse archive + VMs verified intact,
#   Tier-3 sweep (17 bundles + sda mirror + state). Change-log stamped.
#   Arion USB enclosure SUSPECT-DEAD (zero LUN). Mullvad fixed (Chief Camel, lockdown ON).
#   OPEN: knetd 5GHz band-steer — coded + deployed but DORMANT (scan() returns on first
#   2.4GHz dump, never sweeps 5GHz — see knetd skill pitfall + docket). krouter NEXT:
#   FPGA + fibre; WiFi7 = MediaTek mt7996 / Qualcomm ath12k (AP mode), SFP+ 10G server<->router.

Read THIS FILE first in any reset session. It is the live state of the Great
Reset (SYSTEM.md is the arbiter; this file is the running ledger). Update it
after every verdict. The old MEDIA CENSUS (embedded-player hunt, verdicts 1-28)
is retired — those verdicts live in git history and their laws survive in the
# kmedia + ksd-input-claim-law skills.

# VERDICT 139 (bobdotrix 2026-10-20) — C2 PHASE 2 DONE (BUILT + SMOKE-TESTED): KMEDIA REQUESTS FULLSCREEN, WM HONORS IT. NEEDS HOST EYEBALL.
#   kmedia de69f47: Wayland.zig syncs toplevel fullscreen to player_active — set_fullscreen on playback
#   start, unset on stop. No kplayd, no cross-process parenting: the video is kmedia's own in-process
#   render, and fullscreen is kmedia's toplevel going edge-to-edge.
#   KidulWM 3fd1aa4: window.zig wires xdg request_fullscreen -> server.windowSetFullscreen ->
#   deck.setFullscreenByWindow(window.id). Fullscreen is a SIZE (slide fills output); chrome law derives
#   zero-chrome from full-bleed geometry (focusedSlideIsFullBleed).
#   Verified on ksd-reset: both build green; WM boots clean (bootcheck OK) with the new listener; kmedia
#   seats clean (Phase 1 regression); no spurious fullscreen request on launch (wall mode).
#   NOT verified (needs HOST): play a movie -> kmedia requests fullscreen -> slide fills output -> zero
#   chrome; EGL video on host GPU (VM is pixman/shm, no GL). NEXT: host eyeball, then Phase 3 (delete
#   media.zig + media_slide.zig + fullscreen-video machinery + kplayd + WM internal_client host-surface).

# VERDICT 138 (bobdotrix 2026-10-20) — C2 PHASE 1.1 DONE: FOCUS-OR-SPAWN. (Phase 2 step 1 exporter REVERTED — correction.)
#   Phase 1.1 (KidulWM 7727f31): mediaCardToggle() is now focus-or-spawn — if a com.kidulwm.kmedia
#   client slide already exists on the spawn row, focus it (wall state survives); else spawn. Kills the
#   rescan-per-toggle pain. Verified on ksd-reset: toggle twice -> same kmedia pid, one window.
#   CORRECTION (recon, 2026-10-20): kmedia's client is SELF-CONTAINED — App uses Player.zig (embedded
#   ffmpeg, in-process decode + pulse + EGL present on its own toplevel), NOT a kplayd handoff. kplayd
#   (kplayd_main/kplayd_shell) is the WM's playback engine over kplay.sock. So the xdg-foreign exporter
#   (f52b49b) was a detour and was REVERTED (2d33df2) — no cross-process parenting needed.
#   Phase 2 (corrected): kmedia requests fullscreen (xdg set_fullscreen) + enforces zero-chrome on
#   playback; the WM honors it (fullscreens the kmedia slide). No kplayd, no 'parent' wire.
#   NEXT: phase 2 (kmedia fullscreen request + zero-chrome on playback; verify EGL video on host GPU),
#   phase 3 (delete media.zig + media_slide.zig + fullscreen-video machinery + kplayd + WM internal_client
#   host-surface exporter). Cache-load (verdict 134) still open, now low priority.

# VERDICT 136 (bobdotrix 2026-10-20) — MEGA ROACH C2 PHASE 1 DONE: MEDIA CARD SPAWNS KMEDIA CLIENT (APP SLIDE), COMPOSITOR media_player SLIDE BYPASSED.
#   Barticus ruling: "media.zig has no place" — WM's in-process media scene tree is to be retired (gsi).
#   media_card_toggle (keybind + IPC verb) now routes to Server.mediaCardToggle(): kill-then-spawn
#   /usr/local/bin/kmedia (house satellite singleton, ksignals precedent). kmedia's toplevel auto-seats
#   as an .app slide via handleNewXdgToplevel; the compositor no longer builds the media_player scene
#   tree on toggle. Commit 1ee6089 (server.zig + keyboard.zig). Verified on ksd-reset: toggle spawns one
#   com.kidulwm.kmedia window (mapped, pixman fallback graceful), second toggle respawns the singleton,
#   ZERO "media player slide open" logs. media.zig + fullscreen-video machinery stay wired but
#   unreachable — they retire in phase 3.
#   KNOWN GAPS (NOT host-ready yet): (1) kill-then-spawn rescans the library every toggle — needs
#   focus-or-spawn + kmedia cache-load (verdict 134 gap); (2) playback still rides the WM's fullscreen-
#   video path (media_play verb -> kplayd -> curtain), not the kmedia client's EGL surface — that is
#   phase 2 (xdg-foreign export in kmedia). Spec: kmedia docs/design/c2-client-ify.md.
#   NEXT: phase 1.1 (focus-or-spawn + cache-load), phase 2 (xdg-foreign + video-in-client), phase 3
#   (delete media.zig + media_slide.zig + fullscreen-video machinery).

# VERDICT 135 (bobdotrix 2026-10-20) — MEGA ROACH C1 SLICE 1 DONE: FIND-SHELL SCAN -> SCANNER (LAZY), BOOT PREWARM RETIRED.
#   media.zig no longer shells `find -L *.mkv` at boot (execFind/scanCategory popen path gone) and no
#   longer pre-decodes art thumbs on a prewarm thread (prewarmThread/spawnPrewarm + server.zig call gone).
#   getLibrary() now builds the library LAZILY on first media-card open via kmedia Scanner (scanRootAs for
#   movies, scanMusic for music), flattening the rich model into the SAME per-file LibraryEntry list the wall
#   renders today (the flat bridge; the structured wall = C2). Commits: KidulWM 0b67e5a, kmedia 4ab8e2d
#   (scanreal now reports the flattened count). build+test green; ReleaseSafe built + DEPLOYED to ksd-reset
#   (/usr/local/bin/kidulwm sha 9e2a990d, .bak-c1slice1 kept); smoke: media slide renders, TV scan 0 channels
#   (kmedia_lib in-process), no panic.
#   PARITY PROVEN (scanreal, host real tree): flattened movies 516 = old find 516, music 27 = 27. No files
#   lost in the swap. NOT retired yet: g_movies/g_music/g_tv globals + LibraryEntry (the flat bridge) — they
#   survive as the derived view until C2 deletes the WM's media presentation (kmedia becomes the client).
#   EYEBALL OWED: host relog — media wall should show all 516 movies / 27 music, identical look, now from
#   Scanner. NEXT: C2 client-ify (kmedia standalone Wayland client; no kushd gate — that is C3).

# VERDICT 134 (bobdotrix 2026-10-19) — MEGA ROACH C1 PREP DONE: REFRESH+LAZY-ART LAWS LOCKED, REAL-DRIVE SCAN PROVEN (EXTENDS 126).
#   Laws LOCKED (Barticus gsi, kmedia 92acd54): library-model "Refresh — lazy, never a timer"
#   (four triggers: additions=inotify / removals=lazy-miss / manual=rescan-button / purchase=
#   inject-on-delivery; NEVER boot, NEVER timer) + art-chain "Art resolution — lazy, not prewarm"
#   (art resolved only on request). Kills the WM's find-based boot scan + ArtPipeline prewarm.
#   Real-drive proof GREEN (kmedia 5636e96, harness `zig build scanreal`): Scanner produces the
#   real /mnt/sda_backup/Jelly library — 127 items = 119 movie / 8 series / 0 collection,
#   sections correct (movies=3 tv_series=3 kids_movies=116 kids_shows=5), music 11. Extends
#   verdict 126 (synthetic modeltest) to the REAL tree: Scanner is a drop-in for media.zig's
#   scanCategory/execFind + g_movies/g_music/g_tv globals.
#   FOUND: kmedia App.zig WRITES library.cache but never LOADS it (re-scans on init) — the
#   "scan once, deltas after" load path is UNBUILT C1 work.
#   NEXT ATTACK (fresh session): slice 1 — retire prewarmThread/scanCategory/execFind + globals
#   in src/ui/media.zig, build Scanner.Library lazily on media-card open. VM-first (ksd-reset),
#   small incremental commits. boot-state law also LOCKED+committed (KidulWM 3e3051e, docket #8).

# VERDICT 130 (bobdotrix 2026-10-14) — TV LIVE CHANNELS FOR THE ROAD: SEVEN AKAMAI + ABC GEO-BLOCK + FANART.
#   SEVEN main channel mid-migration to Akamai (npc-live-sevennetwork.akamaized.net): Sydney AND Brisbane
#   403 their AES keys; only Toowoomba (7livecloud) works. 7two/7mate/7flix unaffected (all still 7livecloud).
#   Swapped shipped /usr/share/kidul/tv/au.m3u Sydney/NSW -> QLD feeds (Seven->Toowoomba, 7two/7mate/7flix->
#   Brisbane, Nine->channel-9-qld, ABC->abc-qld); backup au.m3u.bak-20261014. Added "Seven Mackay" (seven-mky)
#   to household tv.m3u. mjh.nz has NO Wide Bay/Hervey Bay feed (Seven regions: syd/mel/ade/per/bri/twb/mky/
#   tsv/cns). Note: TvChannels dedups by DISPLAY NAME only (tvg-id ignored) — a name mismatch shows BOTH.
#   ABC "outside Australia" = mjh.nz c.mjh.nz resolver GEOTESTS the client IP: residential AU (Aussie
#   Broadband) -> DIRECT ABC master (Akamai hdntl tokens, works); datacenter (Mullvad/Host Universal) ->
#   broken proxy path (relative 1080p.m3u8 -> 404). FIX: kplayd now launches via `mullvad-exclude` (systemd
#   ExecStart) so live TV uses the residential IP. PROVEN end-to-end: open -> ok, playing=1 title=abc-qld,
#   direct Akamai stream + VA-API active. Split-tunnel is PID-based (whole kplayd = effectively live TV only,
#   movies/music are local); systemd re-runs mullvad-exclude on every respawn so exclusion follows the PID.
#   VPN: lockdown ON + autoconnect ON for the Hervey Bay trip.
#   FANART (KidulWM c5e110e, signed B&B): TV cards render channel logos (tvg-logo) instead of the deterministic
#   gradient. LibraryEntry gains `logo`; loadTvChannels populates it from tvg-logo; requestThumb uses the local
#   logo path directly (resolveArtPath finds nothing for http stream URLs). Built ReleaseSafe, installed
#   /usr/local/bin/kidulwm (backup .bak-20261014). ACTIVATES ON RELOG — verify channel logos post-relog.

# VERDICT 131 (bobdotrix 2026-10-14) — TV FANART STILL BLANK AFTER RELOG+REBOOT: PREWARM POISONED g_no_art.
#   c5e110e taught requestThumb the logo branch, but the BOOT PREWARM still called resolveArtPath(entry.path)
#   directly on the http stream URL -> null -> put every TV URL into g_no_art. requestThumb's fast path
#   (g_no_art.contains(entry_key)) then bailed BEFORE the logo branch, so no logo ever queued — movies worked
#   because their path IS a local file that resolves. FIX (KidulWM ac937bc, signed B&B): one entryArtPath()
#   helper owns logo-vs-chain resolution; BOTH the prewarm and requestThumb call it — the two can't diverge
#   again. Built ReleaseSafe c132bf71, installed /usr/local/bin/kidulwm (backup .bak-20261014-fanart-pre),
#   zig build + zig build test clean. ACTIVATES ON RELOG — verify channel logos now render.
#   LIPSYNC (separate, Barticus live): ABC + a couple channels lipsync WAY out; 7/9/SBS spot-on. This is the
#   "lesser-quality broadcast" class — feeds whose own A/V interleave is offset. Needs a per-channel A/V
#   offset allowance, NOT a player-clock change (a player bug would hit every channel). See DOCKET below.

# VERDICT 132 (bobdotrix 2026-10-14) — LIVE TV OPENS AS FILE (url=file): open_live IS DEAD CODE IN THE COMPOSITOR.
#   AVOFF probe (kmedia Timing.avoff, KMEDIA_TIMING=1) measured lipsync per channel: 7 ~0ms, SBS +25ms
#   (oscillating ±10ms = the "stuttery" cadence jitter), 9 ~±30ms, ABC -1000ms constant (feed A/V skew =
#   lipsync disease #1), Ten (10/10 Drama) and Indonesian = AUPTS jumps of -30s/-15s + STARVE vq=0 (PTS
#   discontinuity = disease #2, frozen). The tell: EVERY OPEN line said url=file, even live channels. Root
#   cause: kplayd has open_live + Player.openLive (reconnect/watchdog/discontinuity recovery/live ring cap)
#   fully built, but the compositor's kplay_client.zig had NO openLive method and server.zig routed music+movies
#   +TV all through kplayOpen(path) -> is_live=false for every channel, so live handling never engaged. Clean
#   feeds mask it; feeds with discontinuities freeze with nothing to rescue them. FIX (KidulWM, this commit):
#   kplay_client.openLive(url,key) + server.kplayOpenLive(url,key) + .result handler branches TV->open_live
#   <url> <id> (id = stable channel id, the watch-state key). Built ReleaseSafe 0854b01e, installed
#   /usr/local/bin/kidulwm (backup .bak-20261014-live-routing-pre). ACTIVATES ON RELOG — verify Ten/Indonesian
#   recover instead of freezing (url=live in timing log), 7/9/SBS unaffected. DEFERRED: PTS-discontinuity
#   REBASING if reconnect doesn't catch a live discontinuity; ABC av-offset (disease #1) is a separate card.

# VERDICT 133 (bobdotrix 2026-10-14) — TV FANART "WAY TOO BIG": LOGOS RENDERED WITH COVER-FIT, NOT CONTAIN.
#   Barticus eye-test after relog: channel logos render, but ALL of them read oversized for the cards.
#   (His "7/9/SBS look good" notes were the CHANNELS PLAYING, not the art — the art is oversized on every
#   card.) Root cause: renderTileArt used a COVER fit (@max scale) for every surface, correct for 2:3 poster
#   art but wrong for logos — a wide banner (10=600x300, abc-tv=1024x576, jogja=391x57, 7flix=1000x485) scaled
#   up until its SHORT side filled the 2:3 card, cropping the sides and blowing the mark up huge. FIX
#   (KidulWM f8a3a69, signed B&B): logos (entry.logo != null) now CONTAIN-fit (@min scale) with a 15% inset
#   pad — whole mark visible, letterboxed, never cropped. Poster art (logo==null) keeps cover. Built
#   ReleaseSafe 38a0101c, installed /usr/local/bin/kidulwm (backup .bak-20261014-fanart-fit-pre),
#   zig build + zig build test clean. ACTIVATES ON RELOG — verify logos sit inside the card, whole mark.
#   Tuning knob if too small = the 0.15 pad in renderTileArt (media.zig).
#   PLAYBACK (separate, already-diagnosed, NOT this commit): ABC out-of-sync = lipsync disease #1 (feed A/V
#   skew, needs per-channel av-offset allowance); 10 "stuttery" + jogja "play & stuttery/stop" = disease #2
#   (PTS discontinuity — open_live routing landed in verdict 132 but PTS REBASING still deferred); sky news
#   blackscreen = feed has NO video stream (session-31 curation, parked).

# VERDICT 129 (bobdotrix 2026-10-14) — KMEDIA ASYNC OPEN: POLL LOOP NEVER BLOCKS ON OPEN (STRUCTURAL FIX).
#   Verdict 128 bounded the 403-key wedge with a 20s deadline, but Barticus's point stood: the open
#   still ran ON the single-threaded poll loop, so a hung open stalled every verb for up to 20s.
#   "Streaming should use everything it can get to stay smooth" — and the loop must never block.
#   FIX (kmedia 58c90c1, signed B&B, deployed + proven): openPath/openLive spawn a worker (PendingOpen)
#   that runs openInternal off the loop; the loop finalizes on the next tick (install player +
#   ensureShell + best-effort reply — the compositor is fire-and-forget). closePlayer cancels an
#   in-flight open via stop_flag -> ioInterruptCb abort (bounded join; full close() if it completed
#   just before). openInternal now wires the interrupt callback + 20s deadline for BOTH live AND file
#   (was live-only), so file opens and cancellation are bounded too. The loop stays single-threaded
#   ON PURPOSE (one-usher doctrine: serialized lifecycle = no player-state races; multithreading the
#   loop would reintroduce them). LAW frozen: docs/design/async-open.md.
#   PROOF: drip-feed open in flight -> status from 3 separate connections answered in 0ms; open
#   aborted at 20.0s "err OpenFailed"; normal Seven open deferred ok at 5.6s (playing=1); close-in-
#   flight returned ok in 5ms. Deployed /usr/local/bin/kplayd sha 5139d4fe; rollback .bak-d4ff6244.

# VERDICT 128 (bobdotrix 2026-10-14) — KMEDIA BLACK SCREEN: LIVE-OPEN WEDGE BOUNDED (403-KEY LOOP).
#   Barticus live: "TV + movies black screen". ROOT CAUSE: kplayd (pid 1743) wedged inside
#   avformat_open_input on the Seven live channel — its AES key URL returned 403 (feed-side
#   rotating/stale hdnts token), and FFmpeg's HLS demuxer looped forever re-trying the key.
#   rw_timeout (5s) never tripped because the 403 reads FAIL FAST (they return, they don't block);
#   ioInterruptCb could not abort it because it was wired only AFTER open returned (old
#   Player.zig:511). The single-threaded poll loop was stuck, so kplayd stopped servicing the
#   socket -> every play verb timed out -> no video ever committed -> black screen.
#   FIX (kmedia f08ea00, signed B&B, deployed + proven): pre-allocate the AVFormatContext and wire
#   ioInterruptCb BEFORE avformat_open_input (avio_open2 inherits interrupt_callback from the
#   pre-allocated ctx), plus a 20s wall-clock open deadline (IO_OPEN_TIMEOUT_US) checked in
#   ioInterruptCb — a broken feed now aborts the open in <=20s with "err OpenFailed" instead of
#   wedging. Same gap fixed in reconnectLive (pre-allocate + wire + arm). Mullvad RULED OUT
#   (CloudFront Policy is time-only, egress AU Brisbane).
#   PROOF: (1) deployed /usr/local/bin/kplayd sha d4ff6244 == running pid exe == zig-out;
#   (2) drip-feed repro (bytes forever, rw_timeout silent) -> open aborted at EXACTLY 20.0s
#   "err OpenFailed", post-open status responsive (playing=0 live=0); (3) normal Seven open OK
#   (5.3s playing=1). Seven recovered on its own (fresh token) — this fix is the guard for the
#   NEXT 403 loop. Rollback: /usr/local/bin/kplayd.bak-c5c24e05 (pre-fix).

# VERDICT 127 (bobdotrix 2026-10-14) — DOCKET #7 NOTIFY-BRIDGE: SEAM SHARPENED + FORMALLY DEFERRED.
#   The "one live systemd remnant" is dormant, and its fix is gated on kushd-live.
#   SHARPENING (what the bridge actually IS): a RECEIVER. It implements
#   org.freedesktop.Notifications on the session bus (scripts/notify-bridge.py,
#   dbus-python + GLib) and forwards every Notify -> `kidulwm-control
#   notification_test` -> NotificationStore (home slide CFC feed). It does NOT
#   emit kidulwm's own notifications — kidulwm's surfaces (weather/media/etc.)
#   write the store directly via self.notificationAdd. So the seam is
#   one-directional: external app -> bus -> bridge -> IPC -> face.
#   THE "sd-bus" SEAM IS THE DEAD ZIG SCAFFOLD, not the live path:
#   src/notify-bridge/main.zig does @cInclude("systemd/sd-bus.h") and its main()
#   never even opens a bus (loads config, returns) — it is NOT in build.zig and
#   NOT compiled. The Python bridge uses dbus-python, no libsystemd. So SYSTEM.md
#   §2.4's "sd-bus" name = the scaffold, and it is a false start, not a dependency.
#   HOST STATE: bridge NOT installed, NOT running — no
#   /usr/local/bin/kidulwm-notify-bridge, no systemd user unit, no process.
#   The systemd user unit file exists only in-tree (config/systemd/user/).
#   I2/I7 VIOLATION is precise: the unit makes systemd the lifecycle owner of a
#   tentacle (I2 one-usher) and hardcodes uid 1000 + wayland-1 (I1). The fix =
#   kushd cues the bridge as a cued tentacle. GATED: kushd built+installed
#   (686c39d) but NOT running (docket #4/#24 GATE) — cannot route through a
#   usher that is not up, and proving it needs kushd live in a VM first.
#   RESOLUTION: FORMALLY DEFERRED. Un-block condition = kushd live as PID-1 (or
#   a VM proof). When it lands: kushd owns the bridge lifecycle with session-bus
#   + runtime env inherited from the usher (I1). DO NOT finish the Zig scaffold
#   on libsystemd (contradicts I7) — either keep the Python interim kushd-owned,
#   or build a native bridge on pure Zig D-Bus wire (no sd-bus). Docket #7 done.

# VERDICT 126 (bobdotrix 2026-10-14) — MEGA ROACH C1 PRECONDITION: SURVIVOR MODEL PROVEN.
#   The slide-process.md law (docket #24) says "reconcile the two model copies to ONE".
#   Census SHARPENED that: they are NOT two copies of one model — they are two DIVERGENT
#   models. The WM's media.zig builds a FLAT LibraryEntry {title, artist, path} by shelling
#   `find -L "*.mkv" | sort | head -1024` at boot (scanCategory/prewarmThread); kmedia's
#   Scanner walks dirs natively and builds the RICH MediaItem model (series/collection/movie,
#   seasons, episodes, norm, art resolution, MusicLibrary). The law already names the
#   survivor: kmedia's Scanner.Library. So C1 = make the WM consume kmedia's Scanner and
#   DELETE its find-shell copy — a real migration, not a copy-paste.
#   DONE THIS SESSION: committed the frozen law + companions in BOTH repos (KidulWM 99d571c,
#   kmedia 16c81e6, signed B&B), then built test_model.zig — a HEADLESS model proof
#   (zig build modeltest) asserting Scanner+WatchState produce the correct series/collection/
#   movie/music model from a synthetic /tmp tree: 5 movie items (2 flat + 1 folder + 1 series
#   + 1 collection), Bluey season/episode parse (S1=2, S2=1), Planet Earth collection,
#   normaliseTitle ("Oppenheimer.2023..." -> "oppenheimer"), MusicLibrary (album + flat track),
#   WatchState resume (bluey/1 watched -> nextUnwatched resumes at ep2). ALL PASS.
#   FINDING (pre-existing, NOT C1 scope): normaliseTitle strips at the LAST dot, so a folder
#   named "Planet.Earth" normalises to "planet" (it reads "Earth" as an extension). Folders
#   with dots in the name lose their tail. Logged, not fixed — flag if it shows in a real scan.
#   NEXT (C1 proper): swap the WM's scanCategory to consume kmedia Scanner.Library/MusicLibrary,
#   delete the find-shell + g_* globals + LibraryEntry, thread the rich model into MediaWidget.
#   GATE still: kushd built+installed NOT running — C3 (seating) needs it live. C1/C2 don't.


# (relog handoff 2026-09-21 resolved: hub WORKED — TV on Intel DP-3. See verdict 53.)
#
# (relog handoff 2026-10-12 RESOLVED, bobdotrix): Barticus relogged. VERDICT 115 closes it — full
#   red slide 1:1 + peek law verified per-output. See verdict 115 below.
#
# VERDICT 125 (bobdotrix 2026-10-13) — MEDIA SLIDE SELF-FRAME KILLED ON FULL-BLEED (the "ghost").
#   Barticus eye-tested verdict 122, saw "a border around the edges, not a full slide" on the media
#   card. Root cause (mapped): media.zig renderCard's as_slide path drew its OWN frame — a rounded
#   corner clip with transparent-outside (alpha-0 corners) + a 1px ring at the buffer edge — and
#   NEVER consulted focusedSlideIsFullBleed(). window.zig updateChrome gates on full-bleed; the
#   media card was carved out of that (chrome.md "what stays") so it drew its frame forever.
#   THE REAL GHOST: the corners weren't painted, they were alpha-0 HOLES revealing the wallpaper +
#   background-color layers beneath the card. Same pattern as the browser — any rounded-clip +
#   transparent-outside surface shows the layer under it at its corners. Not one ghost layer, a
#   porous-corner pattern.
#   FIX (build + test green, not deployed): chrome.md amended (media slide self-frame obeys the
#   full-bleed test, carve-out dies). renderCard gains full_bleed param; frame = as_slide && !full_bleed.
#   mediaSlideRefresh computes full_bleed from the media slide's OWN target rect (>= deck w/h) and
#   threads it through media_slide.renderToBuffer. Full-bleed = square, opaque, edge-to-edge, no ring.
#   Also found: card mat painted at 0.91 alpha (black-glass-halo, INTENTIONAL translucency) — not a
#   bug; if a full-card wallpaper wash is part of the ghost, 0.91 is the lever, but it's DESIGN.
#   DEFERRED to Barticus: keep 0.91 or go 1.0. Docket 22 implemented; docket 23 (dead Style.gap) open.
#
# VERDICT 124 (bobdotrix 2026-10-13) — "ESC STILL QUITS" WAS A STALE BINARY, NOT THE FIX.
#   Barticus relogged and Esc STILL closed the media slide (subcategory test too). Diagnosis:
#   running pid 419029 -> /usr/local/bin/kidulwm == sha ae66c272 (verdict 121's binary, deployed
#   11:51, which still calls mediaSlideToggle on Esc). The BACK/QUIT fix (5be1ae9) was committed
#   and pushed but NEVER built ReleaseSafe NOR deployed — verdict 122's "NOT EYE-TESTED" was the
#   tell, and this is stale-binary-detection variant "built but never installed". Contradiction
#   check CLEAN: the only mediaSlideToggle callers are mediaSlideFocusOrSpawn (Mod4+m spawn) and
#   the music-dismiss path (line 2791) — neither is Esc. No code fights the BACK/QUIT axis.
#   FIX: zig build -Doptimize=ReleaseSafe (7.14MB, rev 5be1ae9) -> rename-swap to /usr/local/bin/
#   kidulwm == sha 203122ba. Running pid still holds old inode (deleted) — live at next relog.
#   Esc-as-back is keyboard-testable AFTER relog: open media card, open subcategory, Esc collapses
#   it instead of closing the slide.
#
# VERDICT 122 (bobdotrix 2026-10-13) — BACK (Esc) AND QUIT (XF86HomePage) ARE TWO AXES, FROZEN.
#   Design (Barticus present): the remote has two left-of-crosspad buttons — NW = back-through-app,
#   SW = back-to-home. They must NEVER collapse into one key. Frozen in docs/law/back-home.md.
#   VERBS: BACK = walk UP one level in the current app (hard stop at root, no wrap, no fall-through).
#   QUIT/HOME = close the focused slide and reveal the deck (destructive). text-edit keys
#   (BackSpace/Delete/Home/End) stay a SEPARATE axis, scoped to text fields only — the `Home` keysym
#   (0xff50) is caret-to-line-start and must never be rebound to the home button.
#   KEYS: BACK = Escape (HID 0x29, the NW button). QUIT = XF86HomePage (0x1008ff18, the SW button,
#   the standard TV "home" key), same verb as Mod4+Q/Ctrl+Q close_focused (keyboard chord stays).
#   CODE: server.zig mediaSlideKey Escape no longer calls mediaSlideToggle (quit); it walks the ladder
#   (video_fullscreen -> videoFullscreenExit RETIRE; subcategory_open -> closeSubcategory; else hard
#   stop). keyboard.zig handleKey adds unmodified XF86HomePage -> close_focused, placed with the other
#   blind-safe/unmodified keys before the Mod4/Ctrl match.
#   BUILD: zig build + zig build test clean. Committed 5be1ae9, signed B&B (good sig), pushed origin main.
#   NOT EYE-TESTED: running compositor untouched. XF86HomePage has no physical sender yet (remote is the
#   north star) — relog + eye-test is Barticus's call. Esc-as-back is keyboard-testable NOW (open media
#   card, open a subcategory, Esc should collapse it not close the slide).
#
#   Bug (Barticus live, "the videos wont quit or esc"): on a fullscreen movie, ESC removed the
#   media card from the deck but the video STILL owned the output — black curtain held, deck buried,
#   only escape was opening another instance + playing a song on the other screen to churn the stage
#   free. Confirmed in session.log: "media player slide closed" with NO "fullscreen exit" after it,
#   and "scanout candidate — disabling overlay_tree (fullscreen video)" repeating (video_fullscreen
#   stayed true, phase stayed .idle).
#   ROOT CAUSE: mediaSlideToggle's close branch (ESC -> mediaSlideKey -> mediaSlideToggle) removed
#   the card (mediaSlideCloseOn + removeCompositorSlide) but never called videoFullscreenExit().
#   Every OTHER close door already guards: mediaSlideClose (line 2053), handleAction close_focused,
#   kplayStop (128bc9a), focusNext/focusPrev/overview. mediaSlideToggle was the last door without it
#   — a latent gap since the fullscreen-mode rewrite (596f80b, 2026-09-22), surfaced now that the
#   STOP door (verdict 120) no longer masks it.
#   FIX: mediaSlideToggle now exits fullscreen first when video_fullscreen (same guard as its
#   siblings). Symmetric with close_focused, which also exits-then-closes.
#   BUILD: zig build + zig build test + ReleaseSafe clean. Deployed mv-over swap -> /usr/local/bin/
#   kidulwm == zig-out (sha ae66c272). Running compositor UNTOUCHED — relog + eye-test = Barticus's call.
#   Fallback: sudo mv /usr/local/bin/kidulwm.bak-5905a101 /usr/local/bin/kidulwm + relog.
#
# VERDICT 120 (bobdotrix 2026-10-13) — STOP ON A FULLSCREEN MOVIE NO LONGER HOLDS THE STAGE.
#   Bug (Barticus live): STOP on a fullscreen movie killed sound+video but the media player STILL
#   owned the stage — the black curtain held the output, deck buried, card never returned.
#   ROOT CAUSE: kplayStop (server.zig) closed kplayd + cleared now-playing but never called
#   videoFullscreenExit(). The EXIT choreography (video 1->0 -> teardown -> curtain 1->0 -> deck
#   back in, fullscreen.md) never ran, so video_fullscreen stayed true and the curtain stayed at
#   opacity 1. mediaSlideClose and handleAction already guard with videoFullscreenExit() first —
#   kplayStop was the one door that didn't. STOP is routed XF86AudioStop (blind-safe, both screen
#   states) -> handleBlindSafeKeysym -> kplayStop.
#   FIX (128bc9a): kplayStop exits fullscreen first when video_fullscreen, then closes+clears for
#   the non-fullscreen (music) path. videoTeardown inside the exit path already closes kplayd +
#   clears now-playing, so no double-clear.
#   BUILD: zig build + zig build test clean. Deploy + eye-test OWED (needs relog — Barticus's call).
#   Pushed to codeberg (98a7541..128bc9a).
#
# VERDICT 119 (bobdotrix 2026-10-12) — WAKE PARKS CURSOR ON THE "NO1" SCREEN (KOGAN SLOW-WAKE KILL).
#   Bug: smartLock blank -> wake left the cursor where it was. On the Kogan (DP-3), which powers up
#   seconds behind the laptop panel, it resurfaces invisible on a still-black screen and the next
#   click/keystroke lands blind (killed the bobdotrix session mid-return). Barticus's fix (locked):
#   call the laptop the "no1" screen; on wake, park the cursor there.
#   CODE: outputs.toml [arrange] gains `primary = true` (Placement.primary, parsed in
#     output_layout_config.zig). Host marks eDP-1 (laptop) primary. server.zig warpCursorToPrimary()
#     warps to the primary output's logical box centre on screensOffSet(false) — every wake path
#     (blind-first-press, screen_off toggle). Mirrors the boot-park idiom (absolute warp, no relative
#     deltas; single-cursor-truth law). No primary declared -> no-op (previous behaviour). No UI change.
#   VERIFY: zig build + zig build test + ReleaseSafe clean (zig 0.16.0). Deployed mv-over swap ->
#     /usr/local/bin/kidulwm == zig-out (embedded rev = HEAD), .bak kept. Running compositor UNTOUCHED
#     — relog is Barticus's call.
#   Fallback: sudo mv /usr/local/bin/kidulwm.bak-* /usr/local/bin/kidulwm + relog again.
#
# VERDICT 118 (bobdotrix 2026-10-12) — SHUTDOWN VERB FIXED: SIGTERM -> CLEAN S5 POWER-OFF (WAS HANGING ON THE MOUTH).
#   Verdict 117's done-line MISSED the power-verb clause: kill -TERM 1 left the VM running. Root cause = THREE stacked
#   bugs in kboot shutdown() + a reboot-call hardening, all fixed + proven on a CLONE (ksd-boot-tweak, COW overlay on ksd-boot — original untouched):
#     (1) glibc signal() sets SA_RESTART -> the blocking waitpid(-1) in supervise() restarts on SIGTERM, never re-checks
#         the shutdown flag. FIX: sigaction, sa_flags=0 (no SA_RESTART).
#     (2) shutting_down/shutdown_sig non-volatile -> ReleaseSafe hoisted the read out of the while loop. FIX:
#         std.atomic.Value (seq_cst) for the flags.
#     (3) THE BLOCKER: terminateChildren() used a BLOCKING waitpid(-1, 0) after SIGTERM-ing knetd/kushd/getty. The
#         mouth getty is an INTERACTIVE bash, which IGNORES SIGTERM -> waitpid hung forever, sync/reboot never ran
#         (the i<40 timeout was dead code — waitpid blocks before i advances). FIX: WNOHANG reap loop (~2s grace)
#         then SIGKILL the stragglers.
#     (hardening, not a bug) reboot = raw reboot(2) syscall with explicit magic (0xfee1dead / 672274793) + cmd — the
#         own-the-primitive alternative to glibc's reboot(), equally proven (both reach ACPI S5).
#   PROOF (ksd-boot-tweak, live serial): kill -TERM 1 -> knetd/kushd/seats tear down (kushd unseats on SIGTERM, its
#     law) -> getty SIGKILL'd -> sync -> reboot(RB_POWER_OFF) -> kernel "ACPI: PM: Preparing to enter system sleep
#     state S5" / "reboot: Power down" -> domstate "shut off". SIGINT still maps to RB_AUTOBOOT (reboot).
#   Docket #4's power-verb clause is NOW genuinely closed. kboot src/main.zig changes UNCOMMITTED in /home/dad/dev/kboot
#   (review + commit pending Barticus). Media-lane flag from verdict 117 (video surface not mapping) stands.
#
# VERDICT 117 (bobdotrix 2026-10-12) — CONSOLIDATED COLD-REBOOT E2E: THE TOWER BOOTS ZERO SYSTEMD, ALL DAEMONS UP, CURRENT BINARIES.
#   Docket #4's done-line, re-proven as ONE clean cold reboot on ksd-boot (COW overlay, backing ksd-reset) with
#   TODAY's binaries (kboot 5368c4a + kmodd 5368c4a + kushd 686c39d, all ReleaseSafe, sha256-matched into the overlay):
#     grub init=/usr/local/bin/kboot -> kernel -> kboot PID-1
#       -> kmodd (tv class, no module load) -> knetd (foundation) + getty (mouth) + kushd (usher)
#       -> kushd seats seatd(service) + kidulwm(user) + ksound(user)  [13-act bill parsed]
#   PROOF (live, serial mouth + host):
#     /proc/1/comm = kboot; ps tree = 1:kboot -> {230:knetd, 231:bash(getty), 232:kushd} -> {233:seatd,
#       234:kidulwm, 235:ksound}. ZERO systemd: /run/systemd absent, no systemd process, no systemd unit for
#       any daemon. DHCP lease 52:54:00:0c:96:83 -> 192.168.122.88 (only knetd leases under PID-1); /tmp/knet/state
#       = "link 2 eth0 ... 192.168.122.88/24, gw 192.168.122.1". Face renders (clock 20:05, wifi icon, KSD logo) via
#       virtio-gpu. Session minted: /run/user/1000/{wayland-1, kidulwm-control.sock, ksound.sock}, /run/seatd.sock.
#   CUED TENTACLES PROVEN LIVE: cue -> kushd seats -> ACTIVE (kplayd pid 600, pipewire 649, wireplumber 651,
#     pipewire-pulse 656 — all kushd children). kplay.sock + pulse/native bound.
#   MEDIA PLAYS (pipeline): `open /home/kidul/test-media.mp4` (12s H.264+AAC, generated by ffmpeg, injected) ->
#     ok; status playing=1, pos_us 2.0s -> 5.0s advancing at real-time (audio clock drives it — VERDICT 96's
#     software-present fallback is live: "shell live: no EGL — software shm present (lossless fallback)", VAAPI
#     correctly refused on no-GPU). The video DECODES + the audio clock runs.
#   OPEN GAP (flagged, media lane — NOT a kushd ladder issue): the video SURFACE is NOT mapped to the face.
#     kidulwm-control get_windows = {windows:[]} while kplayd plays — no toplevel surface committed. The audio
#     plays (pos_us advances) but the video pixels never reach the deck. This is the kplayd software-present
#     surface-mapping path on the STALE Sep-19 face (kidulwm 7135488 2026-09-19 12:11 in the overlay), NOT the
#     kboot/kushd supervisor. Route to the media lane (kplayd present-path / docket #12 / kscope software-present
#     seam). Do NOT mark "media plays" fully-closed on visual until the surface maps.
#   LADDER VERDICT: docket #4 (BUILD kushd Phase 1) cold-reboot done-line PROVEN — kboot PID-1, all daemons up,
#     zero hands, zero systemd, cued tentacles seat + media pipeline runs. The "media plays" VISUAL caveat is a
#     media-lane follow-up, recorded below as its own item.
#
# VERDICT 115 (bobdotrix 2026-10-12) — POST-RELOG E2E PASSED: FULL 16:9 SLIDE 1:1 + PEEK LAW VERIFIED.
#   Barticus relogged; running compositor (pid 643410) embeds 98a7541 = verdict 114 peek-visibility
#   law is LIVE. Post-relog E2E (docket #4 close thread) ran clean:
#     drive14.py -> guest rendered 1920x1080 RED (drm-fill custom SETCRTC mode), brig-shim captured
#     the full 8294400 bytes (1920x1080x4) to /tmp/brig-frame.rgba.
#     brig-present -> "letterboxed 1920x1080 into 1920x1080 at +0+0" = ZERO letterbox, gap 0,
#     focus 1.0 -> the guest slide is FULL 16:9 1:1 (no bars, no misalignment). USER: "full red screen".
#   PEEK LAW VERIFIED per-output (scene_dump): brig slide (window_id=2) fullscreen on output 1; the
#   peek trees on output 1 (at 23,986 / 1807,20) are enabled=FALSE (removed over the content slide);
#   the peek trees on output 2 (at 23,2066 / 1807,1100) are enabled=TRUE (shown where nobody's home).
#   Exactly verdict 114 "if slide = remove peeks". Docket #4's AWAITING-RELOG thread CLOSED.
#   NOTE (then-open, now FIXED by verdict 116): the window chrome border ring drew 2px rects around
#   the full-bleed brig slide — "zero chrome over an app slide" (bf3650d) was SPEC ONLY.

# VERDICT 116 (bobdotrix 2026-10-12) — CHROME BORDER ON FULL-BLEED FIXED: GEOMETRY GATE, NOT THE FLAG.
#   Barticus (2026-10-12, after "full red screen"): full screen = ZERO chrome; 2+ slides sharing the
#   output = border on each slide; full -> smaller transition = border back SAME FRAME.
#   ROOT CAUSE: chrome was gated on the `slide.fullscreen` hotkey FLAG. Under the under/over change
#   (focus=1.0, gap=0) a slide is full-bleed WITHOUT the flag set, so the 2px border ring kept drawing
#   over a full-bleed slide (seen live over the brig's red slide, verdict 115).
#   FIX: SlideDeck.focusedSlideIsFullBleed() — GEOMETRY test (focused slide's target width/height >=
#   output box). Both chrome decision sites (server.zig per-output loop + headless fallback) call it:
#   TRUE -> clearChrome, FALSE -> updateChrome(true, .all). Empty deck + virtual end slots -> FALSE.
#   Unit test "focusedSlideIsFullBleed: full screen vs split" (full-bleed / split / empty / end-slot).
#   Law frozen: docs/law/chrome.md §2-§4 (full-bleed = no border; split = border each; geometry not
#   flag). Slide-unification-spec.md §5 (was SPEC ONLY, now BUILT).
#   VERIFY: zig build + zig build test + ReleaseSafe all clean; isolated nested-smoke PASSED
#   (scratch XDG_RUNTIME_DIR, per verdict 111). Deployed mv-over swap -> /usr/local/bin/kidulwm ==
#   zig-out (e5216914...), .bak-14e2497 kept. Running compositor UNTOUCHED — relog is Barticus's call.
#   Fallback if the relog shows a problem: sudo mv /usr/local/bin/kidulwm.bak-14e2497 /usr/local/bin/kidulwm
#   + relog again. Expected after relog: full-screen slide = no border ring; split two slides = thin
#   border on each; shrinking a full slide re-adds the border immediately.

# VERDICT 114 (bobdotrix 2026-10-12) — PEEK VISIBILITY LAW (2026-10-07): PER-OUTPUT, "IF SLIDE = REMOVE PEEKS".
#   Barticus (2026-10-07, recorded after the credit cut): each screen owns its own peek — fullscreen on
#   one stage never blanks the widgets on another. VISIBILITY LAW: "if slide = remove peeks" — hide ONLY
#   while a content slide (app / media) is focused. Empty deck (boot), the row ends ("nobody home"), and
#   the home slide (landing/launcher) all SHOW peeks from the FIRST frame — no delay.
#   CODE (189bdd2): server.zig updateOutput() predicate rewritten. The old law (VERDICT 108/109 + 110
#   naming) showed peeks only on row ends + home slide and hid them over app/media; the new law inverts it
#   to a single `content_slide` test (focused slide kind != .home), so hide = content-slide-focused and
#   show = everything else. No interface change. ReleaseSafe clean (zig 0.16.0).
#   DEPLOY (CORRECTED 2026-10-12 relog audit): the first mv-over swap (07:37) shipped a STALE build —
#   embedded rev 83a48d7, built 07:35, predating 189bdd2 (committed 07:36:52). Binary audit caught it
#   (running pid == deployed hash f74c23e9, but embedded rev 83a48d7 != HEAD 98a7541). Rebuilt at HEAD,
#   re-deployed: /usr/local/bin/kidulwm == zig-out, hash dea5fd84, embedded rev 98a7541. .bak kept.
#   relog is Barticus's call (running compositor PID 619618 is STILL 83a48d7 until relog).
#   NOTE: window-chrome border ring (window.zig updateChrome, VERDICT 112's separate item) is still unfixed
#   — "zero chrome over an app slide" remains the slide-unification spec (bf3650d), SPEC ONLY.

# VERDICT 113 (bobdotrix 2026-10-06) — OWNER CLASS LOCKED: THE FACE IS A FLAT SLIDEDECK, NO UNDER/OVER.
#   Barticus's angle: under/over is retired from the FACE. Every slide is a full screen; nothing sits
#   over or under a slide. The one distinguishing axis is OWNER CLASS (Barticus's word, locked): three —
#     host-owned  the face's own surfaces (home/media-player/overview). No arm.
#     cell-owned  the pen (kcell) — foreign DISTRO + our code, fork/exec arm.
#     brig-owned  the KVM guest — foreign CODE, the second arm.
#   Every app maps to exactly one. Owner class is a SEATING fact: kushd decides who's seated and by which
#   arm; kidulwm only CONSUMES it to tag a slide. NOT a boot fact (kboot/kmodd's machine-class tv|brig is
#   separate). Under/over survives ONLY below the face, in video+audio (scanout above the deck, the curtain,
#   the audio clock) = godcodemode.md + playback.md.
#   NAMING DISCIPLINE — three "class" words, never blurred: machine class (kboot: tv|brig), seat class
#   (kushd: system|service|user|restricted = the walls), owner class (face: host/cell/brig). Say the full
#   phrase. "CID" stays = AF_VSOCK context id (host CID=2, guest CID=3) — do NOT overload it.
#   Written to slide-unification-spec.md (LOCKED section) + ksd-vocabulary-law skill. No code change.
#   NOTE: this makes VERDICT 110's "under/over" naming historical; the peek-on-ends visibility still stands
#   (widgets only on row ends + home slide) but is now just "full-bleed slides", not "under/over".

# VERDICT 112 (bobdotrix 2026-10-06) — PEEK WIDGETS OVER APP SLIDES: ORDERING BUG, NOT A STALE BINARY.
#   Barticus: "still seeing the widgets over the top of the slides" after the 417e8ad relog.
#   Binary audit PROVED the deploy took: running compositor (PID 1783, up 19:31:15) md5 72bd7b97 ==
#   /usr/local/bin/kidulwm == zig-out, embedded rev 417e8ad (latest CODE commit; bf14713/bf3650d/4f0f3a5
#   are census/spec docs). scene_dump PROVED the peek trees (logo/clock/signage) still enabled=true over
#   the focused ghostty slide (window_id=1) on BOTH eDP-1 and DP-3.
#   ROOT CAUSE (order-of-operations, not the layout law): peek.zig setHidden() short-circuits on
#   `if (self.hidden == hidden) return`, but left_tree/right_tree are created LAZILY in updateOutput().
#   applyLayout calls setHidden(true) BEFORE updateOutput() (server.zig:3412 then 3437). On a boot/relog
#   straight onto an app slide: setHidden(true) flips hidden false->true and no-ops on null trees; then
#   updateOutput() creates the trees ENABLED; next layout setHidden(true) early-returns. Net: hidden=true
#   in the flag but the widgets render anyway.
#   FIX (order-independent): updateOutput() now re-asserts `setEnabled(!self.hidden)` on left/right_tree
#   right after creating them. Commit 1c81a02. ReleaseSafe clean; isolated nested-smoke PASSED; deployed
#   mv-over swap (hash fff38f07 == zig-out). Running compositor UNTOUCHED — relog is Barticus's call.
#   SEPARATE OPEN ITEM (NOT fixed here): the window chrome border ring (window.zig updateChrome(true,.all),
#   chrome_enabled=true) still draws four 2px rects around every focused non-fullscreen slide. 417e8ad only
#   touched peek visibility; "zero chrome over an app slide" is the slide-unification spec (bf3650d), SPEC
#   ONLY, no code yet. After this peek fix, the border will still be visible until that unification pass.

# VERDICT 98 (bobdotrix 2026-10-06) — MICRO-BRIG SLICE 1: THE ARM IS REAL. STOCK KERNEL + MINIMAL INITRAMFS BOOTS UNDER KVM.
#   The brig (KVM arm, cells.md) got its first empirical proof on the HOST (has /dev/kvm,
#   nested=Y): a stock kernel + a mkinitcpio `base`-only initramfs booted under qemu -enable-kvm
#   to a LIVE busybox shell. kernel = /usr/lib/modules/7.2.8-1-cachyos/vmlinuz (17.2MB) +
#   initramfs (HOOKS=(base), MODULES=()) = 7.5MB => ~25MB total, inside "tens of MB".
#   PROOF: boot -> "Failed to mount '' on real root" -> emergency shell -> "[rootfs ~]#"; then
#   uname -a EXECUTED over a PTY-driven serial -> "Linux cachyos 7.2.8-1-cachyos ... x86_64 GNU/Linux".
#   GOTCHAS HIT + FIXED (recipe + pitfalls now in docs/design/micro-brig.md §9):
#     - qemu64 DEFAULT CPU LACKS AVX: CachyOS glibc/busybox is -march=x86-64-v3 -> init hit vpxor
#       (AVX) -> SIGILL -> "Attempted to kill init! exitcode=0x00000004" panic. FIX: -cpu host.
#       (For a REAL brig, decide -cpu host vs a defined model — host exposes the full CPU.)
#     - -nodefaults STRIPS the serial port -> console=ttyS0 had no ttyS0 -> silent empty boot.
#       FIX: drop -nodefaults; -nographic alone wires serial to stdio.
#     - mkinitcpio writes the img root-owned 600 -> qemu-as-user "Permission denied". FIX: chown.
#     - busybox from mkinitcpio base is DYNAMICALLY linked (interpreter /lib64/ld-linux...), so a
#       hand-crafted cpio is a trap; MUST use the base hook (it copies glibc+ld into the img).
#     - piped stdin never reaches the emergency shell (needs a controlling tty); drive via PTY
#       (pty.fork). "sh: can't access tty; job control turned off" is normal, not a fault.
#   LESSON: the emergency shell is mkinitcpio's no-root path — a READY-MADE minimal prompt, but the
#   REAL micro-brig init is the SAME ladder as the host: kboot (PID-1) -> knetd + kushd (subordinate
#   usher). NOT kushd-as-init — kboot.md owns PID-1; the usher is always a killable child, never init.
#   knetd in the guest base gives the subordinate usher a network, so the two ushers talk (cells.md
#   superior-usher). Slice 1 proved the KVM boot + live userspace; slice 1b swaps busybox for
#   kboot->knetd+kushd.
#   RUNG COMPLETE (slice 1). Next: slice 1b — boot kboot (PID-1) -> knetd + kushd in the initramfs.

# VERDICT 99 (bobdotrix 2026-10-06) — MICRO-BRIG SLICE 1b: THE TRUSTED LADDER RUNS IN THE GUEST (kboot PID-1 -> knetd + kushd + getty).
#   The SAME boot ladder as the host boots inside a KVM guest. kboot as initramfs /init
#   (rdinit=/usr/local/bin/kboot) becomes PID-1, mounts (proc/sys/dev/devpts/shm/run/tmp),
#   forks knetd + kushd + getty. PROOF: /proc/1/comm = "kboot"; ps shows /usr/local/bin/knetd
#   ("knetd v0.4 up (event-driven)" = the foundation actually started) + /usr/local/bin/kushd
#   + -bash (getty, "-bash-5.3#") all running under PID 1.
#   Build: cp kboot+kushd -> /usr/local/bin (knetd already there), mkinitcpio HOOKS=(base)
#   BINARIES=(/usr/local/bin/kboot /usr/local/bin/kushd /usr/local/bin/knetd /bin/bash),
#   boot rdinit=/usr/local/bin/kboot. initramfs 14MB (+kernel 17MB = ~31MB, still "tens of MB").
#   PITFALL: kboot fopen's /tmp/kboot.log BEFORE mountEarly mounts tmpfs over /tmp, so in a bare
#   initramfs (no /tmp dir yet) fopen SILENTLY fails and kboot logs nothing — the "forked knetd
#   pid=X" lines never land. On the host (real root) /tmp exists so the log works. The ladder is
#   proven via /proc/1/comm + ps instead. FOLLOW-UP (kboot slice, not now): mkdir /tmp or fopen
#   after mountEarly so the log survives an initramfs boot — needed for slice 3+ debugging.
#   RUNG COMPLETE (slice 1b). Next: slice 2 — AV bridge over virtio-vsock + virtio-gpu scanout.

# VERDICT 100 (bobdotrix 2026-10-06) — KMODD PROVEN: THE BRIG LOADS ITS OWN MODULES (vsock + virtio_net LIVE).
#   Built kmodd (new kboot-sibling exe in kboot/): the machine-class module loader, kboot step 2.
#   kboot now forkKmodd()s (fork + waitpid) between mountEarly and startFoundation; kmodd reads the
#   class (kclass=brig via /proc/cmdline, or /etc/kboot/class, default tv), decompresses + loads that
#   class's modules, then EXITS (one-shot, not a body act — kboot does not respawn it).
#   PROOF (guest: -device vhost-vsock-pci,guest-cid=3 -device virtio-net-pci, append kclass=brig):
#   /proc/modules shows all six Live, dependency-ordered —
#     vsock 77824 (2 users) -> vmw_vsock_virtio_transport_common 61440 -> vmw_vsock_virtio_transport 20480
#     failover 16384 -> net_failover 24576 -> virtio_net 122880
#   MECHANISM (own-the-primitive; no kmod, no kernel-config dependency):
#     - mkinitcpio stores modules COMPRESSED (.ko.zst), so kmodd zstd-decompresses in USERSAPCE (links
#       libzstd) and init_module(2)'s the ELF bytes.
#     - PITFALL: finit_module does NOT decompress here despite CONFIG_MODULE_DECOMPRESS=y — it returns
#       ENOEXEC (errno 8) on .ko.zst. So kmodd decompresses itself rather than lean on the kernel.
#     - PITFALL: init_module does NOT auto-load deps (ENOENT errno 2 on a missing provider symbol) — load
#       in TOPOLOGICAL order. virtio_net -> net_failover -> failover; vsock <- _common <- _transport.
#     - Zig 0.16: linkSystemLibrary is on Module (kmodd_mod.linkSystemLibrary("zstd", .{})), NOT Compile.
#   virtio-gpu DEFERRED: its drm dep chain (drm_kms_helper/ttm etc.) is a later kmodd slice. vsock
#   (control plane) + virtio_net (network plane) unblock slice 2.
#   RUNG COMPLETE (kmodd). Next: the AV bridge handshake itself (host CID 2 <-> guest CID 3) + virtio-gpu scanout.

# VERDICT 101 (bobdotrix 2026-10-06) — BRIG SLICE 2: THE VSOCK WIRE IS LIVE (guest CID 3 <-> host CID 2, bidirectional).
#   With kmodd loading vsock in the guest, the AV bridge control plane is PROVEN end-to-end: a static
#   vsock-test client in the guest connected to CID 2 (the host), sent "ping-from-brig"; the host's
#   AF_VSOCK server received it and echoed "pong-from-host" back.
#   PROOF: "HOST ACCEPT from (3, ...)" = guest CID 3 reached host CID 2; "HOST GOT: ping-from-brig"
#   (guest->host) + "BRIG GOT: pong-from-host" (host->guest). Both directions carry bytes.
#   PITFALL (vsock, will recur in the real AV bridge): close-reset RACE — a server that send()s then
#   immediately close()s races the FIN against the data; the client reads EOF/partial. FIX: flush (sleep)
#   before close on the sender side, or shutdown(SHUT_WR) and let the peer drive the close.
#   Next rung: virtio-gpu scanout (pixels over the wire) — still needs its drm dep chain (later kmodd
#   slice); then the guest client renders as a host kidulwm slide.

# VERDICT 102 (bobdotrix 2026-10-06) — BRIG SLICE 2 SCANOUT: VIRTIO-GPU LIVE, GUEST HAS ITS OWN DRM DEVICE.
#   kmodd's brig class extended with the virtio-gpu chain. The drm core + kms/shmem helpers are BUILT-IN
#   on this kernel, so the ENTIRE loadable chain is just two modules: virtio_dma_buf -> virtio-gpu
#   (modprobe --show-depends order — much shorter than the feared drm_kms_helper/ttm chain). Booting with
#   -device virtio-gpu-pci gives the guest a real DRM device.
#   PROOF: /proc/modules shows virtio_gpu 114688 (virtio_dma_buf 12288, 1 user); /dev/dri/card0 (226,0)
#   + /dev/dri/renderD128 (226,128) present — the guest can render via its own virtio GPU.
#   Note: virtio_dma_buf is the SEAM — it is the dma-buf export path from the guest's virtio-gpu (the
#   no-host-/dev/dri pixel bridge cells.md names). The guest is now a COMPLETE foreign-code cell:
#   own GPU (virtio-gpu) + network (virtio-net) + control (vsock).
#   RUNG COMPLETE (scanout modules). Next: the actual scanout share — guest renders a surface, host
#   kidulwm shows it as a slide (the AV bridge payload).

# VERDICT 103 (bobdotrix 2026-10-06) — BRIG SLICE 2 SCANOUT SHARE PROVEN: GUEST PIXELS CROSS THE WIRE.
#   A raw-DRM guest program (drm-fill, no libdrm) modesets virtio-gpu's virtual connector and scans out a
#   solid red framebuffer. qemu boots with -vga none -device virtio-gpu-pci -display vnc + a unix monitor;
#   screendump captures the host-side scanout. RESULT: 1280x800 all-red, center pixel (255,0,0), 400/400
#   samples red — the guest's framebuffer is visible on the host. The AV bridge's PIXEL plane is proven
#   end-to-end: guest renders via its own virtio GPU, pixels cross, host sees them.
#   Pitfalls (raw DRM modeset, modern _ptr UAPI):
#     - connection-status enum (drm_connector_status) is NOT in the installed UAPI header — use numeric 1.
#     - GETCONNECTOR is two-phase: pass 2 MUST allocate props_ptr + prop_values_ptr too, or the ioctl fails.
#     - virtio-gpu's connector is type 15 (VIRTUAL), connection=1, default mode 1280x800 (26 modes).
#   Next: route the virtio-gpu scanout to a dma-buf kidulwm imports as a slide (the virtio_dma_buf seam),
#   instead of qemu's VNC window — the real "foreign code paints the face" integration.

# VERDICT 104 (bobdotrix 2026-10-06) — SHOW TIME: FOREIGN CODE PAINTS THE FACE.
#   First end-to-end VISIBLE render. The brig booted with -display gtk (qemu's GTK window is a native
#   kidulwm client); drm-fill modeset + filled virtio-gpu's framebuffer red; the window landed on the
#   kidulwm face as its own space inside the slide. Barticus confirmed: RED, in its own space, in the slide.
#   This is RUNG A (stepping stone): pixels go guest virtio-gpu -> qemu's GTK surface -> kidulwm.
#   RUNG B (production) is the dma-buf seam: import the guest's virtio-gpu framebuffer directly as a slide
#   texture (virtio_dma_buf / udmabuf), no qemu surface in between.
#   Note: screendump of the full GTK window sampled (0,0,255) at the centre — the red 1280x800 framebuffer
#   is a sub-region of the window; Barticus's eyes are the authoritative red confirmation.

# VERDICT 105 (bobdotrix 2026-10-06) — RUNG B SEAM: DBUS HANDOFF UNBLOCKED + MAPPED.
#   Leg 1 (blob+udmabuf, true zero-copy) is BLOCKED: qemu 11 ships the `blob=` flag but NOT the udmabuf
#   backend ("need rutabaga or udmabuf for blob resources"; no udmabuf device option / build link).
#   Leg 2 (qemu -display dbus) is the seam, UNBLOCKED + fully mapped:
#     qemu exports org.qemu.Display1 with /org/qemu/Display1/Console_0 (org.qemu.Display1.Console):
#       RegisterListener(h)  — take a unix-fd handle; qemu pushes the scanout (dma-buf fd via SCM_RIGHTS)
#       Width=1280 / Height=800 properties — the guest's virtio-gpu mode, already reported live.
#   This is the RIGHT architecture: own software virtio-gpu (2D), no host /dev/dri in the cell, pixels cross
#   via the dma-buf fd. virgl/rutabaga would put the host GPU INSIDE the cell (against cells.md).
#   Next: build the brig shim — a GDBus/sd-bus client that RegisterListener()s a socket and reads the
#   scanout dma-buf fd, then maps it as a kidulwm slide texture.

# VERDICT 106 (bobdotrix 2026-10-06) — BRIG SHIM WORKS: GUEST FRAMEBUFFER DELIVERED VIA DBUS P2P.
#   brig-shim.c (GDBus) receives the guest's virtio-gpu framebuffer from qemu's -display dbus over a p2p
#   D-Bus connection. RegisterListener(h) hands qemu one socketpair end; qemu is the D-Bus SERVER
#   (AUTHENTICATION_SERVER), the shim is the CLIENT (AUTHENTICATION_CLIENT, guid=NULL — client receives the
#   guid) and exports org.qemu.Display1.Listener at /org/qemu/Display1/Listener. qemu CALLS Scanout() on it.
#   RESULT: "Scanout 1280x800 stride=5120 pixman_fmt=0x20028888 (X8R8G8B8) bytes=4096000" — full framebuffer.
#   Delivery is the RAW-BYTES Scanout fallback, NOT ScanoutDMABUF: virtio-gpu 2D keeps the framebuffer
#   guest-local (shmem), so qemu's dbus display copies it to a pixman surface. ScanoutDMABUF needs blob+udmabuf
#   (blocked: qemu lacks udmabuf) or virgl (host GPU inside the cell — against cells.md).
#   Pitfalls: qemu = D-Bus SERVER, shim = CLIENT (guid=NULL + AUTHENTICATION_CLIENT). Listener methods (9):
#   Scanout(u,u,u,u,ay), Update(i,i,i,i,u,u,ay), ScanoutDMABUF(h,u,u,u,u,t,b), UpdateDMABUF(i,i,i,i),
#   Disable(), MouseSet(i,i,i), CursorDefine(i,i,i,i,ay), ScanoutMap(h,u,u,u,u,u), UpdateMap(i,i,i,i).
#   Next: import the framebuffer into kidulwm as a slide (wl_shm for raw bytes; the 4MB copy is the pacing risk).

# VERDICT 107 (bobdotrix 2026-10-06) — THE SEAM IS PROVEN: GUEST PIXELS ON THE FACE.
#   Full chain: guest drm-fill (red) → qemu -display dbus Scanout (raw X8R8G8B8) → brig-shim (p2p Listener)
#   → /tmp/brig-frame.rgba (verified 100% red, 1280x800x4) → brig-present (wl_shm client) → kidulwm slide.
#   Screenshot census: red=509124 (was blue=509124 with the fallback, then red when the shim's bytes flowed).
#   KEY FACTS: pixman X8R8G8B8 == wl_shm XRGB8888 byte-for-byte (ZERO conversion). Little-endian XRGB8888:
#   red=0x00FF0000, blue=0x000000FF (NOT 0xFF000000 — that's black; X is the HIGH byte). kidulwm slide =
#   1673x1064 logical (HiDPI 3840x4320 physical). xdg-shell: empty commit → roundtrip (ack configure) →
#   attach buffer; committing a buffer pre-configure is protocol error 3 "never been configured".
#   REMAINING POLISH: guest framebuffer 1280x800 vs slide 1673x1064 = misaligned top-left; fix = letterbox or
#   set guest mode to slide size. Then: continuous frames + frame-callback pacing (the "timing is everything" law).

# VERDICT 109 (bobdotrix 2026-10-06) — UNDER/OVER IMPLEMENTED + DEPLOYED (awaiting relog).
#   style.zig: default_split + horizontal_split -> {left=0.0, focus=1.0, right=0.0}; layout.gap 8->0.
#   Focus slide is now FULL 16:9 (1920x1080) == fullscreen (gap 0 removes the 8px inset that made it
#   1904x1064). Peeks stop being shrink-columns; the Peek widget (logo/clock/EXIT dots) is ALREADY in
#   overlay_tree and floats as glass ABOVE the full slide. Guest (drm-fill) + presenter (brig-present)
#   -> 1920x1080; initramfs microbrig-kmodd.img rebuilt with the new drm-fill.
#   VERIFY: ReleaseSafe build clean; nested-smoke PASSED (boot + client + quit, no crash). Deployed via
#   mv-over swap (/usr/local/bin/kidulwm, .bak-b4ae652 kept). Running compositor UNTOUCHED — relog is
#   Barticus's call. Post-relog E2E: drive14.py (guest 1920x1080) + brig-present -> full 16:9 slide 1:1.
#   PROOF CODE DURABLE: microbrig-proof/ self-contained (drive14.py paths -> /home/dad/dev/microbrig-proof/).
#   Commit b4ae652 (signed B&B).

# VERDICT 110 (bobdotrix 2026-10-06) — PEEK CHROME ONLY ON ROW ENDS + HOME (deployed, awaiting relog).
#   Barticus flipped the under/over into a cleaner law: EVERY slide is full-bleed with ZERO chrome
#   (no borders/corners/chamfers over a full page — "just a full screen display"). Widgets +
#   notifications belong ONLY where "nobody is home" — the row ends (before_first / after_last) and
#   the home slide (the landing/launcher). App + media slides render nothing over them.
#   CHANGE: server.zig applyLayout peek visibility. Old law hid the peek ONLY on a fullscreen slide;
#   new law SHOWS it only when empty_slot != .none (row end) OR the focused slide kind == .home.
#   Notifications already live on the home slide (NotificationStore -> home CFC section), so nothing
#   else floats over a slide. handleClick in peek.zig already gates on self.hidden, so the click
#   router (walk-to-neighbor) dies on app slides with the render — no separate path to change.
#   FINDING (deploy audit): the running compositor (PID 1753, 17:52) boots kidulwm=953d817, NOT
#   b4ae652 — VERDICT 109's deploy shipped a binary stamped BEFORE the under/over commit (build ran
#   at 953d817; b4ae652 committed after). Under/over never actually went live. This deploy ships
#   under/over + the peek change together from the full tree (HEAD 417e8ad).
#   VERIFY: ReleaseSafe clean; zig build test clean; isolated nested-smoke PASSED (boot + alacritty +
#   quit, 1 output driven, 0 drops) — run under XDG_RUNTIME_DIR=/tmp/... because the host compositor
#   owns wayland-1 + /run/user/1000/kidulwm-control.sock. Deployed mv-over swap -> /usr/local/bin/kidulwm
#   (md5 72bd7b97, matches zig-out; .bak-953d817 kept). Running compositor UNTOUCHED — relog is
#   Barticus's call. Commit 417e8ad (signed B&B).

# VERDICT 111 (bobdotrix 2026-10-06) — SLIDE-UNIFICATION SPEC NOTED + BRIG LIVE + SOCKET INCIDENT.
#   (1) Barticus's rethink frozen as docs/log/slide-unification-spec.md (NO code — spec only): every
#       surface is a full-bleed slide — ghostty/media-player/home all "just a slide in the deck"; media
#       stays OPEN parked LEFT and a playing movie/TV fades back to it on stop/quit (user-only open/close);
#       songs get a compact control panel at the top of the media slide; "home/landing" is renamed the
#       far-left slide (no landing/home page — left/right row ends are one thing). GREAT RESET core.
#   (2) BRIG IS LIVE: drive14.py PASSED — kboot PID-1 -> knetd v0.4 up -> drm-fill rendered 1920x1080 RED,
#       brig-shim captured 8294400 bytes (1920x1080x4) to /tmp/brig-frame.rgba. Guest renders the correct
#       16:9 slide size (under/over micro-brig.md §21 PROVEN in the brig). It plays a SOLID RED slide, NOT
#       media yet — actual media is still kmedia/kplayd on the host; the brig is the slide-producer proof.
#   (3) SOCKET INCIDENT (mine): the first nested-smoke run was NOT isolated (inherited the host's
#       KIDULWM_WAYLAND_DISPLAY=wayland-1 + XDG_RUNTIME_DIR=/run/user/1000), so the script's `rm -f` deleted
#       the RUNNING compositor's /run/user/1000/wayland-1 + kidulwm-control.sock. Host compositor (PID 1753)
#       still runs and serves existing clients, but NEW clients + IPC fail until relog; brig-present could
#       not present to the face for this reason. RELOG (Barticus's call) restores the sockets AND activates
#       the 417e8ad deploy (peek-on-ends + under/over). LESSON baked into devskills: always isolate the smoke
#       run. Spec + lesson committed; this entry is the durable record.

# VERDICT 108 (bobdotrix 2026-10-06) — 1:1 SLIDE PROVEN + THE UNDER/OVER FROZEN.
#   drm-fill now sets a CUSTOM virtio-gpu mode (1673x1064, hand-built drm_mode_modeinfo via SETCRTC)
#   instead of modes[0]. Guest "rendered 1673x1064 RED"; shim's final Scanout = 1673x1064 (7,120,288
#   bytes); presenter letterbox became a no-op (guest == slide) -> FULL RED SLIDE, no bars, no
#   misalignment. USER: "full red slide".
#   BUILD PITFALLS: (1) #include <drm.h> needs -I/usr/include/libdrm (not on the default path);
#   (2) sudo mkinitcpio emits a root-owned 600 image -> chmod 644 before qemu (user) can read it.
#   DESIGN FREEZE (Barticus): deck slide and fullscreen share ONE shape, 16:9 (1920x1080 logical =
#   BOTH outputs: Kogan scale 2, Predator scale 1). The peeks are HOST notifications, not guest
#   content -> they float as glass OVERLAYS ABOVE the 16:9 slide, not beside it (which reduced the
#   slide to 1673x1064). Guest renders 16:9 forever; fullscreen = show/hide the chrome layer.
#   "the wayland remote desktop we only dreamed of at the start." (micro-brig.md §21).

# VERDICT 94 (bobdotrix 2026-10-05) — COLD-REBOOT E2E PROVEN: THE TOWER BOOTS ZERO SYSTEMD.
#   The full ladder ran for real, end to end, on a disposable COW clone (ksd-boot):
#     grub -> kernel 7.1.11 -> init=/usr/local/bin/kboot (PID 1)
#       -> knetd (foundation: DHCP lease 192.168.122.88, ping 3/3)
#       -> kushd (usher: seated seatd + kidulwm + ksound) -> kidulwm (the face, rendered).
#   PROOF (three independent): (1) GUI came up "in full glory" (kidulwm only runs if kboot
#   forked kushd; nothing else in the boot chain can paint a desktop under init=kboot);
#   (2) DHCP lease 52:54:00:0c:96:83 -> 192.168.122.88 (only knetd can lease under PID-1);
#   (3) ping 192.168.122.88 3/3 0% loss. Zero systemd, zero display manager, zero getty.
#   THE TWO REAL BLOCKERS AND HOW THEY FELL:
#     - initramfs MODULES (verdict 91/93 said "blocked on serial 8250 / net / GPU"): it was
#       ALREADY solved — virtio_net + virtio_gpu are baked into the initramfs (confirmed via
#       lsinitcpio). serial 8250 is absent but NOT needed: observation rides on virtio-gpu
#       (the face) + DHCP/ping, not serial. The old note was stale.
#     - OBSERVATION LIMIT (no sshd, no serial under PID-1): solved by (a) grub cmdline
#       console=ttyS0,115200 for serial capture, (b) DHCP lease + ping as network proof,
#       (c) Barticus's eyes on the virtio screen for the face.
#   GOTCHAS HIT AND FIXED EN ROUTE:
#     - FIRST boot attempt hung at "pci 0000:00:01.0: BAR" @ 0.379s — a virtio-gpu PCI BAR
#       stall in the STALE slice-12 overlay (had console=ttyS0 + init=kushd leftovers).
#       NOT our code: same kernel/initramfs/video config as ksd-reset (which boots clean).
#       Fixed by REBUILDING ksd-boot fresh: rm stale overlay -> qemu-img create -F qcow2 -b
#       ksd-reset.qcow2 -> copy ksd-reset's XML (new uuid, new MAC 0c:96:83, ksd-boot_VARS.fd).
#     - Fresh clone had NO UEFI boot entry ("No bootable option or device was found") because
#       the new NVRAM was blank. Fixed by copying ksd-reset_VARS.fd -> ksd-boot_VARS.fd (same
#       GPT UUIDs via COW backing, so the boot entry resolves verbatim).
#   LESSON: a COW clone shares the BACKING's kernel/initramfs/binaries (they show up "already
#   there" on the fresh clone) but the OVERLAY is where the UEFI NVRAM + grub cmdline live —
#   refresh those explicitly. And guestfish WRITE mode crashes under nested virt; use
#   qemu-nbd + mount to inject files into a disk instead.
#   RUNG COMPLETE. Remaining on the ladder: (a) kboot logdrain + getty (the mouth), (b)
#   machine-class branch (kmodd), (c) kplayd cued + media playing under PID-1 (the cued
#   tentacles were in the bill but not cued this boot), (d) Secure Boot on real hardware.
#
# VERDICT 95 (bobdotrix 2026-10-05) — THE MOUTH IS OPEN: SERIAL SHELL + HTOP ON THE FACE.
#   kboot slice-3 "mouth" rung done in two commits: d3224ea (getty) + bba0319 (devpts).
#     - GETTY: kboot now forks a THIRD child (the getty) alongside knetd+kushd. Instead of
#       agetty (whose --autologin + --login-program feed the username to bash as argv[1],
#       which bash reads as a script path -> EISDIR "Is a directory"), we do the getty dance
#       INLINE: open /dev/ttyS0 (O_NOCTTY) -> setsid -> TIOCSCTTY -> dup2 0/1/2 -> exec
#       /bin/bash with argv[0] "-bash" (login shell). No login/PAM: possession of the serial
#       port IS access (possession-not-password). Supervised like knetd (immediate respawn).
#       PROVEN: serial console gives [root@archlinux /]# with zero systemd/PAM/login.
#     - DEV/PTS: devtmpfs does NOT create /dev/pts, so the old devpts mount() failed ENOENT
#       (silently swallowed by _ =). Result: openpty() broke -> ghostty "OpenptyFailed" /
#       "too many pty open", and 'ghostty -e htop' opened an EMPTY window. Fixed by mkdir
#       /dev/pts before the devpts mount (also /dev/shm before tmpfs).
#   THE HTOP TEST BARTICUS WANTED — htop ON THE DESKTOP (not serial text), on the face:
#     ghostty 1.3.1 (the terminal concept, launch-kidul-terminal.sh) launched as a foreign
#     Wayland client:  runuser -u kidul -- env WAYLAND_DISPLAY=wayland-1
#     XDG_RUNTIME_DIR=/run/user/1000 GHOSTTY_RESOURCES_DIR=/usr/share/ghostty
#     ghostty -e htop   -> kidulwm-control get_windows shows {window_id:1, title:"htop",
#     mapped:true}; htop runs pid N (STAT Ss+, session leader) on a clean /dev/pts/0.
#     EGL warns (ZINK vkCreateInstance fails, no GPU) but falls back to llvmpipe OpenGL 4.6 —
#     renders under the pixman compositor. 8 procs total, no systemd, load 0.00.
#   LESSONS:
#     - devtmpfs gives you device nodes but NOT mountpoints; mkdir /dev/pts (and /dev/shm)
#       BEFORE mounting them, or the mount silently no-ops and openpty breaks later.
#     - agetty's autologin+login-program don't compose; a real mouth is ~10 lines of inline
#       getty (open/setsid/TIOCSCTTY/dup2/exec), no PAM, no util-linux dependency.
#     - ghostty runs on the SOFTWARE (pixman) path via llvmpipe; the MESA/ZINK errors are
#       noise, not fatal.
#     - kboot's third child is the mouth; it is the OBSERVATION rung that makes every later
#       rung (kmodd, kplayd) debuggable without a second box.
#   RUNG COMPLETE. The tower can now be watched from inside: serial shell + GUI terminal.
#
# VERDICT 96 (bobdotrix 2026-10-05) — KPLAYD SOFTWARE-PRESENT FALLBACK BUILT: MEDIA PLAYS ON A NO-GPU VM.
#   The last "media plays" blocker (verdict 95 note) falls. kplayd now presents video pixels
#   WITHOUT EGL/GLES2 zero-copy. On a no-virgl VM, Mesa llvmpipe makes Gl.init() return NON-NULL,
#   so the old code flipped zero_copy_ok=true -> decode tried the dead VAAPI path -> no frames,
#   presentBlack() forever, poll loop wedged. The software branch never fired because `gl != null`.
#   THREE fixes in kmedia:
#     1. EglShell.init() REJECTS software GL at the source: after eglMakeCurrent, query
#        glGetString(GL_RENDERER) for softpipe/llvmpipe/swrast -> destroy surface/window, return
#        error so gl==null. (commit 12dada1)
#     2. kplayd_shell.render() calls presentSoftware() when gl==null: blit the decoded BGRA frame
#        (letterboxed, nearest-neighbour) into the shm double-buffer, attach to main surface,
#        damage, commit. (commit 12dada1)
#     3. EglShell caches software_renderer process-globally: llvmpipe eglMakeCurrent SEGFAULTED
#        (0x28) on a SECOND init (close+reopen in the same process); once software is seen, skip
#        EGL entirely forever. (commit 7bc14de)
#   PROVEN: detection fires ("[egl] software renderer 'llvmpipe...' rejecting GL"), gl==null,
#   pos_us advances (was stuck 0), FRAMETRACE kplay climbs. This shm blit is ALSO the kscope
#   TV-side seam ("paint pixels on cue") — the same present path a thin client needs.
#   RUNG COMPLETE: plumbing + present both proven on the no-GPU VM, zero systemd.
#
# VERDICT 97 (bobdotrix 2026-10-05) — BOOT-HANG AFTER HARD DESTROY: ROOT CAUSE + START-FRESH REBUILD.
#   After the kplayd deploy, "reboot the VM" went to `virsh reboot` — a NO-OP (kboot PID1 has no
#   ACPI power-button handler). Reached for `virsh destroy` (hard power-cut on a running COW
#   overlay) -> guest ext4 journal left dirty -> next boot hung. Serial showed it got PAST
#   virtio-gpu (`[drm] Initialized virtio_gpu` + "Run /init" fired) to the SATA/cdrom probe —
#   NOT last night's stale-overlay virtio-gpu BAR stall (0.379s). Same "cdrom: Uniform CD-ROM
#   driver" line on the framebuffer, different mechanism — serial is the honest witness.
#   RECOVERY = start-fresh rebuild (the overlay is disposable): cp -a backup -> qemu-img create
#   -F qcow2 -b ksd-reset -> re-inject grub init=kboot line + current kushd/kplayd binaries +
#   bill (the backing carries OLD copies of all three — a naive rebuild silently reverts session
#   work) -> start. Recovered: ping OK + GUI face renders (clock 23:58, KSD logo, wifi icon) =
#   kboot->knetd->kushd->kidulwm all up. sshd is NOT in the bill (manual convenience, dies on
#   reboot) — "ssh refused after fresh boot" is NOT a regression.
#   LESSON: never `virsh destroy` a running ksd-boot without a guest-side `sync`; the full
#   start-fresh recipe is now in the kidul-system-daemons skill.
#
# VERDICT 93 (bobdotrix 2026-10-04) — KBOOT FOUNDATION FORK LANDED; KNETD SURVIVES KUSHD.
#   kboot slice 3 (commit 33a869e): kboot now forks BOTH knetd (foundation) AND kushd (usher)
#   as its own children, supervising both via waitpid(-1) — respawn whichever dies (knetd
#   immediate, kushd backoff). This makes the recovery law TRUE IN CODE, not just on paper:
#   "knetd survives kushd" because knetd is kboot's child, NOT kushd's.
#     - startFoundation() forks knetd FIRST (usher stands on it to mint pens)
#     - generic execChild()+hardenChild() apply the 3 walls (ptrace drop/signal reset/fd close)
#       to BOTH children identically
#     - signals installed in BOTH modes; only PID 1 turns them into reboot
#     - terminateChildren() clean teardown
#   PROVEN on ksd-reset: tree kboot->knetd+kushd (both PPID=kboot). kill kushd -> knetd SURVIVED
#   (never re-forked, pid 479038), kushd respawned (new pid 479354). kboot log:
#     forked knetd pid=479038 / forked kushd pid=479039 / kushd died, respawn in 1000ms / forked
#     kushd pid=479354.
#   FIXED EN ROUTE: knetd/conntrack.zig _FORTIFY_SOURCE build break (swept into knetd 07e405d).
#   SAFETY: verified enp1s0 already leased + no persisted MAC spoof BEFORE running knetd, so it
#   ran passive (did NOT grab the SSH lane). Lesson: knetd owns interfaces — always verify the
#   lease/spoof state before a live run or you strand your own SSH access.
#   RUNG COMPLETE. Remaining on the ladder: (a) kboot foundation fork for logdrain + getty (the
#   mouth), (b) machine-class branch (kmodd, slice 2 stub), (c) the full cold-reboot E2E (kboot
#   -> knetd -> kushd -> kidulwm -> kplayd, zero systemd) — still blocked on initramfs MODULES
#   (serial 8250 / net / GPU) per verdict 91.

# VERDICT 92 (bobdotrix 2026-10-04) — IDENTITY + KWEB LAWS FROZEN (the crypto spine, end to end).
#   Whole architecture day: boot ladder -> crypto -> network, one spine. FROZEN THIS SESSION:
#     - identity.md (KidulWM 46a694c): the FOUR SCOPES + "HOLD THE BAR NOT THE PROTOCOL". websites=
#       passkeys/FIDO2, bank/gov=OMEMO-class E2E+in-person verify+key transparency, mesh=OMEMO+
#       kidulKey identity, root=cold kidulKey. One token, many keys (per-scope, no shared secret).
#       Two-factor by architecture: TPM=device-bound, token=human-bound. + the rendezvous law:
#       "run it, don't trust it" (coordinator on our krouter, kidulKey-signed, dont-trust-verify).
#     - kweb.md §12-14 (knetd e3a757e): §12 hash-as-name (key=name, two signed maps static roster/
#       dynamic endpoint, possession=auth). §13 NO LOGIN EVER (router admin password dissolves into
#       identity-by-key + authority-by-role; already-signed keys need zero ceremony, new device =
#       ONE possession ceremony; LOAD-BEARING CAVEAT kidulKey must stay COLD or auto-recognition
#       becomes a CA an attacker mints adult keys from). §14 NO LOGS BY CONSTRUCTION (resolver needs
#       only transient hash->endpoint RAM state, no logging code path EXISTS, immutable — "nothing to
#       subpoena because nothing was collected"; privacy = architecture not policy).
#     - Also: knetd/conntrack.zig fixed _FORTIFY_SOURCE build break (matches house pattern).
#     - Also: identity map — "identity rides on KEYS never addresses" is the load-bearing line tying
#       crypto.md (who) + identity.md (which key) + kweb.md (how to reach) into one spine.
#   NOT YET DONE (next): kweb.md §12's two maps are SPEC — krouter's actual rendezvous (dynamic
#   hash->endpoint) is unbuilt; kvaultd/kidulKey provisioning ceremony is unbuilt. These are the
#   NEXT settings-tweaks, not new architecture.

# VERDICT 91 (bobdotrix 2026-10-04) — KUSHD PID-1 FLOOR STRIPPED; PURE USHER UNDER KBOOT.
#   The kboot fork correction (kboot = PID 1, kushd = child) made kushd's own PID-1 floor DEAD WEIGHT
#   AND a live hazard: two binaries both carried "am I init?" logic. STRIP (kushd c5bce6e):
#     - mountEarly() removed (kboot mounts alone; kushd never touches the VFS)
#     - reboot() on signal removed (was SIGINT=reboot else poweroff — a plain SIGTERM to the usher
#       could power off the host). This is the verdict-90 bug's final closure: the floor is GONE,
#       not just gated.
#     - is_pid1 flag + SIGPWR handler removed (init's signal, kboot's job)
#     - shutdown() now ALWAYS: term seats -> sync -> clean-exit (c._exit(0)), no reboot path at all
#   PROVEN on ksd-reset: kboot->kushd->seatd/kidulwm/ksound tree correct (kidulwm dies as expected,
#   no GPU on this VM, kushd respawns it). SIGTERM kushd -> "usher clean-exit (no reboot — kboot owns
#   the power verb)", VM stayed up (systemd PID 1, uptime unchanged). No stray seats.
#   RUNG COMPLETE. Next rung: kboot foundation fork (knetd/logdrain/getty = SLICE 3 stub), then the
#   full cold-reboot E2E. kboot slice-1 mount+fork+supervise+respawn+shutdown+hardening is DONE (kboot
#   bd5e3c3, hardening 57d33f0 = ptrace drop proven CapBnd bit19 clear).

# VERDICT 90 (bobdotrix 2026-10-04) — KUSHD NON-PID-1 FLOOR GATED + DOUBLE SHIFT PROVEN (media stack).
#   1. BUG FOUND+FIXED: kushd's PID-1 floor ran UNCONDITIONALLY. A root non-PID-1 kushd (manual/rig
#      run) called mountEarly (remounted tmpfs over live /run+/tmp) AND reboot(RB_POWER_OFF) on a
#      plain SIGTERM — powering off the whole box. Discovered the hard way: `sudo -b kushd` got
#      SIGTERM on session teardown and shut the VM down. Rig scripts only survived because they ran
#      kushd UNPRIVILEGED (mountEarly silently EPERM-failed). FIX (def534d): gate on getpid()==1 —
#      mountEarly + SIGPWR handler + reboot() only when actually PID-1; non-PID-1 SIGTERM/SIGINT now
#      clean-exits the supervisor. Verified live on ksd-reset: root non-PID-1 SIGTERM -> "non-PID-1
#      — clean exit, no reboot", VM stayed up (PID 1 = systemd).
#   2. DOUBLE SHIFT PROVEN: bill now cues pipewire + wireplumber (verdict 85 gap). kushd as root
#      non-PID-1 seated pipewire->wireplumber->kplayd as class=user on cue, in order. RESULT:
#      wireplumber + kplayd alive under kushd. pipewire died fast (status=62720) — NOT a kushd bug,
#      a socket collision with systemd's own pipewire (pid 452) already holding the socket on this
#      dual-stack box. Disappears in the real cold-reboot (zero systemd). Cue socket is root-owned,
#      so cues must be sent as root (or the socket perms widened).
#   REMAINING for docket #4 close: the FULL cold-reboot E2E (grub init=, zero systemd) + a media
#   source on the VM + verify playback. Trap: under kushd-as-PID-1 there is NO sshd and NO serial
#   console (8250 is a module), so verification is virtio-screen + /tmp logs only, and revert needs
#   a console/virsh. Deliberate, reversible — not done this session.

# VERDICT 89 (bobdotrix 2026-10-04) — KCELL PROVEN (Debian-on-Arch as native slide) + TRUST LEDGER LOCKED.
#   Two lanes landed today:
#   1. KCELL = the "guest that isn't a guest": Debian bookworm runs as a native KidulWM slide via
#      bwrap namespaces + Wayland/PipeWire socket passthrough, NO hypervisor. rootfs bound as "/"
#      (--ro-bind /var/lib/kcells/debian /). uname INSIDE the cell reports the HOST kernel
#      (7.2.8-1-cachyos) while /etc/os-release reads Debian — OS=file (cell's own), kernel=syscall
#      (the ONE shared kernel). That is the pen/brig law in one screenshot: pen shares the kernel,
#      so a pen can never hide it; that's why foreign CODE goes to brig (own kernel), foreign DISTRO
#      stays in pen. Prisoner hardening landed (cap-drop ALL + unshare pid/ipc/uts/cgroup + clearenv
#      + tmpfs /tmp + die-with-parent). Names locked: the plank (discard verb), micro-brig (lean
#      foreign-code guest). Repo kcell, top commit 19884b9. OPEN (kcell HANDOFF): browser cell,
#      Freenet cell, filtered network (netns+nftables TODO), cued-under-kushd.
#   2. CRYPTO / TRUST LEDGER (full spec in the crypto skill): kidulKey = SIGNING ROOT not seed
#      (derive=material-leaves-key FORBIDDEN; certify=signs public halves, only sigs leave). Private
#      key NEVER hits any box. Two SEPARATE keypairs (never one copied), no private-key backup,
#      revocation = strike a public key from the muster. OMEMO kept as async-E2E gold standard;
#      kidulKey CERTIFIES each device's OMEMO identity key (fixes OMEMO's TOFU/fingerprint-bootstrap
#      hole). Five open problems locked as the trust ledger, ranked: (1) THE BOX CAN LIE — SB OFF +
#      TPM unused; turn SB on BEFORE building the three crypto faces; (2) what does the key approve
#      (WYSIWYS display); (3) deniability vs non-repudiation split on one key; (4) revocation
#      propagation (CRL/gossip); (5) store-now-decrypt-later (PQ horizon). SB reality on THIS box:
#      Limine 12.9 has NO SB support (no key-enroll, no shim) — flipping SB on now = no boot; path =
#      sbctl -> gen key -> enroll (human-present) -> sign kernel+limine+initramfs (or UKI) -> dry-run
#      -> flip on; do KSD golden image (VM, reversible) FIRST, workbench after. LUKS verdict: KEEP —
#      orthogonal to SB, is the at-rest law (cold-storage.md), does NOT risk Hermes access.

# VERDICT 88 (bobdotrix 2026-10-03) — SILICON FLOOR LOCKED: zeroizing kboot de-foreigns SOFTWARE only.
#   kboot+kushd+kidulwm = one tower, all ours, from firmware handoff up. What it does NOT remove:
#   the silicon (CPU microcode, Intel ME/AMD PSP, UEFI firmware) — resident before our code, DMA to
#   memory, whole session. No software evicts it; only owning the chip (RISC-V+FPGA north star) does.
#   Skipper's law "NOTHING IS EVER 100% safe" = doctrine, not defeatism. Corrected dom0.md, power-states.md,
#   kboot.md. Sounds parked at ~/Music/kidul-chimes/ (17 files) + ksound/assets/om-gen.py (tweakable generator).

# VERDICT 87 (bobdotrix 2026-10-03) — KBOOT + RECOVERY-PATH LAW LOCKED (power-states.md).
#   kboot = the boot stage (firmware->kernel->mount/load->exec kushd), job = "kboot->kbuggerOff".
#   Boot order IS the usher's handoff: mkinitcpio HOOKS/limine.conf = HANDOFF NOTES for the next
#   usher, a fresh usher every boot. De-systemd-ize = hand back the jobs Linux already does.
#   Recovery path lives BELOW the thing it recovers (limine recovers kushd; knetd survives kushd;
#   remote survives the vault). kushd does NOT do the bootloader job. Snapper + limine-snapper-sync
#   + btrfs tiers already live on the host (verified); the one systemd artifact left = snapper's timer.

# VERDICT 86 (bobdotrix 2026-10-03) — INPUT TRUST LAW LOCKED: the seat admits input by proof, not presence.
#   TV has no keyboard; the keyboard is the crypto-connected remote. Seeds live on the
#   remote/mobile, NOT the vault (vault=cold rest, seed=live proof). Auth is a GATE
#   BELOW seatd (input-enumeration path, not a daemon): pass=TRUSTED keyboard, fail=
#   UNTRUSTED. Pair once over the wire, challenge/response on connect. Base keys are
#   standard HID usage codes; chord layer in /etc/kushd/keycombo.map (pre-settings).
#   Remote = fallback getty's hand (works when vault cold + kidulwm dark). Doc: docs/law/
#   input-trust.md. Closes 3 kidul-remote open questions (HID single, carry-key protocol,
#   seat trust). Also: kidulwm bootcheck no longer FAILs on "no keyboard" (removed branch).

# VERDICT 85 (bobdotrix 2026-10-03) — SEAT MINTED: kidulwm + ksound run under kushd, zero systemd.
#   kushd mintSession (root, pre-setuid): /run/user/<uid>, setgroups(audio video input
#   seat render), XDG_RUNTIME_DIR+HOME; seatUid()=/etc/kushd/seat->1000 (no more nobody).
#   seatd BODY act mints /run/seatd.sock; ksound class service->user. kidulwm runs via
#   rig/kidulwm-seat.sh (WLR_* scaffolding incl WLR_LIBINPUT_NO_DEVICES=1 for no-evdev VM).
#   RESULT: comm=kushd, seatd+kidulwm+ksound ALL up no crash-loop; kidulwm "backend
#   started", DRM fd, output Virtual-1 1920x1080, 22 keybinds; ksound "daemon up socket
#   /run/user/1000/ksound.sock". bootcheck "FAIL no keyboard" = expected (0 evdev, not a
#   crash). REMAINING for media-plays: pipewire (not cued) + kplayd + media source.
#   DEPLOY TRAP: virsh destroy never fsyncs — sync before destroy, or guestmount --rw.

# VERDICT 84 (bobdotrix 2026-10-03) — kushd PID-1 cold reboot PROVEN; media blocked on seat+dev-node.
#   grub init=/usr/local/bin/kushd + base/udev + MODULES=(virtio_net virtio_gpu) ->
#   comm=kushd, zero systemd, SIGTERM-1 clean poweroff (domstate=shut off). virtio_gpu/
#   virtio_net load, eth0+lo present, bill seats 10 acts, respawn backoff works. TWO named
#   gaps stop 'media plays': (1) kidulwm libseat "No backend was able to open a seat"
#   (no logind under kushd -> no DRM session -> headless fallback -> die). Needs seatd or
#   kushd-minted seat. (2) ksound "syscall NOENT" main.zig:35 (dev node absent, no udev
#   coldplug). Box RESTORED to systemd (grub reverted, proof act removed, SSH alive).
#   Next lane: seat provider for kidulwm under kushd, then ksound node bring-up.

# VERDICT 83 (bobdotrix 2026-10-03) — STARSHIPKIDUL FRAME LOCKED + dom0 = the captain's safe.
#   The ship is the OUTER frame; the theatre is its TOP DECK. kushd = the joint
#   (first mate / usher). Two boundaries: sea (untrusted local, pen+brig wall) and
#   sky (WAN, knetd wall). Trust grades named: bridge (system), wardroom
#   (service), deck/crew (user), quarters (restricted), brig (KVM arm). Three axes
#   never blurred: class=walls, arm=mechanism, uid=identity. Eye-above law: Captain
#   ABOARD (wheel) vs KEYE ABOVE (cord) — two powers, never merged. One name per
#   thing (face=conductor, sails=the boot image). Theatre = the UPPER LEVEL, not
#   the top deck (top deck is open to the weather, reveals storms ahead; the
#   theatre is sheltered so px stay none the wiser). dom0 = the CAPTAIN'S SAFE —
#   NOT below decks, in the COCKPIT, security 24/7, ONLY the captain has the keys,
#   skipper dies before he hands them over. SKIPPER'S LAW: nothing is 100% safe;
#   a good skipper gets you home unscathed through experience + know-how. px never
#   know the real truth, they just enjoy the show.

# VERDICT 82 (bobdotrix 2026-10-03) — NAME LOCKED "the brig" + vault/brig split corrected.
#   Barticus overruled "bubble" -> "the brig" (StarShipKidul's ship jail; staunch,
#   authoritative). AND corrected the framing: the vault is NOT put in the cage.
#   The vault is ALREADY the coldest storage (cued, not resident) — that IS the
#   "colder than Qubes" claim. The thing in the brig is the NETWORK (knetd), on
#   the usher's leash: "make a mistake and I will cut you." vault = data at rest;
#   brig = network authority, cut-able. One word each, never shared. Propagated
#   bubble -> brig everywhere (dom0.md rewritten, theatre.md, power-states.md,
#   SYSTEM.md, KSD-INDEX, DOCKETS #4, skill SKILL.md + kushd-usher.md two-arms +
#   slice 11c). Verdict 81's "bubble" lines are superseded.

# VERDICT 81 (bobdotrix 2026-10-03) — DOM0 LAW LOCKED + "bubble" naming + docket #4 cold-reboot prep.
#   Architecture decision with Barticus (the Qubes question). Two locks:
#   1. DOM0 LAW (new docs/law/dom0.md, LOCKED): KSD IS dom0 — recognised, not
#      built. The bare kernel + kushd + kidulwm + kidulKey/kvaultd is the Qubes
#      dom0 (hardware/GUI/mgmt/trust), but type-0 (no hypervisor tax on our own
#      code) instead of Xen's type-1. THE ONE RULE we'd been violating: network
#      does NOT live in the trust core. knetd is the CAGED sys-net bubble, not a
#      bare-kernel peer of kvaultd/kidulKey. Keeps both hard-won properties
#      (boots before kushd = recovery; owns the pens) but a knetd compromise is
#      now a bubble compromise, never a dom0 compromise. "Colder than Qubes":
#      our vault is cued-not-resident (cold-storage.md), Qubes' is a resident
#      KeePassX in a networkless VM — we refuse the resident process entirely.
#      North star named: "Qubes that isn't ugly" (the face is the legible
#      surface Qubes never built).
#   2. NAMING: the VM'k cage arm is RENAMED "bubble" (kbubble where the k-prefix
#      is wanted). pen = fence (namespaces); bubble = sealed room (KVM). "Pop
#      the bubble" = process-death-is-the-kill. One word to veto; it propagates.
#   Propagated: theatre.md (BODY note + beer-garden "bubbles"), power-states.md
#   (boot graph + foundation), SYSTEM.md §2.1 (knetd dropped from TIER-1 BODY
#   list, NOTE added; "knetd = foundation organ, CAGED not body"), KSD-INDEX,
#   DOCKETS #4 (VM'k cage -> bubble), skill kidul-system-daemons (SKILL.md usher
#   law + kushd-usher.md two-arms + slice 11c SHARPENED). Commits: KidulWM
#   b7586d9 (dom0 law), kushd d008ebc (bill: drop knetd+kvaultd from BODY).
#   MECHANISM of knetd-in-a-bubble (VFIO vs pre-kushd launcher vs cgroup) = a
#   DOCKET, not built. Until then knetd runs bare-kernel but is DESIGNED caged.
#   OPEN: the cold reboot (docket #4) was mid-flight when this decision arrived.
#   Guest bill now BODY= kidulwm+ksound only; grub init= line still pending.

# VERDICT 80 (bobdotrix 2026-10-02) — kushd PID-1 FLOOR + POWER VERBS PROVEN + GAMMA CONTROL.
#   12h coherent session; three lanes landed:
#   1. kushd = PID-1 (commit c976d02): mountEarly (proc/sysfs/devtmpfs/tmpfs/run
#      + remount root) + installSignals (SIGTERM/SIGINT/SIGPWR) + shutdown()
#      (term seats -> SIGKILL stragglers -> sync -> reboot/poweroff). BILL_PATH
#      -> /etc/kushd/bill.kush. POWER VERBS PROVEN on the ksd-boot COW clone:
#      SIGTERM -> RB_POWER_OFF ("shut off"), SIGINT -> RB_AUTOBOOT (serial
#      "reboot: Restarting system" + GRUB reload, loop observed). Signal map
#      LOCKED: SIGINT=reboot, SIGTERM/SIGPWR=poweroff; no RB_HALT_SYSTEM / kexec
#      / runlevels. REMAINING (docket #4): initramfs MODULES (serial 8250 / net
#      / GPU) -> cold reboot E2E (zero systemd + media plays).
#   2. GAMMA CONTROL (commit 0a708bc): zwlr_gamma_control_v1 wired into kidulwm
#      (wlr_scene_set_gamma_control_manager_v1, 2 lines in server.zig init).
#      ReleaseSafe + smoke-test + DEPLOYED /usr/local/bin/kidulwm (.bak kept).
#      Enables night-light (gammastep installed; wlsunset; noctalia nightlight)
#      + the movie/sports picture-mode substrate. Glare root cause = cold 6500K
#      colour temp, NOT the soft-white hex values or the backlight (now 20%).
#   3. LAW DOCS LOCKED (commit 09c7bc5): power-states.md (boot graph, S3/WoL by
#      machine class, kmodd device bring-up), cold-storage.md (vault = encrypted
#      FS, cued not resident), crypto.md (kidulKey root of trust, SSH data lane,
#      household roster). + aig 0002 (LLD/LLVM glibc 2.39 .sframe, 5c93c0a) +
#      kfiles home_root/zram (8a541d7) + ksd-golden host-setup-log (1db8a16).
#   FLAG (Barticus): 10 repos carry an untracked Apache-2.0 LICENSE — contradicts
#   the GPL law. Left untracked pending his call.

# VERDICT 70 (bobdotrix 2026-09-30) — RELOG-VERIFY 68/69 PASSED. The four
#   createSceneBuffer creator-drop fixes (media slide, overview card, home
#   card, home chrome) are CONFIRMED by the hard play/close cycle, not just
#   the 2-video snapshot. Method: ramsample-gate.sh 1s sampler on the live
#   host i915 (GL) while Barticus drove 4 full play/close cycles (Mod4+m open,
#   video ~10s, Mod4+q quit = full teardown: fullscreen exit + card destroy;
#   Mod4+Tab overview open/close). RESULT: kidulwm anon 227356 kB baseline,
#   close-point deltas +16/+28/+36 kB (NOISE, not the ~27MB/card stack), final
#   +76 kB over the whole run. kplayd clean every cycle (0 renderD fds on
#   close). Pre-fix verdict 69 measured +121MB on one open and 27-33MB stacking
#   per card render — all dead. DOCKET #1 CLOSED.
#   FOLLOW-UP (Barticus): Escape's mediaSlideToggle path does NOT call
#   videoFullscreenExit — only Mod4+q's close_focused does. Both close paths
#   should exit fullscreen for parity. Not fixed this session; todo'd.

# VERDICT 71 (bobdotrix 2026-09-30) — PHASE 2 GATE RE-VERIFY: LEAK DEAD, CPU ABOVE TARGET.
#   Ran the gate soak on the live host i915 (GL): media card open + media_play
#   A.Minecraft.Movie.mp4 (1920x1040 h264 24fps) fullscreen on DP-3 (4K@30, scale
#   2.0), ramsample-gate 1s sampler. RESULT:
#     LEAK DEAD (the Phase 2 core): kidulwm anon pinned 227504 kB, ZERO drift
#       over 3+ min playback; kplayd fds 5 / kidulwm fds 6, both bounded; GEM
#       bounded both sides. No per-cycle stack, no steady climb. I4 pool +
#       verdict 68/69 hold under real playback. Clean close -> kplayd standby
#       (27MB, 0 renderD). Daily-driver OOM is dead.
#     CPU ABOVE TARGET: kidulwm ~6.5% + kplayd ~4.9% (single-core %) during
#       playback = ~11% total vs the ~2% gate number (that 2% was measured on
#       a 1080p NV12 scanout, pre-compositor-composite). NOT a leak (anon flat),
#       an EFFICIENCY item.
#     COMMIT-RATE TELL: kplayd commits ~62/s against a 24fps source (~2.5x).
#       Two suspects, not yet pinned: (a) wlroots rejecting the direct-scanout
#       candidate (buffer 1920x1040 vs output 3840x2160 scale 2.0 -> compositing
#       every frame, kidulwm pays 6.5%); (b) kplayd EGL shell re-presenting at
#       frame-callback rate regardless of new frames (the verdict-64 per-frame
#       import churn PoolImage was meant to kill — maybe not fully).
#   VERDICT: docket #2 NOT closable yet — leak half closed, ~2% CPU half is
#   not. Pin the commit-rate cause next (overlaps docket #5 judder/mode-select).

# VERDICT 72 (bobdotrix 2026-09-30) — PHASE 2 CPU/COMMIT-RATE PINNED. Read the
#   present path end-to-end (kplayd_shell.zig render/tick + Gl.zig + EglShell
#   + kidulwm syncScanoutOverlay). The ~62/s commit and ~11% CPU are BOTH
#   explained, and NEITHER is a leak — they are compositing/render inefficiency.
#     COMMIT RATE ~62/s: kplayd render() commits the MAIN surface TWICE per
#       tick when the overlay exists — eglSwapBuffers in presentDmabuf
#       (Gl.zig:597) + an explicit wl_surface_commit(w.surface) at
#       kplayd_shell.zig:346 (plus wl_surface_commit(ovl) for the subsurface).
#       And tick() renders at the COMPOSITOR's vsync (frame-callback fresh),
#       not the video fps — DP-3 is 30Hz, so ~30Hz x 2 commits = ~60/s against
#       a 24fps source. So it's not "per-frame import churn" (PoolImage killed
#       that) — it's double-commit + render-at-vsync.
#     CPU ~11% (kidulwm 6.5% + kplayd 4.9%): scanout is NOT engaging. Buffer
#       is 1920x1040 (decoded), output is 3840x2160 @ scale 2.0. wlroots can
#       only direct-scanout a buffer that matches the output mode/plane; a
#       1080p buffer on a 4K scale-2.0 output must be COMPOSITED (scaled) every
#       frame — kidulwm pays the per-frame GL composite at 30Hz. The ~2% gate
#       number was measured on a 1080p panel scanout, a different geometry.
#   VERDICT: docket #2 "pin the cause" DONE. The ~2% CPU target is UNACHIEVABLE
#   on 4K scale-2.0 with 1080p content via compositing — the honest close is
#   either (a) accept compositing cost as not-a-leak, or (b) the real fix is
#   content-aware mode-select (drop output to 1080p for 1080p source so the
#   plane scans out directly) = docket #5 territory. Leak remains DEAD.

# VERDICT 73 (bobdotrix 2026-09-30) — KADENCE VERB + THE DOTCLOCK WALL. C3
#   select's conductor primitive BUILT (uncommitted, deploy = your reload):
#   `kidulwm-control kadence <output> <w> <h> <refresh_mhz> [scale]`. Plumbed
#   message.zig (new RequestTag .kadence + struct), kidulwm-control.zig parser,
#   server.zig setStageKadence (find output by name -> setCustomMode + CFC
#   scale or override -> atomic commitState -> syncOutputScaleToWindows on
#   success). Failed commit = ok:false, output untouched. Build ReleaseSafe
#   clean, tests pass. kidulwm hash 1f0c0541, control 9b7baac9.
#   THE DOTCLOCK WALL (read the wlroots source, not guessed):
#     wlroots generate_cvt_mode(..., reduced=false, false) — custom modes are
#     ALWAYS standard CVT, never reduced-blanking. Kogan EDID caps dotclock at
#     300 MHz. Standard CVT 2560x1440@60 = 312.25 MHz (REJECTED); @55 = 284;
#     @48 = ~250; reduced-blanking @60 = 241.5 (what Barticus's old 1440p used,
#     driven below wlroots' API). So `kadence DP-3 2560 1440 60000` bounces
#     off the cap; `48000` fits AND is clean 2:2 cadence for 24fps film.
#   TEST PLAN (your reload, your eyes): reload, then
#     kidulwm-control kadence DP-3 2560 1440 48000   # 2:2 for 24fps, ~250MHz
#     kidulwm-control kadence DP-3 3840 2160 30000   # back to native 4K@30
#   Scale note: CFC law gives 2560-wide -> scale 2 (1280x720 logical). Add an
#   explicit scale arg (e.g. `... 48000 1.0`) to force 1x if you want the big
#   desktop. 1440p@60 (your go-to) needs raw-modeline/DRM-level support — a
#   follow-up card, NOT this verb (wlroots won't emit RB).

# VERDICT 74 (bobdotrix 2026-09-30) — KADENCE DEPLOYED + 1440p DEAD, LANE = 1080p.
#   kadence is now DEPLOYED to /usr/local/bin/kidulwm (hash 710076d0, matches
#   zig-out) — corrects verdict 73's "uncommitted/deploy=reload"; it goes live
#   on the relog happening NOW. 1440p@48 is DEAD as a target: non-native res
#   (TV rescales 1440p->4K) + non-native refresh (panel V-range 40-62Hz) =
#   worse than 4K, confirmed by Barticus. The Kogan 4K panel is dotclock-capped
#   300MHz (EDID "max dotclock 300") -> 4K = 24/25/30Hz ONLY (60 needs ~594MHz).
#   The lane is NATIVE: 1080p@60 (3:2, standard) or 1080p@24 (pure), both in
#   the Kogan EDID. Payoff: output==source promotes present from GL-composite
#   to DRM scanout (Tier 2, no composite pass). Full rationale:
#   kmedia/docs/design/silk.md (new — cadence/zero-copy study).
#   TEST PENDING (the relog's first move): kidulwm-control kadence DP-3 1920
#   1080 60000 -> eyeball a 24fps film; if 3:2 nags, `... 1920 1080 24000`.
#   Docket #5 reframed to match (1440p@48 dead, lane = 1080p@60/24).

# VERDICT 75 (bobdotrix 2026-09-30) — KADENCE DEPLOY COMPLETE + DOCKET #2 CLOSED.
#   FOUND + FIXED: verdict 74 deployed the kadence SERVER (/usr/local/bin/kidulwm,
#   710076d0) but NOT the control client — /usr/local/bin/kidulwm-control was the
#   pre-kadence Sep 19 build (46b89df5), so `kadence` was an unknown verb on the
#   deployed client (server + parser both had it, the client alone was stale).
#   Deployed zig-out/bin/kidulwm-control (9b7baac9) over it; parser liveness
#   confirmed (no-arg `kadence` -> MissingArgument). kadence is now live
#   end-to-end; the eyeball test is unblocked.
#   DOCKET #2 CLOSED: Phase 2 gate re-verified (verdict 71/72) — LEAK DEAD (anon
#   227504 kB pinned, zero drift, bounded fds/GEM); CPU ~11% is compositing +
#   kplayd double-commit, NOT a leak (verdict 72). Compositing cost ACCEPTED as
#   not-a-leak; the efficiency fix = mode-select = docket #5 (kadence built +
#   deployed, eyeball test pending).
#   FOLLOW-UP (kplayd commit-rate, new docket #12): ~62/s commits = double-commit
#   (presentDmabuf eglSwapBuffers + wl_surface_commit at kplayd_shell.zig:346) +
#   render-at-vsync (tick at 30Hz compositor vs 24fps video). Distinct from
#   mode-select — a kplayd render-loop fix.

# VERDICT 76 (bobdotrix 2026-09-30) — KADENCE EYEBALL: MODE-SELECT DEAD ON KOGAN + BLACK-SCREEN BUG FIXED.
#   Barticus drove the relog test (verdict 74 plan). RESULT (his eyes):
#     1080p@60 (60000): not better, maybe slightly worse than the 4K@30 baseline.
#     1080p@24 (24000): WORST by far.
#     3840x2160@30 (30000, "back to 4K"): BLACK SCREEN — recovered by
#       re-applying 1080p@60.
#   ROOT CAUSES (both real; one is a bug, one is a hardware wall):
#     1. BLACK SCREEN = setStageKadence used setCustomMode for EVERY target,
#        including the NATIVE 4K@30. setCustomMode emits standard-CVT (reduced
#        blanking OFF) 4K@30 = ~297MHz, a timing the Kogan can't sync; the
#        panel's real preferred 4K@30 uses different blanking. 1080p@60 "worked"
#        only because standard-CVT 1080p@60 ~= CEA 1080p60. FIXED: kadence now
#        prefers an EXISTING EDID mode (setMode = exact panel timing) when one
#        matches w/h/refresh within ±1Hz, and only falls back to setCustomMode
#        when the panel doesn't advertise the mode. DEPLOYED /usr/local/bin/
#        kidulwm 1d0d87ec (relog to take effect; .bak-710076d0 = verdict 74).
#     2. MODE-SELECT IS A DEAD END on the Kogan: 1080p is NON-native (the TV
#        rescales 1080p->4K, the same wall that killed 1440p@48); 24Hz is BELOW
#        the panel V-range 40-62Hz (EDID lists 1080p@24 as an input mode, the
#        panel can't run it natively); 4K tops out at 30Hz (dotclock cap). NO
#        clean cadence exists for 24fps on this panel: 48Hz needs a non-native
#        res, 120Hz exceeds the cap, 24Hz is out of V-range. Judder on the Kogan
#        is a HARDWARE CEILING, not a software bug.
#   NEXT: the silk lever that IS ours is the present path, not mode-select —
#   docket #12 (kplayd double-commit + render-at-vsync) + the scanout-tier
#   "submit early into DRM atomic queue" work (silk.md §7). C3 mode-select stays
#   valid for the laptop eDP-1 (144Hz native, clean 6:6) and the future
#   battery-TV panel; on THIS Kogan it cannot help.

# VERDICT 77 (bobdotrix 2026-09-30) — DOCKET #12: DOUBLE-COMMIT REMOVED (kplayd).
#   Removed the second wl_surface_commit(w.surface) in kplayd_shell.zig render():
#   presentDmabuf/presentFrame/presentBlack all end in eglSwapBuffers, which on a
#   wl_egl_window already attach+commit the main surface. The extra commit doubled
#   the commit rate (verdict 72 ~62/s = 30Hz vsync x 2). The overlay is a DESYNC
#   subsurface (ensureOverlay), so its own commit applies independently — the parent
#   needs no re-commit. DEPLOYED /usr/local/bin/kplayd 39b082f4 (ReleaseSafe;
#   .bak-d3e40c3a = prior). Single-commit now ~30/s (vsync), within the docket #12
#   "24-30/s" target.
#   BUILD TRAP (again, see HANDOFF line 405): plain `zig build` ships DEBUG (~13.6MB);
#   the canonical kplayd build is -Doptimize=ReleaseSafe (~4.1MB). First deploy was
#   Debug by accident — caught by size, redeployed ReleaseSafe.
#   RESIDUAL (not a quick fix): render still fires at the compositor 30Hz vsync, so a
#   24fps frame is re-blitted ~6x/s extra. Skipping that commit would starve the frame
#   callback (no commit -> no vsync wake -> cb_starved -> late frames = judder). The
#   clean ~24/s present-by-clock fix is silk.md §7 (submit early into DRM atomic
#   queue), a larger present-path redesign, not this docket.
#   TEST OWED: relog, play a 24fps film — confirm smooth + commit rate halved.

# VERDICT 78 (bobdotrix 2026-10-01) — BINARY AUDIT POST-RELOG: kplayd CURRENT, kidulwm WAS STALE (redeployed).
#   Barticus ran verdict 77's owed test (relog + 24fps film) -> "still juttery".
#   Audited every deployed binary against source (sha + embedded git-rev + cmp):
#     kplayd = CURRENT (sha 39b082f4 == fresh HEAD build; verdict-77 double-commit
#       fix ec17c8a IS live). Running pid restarted 07:21 post-relog on this binary.
#     kidulwm-control = CURRENT (sha match; kadence verb present).
#     kidulwm = STALE. Deployed binary (mtime 22:16:27) was CLEAN 875d052 (verdict 75),
#       built 47s BEFORE the verdict-76 findMode fix (5672c93, server.zig "kadence
#       prefers EDID modes / black-screen prevention") committed 22:17:14 — the fix
#       never made it into the deployed binary. cmp vs fresh HEAD build = 10655
#       differing bytes -> findMode NOT in the running compositor. REDEPLOYED at HEAD
#       1ab3e58 (sha 378b4cad), .bak-875d052 kept. RELOG OWED to activate (running pid
#       3200771 still on the old inode).
#   JUDDER RE-VERDICT: the "still juttery" is the 3:2 pulldown HARDWARE CEILING (24fps
#       on the Kogan's 30Hz-capped 4K, silk.md §6), NOT a stale binary. The double-commit
#       fix (verdict 77) was a CPU fix (~62/s -> ~30/s commits), not a judder fix — mode
#       select is DEAD on Kogan (verdict 76). Remaining software lever = silk.md §7
#   present-path (DRM atomic queue submit-early), gated behind kushd (docket #4).

# VERDICT 79 (bobdotrix 2026-10-01) — DOCKET #12 CPU RE-MEASURE: DOUBLE-COMMIT WAS CPU-NEUTRAL.
#   Re-measured live via kidulwm-control media_play (A.Minecraft.Movie.mp4, fullscreen
#   DP-3 4K@30, 40s tick-delta sampler): kplayd ~5.0% + kidulwm ~6.5% = ~11.5% total —
#   IDENTICAL to the verdict 71/72 baseline (~11.4%). The verdict-77 double-commit removal
#   (sha-verified live) did NOT move CPU. Reason: a wl_surface_commit is a cheap protocol
#   round-trip; removing ~32/s of them saves nothing measurable. The real cost is tick()
#   rendering at the compositor's 30Hz vsync (re-blitting a 24fps frame ~6x/s extra) +
#   kidulwm scale-2.0 compositing every frame — neither touched by verdict 77.
#   DOCKET #12 corrected: commit-rate cleanup DONE (real redundancy removed), CPU lever =
#   silk.md §7 (DRM atomic queue submit-early), gated behind kushd (docket #4). The
#   "half the ~11% CPU" hypothesis was wrong.
#   SIDE-NOTE (Barticus): IPC media_toggle did not pause the on-screen playback (kept
#   playing until card moved to peek, then stuck until reopen+quit). Known, not chased.

# KBOOT NOTE (bobdotrix 2026-09-29, end of night) — docs/design/kboot.md.
#   Drop-back boot by CUE, not key-wait: "BIOS"/"BOOT"/"DM"/snap verbs in the
#   terminal, one-shot boot vars (OsIndications bit 0 = VERIFIED live on this
#   box, UEFI + efivarfs + bit set; limine snapper entries = already there;
#   DM = kiduldm; only BOOT-to-editor flag is new). Bootloader = Limine,
#   firmware Timeout already 0. Non-negotiable: keep ONE held-key at boot
#   (the mouth, §2.1). Toolchain isolation = ALREADY done (aig `a/` namespace,
#   pinned 0.16.0, separate binary). CANDY (sysadmin-only): snappies as media
#   cards with stateDetails — would've saved the knetd outage. NOT frozen;
#   merge-decision open. Boot claim = TIME-TO-PLAYABLE by STRUCTURE (we
#   deleted the DM/login gate; public mode has no secrets to gate; personal =
#   key-cast, no name/password) — beats everyone, Apple included, by removing
#   a stage, not by ms. Shared floor = firmware POST (hardware, identical for
#   all).

# LOG LIFECYCLE (bobdotrix 2026-09-29, session with Barticus) — frozen as
#   SYSTEM.md §2.5 (ring / drain / brain). Kernel ring is a FIXED 128KB
#   circular buffer (fill-then-overwrite-whole-record, reads snapshot, never
#   consume) — the last-breath backstop, no watermark to add. The drain reads
#   /dev/kmsg losslessly (journald today, our plain-text drain at Phase 5);
#   the ring's overwrite never touches the drain's on-disk copy. Retention is
#   TWO MODES: DEV MODE (now) = treasure chest, no prune, keep everything for
#   script refinement (watch for runaway); STEADY MODE = ~150MB fill, weekly
#   analysis pass (distill to brain) then prune to ~50MB. Analysis cadence is
#   a bobDotrix/usher job, never the kernel's. Measured real rates this boot:
#   journald ~5MB/day; watchdog sampler ~9MB/day (the leak, not the budget).
#   The 3GB/year figure is the BUG, not a target. Watchdog cap + lookup-script
#   set = separate work-over-time cards.

# DOCTRINE CORRECTION (bobdotrix 2026-09-29, session with Barticus) — the
#   theatre's top tier was mislabeled. usher.md called it "OWNER = holds
#   stageStats, captured once" — a facts block, not an owner. Corrected:
#   KSEAT = the brain (human + authored blueprint, flat file, disk-is-truth);
#   kushd = the breeder (owns fork/exec/wait/kill = seat acts, terminus PID-1);
#   kidulwm = the brush (executes pixels, never decides, ZERO policy);
#   kernel = the physics. The running order is AUTHORED by kseat, READ by the
#   usher (never owned by it). Applied: SYSTEM.md §2.4 (seam map: fluid
#   Zig==I4/I6, wlroots==I5, Wayland==tier, waitpid==death; seams cairo/ffmpeg/
#   iHD/sd-bus) + §7.2 rename; usher.md top tier + §4 handoff. Draft preserved
#   at docs/design/kseat-theatre.draft.md. OPEN: sd-bus notify-bridge should
#   route through kushd (contradicts I2/I7) — flag, not yet fixed.

# GATE RE-VERIFY (bobdotrix 2026-09-29) — PHASE 2 I4 GATE: steady-state leak DEAD,
#   but PER-CYCLE P010 RETENTION STILL LIVE (stacks). Two clean play/close cycles on
#   the Kogan (4K DP-3), live sampler 1s + smaps fingerprint.
#   STEADY-STATE (verdict 66 chrome leak): CONFIRMED DEAD — kidulwm RSS pinned 853MB
#     for 21min fullscreen playback, delta +0kB/min. VA-device leak dead (kplayd
#     5 fds/856MB GEM -> 0/0 on pause). assertStandby held.
#   PER-CYCLE RETENTION (NEW/REMAINING): kidulwm 336 -> 914 (cycle 1) -> 2639MB
#     (cycle 2). kplayd 27 -> 256 -> 399MB. STACKS, not a warm cache. smaps: 68 x
#     ~27.8MB anon chunks = EXACT verdict-57/62 "one 4K P010 frame each" fingerprint
#     (1.89GB), + 2x168MB + 4x45MB + ~1.1GB GEM. Allocated in ~24s on fullscreen
#     ENTER, never released on EXIT/close.
#   CONCLUSION: verdict 66 killed the CHROME half only. The P010 staging/import
#     retention (verdict 64 suspect A / per-frame import churn, ~8-slot cache never
#     landed) is a SEPARATE leak still open. Daily-driver = OOM after a few movies.
#   NEXT: pin the allocator — which path mallocs the ~27.8MB chunks on fullscreen
#     enter and skips free on exit (suspect: per-frame dmabuf import vs media-slide
#     ARGB32 re-render vs host-surface/curtain setup). Then cache/reuse or free.
#   METHOD: ramsample-gate.sh (1s RSS/fds/GEM/CPU) + smaps chunk histogram. The
#     magnitude differed per cycle (500MB vs 1.7GB) — pin the video/frame-count
#     dependency, don't assume linear.
#   PINNED + FIXED + DEPLOYED (2026-09-29, same session): uprobe
#     heap.PageAllocator.alloc --call-graph fp -> len=0x1b29680 (27.17MB) ->
#     DataBuffer.create <- ui.media_slide.renderToBuffer <- mediaSlideRefresh <-
#     mediaSlideOpen/Key. NOT the P010 frames (GEM/dmabuf clean), NOT chrome
#     (verdict 66). It is the MEDIA SLIDE ARGB32 re-render (verdict 64 SUSPECT A).
#     ROOT CAUSE: renderToBuffer returns *wlr.Buffer (refcount 1); createSceneBuffer
#     locks it (2); the creator's ref was NEVER dropped on success, so node.destroy()
#     left refcount 1 and DataBuffer.destroy never fired -> ~27MB leaked per card
#     render. Every OTHER createSceneBuffer caller drops (curtain/peek/tray);
#     mediaSlideRefresh was the ONE missing it. FIX: +1 line wlr.Buffer.drop(buffer)
#     after createSceneBuffer (server.zig mediaSlideRefresh). DEPLOYED
#     /usr/local/bin/kidulwm 61366e08 (.bak-ca7571d4 = verdict 66). RELOG OWED:
#     re-run play/close cycle -> kidulwm RSS must RETURN to baseline (no stack).
#   SUSPECT (same bug, separate path, NOT yet pinned): overview_card render
#     (server.zig ~1689) also missing the drop — verify next cycle.

# VERDICT 69 (bobdotrix 2026-09-29, same session) — overview + home-slide
#   card/chrome per-cycle leak: SAME missing-drop bug as 68, three more sites.
#   Pinned by the live post-reboot cycle (not uprobe — fingerprint already
#   known): kidulwm anon 228 -> 350MB (+121MB) on one media-slide open, FLAT
#   during 2.5min playback (per-render leak DEAD), but NOT reclaimed after the
#   slide was FULLY closed (still 350MB at +3min). smaps: 2x ~32.7MB + 6x
#   ~43.5MB anon chunks held post-close.
#   CAUSE: three more createSceneBuffer callers missing the creator-drop on
#   success (same one-line shape as the 68 fix):
#     1. overviewSlideOpen card   (server.zig ~1689) — deck card, ~33MB
#     2. homeSlideRefresh card    (server.zig ~1859) — tray slide card, ~33MB
#     3. homeSlideRefresh chrome  (server.zig ~1876) — success path never dropped
#   FIX: wlr.Buffer.drop(buffer) after createSceneBuffer in all three; the
#   overview card also gained the error-path drop. DEPLOYED /usr/local/bin/
#   kidulwm 337fb0a0 (.bak-61366e08 = verdict 68). RELOG OWED: play/close cycle
#   -> kidulwm anon must RETURN to ~228MB and NOT stack on a second cycle.
#   SEPARATE (still open, not this dragon): kplayd anon 27 -> 408 -> 252MB on
#   CLEAN close (0 renderD survived -> no exit(1)) — pin separately.


# VERDICT 67 (2026-09-30): DOCTRINE SESSION — kushd rename, Captain law, public
#   stance, stageStats. NO code change to kidulwm/kmedia binaries; this is the
#   naming + identity reset that un-fuses three owners and names the succession.
#   All in SYSTEM.md (the arbiter, on disk — NOT in git) + kmedia usher.md +
#   screen-stats.md (pushed). Summary for the next session:
#
#   1. ksvd -> kushd (THE USHER). The old "supervisor" was the wrong name: it
#      undersold the job to lifecycle-only. The usher knows every stage, seats
#      each act, brings it in on time, enforces open & close. ONE actor, two
#      arms: open/close rules + the stage map (placement). NO baton.
#   2. THE FACE (kidulwm) = THE CONDUCTOR. It paints the pixels, owns the
#      baton. The doctrine had double-claimed the baton (ksvd was "the
#      conductor" in 3 places) — fixed. cue = running order (usher); baton =
#      paint (conductor). Two different things; their conflation was the bug.
#   3. OWNER (I1) = holds stageStats (charts) and hands them down. Three
#      owners now clean: OWNER / USHER / CONDUCTOR.
#   4. stageStats absorbs screen-stats.md: capability (EDID, forever) + live
#      mode (per-session) + wall position/role. Identity key = mfg+model+
#      edid-hash (serial is all-zeros on the Kogan — found live). TV probed:
#      Kogan KGN/2800 is 60Hz-class (40-62Hz, NO 120Hz), preferred 3840x2160@
#      30, but advertises native 24.000 + 23.98 at 1080p AND 4K. 24fps film on
#      a fixed 30/60Hz mode = the judder root; the fix is content-aware mode
#      select (C3), not a magic mode. Judder substrate = screen-stats C1/C2/C3.
#   5. PUBLIC STANCE (§7.1): all public = AI training corpus; B&B in control
#      ALWAYS — suggestions box, NOT community project, more eyes not more
#      votes. knetd = the one thing built to STAND ALONE (routers, cross-
#      compiled, decoupling is a LAW). Everything else = made-for-our-machines,
#      fork-friendly. A stranger forks or sends a suggestion, never steers.
#   6. CAPTAIN LAW (§7.2): B&B = the Captain — a TEMPORARY ROLE, not an
#      identity. Held, not owned. The ship outlives the captain; succession is
#      a design principle, not an afterthought. Duty: find + prepare the next
#      captain BEFORE stepping down. No absolutes — the wheel is a handover,
#      not a crown. Held by the most responsible person in the room.
#
# NEXT SESSION (the actual work, prioritized):
#   1. CLOSE Phase 2 gate — the I4 GPU pool (EglShell+PoolImage+assertStandby)
#      LANDED but the gate is NOT re-verified: flat RSS after warmup, bounded
#      fds, hours of playback, ~2% CPU on HOST i915. This is the live-bleed
#      item, highest Granny-visibility. Re-verify before anything else.
#   2. Phase 1 — build kushd (now spec'd in usher.md). Retires the four-way
#      supervision split + kvisd-dead-after-reboot. The spec is the ticket.
#   3. Parallel: judder (screen-stats C1 capture -> C3 mode-select). Spec'd,
#      not blocking 1-2.
#   OLD: verdicts 59 (TV cut), 65/66 (chrome/RSS) still carried below.
# (relog handoff 2026-09-28 RESOLVED — VERDICT 66 RELOG VERIFY PASSED. Border
#  visible (square, thin — the verdict 66 shape), RSS FLAT 1812700kB over 90s on
#  a 5h19m compositor (the 27.14MB/layout leak is dead by construction: no raster
#  buffer exists). See verdict 66 block.)

# VERDICT 66 (2026-09-28): CHROME LAW AMENDED — THIN BORDER RESTORED. Borders
#   are back, but as thin scene-rect strokes (createSceneRect x4, O(perimeter)),
#   NOT the leaky full-window cairo/DataBuffer path. The 27.14MB/layout leak is
#   dead BY CONSTRUCTION (no raster buffer at all) — not by disabling chrome.
#   Law: docs/law/chrome.md amended — thin border only; no full-window buffer;
#   border colour = color_border_focused theme token, syncs on
#   chrome_style_generation bump (widgets + borders change together). window.zig
#   updateChrome rewritten (scene rects; TEMP DIAG cache-miss/create/destroy
#   logs removed). renderChrome + surfacePixels now dead (renderMiniRing lives).
#   Design (Barticus): user apps keep this thin border; KSD apps drop the
#   compositor border and self-frame (fade-to-black, 96% opacity) — client-side.
#   DEPLOYED /usr/local/bin/kidulwm (.bak-95be9e9 = verdict 65 no-chrome).
#   RELOG OWED — verify border + RSS flat.

# GREAT RESET — REMAINING WORK (prioritized, 2026-09-28)

#   1. RELOG VERIFY — DONE (2026-09-28): border visible + RSS flat.
#   2. KPLAYD VA-DEVICE LEAK root — DONE (session 38/39/40). The surviving
#      renderD fd is the VA DECODE DEVICE (drm-engine-video), NOT the EGL
#      shell. Root cause: iHD's vaTerminate does not close the decode device
#      fd after vaExportSurfaceHandle + Wayland EGL import (driver-level; the
#      old "extra ref"/pool-corruption theory was WRONG — hw_frames_ctx
#      ref=121 is just frame threading, thread_count=0 = ~16 threads).
#      FIX (CORRECTED session 39, do NOT trust session 38's "in-place close"):
#      session 38's closeRenderFds was REVERTED — close() on a DRM node runs
#      drm_release() reaping GEM the compositor still imported, so "quit &
#      re-enter" showed a BLACK SCREEN and the last quit RELOADED THE WM
#      (use-after-free). The correct terminal answer is PROCESS-DEATH:
#      closePlayer calls assertStandby() = 0 renderD fds or exit(1) respawn.
#      The fd leak is an iHD driver wart we STOP DEPENDING ON, never patch in
#      the hot path. See kmedia HANDOFF session 39/40 (Cuts A/B/C).
#   3. TV ~10min CUT + 7/9 channel fail (verdict 59) — confirm if still live.
#   4. xdg-decoration .client_side flip + GTK_CSD un-flip (applyTitleBarEnv).
#      Feeds item 5.
#   5. CORNER BLEED on foreign apps (browsers/proton). Client "factory round
#      corners" still bleed against the compositor frame — SSD/CSD corner
#      mismatch. OBSERVE this reload first (thin square border may shift it).
#   6. GRAND DESIGN framing (chamfer). DEFERRED — see ksd-design-language
#      skill. Sub-order: fix DataBuffer free -> chamfer.frag.glsl frame ->
#      tune depth on TV -> scallop upgrade.
#   7. KSD apps fade-to-black self-framing (96% black, no compositor border) —
#      client-side, the "one system" look. DEFERRED.

# VERDICT 65 (2026-09-28): LEAK PINNED + CHROME LAW. The 27.14MB/layout-event
#   leak is updateChrome -> DataBuffer.create (window.zig:574), the full-window
#   ARGB chrome buffer for the rounded-corner border — NOT the media slide, NOT
#   dmabuf (import 18x == close 18x, exonerated). Pin via perf uprobe
#   (heap.PageAllocator.alloc, --call-graph fp — dwarf/LBR both fail; see skill
#   zig-allocation-leak-pinning).
#   Law: docs/law/chrome.md (compositor draws no window chrome — no border, no
#   corner mask, no full-window buffer; fullscreen = bare pass-through; windowed
#   = client-side). fullscreen.md rulings 7-8 added. updateChrome disabled via
#   chrome_enabled=false toggle (body retained, renderChrome/surfacePixels DCE'd).
#   DEPLOYED /usr/local/bin/kidulwm 95be9e9 (.bak-8cb8d52 = verdict 64). RELOG
#   OWED — verify compositor RSS stops climbing. Follow-on: xdg fullscreen
#   handler + client-side decorations flip (see HANDOFF "Next action").

# KNOWN-GOOD + FALLBACK (Barticus, 2026-09-28): verdict 64 (8cb8d52, kept as
#   /usr/local/bin/kidulwm.bak-8cb8d52) runs helium with ZERO screen tearing
#   and very smooth playback, and its matching rounded corners looked really
#   good. If a later verdict regresses smoothness or visuals, FALL BACK to
#   kidulwm.bak-8cb8d52.
#   CAVEAT: 8cb8d52 is the leaky one (27.14MB/layout event, the RSS wedge) —
#   the smoothness + corners come with the leak. Reconcile by keeping the
#   windowed corners but killing the full-window buffer (thin border / proper
#   free), NOT nuking all chrome (verdict 65 did the latter).

# (relog handoff 2026-09-27 — SYSTEM FIXES + FULL REBOOT, bobdotrix)
# System admin session (NOT a KSD code verdict); detail in sda1 change journal.
#   - kernel split-brain FIXED: linux-cachyos 7.2.8 rebuilt to /boot + limine.conf
#     (pacman bumped 7.2.6->7.2.8 and deleted the 7.2.6 modules but never rebuilt
#     /boot — stale 7.2.6 vmlinuz, empty /etc/mkinitcpio.d -> SDDM dead on cachyos).
#   - fstab FIXED: /mnt/lacie-apocalypse listed twice -> fstab-generator + /boot
#     mount failure. Removed one line.
#   - NVIDIA -> COMPUTE-ONLY (SUPERSEDES verdict 53's FULL blacklist): the full
#     4-module blacklist made ollama model-load HANG (CUDA needs nvidia_uvm).
#     Now blacklist nvidia_drm + nvidia_modeset ONLY; nvidia + nvidia_uvm stay
#     loadable. Toggle /usr/local/bin/nvidia-profile (off|gaming: prime-run).
#     Intel iGPU still drives all screens. verdict 53's POST-REBOOT VERIFY
#     (nvidia-smi gone / D3cold / no card0) is VOID — nvidia SHOULD be present
#     but with NO display output.
#   - bobdotrix approvals.mode -> smart.
#
# FULL REBOOT resolves the REBOOT/RELOG OWED markers (53-62) + reaps the leaked
# GEM. Post-reboot: resume verdict 63's RSS checks fresh.

# VERDICT 64 (bobdotrix 2026-09-28, end of night) — COMPOSITOR IS THE LEAK (CORRECTS 63's "did NOT reproduce"); TWO FIXES DEPLOYED, ALLOCATOR PIN OWED TOMORROW
#
# LEAK (live host, Barticus open/close testing over ~1h): kidulwm anon 325MB
#   -> 3.45GB, RSS 3.6GB, STILL climbing, NO drop on close. kplayd CLEAN every
#   cycle (respawns 27MB / 0 renderD / 0 GEM — put-to-bed holds). smaps =
#   verdict-57 fingerprint: ~27.8MB anon rw- chunks coalescing into
#   83/111/166/250/278MB slabs ("one 4K P010 frame each"). Renderer gles2
#   (pixman=false), outputs DP-3 (Kogan 4K scale 2) + eDP-1 (1080p scale 1).
# WHY 63 MISSED IT: tested over RAW kplay.sock (open->close) which never enters
#   the fullscreen present path. Barticus's Mod4+m flow DOES — host surface +
#   curtain + scanout + per-frame video import. REPRO-DOOR LAW (video-playback-
#   architecture skill) named this exact false negative; I stepped on it.
#   Corrections to 63: the "compositor does NOT retain" + "did NOT reproduce"
#   lines are VOID for the fullscreen path. kplayd verdict 63 itself stands.
#
# FIXES DEPLOYED (src/server.zig, ReleaseSafe hash 39193e2d -> /usr/local/bin/
#   kidulwm; running pid NOT restarted — relog picks it up):
#   1. FULLSCREEN CHROME REMOVAL: applyLayout called updateChrome(true, .all)
#      unconditionally on the focused slide, ignoring slide.fullscreen (the peek
#      already hid itself via focused_fullscreen; the window chrome had no
#      matching check). Now clearChrome() when slide.fullscreen, in BOTH the
#      normal and headless branches. Fullscreen slide = edge-to-edge, zero
#      chrome, every app (shared focused-slide branch).
#   2. MEDIA PLAYER SPAWN DIRECTION: was addCompositorSlide(.media_player, 0)
#      = index 0 (far LEFT, pushed everything RIGHT — backwards vs addWindow).
#      Barticus: new slide becomes focused + pushes former focus LEFT; home is
#      the ONLY far-left (index 0) resident. Now spawns at focused_index+1.
#
# OWED TOMORROW — "2 SUSPECT REVIEW" (pin the allocator, then fix). Both fire
#   on fullscreen enter/exit layout events:
#   A. media-slide 33MB ARGB32 re-render (mediaSlideRefresh -> renderToBuffer,
#      server.zig ~2072; card_dirty guard exists but re-fires on fullscreen
#      layout events).
#   B. chrome border regen (updateChrome create/destroy churn, window.zig ~472;
#      TEMP DIAG "CHROME cache-miss" log still in place).
#   Plus (skill-documented): per-frame dmabuf import churn — cache per
#   VASurfaceID (~8 slots), scene node ONCE, setBuffer the cached entry.
#   Sampler trace: ~/.hermes/profiles/bobdotrix/cache/scratch/ramsample-*.log
#   (ts kplayd_pid rss fds gem kidulwm_pid rss fds gem anon memavail).
#   METHOD: relog first (deploys live), re-test, re-run sampler while Barticus
#   cycles fullscreen, correlate anon delta vs CHROME cache-miss +
#   mediaSlideRefresh log lines. Don't guess — the log distinguishes A vs B.

# VERDICT 63 VERIFIED LIVE (bobdotrix 2026-09-27, post-reboot) — RAM FLAT, NO LEAK
#
# Fresh-boot 3-cycle open->play->close over kplay.sock (Bob.Marley 1080p NV12):
#   - kplayd DURING: RSS 209-212MB, 5 renderD128 fds, ~180MB GEM. AFTER close:
#     pid CHANGES every cycle (1761->28743->29095->29407), new proc 0 renderD,
#     0 GEM, 27MB RSS. The close reply is EMPTY (no "ok") — exit(1) fires BEFORE
#     reply("ok"), confirming the put-to-bed path runs on EVERY video close (the
#     VA device still survives close; process death reaps it). By design.
#   - kidulwm: RSS 262->269->262MB (returns to baseline), GEM 1.111->1.193->1.111GB
#     (transient +82MB during play, released on close). NO retention. Verdict 62's
#     "2.5GB compositor climb" CONFIRMED dead post-reboot (was the wedged driver).
#   - MemAvailable oscillates 61.8-62.1GB, NO downward trend. Final = baseline.
# VERDICT 63 STILL-OPEN items both RESOLVED: (1) compositor does NOT retain;
# (2) root fix (avcodec_free_context releasing the zero-copy pool) stays deferred —
# the exit(1) kill covers it. NOTE for future clients: the `close` verb's "ok"
# reply is LOST (exit(1) preempts it); kplay client is fire-and-forget so it's
# harmless, but any future synchronous close waiter will time out.

# VERDICT 63 (bobdotrix 2026-09-25) — KPLAYD VA-DEVICE LEAK = THE RAM CLIMB, FIXED (exit(1)); COMPOSITOR "2.5GB" DID NOT REPRODUCE
#
# PIN (live, clean post-reboot): kplayd leaks ~1 VA decode device (renderD128,
# distinct client-id) + ~440MB GEM per video (4K; ~121MB @1080p). 6 open/close
# cycles → kidulwm RSS FLAT, kplayd +1 fd + ~440MB GEM per cycle. GEM is SYSTEM
# RAM on the iGPU → this IS the "5GB climb", NOT the compositor. Verdict 62's
# "kidulwm 2.5GB dominant" = misattributed (or tied to the since-rebooted
# wedged-driver state); clean kidulwm does NOT retain buffers.
#
# ROOT CAUSE (instrumented, live): avcodec_free_context fails to free the VA
# device + surface pool in the ZERO-COPY path. dev_ref=2 (normal), frames_ref=81,
# hw_live=1 (our av_frame_ref/free balanced) — ~79 dangling refs are the DECODER's
# internal pool, kept alive by the zero-copy export/import path. Plain decode (C
# probe) frees clean; vaExportSurfaceHandle alone = clean; the successful EGL
# import is the trigger. Per Barticus: pool count is codec-fixed, pool BYTES scale
# resolution × bit-depth — the fix must be per-stream-agnostic.
#
# FIX (kmedia 31c5c9f, DEPLOYED /usr/local/bin/kplayd): PUT-TO-BED LAW — after
# dropShell + close, if any renderD fd survives, exit(1) (PROCESS-DEATH IS THE
# KILL). systemd respawns clean; fd + GEM + pool reaped in one syscall. VERIFIED:
# 3 open/close cycles → fresh kplayd 0 renderD fds each, RAM flat.
#
# STILL OPEN: (1) compositor retention (verdict 62 step 3) did NOT reproduce
# cleanly — re-examine only if kidulwm RSS ITSELF climbs (not kplayd GEM).
# (2) root fix (make avcodec_free_context release the pool) deferred — doctrine:
# don't patch teardown to survive its own bugs.

# VERDICT 62 (bobdotrix 2026-09-25) — RAM CLIMB = TWO LEAKS (compositor dmabuf churn 2.5GB DOMINANT + kplayd VA device 224MB); VAAPI possibly wedged — REBOOT OWED
#
# SYMPTOM (Barticus): play-close-play now works (verdict 61 DONE), but RAM
#   climbs to ~5GB and does not release per video/channel.
# FINDINGS (live host, measured):
#   - kidulwm (compositor, pid 210902) RSS 2.5GB = THE "5GB". smaps: 33 x
#     ~27.8MB anon rw- MAP_PRIVATE chunks = EXACT verdict-57 fingerprint (one
#     4K P010 frame each). Verdict 56 deleted the .video slide, but retention
#     returned via the ZERO-COPY present path: kplayd exports a fresh VA
#     surface each frame, wlroots re-imports + recreates the texture per
#     setBuffer, texture-destroy path leaks the GEM (skill "setBuffer import
#     churn" / PER-FRAME DRIVER-CALL CHURN). Total anon rw- = 2.59GB.
#   - kplayd RSS 224MB: session-30 VA-device leak — 5 leaked renderD128 fds
#     (drm-engine-video, distinct client-ids 94/98/102/106/110), ~72-133MB GEM
#     each, one per video. Held by the zero-copy import path (importVaFrame).
#   - VAAPI symptom: since ~16:19 "hwaccel initialisation returned error"
#     (h264 VAAPI decode falls back to software) in BOTH kplayd AND a fresh C
#     probe (/tmp/vadevice_probe.c). At 15:43 VAAPI was ACTIVE. Suspect the
#     leaked iHD contexts wedged the driver; REBOOT to confirm.
# VERDICT: two known leaks (verdict 57 + session 30), now both alive through
#   the zero-copy present path. NOT a regression from verdict 61 (wedge fix is
#   DONE + confirmed working).
# NEXT (post-reboot, in order):
#   1. [DONE 2026-09-25 ~16:30] REBOOT/relog — driver wedge cleared + both
#      leaks reaped (kplayd 27MB RSS / 1 thread / 0 renderD128 fds; kidulwm
#      fresh). Confirmed live post-relog.
#   2. [DONE 2026-09-25 ~16:31] VERIFY VAAPI returns — ffmpeg vaapi decode
#      probe on renderD128 (Intel iGPU, PCI 00:02.0) decodes h264 clean,
#      NO "hwaccel init error". iHD wedge CONFIRMED CLEARED by the reboot.
#   3. PIN + FIX compositor retention (THE 2.5GB fish): per-frame setBuffer ->
#      texture recreate -> GEM leak. Likely fix = cache imported buffer per
#      VASurfaceID (~8 slots), create the scene node ONCE, setBuffer the cached
#      entry; or destroy+recreate the node on surface CHANGE (not per frame).
#      See verdict 52 Card A + video-playback-architecture skill.
#   4. THEN kplayd VA-device leak (session 30): pin the import-path ref
#      (vaExportSurfaceHandle + eglCreateImage holds the device) before any
#      unref — no UAF guess.
#
# VERDICT 61 (bobdotrix 2026-09-25) — "SECOND MOVIE WON'T PLAY" = SESSION-32 POLL-LOOP WEDGE, FIXED + DEPLOYED (eye-test owed)
#
# SYMPTOM (Barticus TV test, post-relog, ~15:00): the FIRST movie/TV channel
#   plays; close it; the SECOND will not play. RAM still climbs.
# CONFIRMED (live host, frozen-process forensics matches session 32 exactly):
#   kplayd pid 190444 (verdict-59 binary a64ef0c3, live since 14:37) holds
#   28 THREADS (16 av:h264:df* frame threads + threaded-ml demuxer + reader
#   STILL ALIVE) and 5 renderD128 fds — fd 12 = leaked VA decode device,
#   fds 19-22 = shell render engine. RSS 233MB vs 27MB clean restart. A player
#   was opened and NEVER torn down (closePlayer never ran dropShell).
#   kidulwm RSS 973MB (at the ~900MB verdict-57 bar, near/over).
#   DOOR (a) PINNED (live thread dump + socket): main thread 190444 parked in
#   __x64_sys_ppoll.cold (wl_display_read_events' NO-TIMEOUT read on the wayland
#   fd), threaded-ml demuxer alive in __x64_sys_poll.cold (av_read_frame),
#   16 av:h264:df* frame threads futex_wait. kplay.sock is SOCK_SEQPACKET and
#   connect() now returns EAGAIN (listen backlog full — the loop is NOT calling
#   accept4). Journal silent since 14:55:36. This is door (a): the poll loop
#   blocked in the Wayland read after the slide closed and the compositor
#   stopped sending events, so the close verb was never read, closePlayer never
#   ran, dropShell never ran. NOT door (b) (main thread is in ppoll, not a
#   futex join).
# VERDICT: NOT a regression from verdict 59/60 (live-reconnect + idle-blank —
#   both remain fixed/live). This is the SESSION-32 kplayd poll-loop wedge
#   (card docs/cards/2026-09-25-kplayd-close-wedge.md, then "DIAGNOSED, FIX
#   SPEC'D, NOT CODED"). Barticus's test REPRODUCED it — confirming the
#   diagnosis. The fix landed later this session — see FIXED + DEPLOYED below.
#   RAM climb = unreaped VA-device GEM + shell (72-133MB each) the wedged
#   close never releases, PLUS the session-30 clean-close VA import-path leak
#   (separate, still open).
# FIXED + DEPLOYED (bobdotrix 2026-09-25, kmedia b55fda1 + 51817f9 signed):
#   CORRECTION (gdb backtrace of the live wedge, 2nd repro): the real block was
#   NOT the read path — it was the PRESENT path. render() -> eglSwapBuffers ->
#   wl_display_dispatch_queue -> ppoll(infinite). eglSwapInterval(1) made
#   eglSwapBuffers block waiting for the compositor's refresh; when the slide
#   closed and the compositor stopped presenting, that block was forever. The
#   read-path fix (door a) removed a real but SEPARATE latent wedge.
#   REAL FIX (51817f9): eglSwapInterval(0) — eglSwapBuffers never blocks; vsync
#   pacing is already the shell's frame-callback gate (cb_fresh) in tick().
#   door (b) = threads_alive + 2s bounded join + exit(1) on wedge (unchanged).
#   playertest PASS + socket open->close PASS (shell live -> threads joined
#   bounded, 0 renderD128 fds after close).
#   kplayd deployed c8b2d9da (.bak-6909a72a = read-path-only; .bak-a64ef0c3 =
#   verdict 59), service restarted clean (1 task, 27MB RSS, 0 renderD128).
#   EYE-TEST OWED (Barticus, TV): play->close->play x3 (no wedge, no
#   play-until-reboot); live cut -> close -> play; after close
#   `ls /proc/$(pgrep -x kplayd)/fd | grep renderD128` = empty; simulated
#   wedge (kill -STOP reader + close) -> systemd respawns <3s.
#   FOLLOW-ON (session 30, separate deploy): pin the third ref in Gl.zig
#   importVaFrame (vaExportSurfaceHandle + eglCreateImage) — clean-close VA
#   leak; needs the import-path repro before any unref (no UAF guess).
#
# VERDICT 60 (bobdotrix 2026-09-25) — IDLE-BLANK CUT THE MOVIE/TV EVERY 10min: playbackInhibitsBlank() never saw fullscreen video [KidulWM a1b2928, DEPLOYED kidulwm 03d9f15d, RELOG OWED]
#
# SYMPTOM (Barticus): a screenBlank fires at the 10 min mark and cuts the
#   movie or TV — should NOT happen while fullscreen is in play.
# ROOT CAUSE: smartLock idle-blank (keybinds.blank.timeout_s=600 = 10min,
#   inhibit_visual=true) calls playbackInhibitsBlank() to decide whether to
#   skip blanking. That fn only read the MUSIC mirror (media_player.cached,
#   set by setMusicNowPlaying) — the video path (kplayOpen + videoFullscreenEnter)
#   never sets cached, so fullscreen video (movies / LIVE TV) returned false and
#   the blank fired mid-watch. SEPARATE from verdict 59 (kmedia reconnect): the
#   "10min cut" was the BLANK, not the feed.
# FIX (KidulWM a1b2928, signed): playbackInhibitsBlank() returns inhibit_visual
#   when video_fullscreen is true (fullscreen-is-a-mode signal, verdict 56).
# DEPLOYED /usr/local/bin/kidulwm 03d9f15d (.bak-b729ded2 = verdict 58).
#   RELOG OWED to pick it up (kidulwm is the compositor — never restarted for
#   the user). bobdotrix dies on relog; this ledger is the bridge.
#   POST-RELOG TEST: play a movie/TV, no input >10min -> screen stays ON.
#   Music still does NOT inhibit (inhibit_audio=false; screen may blank while
#   music plays, per design). Manual Mod4+x blank still works.
# NOTE (architectural, deferred): TV channels play via kplayOpen -> kplayd
#   'open' verb (is_live=false), NOT 'open_live' — the compositor's KplayClient
#   has no open_live method. So the live signal-lost/reconnect path (verdict 59)
#   is NOT yet exercised by the TV rail; a dead feed ends playback like EOF
#   instead of reconnecting. The live rail (open_live verb + IPTV rail) is the
#   deferred follow-on, not this session.

# VERDICT 59 (bobdotrix 2026-09-25) — LIVE-TV RECONNECT/CLOSE WEDGE: hung reopen blocked close(), froze kplayd ("play 10min → cut → no other channel until reboot") [kmedia 5e1cb13, DEPLOYED kplayd a64ef0c3]
#
# SYMPTOM (Barticus): play a live channel ~10 min → it cuts; then can't play
#   ANY other channel until reboot. Channels 7 & 9 (Seven/Nine) also take a
#   LONG time to start now and still cut out. Most channels fail to (re)play.
# ROOT CAUSE (code-proven): kmedia Player.reconnectLive() reopened the dead
#   stream with avformat_open_input(url, null, null) — NO rw_timeout, NO
#   timeout, and the avio interrupt callback is wired only AFTER open returns.
#   A hung reopen (stalled mjh.nz `.r` redirect / TLS / DNS) blocked the
#   READER thread indefinitely. closeInternal() then t.join()s that thread,
#   so close() wedged kplayd's SINGLE poll loop — no further open_live/close/
#   status verb was ever serviced. The initial open (openInternal) already
#   passed rw_timeout=5s/timeout=5s; the reconnect open was the asymmetry.
#   This is the CLOSE-MUST-NOT-BLOCK-THE-LOOP law (video-playback-arch skill).
# FIX (kmedia 5e1cb13, signed): reconnect open now passes the SAME live dict
#   as openInternal (rw_timeout, timeout, buffer_size, probesize,
#   analyzeduration). A dead reopen fails in ~5s; the reader loop stays
#   responsive to stop_flag, close() joins bounded. livetest PASS: backoff
#   retry still recovers (signal-lost -> recovered, clean exit).
# DEPLOYED /usr/local/bin/kplayd a64ef0c3 (ReleaseSafe, mv-over swap, .bak-
#   403639f9 kept), service restarted, daemon responsive (status verb clean).
# OWED (eye-test, TV): play a channel past the ~10min death -> it should
#   freeze-on-last-frame then recover (or at minimum NOT wedge the daemon);
#   Escape/switch channel must work without reboot.
# STILL OPEN (next, "2" of the plan): the ~10min CUT trigger + the 7/9
#   SLOW-START are UNPINNED — need a live repro (mpv control + KMEDIA_TIMING=1
#   on 7 & 9) to separate our clock/reconnect from the mjh.nz feed. Lead:
#   Seven now returns a Yospace CSM playlist (ppId session, #CSM, ad-stitched)
#   — the skill flags SSAI as a known HLS-demux breaker at ad breaks (~10min
#   cadence on commercial TV). Nine is a clean master. Indonesian/Java test
#   channels are parked (test feeds; curation is a later stage, not reset).

# VERDICT 58 (bobdotrix 2026-09-22) — PIPEWIRE "HAMMERING" = ALWAYS-ON FFT MONITOR CAPTURE; NOW CORKED WHEN SILENT [DEPLOYED b729ded2, commit 917e826]
#
# SYMPTOM (Barticus): PipeWire hammering on htop with nothing playing.
# ROOT CAUSE: the "kidulwm-kmedia" sink-monitor LISTENING tap (kmedia.zig
#   capture thread, kmedia_shim.c pw_stream_new_simple) connects ONCE at boot
#   (main.zig:38 kmedia.start()) and is never deactivated. As a live
#   Stream/Input monitor it pins the ALSA sink (graph driver node 57) awake
#   at full quantum 24/7 — data-loop thread never sleeps (1:51 CPU accumulated
#   over 5.5h, ~0.6% steady), sink never suspends. LISTENING is legal
#   (sound.md: "needs no floor") but must not force the graph awake when the
#   room is silent.
# FIX (917e826): gate the capture stream's active state on ksound's floor table
#   — audioLive() (verdict 11 ONE truth; excludes Stream/Input by class so it
#   cannot self-sustain). The existing silence-watchdog thread now also, every
#   ~300ms, calls pw_stream_set_active(stream, audioLive()): cork when silent
#   (sink+graph suspend), uncork the instant a playback stream holds the floor.
#   Our OWN stream -> native set_active, NOT link-teardown (that is for foreign
#   streams, ksound HANDOFF). +1 extern fn, +19 lines, src/core/kmedia.zig.
# DEPLOYED b729ded2 (.bak-5438118f = verdict 56). Build+test clean, signed.
#   bobdotrix does NOT survive relog — handoff recorded here.
# POST-RELOG VERIFY (Barticus): nothing playing -> `pw-cli info 48` (or pw-top)
#   shows kidulwm-kmedia = paused/inactive, and pipewire data-loop CPU ~0 idle;
#   play a video -> stream uncorks, visualizer live; stop -> re-corks within
#   ~300ms. If the graph STILL runs idle, the sink is held by something else.

# VERDICT 57 (bobdotrix 2026-09-22) — IDLE-RAM WEDGE RELOCATED: THE .VIDEO SLIDE (same-GPU, NOT fixed by re-cable); verdict 56 DEPLOYED
#
# Barticus: "800MB extra at idle" after watching videos — each video adds
# RAM and never lets it go. Host live hunt:
#   - kidulwm RSS: ~742MB boot steady-state -> +625MB (13:34:06-14, ~78MB/s)
#     -> +195MB (13:36:55-57), held ~1.6GB after close. Never released.
#   - smaps: 28 x ~27-30MB rw- MAP_PRIVATE ANON chunks (19x27 8x30 1x31MB)
#     = ~800MB retained. EXACT verdict-51 "cross-GPU staging" signature —
#     but ON SAME-GPU now: NVIDIA runtime-suspended, WLR_DRM_DEVICES=
#     /dev/dri/card1 live, TV on Intel DP-3, kidulwm + kplayd BOTH on
#     renderD128. Cross-vendor staging is impossible here -> verdict 53's
#     "cross-GPU, structurally closed" was wrong/incomplete. The retainer is
#     the .video slide, not the GPU boundary.
#   - Running binary was 1afc2343 = verdict 55, which STILL carried the
#     .video slide (renderBlackToBuffer ~33MB black card + chrome_buffer +
#     host surface, videoSlideSpawnRightOfPlayer). Verdict 56 deletes ALL of
#     it (fullscreen = a mode the card enters/leaves, teardown kills
#     host+curtain+kplay on exit).
#
# DEPLOYED this session: verdict 56 -> /usr/local/bin/kidulwm = 5438118f,
#   .bak-1afc2343 kept (drop-back). Build + zig build test clean.
# ALSO FOUND (kmedia, separate, NOT fixed): kplayd leaks its VA-API device
#   per video (~1 renderD128 fd + ~72-133MB GEM each). A plain decode probe
#   (create+decode+avcodec_free_context) closes the fd clean -> the leak is
#   the zero-copy export/import path's extra ref, NOT the device lifecycle.
#   Needs the import-path repro to pin before fixing (no UAF guess). The GEM
#   feeds the SAME 'idle RAM' the compositor retention does.
#
# POST-RELOAD VERIFY (Barticus): play 2-3 videos to natural end + quit.
#   Expect kidulwm RSS ~900MB FLAT after warmup (the bar); and when idle
#   `ls /proc/$(pgrep -x kplayd)/fd | grep renderD128` = 0 (proves the
#   kplayd VA leak out too — if >0 the kplayd leak is still open).

# VERDICT 56 (bobdotrix 2026-09-22) — THE .VIDEO SLIDE IS DELETED; FULLSCREEN = MODE + PRESENT CHOREOGRAPHY [DEPLOYED 5438118f 2026-09-22]
#
# Barticus's call: "the mediaPlayer slide should just be a normal slide." The
# .video deck slide (spawn-right-of-player, focus-walk, player-slip-to-peek,
# black placeholder, chrome ring, rect-chase) is GONE. Fullscreen video is now
# a MODE the card enters and leaves — the card never moves, never parks, never
# peeks. Net code: -36 lines (318 in, 354 out).
#
# THE PRESENT CHOREOGRAPHY (docs/law/fullscreen.md "the kidul way", LOCKED):
#   ENTER: black curtain 0->1 (~180ms) -> hold black, zero energy, until
#          kplayd maps -> video fades ITS OWN pixels 0->1 over black -> at rest
#          curtain stays at opacity 1 behind the video (invisible, free — the
#          black the exit fade reveals), scanout. Controlled present: NEVER
#          pop-on-receive.
#   EXIT:  video 1->0 (reveals curtain) -> teardown kplayd+host -> curtain
#          1->0 -> deck back in. Card still focused, never moved.
#   z-order: deck < overlay(peeks) < curtain < kplayd, re-asserted every tick
#   (applyLayout would strand peeks above the curtain). Same t*t*(3-2t)
#   smoothstep as the boot reveal — one easing language.
#
# DELETED: SlideKind.video, addCompositorSlideRightOf, videoSlideSpawnRightOf
# Player, videoSlidePaint, videoSlideClose/CloseOn, Output.video_slide, the
# black placeholder + chrome ring, pause-on-aside (video_focused +
# kplayPauseForAside/kplayResumeForFocus — fullscreen owns the output, there
# is no "aside"), renderBlackToBuffer, the slidedeck .video test.
# KEPT/REWIRED: kplay_window tracking + placeKplayWindow (now pins edge-to-edge
# over the full output, no rect chase), host surface + xdg-foreign parent
# handshake (videoHostSpawn), syncScanoutOverlay (gate = fullscreen AND idle
# phase, re-fires from the tick's phase edges), nav retire (focusNext/Prev +
# overview + mediaSlideClose + keyboard quit all -> videoFullscreenExit).
#
# State machine: FullscreenPhase enum (idle/fade_to_black/wait_video/
# fade_video_in/fade_video_out/fade_from_black) + curtain_anim struct +
# video_fullscreen/video_fullscreen_output. Driven per-frame from handleFrame
# (tickFullscreen) alongside tickWallpaperReveal.
#
# DEPLOYED 5438118f (bobdotrix 2026-09-22, after verdict 57 RSS hunt). EYE-TEST
# STILL OWED on the TV (host). DROP-BACK = 1edcea7 (verdict 55, binary
# 1afc2343, kept as /usr/local/bin/kidulwm.bak-1afc2343).
#   POST-RELOG TEST: play a movie -> card fades to black -> video fades in
#   edge-to-edge. Quit/nav -> video fades to black -> card fades back in,
#   still focused. No card-to-peek slip, no focus deadlock, no pop-on-receive.

# VERDICT 55 (bobdotrix 2026-09-22) — FULLSCREEN IS A MODE, NOT A DECK POSITION (law 8626a03 + 599a6c8, DEPLOYED 1afc2343)
#
# LAW LOCKED (docs/law/fullscreen.md, 8626a03): the screen is CFC for the eyes
# (sound.md applied to pixels). Fullscreen video owns the output and yields the
# instant deck navigation takes over. Corrects media-is-a-slide.md ruling 6
# ("fullscreen is a size") + kplay.md LAW 4 ("slide moves, video rides").
#
# CODE (599a6c8, 11 lines): focusNext / focusPrev / overviewToggle now RETIRE a
# playing video first (videoSlideClose -> teardown kplayd + .video slide, deck
# settles on the player card) then move. Never navigate with the video slide up.
# Barticus: quit-to-WALL is the wanted shape — card drops to browsing, position
# saved to watch-state, re-select the title resumes. NO retire-paused increment.
#
# OVERRIDES verdict 54's pause-on-aside for the NAVIGATION case (retire wins;
# pause-on-aside now only fires on a cursor-walk across outputs — moot on the
# single-TV appliance). Expected to kill: video riding the deck, the parked
# .video-slide focus deadlock (verdict 51), placeKplayWindow pin-chasing, the
# z-order burial (black placeholder over kplayd).
#
# EYE-TEST OWED (compile-verified only): play fullscreen -> Mod4+Left/Right ->
# video quits to the WALL card, deck settles, no crash, no parked slide. Also
# Mod4+Tab (overview) from fullscreen. DROP-BACK if it fails = b83da5e2
# (verdict 54, kept as /usr/local/bin/kidulwm.bak-b83da5e2).
#
# CROSS-REPO (same session, kmedia): renderD128/shm leak FIXED — the natural
# end-of-stream path (isDone) freed the player inline and left the EGL/GLES2
# shell alive (renderD128 fd + shm/cairo leak + use-after-free). Now routes
# through closePlayer (dropShell first). kplayd deployed 403639f9. Also removed
# the dead Player.hw_device_ctx field (avcodec_free_context already frees it —
# a false lead from the prior session). kmedia commits 70606b7 + 704a4d6.
#
# NOTE: prior kplayd was a 13.6MB Debug build (plain `zig build` defaults to
# Debug). Correct deploy is ReleaseSafe (~4.1MB). `zig build -Doptimize=ReleaseSafe`.

# VERDICT 54 (bobdotrix 2026-09-21) — SLIDE ROUTING + PAUSE-ON-ASIDE (bddc1c5, DEPLOYED b83da5e2)
#
# SYMPTOM (Barticus): opening a media card spawns the fullscreen video but
# pushes the media player to the OTHER screen — the two outputs' decks were
# meeting. "Each screen is its own slideDeck; the two never meet."
#
# ROOT CAUSE: spawn routing used the single global focused_output via
# currentDeck(). media_play already iterated outputs to find the player (correct),
# but media_card_toggle / homeSlideFocusOrSpawn / assignOutput resolved the
# target stage from GLOBAL focus, not the pointer. focusFollowsCursor flapping
# at the eDP-1/DP-3 seam (cursor x ~1920, the old side-by-side auto-placement)
# flipped focused_output every twitch, so the card/video landed on whichever
# stage focus last touched.
#
# FIX (bddc1c5): cursorOutput() / spawnDeck() — a NEW slide (media card, home
# launcher, fresh app window) routes by the POINTER's output (CFC law: the
# cursor is the focus you can see); focus-follow stays on currentDeck.
# assignOutput is cursor-first too. The global focused_output is now a
# focus-follow hint only, never a spawn authority.
#
# PAUSE-ON-ASIDE (same commit, Barticus ruling): the .video slide FREEZES
# playback when walked off-focus (pause verb) and RESUMES when walked back
# (resume verb). Edge-triggered via the new video_focused field in applyLayout.
# OVERRIDES the old "A4 rides at windowed rect" (session-and-deck-spec §2).
# LIVE catch-up-to-edge (seek_abs to live) = follow-on when the IPTV rail
# lands (deferred; resume already lands near the edge since a paused live
# stream stops advancing).
#
# outputs.toml CORRECTED (~/.config/kidulwm): dead HDMI-A-1 (NVIDIA) -> DP-3
# {0,0} above eDP-1 {0,1080}; both 1920 logical wide = laptop centred under
# the TV. No more side-by-side auto-placement (that was the flapping seam).
#
# DEPLOYED /usr/local/bin/kidulwm b83da5e2 (.bak-9fe3b374). RELOG OWED.
# POST-RELOG TEST (Barticus):
#   1. Outputs: TV (DP-3) ABOVE, laptop (eDP-1) BELOW, centred, no side-by-side.
#   2. media_play on the TV -> fullscreen video IN the TV slide; player peeks
#      left ON THE TV. Laptop deck untouched.
#   3. Walk off the video (Mod4+j/l): PAUSES (log "walked aside — pause").
#      Walk back: RESUMES ("refocused — resume").
#   4. media_card_toggle with cursor on the laptop -> card opens on the LAPTOP.
#   5. Watch the return z-order ("comes back under the widgets"): pause-on-aside
#      means the video is frozen, not playing under the bands; the fullscreen
#      return is handled by syncScanoutOverlay (Card A inc1). Flag if it still
#      renders under the bands on return.

# VERDICT 53 (bobdotrix 2026-09-21) — HUB WORKED + GOD CODE LOCKED + CARD A inc1 DEPLOYED
#
# HUB WORKED (post-relog check done): TV on Intel card1 DP-3 (3840x2160 scale=2),
# eDP-1 also card1; NVIDIA card0 HDMI-A-1 + DP-5 BOTH disconnected. Cross-GPU
# staging wedge STRUCTURALLY CLOSED (decode+present both Intel). NVIDIA still
# awake (P0 23W, runtime_status=active, kidulwm+Xorg hold refs) — PARK OWED
# (blacklist nvidia modules, or runtime-PM hard suspend). nvidia-smi shows
# kidulwm 2MiB (WLR_DRM_DEVICES still lists card0) + Xorg 4MiB.
#
# GOD CODE = the name everything converges on; NOT a new phase/refactor. LOCKED
# as docs/law/godcodemode.md. Recon SHRANK the fork: ONLY the CHAMFER corner-clip
# needs a wlroots patch (0.20.2 has no corner primitive at all). Scanout is
# already native (wire it); present-mode = OUR four-axis derivation; slide
# protocol = OUR extension. So slide-protocol + shared-painter "kslate" +
# scanout-by-default = pure KidulWM, zero fork. The sole patch (chamfer) is the
# generic piece to hand back AFTER kidulStyle is recognisable. Patchset-not-fork
# against pinned 0.20.2. Four axes = KIND/GEOMETRY/FOCUS/MOTION; present-mode is
# a DERIVED function, never stored.
#
# CARD A increment 1 DEPLOYED (9fe3b374, .bak-c360c8cc): syncScanoutOverlay() at
# end of applyLayout disables overlay_tree when the video slide is focused AND
# fullscreen, so kplayd's buffer is the sole visible node and wlroots scans out
# directly. Gate = fullscreen AND focused (FULLSCREEN-FOCUS LAW). Log marker:
# "scanout candidate — disabling overlay_tree".
#   POST-RELOG TEST (bobdotrix dies on relog):
#     1. media_play Raya -> fullscreen video slide on TV.
#     2. grep "scanout candidate" ~/.local/state/kidulwm/session.log == present.
#     3. kidulwm CPU during playback: ~2-5% = scanout ENGAGED (win). ~15-33% =
#        overlay disabled but wlroots didn't scan -> next inc targets kplayd's
#        buffer shape (xdg subtree -> bare SceneBuffer).
#     4. Walk video off-focus: peek + chrome MUST return (overlay re-enabled).
#     5. Close video: peek + chrome normal both outputs.
#   KNOWN LIMIT (inc1): fullscreen video also hides peek/chrome on the second
#   output (overlay_tree is global). Fine for the single-TV product; per-output
#   scanout state lands with the slide protocol (Card D). niri = escape hatch.
#   SPRING CLEAN NOTE: ~65 .bak-* binaries now (parked item said "20+" — stale).
#
# NVIDIA BLACKLIST DEPLOYED (2026-09-21, bobdotrix): /etc/modprobe.d/
#   blacklist-nvidia.conf (nvidia/nvidia_drm/nvidia_modeset/nvidia_uvm) +
#   kidulwm-session WLR_DRM_DEVICES=/dev/dri/card1 (card0 dropped). No initramfs
#   regen needed (MODULES=() empty, nvidia loads from rootfs via udev).
#   REBOOT OWED to take effect; POST-REBOOT VERIFY: `lsmod | grep -c nvidia`
#   == 0, `ls /sys/class/drm/` has no card0, `nvidia-smi` gone, dGPU D3cold.
#   Reversible: delete the conf + regen initramfs.

# VERDICT 52 (bobdotrix 2026-09-21) — SCANOUT RECON DONE: present path has ONE seam, direct scanout is wlroots-native but unwired
#
# THE PRESENT PATH (confirmed in tree, wlroots 0.20.1):
#   Output.handleFrame (server.zig:310) -> scene_output.commit(null) (341) ->
#   sendFrameDone. Every frame walks the WHOLE scene graph and re-composites
#   through the GPU renderer. No direct-scanout attempt, no frame gating.
#   That one seam is the root of BOTH live symptoms: fullscreen video jitter
#   (no zero-copy passthrough) + idle 36% CPU (ghostty GTK4 commit ~14/s
#   wakes the loop, every wake = full re-composite of both outputs).
#
# WLROOTS 0.20.1 ALREADY EXPOSES EVERYTHING (bindings present, zero use):
#   wlr_output_is_direct_scanout_allowed, SceneBuffer.OutputSample.
#   direct_scanout, SceneOutput.buildState/commitState, StateOptions. We link
#   these and call none. The fix is wiring, not invention.
#
# THE STRUCTURAL BLOCKER TO SCANOUT TODAY (why fullscreen video can't scan):
#   kplayd's video surface is a SceneXdgSurface inside a per-window
#   scene_tree, raised to top but left BELOW overlay_tree. overlay_tree
#   (peek + chrome rings) is always enabled and raiseToTop()'d — peek hides
#   its child trees on fullscreen but the overlay_tree node itself stays up.
#   wlroots direct scanout requires a SINGLE buffer covering the output with
#   NOTHING above it, no scale transform. So today: fullscreen video =
#   wallpaper + layer strata + slide card + kplayd surface + overlay_tree all
#   composited. Scanout needs the fullscreen path to collapse to: kplayd
#   buffer alone, overlay_tree (and slide card + wallpaper) disabled/hidden,
#   opaque, exact-cover.
#
# NEXT CARD (render-path law, LOCKED docs/law/render-path.md): scanout first,
#   then gating. Card A = fullscreen-video scanout reachability: on focused
#   fullscreen video slide, disable overlay_tree + hide wallpaper/card so
#   kplayd's buffer is the sole cover, then verify wlroots engages direct
#   scanout (log evidence + CPU ~2-5%). Card B = frame gating: handleFrame
#   skips commit when no scene damage + no active animation + no pending
#   layout (kills the idle 36%). Slow path (thin tentacles) unchanged.
#   GHOSTTY FORK + slide-protocol/"GodCodeMode" = separate spec, wargamed
#   after this law lands. Cross-GPU re-cable (verdict 51) still deferred.

# WEDGE ROOT-CAUSED + FOCUS DEADLOCK (bobdotrix 2026-09-20 ~22:30) — VERDICT 51 (LOCKED 2026-09-21)
#
# WEDGE = cross-GPU staging retention (I4). Live repro (Raya, ACTIVE playback,
# kplay committing ~4754 frames, kplayd healthy 400MB): kidulwm 288MB -> 1003MB.
# smaps classifies the +722MB as PRIVATE ANONYMOUS mmap: ~22 chunks of ~27-30MB,
# rw- MAP_PRIVATE, RETAINED (kidulwm stays ~989MB after `close` verb to kplayd).
# Root = hybrid GPU: kplayd decodes on INTEL iGPU (renderD128, VAAPI); the 4K TV
# (HDMI-A-1) is on the NVIDIA dGPU (sysfs card0=0x10de RTX3060 owns HDMI-A-1;
# card1=0x8086 Intel owns eDP-1). Cross-vendor dmabuf import (Intel decode ->
# NVIDIA present) CANNOT zero-copy -> each frame = ~27MB CPU staging buffer,
# wlroots/GL retains them. Phase-2 "zero-copy ~2% CPU" bar is STRUCTURALLY
# unattainable while decode+present sit on different GPUs.
# DECISION (Barticus 2026-09-21, LOCKED): forget the NVIDIA side — drive the TV
# from the INTERNAL Intel GPU (fork b). Decode is already Intel VAAPI; presenting
# on Intel removes the vendor boundary that forced the ~27MB CPU staging buffers.
# No NVDEC, no PRIME offload. wlroots releasing the staging buffers on the
# copy path stays as defense-in-depth (land it regardless of the GPU fix).
# MECHANICS RESOLVED (bobdotrix 2026-09-21): HDMI-A-1 is hardwired to the NVIDIA
# dGPU (card0) — muxless laptop, no mux, no software routing. The Intel iGPU's
# only external outputs are DP-1/DP-2 = the Thunderbolt 4 / USB-C port. So the
# fix is a RE-CABLE: TV -> USB-C hub -> TB4 port, then park NVIDIA.
# DEFERRED ("later thing" — Barticus has a USB-C hub ready for it):
#   BARTICUS does: plug the TV into the USB-C hub / TB4 port (USB-C->HDMI).
#   BOBDOTRIX does, when re-cabled: (1) verify TV lights on Intel DP-1/DP-2;
#   (2) park/disable NVIDIA (runtime PM or BIOS); (3) re-run the wedge repro —
#   kidulwm RSS flat, no staging growth; (4) confirm audio still Intel HDA
#   analog (default sink already is); (5) close verdict 51, retire the
#   cross-GPU staging root-cause.
#
# FOCUS DEADLOCK (separate bug, found live): a .video slide that loses focus
# (focus-follows-cursor / walk) becomes PARKED; focusNext/focusPrev SKIP parked
# slides -> unreachable (no re-focus, no Ctrl+q quit). videoSlideSpawnRightOfPlayer
# guards `findKind(.video) != null` -> no re-spawn either. Net = stuck slide,
# recover only via overview/relog. Fix: focus walk must land on a parked .video
# slide, or the slide must unpark on quit.

# WORKBENCH (READJUSTED 2026-09-19): Phase 2 (RSS wedge) is GPU-only, so the
# workbench moves BACK TO THE HOST for this phase — kidulwm runs on the host's
# real i915/VAAPI/dmabuf (GL, NOT pixman). ksd-reset stays the software/pixman
# workbench for everything else. fresh-one FROZEN, never touch. Host deploy =
# ReleaseSafe build on host -> /usr/local/bin/kidulwm (mv-over swap + .bak).
# bobdotrix does NOT survive an sddm login — document handoff here first.
#
# CURRENT POSITION (2026-09-20 ~20:50): verdict 50 + tracer DEPLOYED 869c68a9
# (commits 57dab29 + f5b4beb signed B&B) AND RELOG DONE — running pid 830305 ==
# /usr/local/bin/kidulwm == 869c68a9 byte-identical, live since 20:39. Git HEAD =
# 3f381ff (2 doc-only CENSUS commits past the deployed code; nothing undelivered).
# 15 commits UNPUSHED to Codeberg (ledger earlier said 3 — stale; list below).
# FRAMETRACE live 10s idle sample: rendered 14.2/s, commit 9.4/s = ghostty 9.4/s
# (100% of commits), all 6 scheduleFrame sites flat, kplay=0 other=0. Idle
# committer NAMED = ghostty. NEW GAP: rendered 14.2 vs 9.4 commit = ~4.8 wakes/s
# with NO named source (not commit, not any scheduleFrame site) — next question.
# Phase 2 step 1 DONE (wedge owner = kidulwm), step 2 IN PROGRESS. Raya = video.
#
# SURGERY DEPLOYED (2026-09-20 ~22:00): per-output render counter. The global
# ft_rendered folded a 144Hz+60Hz two-output rig into one number, so the
# "rendered 14.2 vs commit 9.4" gap was un-attributable. handleFrame now bumps
# per-Output ft_rendered AND emits FRAMETRACE-OUT {s} rendered={d} per output.
#   Deployed c360c8cc (.bak-869c68a9), build+test clean, signed. RELOG OWED.
#   POST-RELOG (bobdotrix dies on relog): grep FRAMETRACE-OUT, compute per-output
#   rate deltas. Expect ghostty's 9.4/s pinned to one output and ~4.8/s of
#   self-wake on the other (eDP 144Hz prime suspect) — names the idle waster.
#
# POST-RELOG READ DONE (bobdotrix, ~22:07) — idle waster NAMED, eDP hypothesis FALSIFIED:
#   Relog done: running kidulwm pid 1691 (started 22:04) == /usr/local/bin/kidulwm
#   == c360c8cc (no "(deleted)" on exe -> per-output tracer LIVE). FRAMETRACE-OUT:
#   eDP-1 rendered FLAT at 425 (never climbs); HDMI-A-1 rendered climbs ~14/s.
#   => idle render is 100% on the 4K HDMI output; eDP 144Hz is NOT the waster.
#   Global: commit ~14/s, ghostty=100% (kplay=0 other=0); rendered~=commit~=14/s
#   now — verdict-50 chrome fix closed the old "rendered 14.2 vs commit 9.4" gap
#   (the mystery ~4.8/s self-wake WAS the chrome regen loop). Idle cost: kidulwm
#   31% CPU, RSS 273MB FLAT (no idle wedge), i915_irqs ~86-100/s; kplayd 27MB/0.1%
#   healthy. ghostty (stock GTK4, pid 2502) is the SOLE committer, mapped on
#   HDMI-A-1 (CHROME create output=HDMI-A-1). 17 KidulWM commits UNPUSHED; kmedia
#   still NO git remote.
#   NEXT (step 2 close, ONE probe): is each ghostty commit a tiny-damage 4K redraw
#   (-> compositor commit-path cost, fix THERE) or a full-surface repaint (-> GTK4
#   frame-clock/client misconfig, fix the CLIENT)? Check ghostty GTK env/config for
#   the ~14/s driver FIRST (no relog); else add damage-rect to commit path + relog.
#
# KEY FINDING THIS SESSION (Barticus caught it): the "thick tentacle" committing
# ~8/s at idle is a STOCK ghostty — CachyOS package ghostty 1.3.1-2.2, a full
# GTK4 + libadwaita + gtk4-layer-shell app (ldd confirms libgtk-4/libadwaita-1/
# gtk4-layer-shell). The stripped-back ghostty fork is the END GAME and is NOT
# built yet. So the idle commit rate is GTK4 frame-clock + libadwaita + GSK
# machinery, NOT a light terminal. kidulwm itself links NO GTK (pure Zig/wlroots/
# cairo; only transitive libglib). The Zig-GTK4 plan has NOT leaked into the
# compositor — it is a separate tentacle (rkt-dashboard/gauge shells).
# VERDICT 50 also killed a stale premise: "damage-clipped commit" is a NON-FIX
# on wlroots 0.20.1 (commit() takes StateOptions, damage is internal).
#
# NEXT SESSION (post-relog): read FRAMETRACE's ghostty=/kplay=/other= split to
# NAME the idle committer by rate. Then answer: is each ghostty commit a cheap
# damage-clipped redraw or an expensive one? Dig the GTK4 frame-clock driver.
#
# LOG-GATE DEPLOYED (verdict 46, commit 8f85879): dev-trace (handleCommit /
# setSurfaceOffsetForFocus / BTN-NOTIFY / PTR-ENTER / pointer-diag) demoted
# info->debug. /usr/local/bin/kidulwm = 4544249f (stamp 8f85879, kmedia 1db5571),
# .bak-37fcf59. TAKES EFFECT ON RELOG. Watchdog now logs kplayd RSS too.
# Commit NOT yet pushed to Codeberg (owes post-relog verify + push).
#
# FINDING (verdict 46): idle CPU ~30-55% is NOT the watchdog (0.2%) and NOT the
# logging (16 lines/s is cheap). i915_irqs climbs ~28/s while idle = continuous
# frame scheduling -> the RENDER LOOP is the suspect, not the commit path (the
# no-op guards already kill the commit->damage->redraw loop). This IS the
# Phase 2 compositor-side suspect (verdict 45), not scope creep.
#
# NEXT SESSION STARTS HERE (2026-09-20):
#   POST-RELOG STATE VERIFIED (bobdotrix 2026-09-20 ~15:52): relog ALREADY DONE
#   (kidulwm pid 465925, started 15:39:58). Running binary == deployed == HEAD:
#   kidulwm 4544249f (8f85879), kplayd 6b6b040b. Log gate LIVE + verified SILENT
#   (dev-trace grep = 0). RESULT: idle CPU STILL ~40% (kidulwm), i915_irqs still
#   ~100/s. Log gate is CONFIRMED not-the-fix — verdict 46 was right that logging
#   was never the cause. The render loop / damage source IS the target.
#   NEW DATA: eDP-1 = 1920x1080 @144Hz + HDMI-A-1 = 3840x2160 @60Hz (2 outputs
#   live). A 144Hz panel amplifies any residual idle damage into 144 commits/s.
#   Live windows: ghostty mapped (the 8 commits/s thick tentacle); video-slide-
#   host unmapped; kplayd toplevel NOT mapped (no video playing). kidulwm RSS
#   flat 528MB / kplayd 429MB — no wedge at idle, as expected.
#   BAR/BUTTONS HYPOTHESIS (Barticus) CHECKED: transport bar + 2 buttons are GONE
#   from the compositor (verdict 33 deleted media_video.zig; media.zig has zero
#   transport/seek/scrub/button code). mediaSlideRefresh is verdict-17 guarded
#   (not a hot loop). kplayd 0.2% CPU = not looping. So no compositor code is
#   "searching for" the absent bar/buttons. Idle wake = damage-driven render-loop
#   churn, NOT an orphaned bar/button poll.
#
#   NEXT (Phase 2 step 2, compositor side): instrument WHO schedules frames /
#   damages at idle — render loop is event-driven (no free-running loop;
#   scheduleFrame sites all bounded: peek minute-timer 1029, requestLayout 1164,
#   scale change 3623, one-shot wallpaper reveal 3872/3911/3942). Prime suspects:
#   ghostty commit damage (thick tentacle) and/or a requestLayout storm. THEN
#   Phase 2 step 1 HOST repro (media_play Raya, watch BOTH RSS in
#   /var/log/kmedia-watchdog.log) to name the wedge owner.
#   Raya: /mnt/sda_backup/Jelly/Kids Movies/Raya.and.the.Last.Dragon.mkv.
#   3 KidulWM commits UNPUSHED (8f85879, 34c129f, 38bc43a) — push owed. kmedia
#   checkout has NO git remote configured (flag).
#
# PARKED (at Phase-2 base):
#   - CONSOLIDATE kidulwm-development skill (100KB god-file at size cap).
#   - Prune 20+ /usr/local/bin/kidulwm.bak-* binaries.
#   - Weather widget redo (new design, not clamps — see verdict 27 below).
#   - Peek-unit law (%-of-peek sizing) — deferred polish pass.
#   - Screens law (Boss/slaves/pack) — docs/law/screens.md, locked.
#
# NEW CARD (2026-09-20, Barticus) — HOUSE TEXT-SIZE TOKEN + remote scroll wheel:
#   TBD date. NOT discussed before tonight. The idea: a smooth scroll wheel on
#   the remote adjusts text size on the focused slide, so Granny sets the right
#   size from the lounge chair, and ALL our apps come ready with the same sized
#   CFC text. The CFC payoff: one token, every app follows.
#   SHAPE (agreed in conversation): do NOT build per-slide "remote -> focused
#   slide -> that slide's font size" as a hack. Build ONE house text-size token
#   (per-output, integer-scaled, like the existing CFC scale law) that every
#   THIN-tentacle app reads through the one shared painter (kpaint — see the
#   thin/thick + kpaint discussion, also new this session). Remote scroll wheel
#   just nudges that single token; all CFC text follows. This is the typography
#   half of the renderer-unification decision, and it supersedes the parked
#   "kfiles font ramp (typography law)" crumb in HANDOFF.
#   PRE-EXISTING HOOKS: theme.toml [typography] font_size_s/m/l=13/16/22, loaded
#   once in core/theme.zig (fixed, not runtime). output_layout_config.zig:24
#   already tags "text size" as the future per-output setting shape. Integer
#   scale from pixel density (CFC scale law, server.zig ~3470) is the model.
#   Frontier: token must live per-OUTPUT (two outputs, different scales) and be
#   integer-scaled, never fractional, to stay crisp (CFC law).

# ─────────────────────────────────────────────────────────────────────
# PROCESS LAWS (load-bearing for all reset work)
# ─────────────────────────────────────────────────────────────────────
# FIX-AND-RECORD (Barticus 2026-09-09): when a verdict is PROVEN (root cause
#   named, mechanism shown in code/logs, not theory) and the fix is small
#   (same file, no interface change), fix immediately — don't wait for approval.
#   Still: repro closes the symptom; early fix != skip verification.
# CENSUS-FIRST, NO PATCHES ON THEORY. Name the boundary, THEN fix.
# ONE CHANGE PER DEPLOY. Commit immediately when something works.
# SESSION HANDOFF (Barticus 2026-09-19): bobdotrix dies on an sddm login —
#   do all host-prep that needs no login cycle, record exact next commands,
#   hand off. This ledger IS the bridge.
# Dmabuf cache-key law: never key a dmabuf cache on surface id alone (pools
#   reuse ids across decoders -> stale hit renders freed GPU surfaces).


