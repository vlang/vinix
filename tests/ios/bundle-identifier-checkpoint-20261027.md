# NSBundle identifier checkpoint — 2026-10-27

Runtime source: `29b98a5530ba729cee846aa824275bf350cdd9d4`.
Audit tools and inventoried sources:
`415d9d4efe5c6457fcbc5bb58589209fabe02060`.
Advertising remains skipped.

`NSBundle bundleIdentifier` now reads `CFBundleIdentifier` from the bundle's
`Info.plist` and caches the owned result, including nil. Concurrent first
reads publish one result; unused candidates are released. The bundle owns
the cached value until teardown.

Fortnite 42.30.1 advances past that selector with the original cooked content
and stops at:

```text
V panic: iOS: unimplemented Objective-C method NSDictionary dictionaryWithContentsOfFile:
```

A native macOS ARM64 Foundation oracle checks eleven plist cases: ordinary,
empty and Unicode strings, integer, Boolean, array, dictionary, absent key,
malformed file, missing file and binary plist. The runtime fixture checks
the same values and cached identity after rewriting the file, including nil
results. Host runs pass twice under AddressSanitizer and
UndefinedBehaviorSanitizer. Coverage includes selector metadata, signatures,
direct IMP calls, eight concurrent first readers, autorelease pool drainage,
retained-result lifetime and two lifetimes ending with zero live runtime
objects. All 22 guest fixtures exit successfully, including the new fixture.

Three images load, nine Objective-C `+load` calls and three initializer
groups complete, and application entry is reached. The intentional fault
captures all 31 ARM64 registers and restores execution; the UIKit window
protocol and child memory-budget checks pass. A tagged 24 GiB virtual
reservation succeeds. Available process memory stays positive within the
enforced 2 GiB game budget; final OOM counters are zero. The fresh guest has
8 GiB RAM and an 1800-second startup limit.

The game exits with status 1. Its desktop peer reports a broken pipe,
20 tree builds, 19 polls and no supervisor kill. The first application tree
has one node, zero images and 336 bytes. The peer has no compositor or input
device. **No rendered game frame is verified.** Progress remains **4/8
observable gates**: load/bind, `+load`, initialization and entry. Frame, menu,
login and playable match remain unverified. This fraction does not estimate
remaining effort or time.

The audit rebuilt the inventory and checker from the committed source.
Its selftest rejected 46 guest-log mutations and 16 host-log mutations,
unsafe IPA entries, malformed manifests and missing/changed/extra resources.
The seal passed, and the checker rebuilt from committed source independently
verified the complete evidence manifest and the guest's extracted resources,
binaries and memory/desktop configuration against the saved inputs.

Evidence location:

```text
/Users/alex/Library/Caches/vinix-ios/bundle-identifier-20261027
VM state: probe-no-ads-1927041
Manifest SHA-256:
18277021e0468ad5d6a914cb66e96026235ca166d7695d6adf2533202bd1c085
IPA SHA-256:
47a17e723f8fae91595ac897d8f59cd3b453c43113a20bb1ff31ab656167332e
Executable SHA-256:
6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
```

Preserve this complete bundle and the complete prior bundle at
`/Users/alex/Library/Caches/vinix-ios/string-path-20261027`, manifest hash
`8e496b665f244be1ca75105da9321454caf2a5641de48107dca679a61dee0d3a`,
plus its [earlier evidence chain](string-path-checkpoint-20261027.md).
Historical checkers remain unchanged.

The original IPA, application and 95 resource files (1,831,863,828 bytes) are
reused unchanged. Twenty-one prior fixture binaries and their generated C
are checked against the prior manifest; they validate the guest environment,
while the new fixture and host tests contain the current runtime. The
runtime and supervisor are rebuilt. The resource overlay is not a complete
installation. The prebuilt kernel is inventoried, not rebuilt; selected
input hashes do not seal complete compiler/header/library closures.

Preserved failed attempts document a concurrent build's TLS-directory
collision, a fixture call to an unsupported integer selector corrected
before validation, host disk exhaustion before the initial VM boot, and an
audit invocation rejected for an abbreviated revision. The first seal also
exhausted host disk because the frozen V's macOS `os.temp_dir()` ignored
`TMPDIR`; the checker now uses the validated scratch path directly. The
corrected builds, fresh probe and full-revision audit pass. The disk failure's
partial archive and inventory of removed partial staging files are retained;
no complete prior bundle was removed. Resource verification uses external
RAM-volume scratch storage. Successful probe status records completed capture; the
game's status 1 records the unsupported selector above.

To reproduce, compile `tests/ios/bundle-identifier.v` with the frozen V
compiler without `-prod`, then run `prepare OUT PRIOR`, `oracle OUT`,
`fixture OUT`, `build OUT`, `host OUT`, `probe OUT`, `audit OUT FULL_REVISION`,
`seal OUT`, `check OUT` and `selftest OUT`. Build fixture and runtime
sequentially. Set `VINIX_IOS_AUDIT_TMPDIR` to external storage with sufficient
space for guest resource extraction. Exact commands, statuses, sources,
original inputs, native observations, build artifacts, boot media and serial
logs are preserved in the bundle.
