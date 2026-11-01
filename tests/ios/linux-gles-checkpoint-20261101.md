# Linux GLES and Mach-O initializer checkpoint — 2026-11-01

**The ARM64 iOS runtime renders and publishes verified GLES pixels on Linux.**
The maintained GNU/Linux graphics fixture passed ordinary and deterministic
ASan/UBSan runs using Mesa softpipe under QEMU. The corrected initializer
fixture also passed both runs, including actual constructor-before-entry
execution. Implementation, local archive restoration and audits are complete.
The complete archive's external upload is pending explicit approval.

**Fortnite remains at the historical 4/8 launch gates.** No fresh Fortnite
probe, frame, menu, login or gameplay is established. The original application,
bundled frameworks, cooked content and complete guest inputs are unavailable
in this workspace. Ads remain skipped. The rendered triangle is a synthetic
runtime regression fixture and does not advance a Fortnite launch gate.

## Published source

The changes continue draft [PR #271](https://github.com/vlang/vinix/pull/271).
They were committed with explicit owned paths after diff review, with
`.githooks` enabled and the maintained outgoing-source policy passing.
Generated evidence remains outside Git. No Python was used.

| Commit | Change |
| --- | --- |
| `32d0371df00e0b00062c9b5bacbe80a745e314c4` | GLES runtime corrections, method metadata and ARM64 rendering fixture |
| `0f6bd7635f13c53157c0b201397c9c1e3db71916` | Maintained Linux GLES/initializer modes, SDK validation and usage |
| `4329882248c23ea1157fb3c9ac6e66b9a727ebfb` | Header-relative Mach-O initializer offsets and execution regression |

Implementation tree: `002ebab8cd6540f289f3ca2cf2f9bca980ac9c34`.
Prior checkpoint: `38877bd457f540a4d3d130d3739ac21290007e82`.
Each published tree exactly matches its reviewed local commit; local originals
remain under `refs/vinix-backups/ios-linux-gles-code-local-20261101`.

## Runtime corrections

### GLES on GNU/Linux

The EAGL/GLKView bridge now exposes its implemented selectors and Objective-C
argument encodings. Inherited EAGL class methods dispatch through subclasses.
GLK format setters read their 32-bit enum argument, and the Boolean setter
reads its low byte, so unused ARM64 register bits cannot corrupt valid calls.
The fixture exercises actual ARM64 `objc_msgSend`, scalar/object signatures,
inherited methods, unsupported queries and poisoned upper argument bits.

The private Vinix DRI directory is selected only when it exists and the
environment variable is unset. Explicit settings, including an empty value,
remain preserved. The Linux qualification selects a GNU ARM64 Mesa SDK,
surfaceless EGL and softpipe; it does not require an Apple SDK, graphical
display, Vinix kernel or game bundle.

The fixture checks compiled shaders, triangle pixels, exported VSF1 XRGB
surface bytes and orientation, four resized/scaled drawables, depth/stencil
attachments, framebuffer/PBO/packing-state restoration, reader-held-buffer
publication dropping, drawable recreation and context replacement. It also
checks weak delegates, per-thread current contexts, last-reference TLS
destruction before join, and two zero-live-object runtime shutdowns.

Across the two runs, 28 draw callbacks produced 24 published frames; four
final PPM artifacts are retained. The PNG preview preserves the exact 60×48
RGB image: all 8,640 channel bytes were checked after PNG reload.
Its SHA-256 is
`6df5b6a07e34866e38e596efbdc582f4fca90e3db27bec1b7c8624a89ea6f5c0`.

Requested API2 contexts are qualified with pbuffer pixels. ES2 GLKView
publication is not qualified. The CGRect initializer is checked through raw
metadata and actual HFA dispatch; aggregate `NSMethodSignature` and
`NSInvocation` values remain unsupported.

### Mach-O constructors

`S_INIT_FUNC_OFFSETS` entries now resolve from the mapped Mach-O header,
which can follow a lower-addressed segment in the reservation. The loader
rejects missing mapped headers, addition overflow and misaligned offset
tables, preserving its existing file-backed, executable-target and aggregate
count checks. This matches the header-relative arithmetic in Apple's
[dyld Loader](https://github.com/apple-oss-distributions/dyld/blob/main/dyld/Loader.cpp)
and validation in
[MachOAnalyzer](https://github.com/apple-oss-distributions/dyld/blob/main/common/MachOAnalyzer.cpp).
The inspected source blob IDs were `a69b28be111c9855762d439610116ab23e55e649`
and `bdf7f5ee11cccb61a7b083a2894d2e1b41ea483c`, respectively.

The historical 176,816-entry case, old/new count boundaries and aggregate
limit remain intact. New V-generated ARM64 Mach-O images cover ordinary,
lower-readonly and lower-executable layouts, each across two lifetimes.
Entry returns 37 only if the correct constructor increments a sentinel once.
The executable lower segment contains a decoy that writes a failure value.

`LoadedModule.code_address` now borrows its record. Generated C confirms that
the validation calls no longer pass the 672-byte record by value. The prior
generated code copied approximately 2.08 GiB of record data over the valid
large-table cases. This is an identified record-copy correction,
not a measured timing speedup: these captures are not a controlled benchmark.

## Execution results

Toolchain: frozen V 0.5.2 at
`c6bb06f5c04d78f9f6d22a57c257d27e835ba40a`, GNU ARM64 GCC
13.2.0-23ubuntu4, QEMU 8.2.2, and Mesa 24.0.5-1ubuntu1. Execution used a
Linux x86-64 host and real ARM64 ABI assembly under user emulation.
The actual renderer reported **softpipe**, **OpenGL ES 3.1**, vendor **Mesa**.
The private SDK was extracted from recorded Ubuntu packages; system packages
were not installed or changed.

| Check | Result |
| --- | --- |
| GLES, ordinary ASan/UBSan | PASS, 46.992985984 seconds; all five distinct markers |
| GLES, deterministic hashing ASan/UBSan | PASS, 50.785546768 seconds; all five distinct markers |
| Initializers, ordinary ASan/UBSan | PASS, 437.693573119 seconds; both markers and six image executions |
| Initializers, deterministic hashing ASan/UBSan | PASS, 532.303828044 seconds; both markers and six image executions |
| GLES-enabled runner | PASS, help/inspect exit 0; entry exit 37; extra-argument exit 99 |
| GLES profile unit cases | 4 passed, including architecture/path/alias, input changes, environment and marker controls |
| Existing Linux inventory/qualification unit cases | 5 passed |
| GLES-enabled and disabled V source generation | Both passed; the disabled fixture cannot satisfy GLES markers |
| Maintained inventory auditor controls | 1 valid control accepted; all 19 corruption controls rejected |
| Additional complete-tree comparator controls | Equal/streaming/copy cases passed; byte, mode, path, link, type and special-file corruption rejected |

Every runtime guard reports a reaped child, complete cleanup and zero residual
descendants. The 600-second deadlines, V assertions, C `-O1`, ASan/UBSan and
full fixture selection were retained. GCC's recorded low-memory setting was
enabled. LeakSanitizer is disabled. Packaged Mesa libraries are not themselves
sanitizer-instrumented; the standalone runner smoke build is unsanitized.

The driver clears inherited Mesa version, shader and rasterization overrides,
uses a private GLVND vendor JSON, keeps target libraries out of host compiler
processes, and pins selected SDK files and aliases before and after execution.
The GLES capture deliberately inherited invalid version/no-raster controls;
the selected execution environment removed them and verified actual pixels.
The manifest is selected-input coverage, not a complete dynamic-library trace
or a claim of hermetic execution.

## Source provenance and rejected attempts

Captures identify the earlier Git base and preserve their full tested source
copies, driver, working diff, generated C, commands and receipts. A separate
provenance check matched 619 GLES inputs and 618 runner inputs, with exactly
one later production difference in each: the borrowed loader receiver.
The initializer capture matches all 620 production/selected-fixture inputs.
The host driver's two new files received formatting changes after its r4
binary build; the recorded driver hash identifies the exact executable used.

`gles-r1` is preserved as a source-generation failure. `initializers-r1`
printed its markers but then failed ASan because the new fixture separately
freed a string already owned by its argument array. The final fixture gives
the array sole ownership. Neither rejected attempt was resealed as a pass.
The earlier cookie policy and method-spelling assertions remain intact;
no new native Foundation comparison or cookie-jar implementation is claimed.

## Complete evidence and restoration

Main archive:
`/workspace/scratch/6384ba2a563f/vinix-ios-linux-gles-evidence-20261101.tar.zst`

- Size: **515,117,768 bytes**.
- SHA-256: `cbc90afa0f531dd8547463430019b7f1670e8db92e56ae418e942c11d9dba461`.
- Contains the complete quiescent `ios-linux-gles-20261101` tree without
  filtering, including failed attempts, expanded Mesa, acquired packages,
  caches, generated artifacts and nested frozen compiler/SDK inputs.

The full archive was freshly restored. The controlled complete-tree comparator
matched **8,272 regular files, 346 directories, 104 symbolic links and
2,693,785,291 logical file bytes**, checking exact paths, bytes, types, modes,
empty directories and link targets. Ownership, timestamps, xattrs and
hard-link-inode identity are outside that comparison.
The unchanged maintained typed comparator separately passed the entire
`captures` subtree, including both failures. The unchanged inventory auditor
passed all three accepted captures before and after restoration:

| Capture | Files / directories | Recorded bytes | Inventory SHA-256 |
| --- | ---: | ---: | --- |
| `gles-r2` | 1420 / 25 | 178615736 | `376138e1c2a4d4961d6d14fd4d086d03ab79a0aec3c33dfffe0a60ca94a74430` |
| `initializers-r2` | 1413 / 24 | 177420015 | `f896248777d5eb5c79026955a974ac57cb6a8a22c03ab995b6a33f7f3220bc4a` |
| `runner-gles-r1` | 1427 / 25 | 72686509 | `917d0ac55706085c7129cf125721c8808ebb0081e8b835844677d23a97cb4f06` |

Nested archives from that restoration were fully extracted and compared with
the selected originals: frozen V (15,250 files), GNU SDK/QEMU (1,949 files,
162 links), bootstrap (37 files), and Mesa (719 files, 104 links). All passed.
No historical auditor was weakened or changed.

Final command arguments, logs, statuses and timings are retained separately at
`/workspace/scratch/6384ba2a563f/vinix-ios-linux-gles-audit-20261101` and its
companion `.tar.gz` bundle. The pre-archive execution record is inside the
main archive; final restoration/publication receipts are in the audit bundle.

**Storage qualification:** automatic approval review rejected the attempted
bulk upload because it contains source, toolchains, SDKs, binaries, logs and
captures without explicit approval for that destination. No archive bytes
were transferred and no workaround was used. The full archive remains local;
a durable external copy still requires approval. Its complete payload and
destination must be approved before upload. The small PNG preview was saved
separately. Prior archive-backed expanded copies were reclaimed only after
their recorded hashes and restoration/audit receipts were checked; the prior
full archive remains retained.

## Remaining work

Usage is maintained in [linux-host.md](linux-host.md), including the new
`gles`, `image-initializers` and `build-run-ios-gles` modes. Native ARM64
hardware, native Apple Foundation and a full Vinix VM boot remain unqualified.
The GLES runner still omits optional C++, video, text and SQLite backends.
`MTLCreateSystemDefaultDevice` still returns nil; Metal command buffers and
AIR shaders are not implemented by this GLES work. A fresh full-game probe
requires the original game input set and an appropriately complete runtime.
