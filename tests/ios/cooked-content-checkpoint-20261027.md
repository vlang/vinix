# Original cooked-content checkpoint — 2026-10-27

Source and audit tools: `b88625069dd096a38086b95d50591e12f6c0d7b0`.
Advertising remains skipped.

The probe now supplies 95 original IPA resource files (1,831,863,828 bytes),
including `uecommandline.txt` and the cooked `.pak`, `.utoc` and `.ucas`
content. The original IPA contains no loose `.uproject`; no substitute
descriptor was introduced. Fortnite advances past the missing-project alert
and stops at:

```text
V panic: iOS: unimplemented Objective-C method NSString precomposedStringWithCanonicalMapping
```

All 16 guest regression fixtures exit successfully. The deliberate fault
fixture captures all 31 ARM64 registers and restores execution. Window
protocol and child memory-budget enforcement checks pass. Three images load,
nine Objective-C `+load` calls and three initializer groups complete, and the
application reaches entry. A tagged 24 GiB virtual reservation succeeds;
available process memory remains positive inside the 2 GiB child budget.
Final cgroup OOM counters are zero.

The application exits with status 1; the desktop peer reports a broken pipe,
one tree build, zero polls and no supervisor kill. Its only application tree
has one node, zero images and 336 bytes. The peer has no compositor or input
device. **No rendered game frame is verified.** Progress remains **4/8
observable gates**: load/bind, `+load`, initialization and entry. Frame, menu,
login and playable match remain unverified; this fraction does not estimate
remaining effort or time.

The complete external bundle passes seal, independent check and mutation
selftest (37 changed guest observations, unsafe IPA members, malformed
manifests and missing/changed/extra resources). The checker also extracts and
hashes the preserved guest initramfs resources and binaries. Historical
checkers remain unchanged. Evidence:

```text
/Users/alex/Library/Caches/vinix-ios/cooked-content-20261027
VM state: probe-no-ads-303541
manifest.sha256 SHA-256:
fb54d1e1768eead6fee86b62b7f3023752b8f97e0846f71471e78d04d5edcd36
IPA SHA-256:
47a17e723f8fae91595ac897d8f59cd3b453c43113a20bb1ff31ab656167332e
Executable SHA-256:
6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
```

Preserve the entire bundle and its prior responder bundle. The application,
runtime, supervisor and 16 fixture builds are reused unchanged and checked
against the responder manifest. Only the resource overlay and boot capacity
change; the guest uses 8 GiB RAM to accommodate cooked resources, while the
application retains its enforced 2 GiB budget. This selected overlay is not a
complete installation. The prebuilt kernel is inventoried, not rebuilt;
selected input hashes do not seal complete compiler/header/library closures.

To reproduce with a fresh external output directory and the frozen V compiler,
compile `tests/ios/cooked-content.v` without `-prod`, then run `prepare OUT
PRIOR IPA`, `probe OUT`, `audit OUT FULL_REVISION`, `seal OUT`, `check OUT`
and `selftest OUT`. Exact commands, statuses, sources, original IPA, build
artifacts, resources, boot media and serial logs are preserved in the bundle.
