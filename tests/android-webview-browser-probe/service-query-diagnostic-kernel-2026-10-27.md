The kernel patcher now accepts a separate `--maps-service-query` profile for
the six-file service-query framework diagnostic. It requires the exact sealed
controller-r1 base and new framework producer, retained controller/JNI/launcher
identities, nine original module digests and order, and only
`maps-service-query-diagnostic.tar` appended. Existing profiles and the frozen
PIDFD kernel installation path are unchanged.

The receipt must declare exactly one changed headless JAR input and five
changed deployment inputs. Their top-level changes are restricted to
`inputs_sha256` for headless and `inputs_sha256` plus
`framework_manifest_sha256` for Maps. The declared five digests must match the
six-file overlay inventory; the JAR, DEX, framework manifest and framework
build receipt are pinned to their sealed producer. Generated headless-input
and Maps-deployment receipt digests remain stager declarations checked by its
complete sealed-stage audit. This tool does not replace that audit or decode
deployed receipt bytes.

Focused negatives reject missing/changed identities or required inputs,
retained framework and wrong-path pins, added/removed/changed delta members,
unsafe inventory entries, links, duplicate/extra/missing files and mismatched
digests, changed module order/pins and another profile's receipt. They and
all existing hash, inventory, browser/Maps/protected/controller FAT and
installation tests pass. The added nine-module FAT fixture checks kernel
readback, all ten module readbacks, firmware/configuration preservation and
once-only installation. It uses a temporary baseline; the exact external
controller-base branch remains reviewed source logic pending actual staging.

Independent read-only review by `printf_path` passed the final source delta
and framework pins. The sole Boehm host build exited zero in 11.49 seconds
with 379,650,048 bytes maximum RSS; the complete self-test exited zero in
4.03 seconds with 28,082,176 bytes maximum RSS. Both recorded zero swaps.
Entry, local dependencies and compiler hashes matched before/after.

The immutable small tool audit is
`/Users/alex/.local/state/vinix/android/maps-service-query-kernel-patcher-2026-10-27-r1`:
entry source, both local dependency files, executable, commands, qualification
and build/self-test logs. Its sibling
`maps-service-query-kernel-patcher-2026-10-27-r1-seal` binds all 11 typed entries.
Creation, internal and separate checks pass; manifest SHA256
`15afc71d235487f12a74d5522d9d1b5f7768e91ad7cdb2ada92a3b0b433b6485`.
The original complete producer/base bundles, compiler, standard library, SDK
and frozen kernel build remain required. No SDK copies or kernel rebuilds
were made.

| Artifact | SHA256 |
| --- | --- |
| Entry source | `d02246f388ef1292bb86584c2d5f8bc8b354e9657f2d26d8350f78d7f99c0f77` |
| Host executable | `c4555e4c7967bb7031f16154cea957fe5cc0e94834a3c0ae29876bd813e67b76` |
| Controller-stage manifest | `3026dfd0e7d69fe81d0b8ba4d504d952fd14fa34d20c9b4cdf6d0b98cc9d857a` |
| Controller-stage boot | `0b8ba1493633c38b599dd368b437da31b5ef2bc421cd7d77c1b5e3960250cd58` |
| Framework manifest | `12f21e139e2602fa9517c6df7d2fda866d366d4d5f0cce6d7e07d62bbd044559` |
| Framework JAR | `74892a013cb72fdaef39852325a3fa46db217fbcd3a4f11fcba4cc7272b2a50b` |
| Framework DEX | `c453e3b480a6dbd0295a46b2a29f5ada5f7d0f7ee8c2bc07b5b9a76355d43e5e` |
| Framework build receipt | `ba4e01cfe7aa4433795de93ee0142f0fcf2501c30b07635b9ef7ab166caf2a83` |

Controller-stage and framework manifests, JAR, DEX and build receipt were
directly hashed in their original bundles. The boot pin was read from the
sealed inventory; actual patch execution hashes its bytes. This change's
source parent was `61088f06c9b866299555e602e8332d88931c9c35`.
Build command and complete qualification are retained in the small audit.

For a complete, sealed, unlaunched service-query-stage clone:

```sh
/Users/alex/.local/state/vinix/android/maps-service-query-kernel-patcher-2026-10-27-r1/patch-kernel --maps-service-query FRESH_CLONE /Users/alex/.local/state/vinix/android/pidfd-wait-kernel-build-2026-10-26-r1/kernel-aarch64-r2 1e9077779aaed08188e6f8111ca9ceb27b479517ece736a58157049f004fb36d
```

This change validates the host tool and fixtures. It performed no VM action
or diagnostic-stage installation. Google account sign-in remains unverified.
