# Canonical string normalization checkpoint — 2026-10-27

Source and audit tools: `aa8c5debcc534751af17c6d7601bd97f61970abb`.
Advertising remains skipped.

`NSString` and `NSMutableString` now implement
`precomposedStringWithCanonicalMapping`, including canonical reordering,
composition exclusions, Hangul and embedded NULs. Mutable input is copied
under the runtime lock; normalization produces an independent, autoreleased
immutable string. Temporary buffers are freed.

Fortnite advances past normalization with the original cooked content and
stops at:

```text
V panic: iOS: unimplemented Objective-C method NSString cStringUsingEncoding:
```

Native Foundation and runtime host tests pass twice under AddressSanitizer
and UndefinedBehaviorSanitizer. They exercise selector metadata, direct IMP
calls, mutation independence, lifetime, constants and eight concurrent
workers. Runtime checks finish two lifetimes with zero live objects. The
observed host Foundation result for already-composed Hangul LV followed by T
is tested separately: it preserves `각`, while the runtime completes NFC to
`각`. The shared cases otherwise agree.

All 17 guest regression fixtures exit successfully, including the new
normalization fixture. The intentional fault captures all 31 ARM64 registers
and restores execution. Window protocol and child memory-budget enforcement
checks pass. Three images load, nine Objective-C `+load` calls and three
initializer groups complete, and the application reaches entry. A tagged
24 GiB virtual reservation succeeds. Available process memory remains
positive inside the enforced 2 GiB child budget; final OOM counters are zero.

The application exits with status 1. Its desktop peer reports a broken pipe,
two tree builds, one poll and no supervisor kill. The first application tree
has one node, zero images and 336 bytes; serial output interleaves the second
exchange. The peer has no compositor or input device. **No rendered game
frame is verified.** Progress remains **4/8 observable gates**: load/bind,
`+load`, initialization and entry. Frame, menu, login and playable match
remain unverified. This fraction does not estimate remaining effort or time.

The complete external bundle passes seal and an independent check using the
checker rebuilt from the committed source. Its selftest rejects 41 changed
guest observations, 16 changed host observations, unsafe IPA members,
malformed manifests and missing/changed/extra resources. The checker extracts
and hashes the guest resources and binaries. Historical checkers remain
unchanged. Evidence:

```text
/Users/alex/Library/Caches/vinix-ios/string-normalization-20261027
VM state: probe-no-ads-425833
manifest.sha256 SHA-256:
9f6b40523391339940642c4e8ffa0f8db38a61540f7beeaa86e743f6325321b7
IPA SHA-256:
47a17e723f8fae91595ac897d8f59cd3b453c43113a20bb1ff31ab656167332e
Executable SHA-256:
6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
```

Preserve the entire bundle and its prior cooked-content bundle at
`/Users/alex/Library/Caches/vinix-ios/cooked-content-20261027` (manifest hash
`fb54d1e1768eead6fee86b62b7f3023752b8f97e0846f71471e78d04d5edcd36`).
The original IPA, application and 95 resource files (1,831,863,828 bytes) are
reused unchanged. Sixteen fixture binaries and their generated C files are
also reused and checked against the prior manifest; those fixtures validate
the guest environment, while the new fixture and host tests contain the
current runtime. The runtime and supervisor are rebuilt. This selected
resource overlay is not a complete installation. The prebuilt kernel is
inventoried, not rebuilt; selected input hashes do not seal complete
compiler/header/library closures.

The first VM attempt exhausted its 240-second startup limit while still
loading the large boot module. Its logs, status and firmware state remain in
`startup-timeout/`. A fresh VM with fresh firmware replayed the same prepared
boot media with 8 GiB RAM and an 1800-second startup limit. The application
kept its enforced 2 GiB budget. The successful probe status records completed
capture; the game's status 1 records the unsupported selector above.

To reproduce, compile `tests/ios/string-normalization.v` with the frozen V
compiler without `-prod`, then run `prepare OUT PRIOR`, `fixture OUT`,
`build OUT`, `host OUT`, `probe OUT`, `audit OUT FULL_REVISION`, `seal OUT`,
`check OUT` and `selftest OUT`. After a recorded startup timeout,
`retry-probe OUT` preserves that attempt and replays the prepared media.
Exact commands, statuses, sources, original inputs, build artifacts, boot
media and serial logs are preserved in the bundle.
