# Native emulator input builders

Four native commands replace **19,437 original Python bytes / 404 lines**:

```sh
build-support/n64-homebrew/build --output build/n64/homebrew
build-support/ps2-homebrew/build --output build/ps2/homebrew
build-support/ps1/build --output build/ps1 --jobs 4
build-support/ps1/download-homebrew --output build/ps1/homebrew
```

The three build scripts invoke these commands directly. PS1's complete core,
homebrew and frontend build path no longer invokes Python. N64 and PS2 core
builders now have [native commands](core-builders.md) too. Emulator guest and
desktop controllers remain pending; no credit is assigned to those Python files.

The homebrew builders retain the original LLVM search order, startup assembly,
strict compiler flags and actual MIPS ABI models. V emits architecture-neutral
C using the original `x86` model through the native module-producer API; LLVM
enforces N64 MIPS-III/o32 big-endian, PS2 IOP MIPS-I/o32 and EE MIPS-III/n32
little-endian. The IOP load image and generated header, N64 header and CIC-6102
checksum, PS2 OSABI `0x56` and copied licenses retain their original bytes.
Malformed ELF segment tables and out-of-region/truncated segments are rejected.

PS1 retains the pinned upstream source and Tetrade URLs/hashes/size limits,
interpreter/CHD configuration, all disabled asynchronous workers, compiler and
libc cache inputs, original make option order and bundled license notices.
The cache stamp uses the original sorted JSON, spaces and Unicode escaping;
literal tool paths use the original shell quoting. Existing output directories
and caches are reused. Failed builds retain their merged partial log and do
not publish a success stamp.

V owns the downloader's private temporary, streamed size/digest verification
and atomic rename. It invokes curl for HTTP/TLS, redirects, the original user
agent and connection/stall limits. curl must support streamed `--max-filesize`
(qualification uses 8.7.1). A corrupt cache is rejected and kept intact.
Source extraction uses the native tar reader, strips one archive root and
retains regular-file bytes and executable modes. Absolute/traversal/backslash
paths, links, rootless files and members above 32 MiB are rejected. Unicode
path bytes, including decomposed names, are retained.

Compiler, make and download commands share the native private-process-group
owner. Interrupts return 130, reap children and retire owned scratch. The module
producer's additive capture callback preserves its default API while allowing
the caller to clean up its own V scratch after compiler interruption. Long
build output streams directly to disk through `fixturehost.logged_owned`;
the parent working directory and closed standard descriptors remain separate.

## Qualification (2026-10-11)

- Four public commands and the boundary checker build on ARM, Rosetta x86 and
  ASan/UBSan; all actual LLVM MIPS homebrew builds pass on all three profiles.
- N64 startup/program objects, both ELFs and the complete cartridge match
  independently reconstructed original recipes byte for byte on all profiles.
  PS2 startup/program objects, both ELFs and the complete IOP header match too.
- Fresh actual PCSX-ReARMed cross-build and cache reuse pass on all profiles.
  The unchanged PS1 script builds and stages the native frontend successfully.
  The independent original make recipe produces a byte-identical complete
  archive when both builds inherit the same `SOURCE_DATE_EPOCH`; upstream
  `frontend/main.c` otherwise embeds the different compile time. The original
  bundled license notices match byte for byte.
- Actual fresh Tetrade release and license downloads pass all four hashes;
  cached verification passes on each controller profile.
- The checker preserves original JSON stamps and shell quoting, binary logs
  above pipe capacity, nonzero exit and partial interruption logs. It covers
  all 27 open/closed/cloexec standard descriptor layouts with exact log bytes,
  both-endian BSS/holes, malformed ELF bounds, original CIC checksum, archive
  path/type/size guards, 256 file owners and decomposed Unicode names.
- Local chunked HTTP success, size overflow, bad status and digest failures
  preserve caches and retire temporary files. Actual LLVM, V producer, make
  and curl interruption paths reap children and retire default scratch.
- The existing module metadata/path suite passes. No Python was executed.
- Four cold shell entrypoints pass from outside the checkout.

Instrumentation covers host controllers, not MIPS guests or the upstream core.
macOS ASan leak detection is disabled. These checks establish no new kernel,
guest gameplay, physical console or commercial-game result. No kernel was
rebuilt. Receipts, frozen original Python bytes, independent V recipes and
`emulator-*.log` are under `~/.cache/vinix-python-zero-process-20261011/`.
