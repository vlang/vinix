# Software Metal compiled-library metadata — 2026-11-12

`753403882` connects the existing metallib reader to the opt-in software
device's `newLibraryWithData:error:`. Libraries own immutable input bytes and
the parsed index, retain their device, enumerate copied function names and
create owned named function handles. Handles retain their library and expose
name, device and vertex/fragment/kernel types 1/2/3. Existing object cleanup
frees index arrays before input storage and releases ordinary object fields.

Live leaf or concatenated dispatch data is accepted. Size is capped at 256 MiB
before mapping; the copied container receives the reader's range/name/hash
checks. Other function kinds reject. Failures return nil with optional
autoreleased NSError (unsupported 1, internal allocation failure 2, malformed
container 3); success leaves the caller's error slot untouched. Metal.framework
also supplies the library error-domain global. See
[the supported API and limits](../../compat/ios/runner/METAL.md).

ASan/UBSan macOS ARM64 checks pass with normal and deterministic Swift hashing:
raw/wrapped bitcode ranges, independent/shared module containers, dispatch
leaf/rope ABI, input release before metadata use, copied names and Unicode,
function/library/device lifetimes, empty libraries, missing/nil/wrong-type
names, every truncated prefix of the single-function fixture, corrupt magic,
hash/range failures, unsupported function kind, optional NSError and stable
domain import. A valid shared dispatch-data rope represents 512 MiB using
30 nodes and is rejected before flattening. Eight concurrent enumeration
workers and two drained runtimes pass, as do all seven prior software groups.
The ordinary runner is also rebuilt: nil device, scoped imports, eight workers
and invalid cache-device checks pass. Its native macOS baseline creates/releases
a real Metal device and checks the device protocol; no GPU work is submitted.

Qualified bundles are outside Git under `/Users/alex/Library/Caches/vinix-ios/`:

- `metal-library-validation-20261112-r3/` — all eight software groups.
- `metal-library-default-20261112-r3/` — ordinary runner/native device baseline.

Both archives were decoded and extracted into sibling directories with
`-restored` appended. Saved source/compiler/header/executable identities match;
both restored sanitizer executables pass, and archive checksums pass afterward.
Receipts remain beside the bundles. r1 is a compiler-rejected test draft; r2
passes before adding the error-domain import check. r3 is the qualified revision.
The maintained harness retains its documented compiler-preamble corrections.
Toolchain library symlinks, host dylibs and SDKs remain external prerequisites;
dependency closures are not sealed. This is not a full typed-inventory audit.
Leak detection is disabled; object drainage is checked, retained heap is not
measured. Fixtures contain synthetic containers and minimal bitcode signatures,
not executable shaders. No native library comparison, AIR verification, shader,
pipeline, rendering, presentation, guest or iOS app is validated here. No new
Fortnite frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Software `.tar.zst` | `ee641d558002b316b3de12abc29f83d1c5dd5e010de8226dfef89cb547539d18` |
| Default `.tar.zst` | `a8edf1cd550b96dbec86ffb0db4aa7d28f8336c69a799d6b190139742da725dc` |
| `source.tar`, revision `753403882`, in both bundles | `1f5a1de1484db32e0c1feed4eb1a892183b92e49814d437af0d3bb2d569a663e` |
