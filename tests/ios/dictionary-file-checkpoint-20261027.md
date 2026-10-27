# NSDictionary file loading checkpoint — 2026-10-27

Runtime, fixture and auditor source: `9b85b59c187353aaab355ee786cc1ca74a36ceeb`.
Advertising remains skipped.

`NSDictionary` and `NSMutableDictionary dictionaryWithContentsOfFile:` now
load XML and binary property lists. Native Foundation observations cover
values, Unicode, empty, malformed and missing files, container mutability
and method metadata. The runtime fixture also checks direct IMP calls,
eight workers, retained results after pool drainage and two lifetimes ending
with zero live runtime objects. Both host sanitizer runs pass. All 23 guest
fixtures exit successfully.

Fortnite 42.30.1 advances past dictionary loading with the original cooked
content and stops at:

```text
V panic: iOS: unimplemented Objective-C method NSString stringByAppendingPathComponent:
```

Three images load, nine Objective-C `+load` calls and three initializer groups
complete, and application entry is reached. The intentional fault captures
all 31 ARM64 registers and restores execution. A tagged 24 GiB virtual
reservation succeeds. The UIKit window protocol and enforced 2 GiB game
memory budget pass, with positive available memory and zero final OOM
counters. The guest has 8 GiB RAM and an 1800-second startup limit.

The game exits with status 1; capture completes with status 0. The desktop
peer reports a broken pipe, 13 tree builds, 12 polls and no supervisor kill.
Final budget usage is 191,984 KiB. The first tree has one node, zero images
and 336 bytes; the peer has no compositor or input device. **No rendered game
frame is verified.** Progress remains **4/8 observable gates**: load/bind,
`+load`, initialization and entry. Frame, menu, login and playable match
remain unverified. This fraction does not estimate remaining effort or time.

The auditor rebuilt from committed source passes seal, check and selftest.
Its negative controls reject 47 guest-log mutations, 16 host-log mutations,
unsafe IPA entries, malformed manifests and missing, changed or extra
resources. The check extracts guest resources and binaries and compares
them with the saved inputs, including memory and desktop configuration.

Evidence identities:

```text
Original complete bundle:
/Volumes/VMacosCacheCI20261027/vinix-dictionary-file-20261027
VM state: probe-no-ads-97041
Manifest SHA-256:
5bf46da4df932605e70ab94aa31dd8dd6bc0110f061757dbe5a7a0030916cfaa

Persistent lossless archive:
/Users/alex/Library/Caches/vinix-ios/dictionary-file-20261027.archive
archive.sha256 SHA-256:
28b7873fe8cf98dfd439dd7386794897e7848d40a71bd01e7c3d2a72fb4a06db

Required complete prior bundle:
/Users/alex/Library/Caches/vinix-ios/bundle-identifier-20261027
Prior manifest SHA-256:
18277021e0468ad5d6a914cb66e96026235ca166d7695d6adf2533202bd1c085

IPA SHA-256:
47a17e723f8fae91595ac897d8f59cd3b453c43113a20bb1ff31ab656167332e
Executable SHA-256:
6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
```

The 371 MiB archive reconstructs the complete approximately 7.8 GiB bundle,
including boot media, original IPA, resources, generated C, binaries, sources
and logs. `tests/ios/evidence-delta-archive.v` records every file's hash, size,
type and permissions, including empty directories and root permissions. It
uses unchanged prior files, literal compression, a boot-image patch and
64 MiB patches of the uncompressed initramfs. Reconstruction checks every
chunk and complete file, then reconstructs the exact original gzip bytes.
Decoder executables and their three non-system libraries are packaged;
macOS system libraries and the complete prior bundle remain prerequisites.

Archive verification and a fresh complete restoration pass. The restored
typed inventory matches exactly, and the unchanged original dictionary-file
auditor passes against that restored bundle at its original absolute path.
The archiver selftest exercises all four storage modes, multiple chunks,
exact gzip reconstruction, modes and empty directories, and rejects 22
negative controls. Validation logs are preserved at:

```text
/Users/alex/Library/Caches/vinix-ios/dictionary-file-20261027.archive-validation
```

To restore, compile the archive's saved `archiver.v` with the frozen V
compiler, run `verify ARCHIVE`, then `restore ARCHIVE FRESH_TARGET FRESH_WORK`.
Allow sufficient external scratch space for both uncompressed initramfs
archives and a complete restored bundle. Historical audit records contain
absolute VM paths: expose the restored tree at the original bundle path
before running its saved `dictionary-file check ORIGINAL_PATH`. Keep the
prior bundle and its [earlier evidence chain](bundle-identifier-checkpoint-20261027.md).
Historical checkers remain unchanged. Failed whole-file compression trials
and their logs are retained externally; no complete prior bundle was removed.

The original IPA, application and 95 resource files (1,831,863,828 bytes) are
reused unchanged. Twenty-two prior fixture binaries and generated C files
are checked against the prior manifest; the new dictionary fixture, runtime
and supervisor are rebuilt. The resource overlay is not a complete
installation. The prebuilt kernel is inventoried, not rebuilt. Selected input
hashes do not seal complete compiler, header and library closures. Native
macOS Foundation observations are a proxy for the iOS target.

Property-list parsing is bounded to 16 MiB input, 32 MiB expanded contents,
65,536 objects and depth 64, and rejects cycles. Dates and OpenStep plists
remain unsupported. Native observations require mutable nested arrays in
both formats, immutable binary dictionary containers, and mutable nonempty
XML dictionary containers when loading through `NSDictionary`; loading
through `NSMutableDictionary` makes all containers mutable.

To reproduce the checkpoint, compile `tests/ios/dictionary-file.v` with the
frozen V compiler without `-prod`, then run `prepare OUT PRIOR`, `oracle OUT`,
`fixture OUT`, `build OUT`, `host OUT`, `probe OUT`, `audit OUT FULL_REVISION`,
`seal OUT`, `check OUT` and `selftest OUT`. Build fixture and runtime
sequentially. Set `VINIX_IOS_AUDIT_TMPDIR` to external scratch storage with
enough room for guest resource extraction. Exact commands and exit statuses
are preserved in the full bundle.
