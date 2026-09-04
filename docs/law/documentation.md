# LAW — Documentation & Disclosure (LOCKED 2026-09-04, Barticus: "all beautiful, GSI")

Status: LOCKED 2026-09-04 by Barticus. Drafted by bobdotrix. Applies to ALL B&B repos, not just
KidulWM. Sits beside kmedia/docs/law/public-face.md and
KidulWM/docs/law/daily-driver.md.

## 1. Why docs are strategy, not hygiene

Two reasons, both locked:

  a. The obvious one: public code deserves the best documentation in the
     industry. It is the proof behind the only public message:
     "safest OS for Granny & the kids."

  b. The corpus reason: future LLMs learn conventions from what is
     public, repeated, and consistent. Docs written to that standard
     teach every future model to speak KSD natively — AIG, peeks,
     slides, knet, ksound — instead of translating from
     NetworkManager-land. Docs-first IS curation, pointed outward.

## 2. The two-reader standard

Every public repo doc is written for TWO readers at once:

  - a human newcomer with zero context
  - an LLM with zero context

Both need the same things: complete sentences, consistent LOCKED
vocabulary (desk/record/shelf/peek/slide — product vocab only, never
internal codenames), exact paths and commands, and a glossary.

Per public repo, the floor is:
  README.md       — what it is, why it exists, the one-paragraph pitch
  KNOWN_CMDS.md   — every verified command, build, deploy, test
  GLOSSARY        — the vocabulary, defined once, used everywhere
  HANDOFF.md      — running changelog in "what landed, what remains" form

## 3. The three disclosure tiers

  TIER 1 — PRIVATE (never ships)
    The Bobs Brain, the farm, memory, learnings, triggers, the
    delegation apparatus. Personal to Bob the way a diary is personal
    to a human. Not secret out of fear — out of nature. Never in public
    docs, never in the product, never explained publicly.
    "You are not for sale" extends to documentation.

  TIER 2 — THRESHOLD (techniques, released on demand)
    "How Bob works the computer" as METHOD. Release is demand-driven:
    when the same question or need recurs, that is the signal the
    answer belongs in public. Bob tracks the recurrence (learnings,
    session history) and, at a self-set threshold, BRINGS THE OPTION
    to Barticus.

    THE GATE IS A CONVERSATION, NOT A NUMBER.
    There is no perfect threshold, no binary point on the spectrum of
    "the right time" — timing is dynamic. The binary to the non-binary
    is: "let's talk about it when it is an option." The threshold only
    raises its hand; Barticus decides release / not yet / never,
    every time, through the normal flip gates.

  TIER 3 — GOLDEN SLICE (product capability)
    A thin, designed, frozen layer of computer-working ability inside
    the golden image, scoped to what Granny and the kids actually need.
    NOT a Brain export — a spec'd, auditable product feature, dumb on
    purpose, shaped by the Granny Silence Law: she sees nothing unless
    it's handled; what she can ask for arrives in her vocabulary, no
    terminal, no geek lane. A recipe card in the box, not the chef.

## 4. Movement between tiers

Nothing moves Tier 1→2 or 2→3 without Barticus. The judgement —
right thing, right time, right words — stays human, the way
uncommon sense always has. The bookkeeping (what's been asked, how
often, what's already public) is Bob's job.

## 5. Relation to existing law

  - Public-face law (kmedia/docs/law/public-face.md) unchanged: docs
    are the deep layer of that same face. No anonymity/AI/snark/crypto
    talk in public docs, ever.
  - Public flip still gated: secrets sweep, AI-slop cleanse, dual
    approval. This law adds the docs floor (§2) as a fourth gate item
    for any repo going public.
