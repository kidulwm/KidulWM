# LAW — cold storage (the vault) (LOCKED 2026-10-02, Barticus present)

Secrets and user data live COLD. The vault is an encrypted FILESYSTEM (the
user's encrypted home), not a resident daemon, not a flat blob.

  what   one per-user encrypted home: LUKS/dm-crypt (per docket #14) or fscrypt
         (per-directory). The volume key is wrapped by the kidulKey (key-mode).
         At rest: ciphertext on disk. A file decrypts only when read — apps
         never know it was encrypted.
  when   cued on demand — unlocked when a secret is needed, wiped on close.
  wipe   zeroize (sodium_memzero) + no-swap (sodium_mlock) + no-dump
         (sodium_madvise MADV_DONTDUMP). Plaintext lifetime is seconds.
  boot   none. No process, no boot presence. Cold storage has no seat.

kvaultd v0.1 is a resident-but-dormant daemon (password-mode) — a systemd-ism,
RETIRED by this law: cold storage is cued, not resident. The cold-unlock cost
(~1s key unwrap / Argon2id) is paid on the rare open, bought back as "nothing
resident, nothing in RAM when closed."

The flat-blob shape (one encrypted file holding everything) is also retired for
bulk data — decrypting a whole home into RAM to read one email is the trap. A
flat blob only fits a TINY secrets store (keys/passwords, KB). For files and
email the shape is an encrypted FILESYSTEM: decrypt-on-read, per page.

## What is cold, what is not

  COLD (the home)       user DATA: emails, documents, photos, keys, secrets,
                        browser data, chat logs — anything private or a secret.
                        Files inside the ONE encrypted home, not separate
                        encrypted files. One volume key for all of it.
  NOT cold (keyed only) user APPS: packages, code, themes, tools. Code is not a
                        secret — encrypting it is wasted cycles. Keyed-access
                        writable subvol, mounts on cast.
  BASE                  the immutable golden image. Not encrypted, read-only,
                        swapped atomically (SYSTEM.md §7.3). Belongs to nobody.

## Who places what

  Linux (kernel)  mount / namespace / btrfs — the physics (theatre.md: KERNEL
                  = the floor).
  init (PID-1)    mounts the base at boot.
  key-cast        the kidulKey cast mounts the user's layers (data vault + app
                  subvol) at the home path. Unplug -> unmount, gone.
  kushd (usher)   seats PROCESSES, not files. Hands a seat the right HOME (the
                  mounted layer); never organises folders.

The fine structure (folders, filenames) is the USER's, done by their own apps
inside the mounted layer. No daemon micro-manages file placement.
