# LAW — StarShipKidul (the ship that carries the theatre) (LOCKED 2026-10-03, Barticus present)

The grandest ship on the sea and in the sky has its own theatre on the upper
level. This law names the OUTER frame that the theatre (theatre.md) has always
been the inner map of. It does not relitigate the theatre — it says what the
theatre sits INSIDE.

## The frame — one vessel, two maps

StarShipKidul is the ship. The theatre is the upper level of it — NOT the top
deck. The top deck is open to the weather, and it reveals the storms and
troubles ahead; the theatre is sheltered below it, enclosed, so the px stay
none the wiser while the weather does its worst. Not two competing metaphors,
not a poem — one vessel, and the stage is a deck:

  SHIP (outer)      governance. Who holds the wheel, who is answerable, who
                    succeeds. §7.2: Captain, crew, PAX. The ship outlives the
                    captain. StarShipKidul sails the SEA and the SKY.
  THEATRE (inner)   lifecycle + trust. Who seats whom, who paints, what is
                    trusted vs the beer garden. theatre.md. The stage.

The joint between them is kushd — the FIRST MATE on the ship and the USHER at
the stage, the same hand. It assembles the pieces so the sails go up: "hoist
the sails" is the boot image, and the usher/first-mate is the one who makes
sure every piece is in place before they catch wind. One actor, one name for
each of its two stances.

DOM0 is the CAPTAIN'S SAFE (dom0.md) — and it is NOT below decks. It sits in
the COCKPIT, at the captain's side, with security around it 24/7. It holds the
trust root — kidulKey, kvaultd, the usher, the face. ONLY the captain has the
keys; no other soul has access. The skipper has to DIE before he hands over
the keys. Neither the crew, nor the sea, nor the sky may reach into it. The
safe in the cockpit is why the network lives in the brig, not the trust core.

## The two boundaries — sea and sky

The ship is sealed against BOTH its oceans, differently:

  THE SEA  the untrusted local. The LAN, the household, the wire. crypto.md
           already says "a LAN is not a trust boundary" — the sea is where one
           pawned device opens the whole stream. The pen and the brig are the
           boundary to the sea.
  THE SKY  the reachable beyond. WAN, the stars, the wider net. knetd is the
           boundary to the sky — the network authority, riding in the brig
           (dom0.md), the one seat the usher can cut.

The ship sails both; it never trusts either. Two boundaries, two walls, one
vessel.

## The seating plan — trust grades, named (LOCKED)

The seat-grade classes carry ship names, top to bottom, no explanation needed:

  bridge              system      full freedom — lives only inside kushd
                                  itself; nothing in the bill uses it.
  wardroom            service     the officers — root but bounded (knetd,
                                  kvaultd, ksound).
  deck / crew         user        the everyday, non-root (kidulwm + tentacles).
  quarters            restricted  hardened non-root, confined to quarters
                                  (browser, email).
  the brig            the KVM arm  the locked cell below decks — worse than
                                  quarters. A place, not a class (dom0.md).

The four classes are all one ARM (the pen, fork/exec); the brig is the second
ARM (KVM, a whole guest). Class = the walls (what); arm = the mechanism (how);
uid = the identity (who). Three axes, never blurred.

## The eye-above law — two powers, never merged

The Captain is the human ABOARD the ship, holding the wheel — governance,
answerable, temporary (§7.2). The KEYE is the human ABOVE the ship, holding
the cord — the master switch, the escape hatch (theatre.md). Steering and
cutting-the-power are two DIFFERENT powers. A ship that loses its eye above is
a crew that cannot be switched off. Both, always, never merged.

## One name per thing

The face is the CONDUCTOR, not "the sails" — the sails belong to the boot
image ("hoist the sails"), not to the face's permanent name. Every job has one
home and one word. A thing with two names is the two-owner smell (theatre.md)
in a new costume.

## The skipper's law — nothing is ever 100% safe

The sea is not always calm; it gets rough, and so does the internet (hackers,
storms, the whole beer garden of machines). So NOTHING is ever 100% safe — and
we do not pretend otherwise. The claim is not "unbreachable"; it is that a good
skipper gets you to your destination unscathed through experience and know-how.
Defence by architecture (the ponder pays off) buys you the rough-water margin;
it does not promise calm seas. This is what "colder than Qubes" actually means:
a better-protected safe and a steadier hand, not a magic hull. And the px
(the audience, the passengers) never know the real truth — they just enjoy the
show. That is the whole point of the theatre.
