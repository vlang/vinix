# NSString path-appending checkpoint — 2026-10-27

Runtime, fixture and auditor source: `ebba251a59a282993f74c854749020f379e72189`.
Advertising remains skipped.

`NSString` and `NSMutableString stringByAppendingPathComponent:` now append
components using observed Foundation separator handling. Repeated slashes
collapse, trailing slashes disappear except at the root, and dot components,
tilde, backslash and Unicode remain literal. Embedded NUL returns nil. The
implementation bounds the combined input and separator to 16 MiB.

The native oracle passes 912 input pairs, 36 long inputs and method signatures
on both classes. The shared native/runtime fixture covers separators, roots, dots,
Unicode, NUL, long inputs, metadata, direct IMP calls, mutation, eight workers
and pool-drain ownership. The runtime ends two lifetimes with zero live objects.
Both host ASan/UBSan runs pass, and all 23 guest fixtures exit successfully.

Fortnite 42.30.1 advances past path appending with the original cooked content
and stops at:

```text
V panic: iOS: unimplemented Objective-C method NSString getCString:maxLength:encoding:
```

Three images load, nine Objective-C `+load` calls and three initializer groups
complete, and application entry is reached. The intentional fault captures all
31 ARM64 registers and restores execution. A tagged 24 GiB virtual reservation,
the UIKit window protocol and the enforced 2 GiB game memory budget pass. The
guest has 8 GiB RAM and an 1800-second startup limit.

The game exits 1; capture completes with status 0. The desktop peer reports a
broken pipe, 17 tree builds, 16 polls and no supervisor kill. Final budget usage
is 191,984 KiB with zero OOM counters. The first tree has one node, zero images
and 336 bytes; the peer has no compositor or input device. **No rendered game
frame is verified.** Progress remains **4/8 observable gates**: load/bind, `+load`,
initialization and entry. Frame, menu, login and playable match remain
unverified. This fraction does not estimate remaining effort or time.

The auditor rebuilt from committed source passes seal, check and selftest.
Its negative controls reject 47 guest-log mutations, 16 host-log mutations,
unsafe IPA entries, malformed manifests and changed, missing or extra resources.
It extracts guest resources and binaries and compares them with the saved
inputs, including memory and desktop configuration.

Evidence identities:

```text
Original complete bundle:
/Volumes/VinixDictionaryRestore20261027/append-path-guest
VM state: probe-no-ads-383000
Manifest SHA-256:
2d908760488c94adff5eac4e7b72c34a9f25a396f934e3f0af2eef4ed8be42b0

Persistent lossless archive:
/Users/alex/Library/Caches/vinix-ios/string-append-path-20261027.archive
archive.sha256 SHA-256:
cdc6337205a91f9ba8712514ead36d2fa1fa292e425b419c6d02e95647f02f2c

Required complete prior bundle:
/Volumes/VMacosCacheCI20261027/vinix-dictionary-file-20261027
Prior manifest SHA-256:
5bf46da4df932605e70ab94aa31dd8dd6bc0110f061757dbe5a7a0030916cfaa

IPA SHA-256:
47a17e723f8fae91595ac897d8f59cd3b453c43113a20bb1ff31ab656167332e
Executable SHA-256:
6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
```

The 57 MiB lossless archive reconstructs the complete bundle, including boot
media, original IPA, resources, generated C, binaries, sources and logs.
`tests/ios/evidence-delta-archive.v` version 2 aligns matching large tar members
before making bounded 64 MiB patches. This preserves shared resource data when
headers shift or members move; the first fixed-offset attempt occupied 1.6 GiB.
Unsupported tar layouts fall back to fixed offsets. Restoration checks every
chunk, complete tar and exact original gzip, then file hashes, sizes, types and
permissions, including empty directories. The saved archiver source SHA-256 is
`22544ffeb520fa9c7739b07ed7e0b2ba126ba3edf26d635f6079f9b1524d7d53`.
Archiver source revision: `481855ca546521f8fd9d58afda0dc2d05c446155`.

The archiver selftest passes all four storage modes, exact gzip reconstruction,
typed inventories, version 1 restoration and 22 original negative controls. It
also restores reordered GNU long-name members with shared incompressible data
spanning multiple chunks, bounds their combined payload below 1 MiB, and rejects
three corrupt reference offsets. The archive packages decoder executables and
three non-system libraries. macOS system libraries and the complete prior bundle
remain prerequisites. Archive verification, fresh complete restoration, typed
inventory comparison and the unchanged saved checkpoint auditor pass. Validation
logs are preserved at:

```text
/Users/alex/Library/Caches/vinix-ios/string-append-path-20261027.archive-validation
```

To restore, compile the archive's saved `archiver.v` with the frozen V compiler,
run `verify ARCHIVE`, then `restore ARCHIVE FRESH_TARGET FRESH_WORK`. Allow
external scratch space for both uncompressed initramfs archives and a complete
restored bundle. Historical audits contain absolute VM paths: expose the
restored tree at the original bundle path before running its saved
`string-append-path check ORIGINAL_PATH`. Keep the complete prior bundle and
its [durable archive and evidence chain](dictionary-file-checkpoint-20261027.md).
Historical checkers remain unchanged.

The original IPA, application and 95 resource files (1,831,863,828 bytes) are
reused unchanged. Twenty-two prior fixture binaries and generated C files are
checked against the prior manifest; the updated string-path fixture, runtime
and supervisor are rebuilt. The resource overlay is not a complete installation.
The prebuilt kernel is inventoried, not rebuilt. Selected input hashes do not
seal complete compiler, header and library closures. Native macOS Foundation
observations are a proxy for the iOS target.

To reproduce, compile `tests/ios/string-append-path.v` with the frozen V compiler
without `-prod`, then run `prepare OUT PRIOR`, `oracle OUT`, `fixture OUT`,
`build OUT`, `host OUT`, `probe OUT`, `audit OUT FULL_REVISION`, `seal OUT`,
`check OUT` and `selftest OUT`. Build fixture and runtime sequentially. Set
`VINIX_IOS_AUDIT_TMPDIR` to external scratch storage with room for guest resource
extraction. Exact commands and exit statuses are preserved in the full bundle.
