# NSString comparison checkpoint — 2026-10-28

Runtime and fixtures: `b9d23fbf12c0ebcd36aba7aff23e86a6641c59d4`.
Saved auditor and source snapshot: `fb745db920181c686d7b5101916a77dbf8c3fcf3`.
Advertising remains skipped.

`NSString compare:` and its mutable-string counterpart compare canonically
decomposed Unicode scalars. Signed return metadata, concrete IMP calls,
embedded NULs, mutation and concurrent calls are checked. The native comparison
includes all 2,704 ordered pairs of a 52-string corpus, including supplementary
characters, Hangul and combining marks. Regular and deterministic ASan/UBSan
runs and the normalization regression pass.

All 31 ARM64 guest fixtures pass in a fresh boot. With the original cooked
content, Fortnite reaches `AVAudioSession setCategory:mode:options:error:`.
Three images, nine Objective-C `+load` calls, three initializer groups and
application entry complete. The game exits 1; the capture exits 0. No
application signal fault, OOM event or supervisor kill occurs. The desktop peer
reports 10 builds and nine polls before a broken pipe. Its initial tree contains
one node, zero images and 336 bytes; the peer has no compositor.

The 8 GiB, single-CPU guest keeps the tagged 24 GiB reservation, enforced 2 GiB
application budget and 1,800-second limit. Under-budget, over-budget and
supervisor-isolation checks pass. Final application usage is 328,118 bytes;
all OOM counters remain zero. Progress remains **4/8 observable launch gates
(50% of the checklist)**: load/bind, `+load`, initialization and application
entry. Frame, menu, login and playable match are unverified. This fraction
estimates neither effort nor time. Metal device execution and presentation
remain absent; the default device query returns nil.

The preceding RAM-backed comparison capture was lost. The earlier persistent
audio-category bundle also lacks four boot-media files, listed in this capture's
`missing-prior-media.txt`. Every surviving file matches that bundle's sealed
manifest. Its historical full auditor still rejects the incomplete bundle;
this checkpoint does not claim to restore it. A new boot recaptures complete
media and firmware using the verified retained IPA, resources and fixture
builds. The 95 resource files (1,831,863,828 bytes) remain unchanged. All 30
prior fixture binaries and generated C are reused unchanged; the comparison
fixture, runtime and supervisor are rebuilt.

The retained kernel has SHA-256
`1aaa1a692fffb653d75787af7df0848b62a0db17af86705f111bfdaf4384a0b6`.
Its historical dirty worktree prevents a reproducible-source claim. Guest
enforcement is verified with this binary. Missing, truncated and x86-64 kernel
inputs are rejected before changing serial capture or firmware.

The saved auditor rejects 61 guest-log mutations, 32 host-log mutations, five
replay-media mutations and five retained-inventory mutations, plus unsafe IPA
members and changed, missing or extra resources. It compares extracted guest
resources and binaries with their recorded inputs. Audit, seal and complete
bundle verification pass. The 708 selected build-input hashes cover selected
dependencies, rather than complete compiler, header and library closures.

The standalone archive was extracted into a fresh directory. Its full typed
inventory, permissions and file hashes match the original. The restored bundle
then passed its unchanged saved auditor at the original recorded path, including
guest resource and binary extraction. The redundant pre-restoration tree was
removed only after those checks passed.

Evidence and standalone archive (no prior bundle required for extraction):

```text
/Users/alex/Library/Caches/vinix-ios/string-compare-20261028
VM state: probe-no-ads-2134000
Manifest SHA-256:
032551d6c59da7fd7118dc4111c127e6b6e67f6709f9765541b02f95ea9b72f9

/Users/alex/Library/Caches/vinix-ios/string-compare-20261028.tar.zst
Archive SHA-256:
a0c69ec52718eb8fbfa3b809cc7b68072453644a27fdc7cd38effec96669897e

IPA SHA-256:
47a17e723f8fae91595ac897d8f59cd3b453c43113a20bb1ff31ab656167332e
Executable SHA-256:
6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
```

Restore with `zstd -dc ARCHIVE | tar -xpf - -C EMPTY_DIRECTORY`, compare with
`tests/ios/evidence-delta-archive.v compare-trees ORIGINAL RESTORED`, and run the
unchanged saved `string-compare check OUT` at the original recorded path.
`VINIX_IOS_AUDIT_TMPDIR` selects external extraction scratch. Validation logs
are retained outside the sealed bundle in
`/Users/alex/Library/Caches/vinix-ios/audio-category-20261027-work`.
