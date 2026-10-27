# NSString bounded C-string checkpoint — 2026-10-27

Runtime, fixture and auditor source: `445f57ce7dd45da2cf407e051603b109803b2c57`.
Advertising remains skipped.

`NSString` and `NSMutableString getCString:maxLength:encoding:` now copy ASCII,
UTF-8 and Latin-1 into caller storage. Capacity includes the terminating NUL;
embedded NUL remains part of the copied data. Insufficient capacity or an
unrepresentable value returns false and clears the first byte when capacity is
nonzero. Zero capacity leaves storage untouched. The implementation snapshots
mutable input under the runtime lock and frees its temporary storage.

The existing `cStringUsingEncoding:` method shares the encoder. Its native/runtime
regression fixture and the new fixture each pass regular and deterministic
ASan/UBSan host runs. Tests cover short buffers with sentinels, Unicode, embedded
NUL, conversion failures, long inputs through 65,536 repetitions, method metadata,
direct IMP calls, mutation, UTF-8/UTF-16 constants, eight workers and two lifetimes
ending with zero live runtime objects. All 24 guest fixtures exit successfully.

The native oracle records 648 conversion observations and both class signatures.
On this host, Foundation 26.5 can report success and write beyond capacity for
non-ASCII UTF-8 with capacity one. The oracle preserves that observation; the
shared comparison skips that native case, and Vinix enforces the capacity bound.
Native direct calls use each concrete class-cluster receiver's implementation.

Fortnite 42.30.1 advances past bounded C-string copying with the original cooked
content and stops at:

```text
V panic: iOS: unimplemented Objective-C method NSBundle infoDictionary
```

Three images load, nine Objective-C `+load` calls and three initializer groups
complete, and application entry is reached. The intentional fault captures all
31 ARM64 registers and restores execution. A tagged 24 GiB virtual reservation,
the UIKit window protocol and the enforced 2 GiB game memory budget pass. The
guest has 8 GiB RAM and an 1800-second startup limit.

The game exits 1; capture completes with status 0. The desktop peer reports a
broken pipe, 13 tree builds, 12 polls and no supervisor kill. Final budget usage
is 191,984 KiB with zero OOM counters. The first tree has one node, zero images
and 336 bytes; the peer has no compositor or input device. **No rendered game
frame is verified.** Progress remains **4/8 observable gates**: load/bind, `+load`,
initialization and entry. Frame, menu, login and playable match remain
unverified. This fraction does not estimate remaining effort or time.

The auditor rebuilt from committed source passes seal, check and selftest.
Its negative controls reject 48 guest-log mutations, 32 host-log mutations,
unsafe IPA entries, malformed manifests and changed, missing or extra resources.
It extracts guest resources and binaries and compares them with the saved
inputs, including memory and desktop configuration.

Evidence identities:

```text
Original complete bundle:
/Volumes/VinixAppendRestore20261027/get-cstring-guest
VM state: probe-no-ads-99833
Manifest SHA-256:
0400b6061bb6983602eba8df0e60298a1141f8e249049fd6346300929c984b32

Persistent lossless archive:
/Users/alex/Library/Caches/vinix-ios/string-get-cstring-20261027.archive
archive.sha256 SHA-256:
d4b77742ad8678018133820dabc879e35123f738a2b6d2775f76cec514d757fc

Required complete prior bundle:
/Volumes/VinixDictionaryRestore20261027/append-path-guest
Prior manifest SHA-256:
2d908760488c94adff5eac4e7b72c34a9f25a396f934e3f0af2eef4ed8be42b0

IPA SHA-256:
47a17e723f8fae91595ac897d8f59cd3b453c43113a20bb1ff31ab656167332e
Executable SHA-256:
6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
```

The 80 MiB lossless archive reconstructs the complete bundle, including boot media,
original IPA, resources, generated C, binaries, sources and logs. The unchanged
`tests/ios/evidence-delta-archive.v` version 2 aligns matching large tar members
before making bounded 64 MiB patches. Restoration checks every chunk, complete
tar and exact original gzip, then file hashes, sizes, types and permissions,
including empty directories. Saved archiver source SHA-256:
`22544ffeb520fa9c7739b07ed7e0b2ba126ba3edf26d635f6079f9b1524d7d53`.
Archiver source revision: `481855ca546521f8fd9d58afda0dc2d05c446155`.

The archive packages decoder executables and three non-system libraries. macOS
system libraries and the complete prior bundle remain prerequisites. Archive
verification, fresh complete restoration, typed inventory comparison and the
unchanged saved checkpoint auditor pass. Validation logs are preserved at:

```text
/Users/alex/Library/Caches/vinix-ios/string-get-cstring-20261027.archive-validation
```

To restore, compile the archive's saved `archiver.v` with the frozen V compiler,
run `verify ARCHIVE`, then `restore ARCHIVE FRESH_TARGET FRESH_WORK`. Allow
external scratch space for both uncompressed initramfs archives and a complete
restored bundle. Historical audits contain absolute VM paths: expose the
restored tree at the original bundle path before running its saved
`string-get-cstring check ORIGINAL_PATH`. Keep the complete prior bundle and
its [durable archive and evidence chain](string-append-path-checkpoint-20261027.md).
Historical checkers remain unchanged.

The original IPA, application and 95 resource files (1,831,863,828 bytes) are
reused unchanged. Twenty-three prior fixture binaries and generated C files are
checked against the prior manifest; the new fixture, runtime and supervisor are
rebuilt. The resource overlay is not a complete installation. The prebuilt
kernel is inventoried, not rebuilt. Selected input hashes do not seal complete
compiler, header and library closures. Native macOS Foundation observations
are a proxy for the iOS target. Other string encodings remain unsupported.

To reproduce, compile `tests/ios/string-get-cstring.v` with the frozen V compiler
without `-prod`, then run `prepare OUT PRIOR`, `oracle OUT`, `fixture OUT`,
`build OUT`, `host OUT`, `regression-host OUT`, `probe OUT`,
`audit OUT FULL_REVISION`, `seal OUT`, `check OUT` and `selftest OUT`.
Build fixture and runtime sequentially. Set `VINIX_IOS_AUDIT_TMPDIR` to external
scratch storage with room for guest resource extraction. Exact commands and exit
statuses are preserved in the full bundle.
