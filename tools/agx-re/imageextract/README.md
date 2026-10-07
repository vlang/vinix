The maintained image-extraction implementation is native V. `core.v` handles
DER/IM4P/IMG4 framing, firmware tables, Mach-O metadata, fileset discovery and
standalone-file rebasing; `compression.v` owns libcompression scratch buffers;
`cli.v` preserves the existing extraction commands and manifest schemas.

The three Python modules retain import compatibility for recovery tools. Their
algorithms call `extractionabi` through `_native_extract.py`; the bridge borrows
inputs synchronously, copies independent libc-owned outputs, and releases each
output exactly once. Foreign calls register their stack with Boehm for the call.
If the library first loads off the main thread, one daemon loader keeps its
initial collector stack alive for the process. The library cache fingerprints
the compiler, compiler source changes and all native implementation sources.

Run `make -C tools/agx-re test` from the repository, or use the V compiler selected
by `build-support/find-v.sh` to run `v -cc clang test tools/agx-re/imageextract`.
Twenty native tests preserve all thirteen original extraction checks and add
unsigned DER lengths, virtual-address overflow, truncation, ownership-related
input boundaries, strict UTF-8 diagnostics and CLI path behavior. Remaining
Python recovery tests exercise the native import bridge; the small
`test_extract_firmware.der` import helper delegates fixture encoding to V.

The October 2026 migration also compared canonical Python controls with native
ARM64 and Rosetta x86-64 builds: 5,419 API cases and 107 CLI cases per architecture,
including binary hashes and parsed manifests, plus all thirteen original tests.
Repeated successful and malformed calls, foreign threads, constructor failures,
cross-thread releases and borrowed-input mutation retained zero libc outputs.
After collection, retained native heap bytes stayed bounded over eight batches.
A standalone Clang ASan/UBSan fixture exercised 10,000 ABI iterations. Those
machine-local controls and source-bound receipts are under
`~/.cache/vinix-python-to-v/agx-extract-20261008/`; they contain no maintained
implementation or private firmware copied into this repository.
