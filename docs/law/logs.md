# LAW — logs (immutable evidence: append-only, hash-chained)

LOCKED 2026-11-14, Barticus present (GSI). This is build-order slice (1) of
docket #59 USER PARTITIONS & ISOLATIONS.

## One sentence

The immutable SYSTEM base (dm-verity) is paired with immutable EVIDENCE: every
system log is append-only and hash-chained, so tampering is visible, not
possible.

## What is append-only + hash-chained

  ALL system logs:  the printk drain (/dev/kmsg -> /var/log/kernel.log, root-
                    owned via kushd redirectStdio), every daemon log, and the
                    klip audit (delegation.md).

The hash chain reuses the roster's prev-hash pattern (roster-format.md): each
record carries the sha256 of the prior bytes, so a back-dated or erased entry
breaks the chain and is detectable at replay.

## Rotation -> encrypted vault

Logs that grow too large rotate into an ENCRYPTED VAULT owned by root,
decryptable ONLY by the owner (Granny / CEO). The archive is cold; it is not a
live-readable file.

## Read is attenuating

Reading a log is itself a grant on the delegation tree (delegation.md): a
sub-user reads only their own scope, the owner/CEO reads the whole chain. Read
access never opens a sibling's or an ancestor's evidence.

## Already built vs missing

  ALREADY  kboot forkLogDrain (fsync/record) + kushd redirectStdio (root
           before privilege drop — a non-root process cannot tamper its own
           log). The printk drain is already root-owned.
  MISSING  append-only enforcement + the hash chain + the encrypted vault
           archive. This law is the spec for those three; none is built yet.

## The tailwind

Immutable base + immutable logs = an audit-grade appliance Linux. That is the
gov story: governments swap Windows for a box whose evidence cannot be quietly
rewritten, and the mega-local LLM gets born on gov money.

## Relationship to existing law

  partitions.md     the immutable base (dm-verity) this evidence pairs with.
  delegation.md     log-read attenuation — the tree decides who reads how much.
  roster-format.md  the prev-hash chain pattern, reused for log records.
  kboot/kushd       forkLogDrain + redirectStdio — the two pieces already in
                    the boot ladder.
  cold-storage.md   the encrypted archive is a cold vault, not a resident
                    daemon.
