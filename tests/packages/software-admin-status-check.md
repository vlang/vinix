# Software administrator startup status

`SoftwareApp.start` publishes its generic worker-start status before beginning
administrator approval. The password guidance, or the refusal explaining that
nonblocking password input could not be protected, therefore remains visible.
The reviewed request and administrator worker lifecycle are unchanged.

The maintained `software_fixture.v` adds an `admin-status` selector. Explicit
checks remain active with `-prod`: a real worker starts through `start`, keeps
the exact password guidance, and is cancelled. A separate real child has its
owned stdin descriptor closed and set to `-1`; the actual `begin_admin_prompt`
refusal must retain its diagnostic, clear prompt/credential state, retire the
worker, and leave `waitpid(..., WNOHANG)` reporting `ECHILD`. This exercises the
refusal directly; it does not force an fd failure inside `start`. No production
fault-injection hooks were added. The shared fixture also declares the existing
heap counter used by the staged audit fixture.

The source baseline is `090202f8e2da1f281b77c012b01fa9e9292da61a`.
The isolated host evidence is retained at:

```
/Users/alex/Library/Caches/vinix-codex/section14/software-admin-status-20261026
```

Validation uses the actual app sources and fixture assembly listed by
`distribution-check.v`, with `software_fixture.v` as `main.v`. The copied UI
overlay comes from `build/package-view-reader-work/desktop/modules/ui2`; its
native macOS/Windows control branches already carry the maintained
`!ui2_headless` guards. Original and qualified UI inputs, logs, source manifests,
generated C and binaries remain in the external bundle. Some C and binary
evidence is gzip-compressed after byte-for-byte decompression checks; adjacent
receipts preserve the original SHA256. Restore executable mode after unpacking
a binary.

The compiler is the complete private toolchain at
`build/package-https-runtime-work/toolchain/v` (V 0.5.2 `fd996fc`), SHA256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`.
Builds use clang, `-backend c -nocache -no-skip-unused -gc none -manualfree
-enable-globals -d ui2_headless`, `-O1`, the desktop include path and the existing
`-Wno-error=incompatible-pointer-types` compatibility flag. The exact commands
are retained externally. `V`, `VEXE` and `V_MACOS_V3_CALLER_VEXE` select that
compiler; fallback is disabled and `VFLAGS` is empty.

Initial failures are preserved: the default `build/vmodules/ui2` overlay failed
native control compilation (exit 1); two shared `/Users/alex/code/v/v` attempts
ended with compiler signal 11 (exit 139, cause undiagnosed). The first tracked
assembly failed because the existing audit fixture's heap-count declaration
was absent (exit 1); the declaration was added beside the shared begin/end
declarations before final validation. Earlier successful checks and their
inputs are retained separately.

Final validation uses the same source set, including the heap declaration:

| Build | Checks | Observed exits |
| --- | --- | --- |
| Normal | Compile, `admin-status`, existing Software regression | 0, 0, 0 |
| `-prod` | Compile, `admin-status` | 0, 0 |
| `-d track_heap` | Compile, `admin-status`, `admin-memory` | 0, 0, 0 |
| ASan/UBSan | Compile, `admin-status` | 0, 0 |
| Baseline ordering, normal | Compile, `admin-status` | 0, 1 (expected) |
| Baseline ordering, `-prod` | Compile, `admin-status` | 0, 1 (expected) |

All 14 build/run outcomes match expectation. Both controls replace only the
assembled `software_app.v` with the baseline source and fail with
`administrator guidance was overwritten after worker startup`. The four fixed
`admin-status` runs emit the exact PASS marker. The existing normal regression
completes. Tracked `admin-memory` reports zero retained tracked bytes for each
of its 1,000 prompt/edit/render/wipe and clipboard credential cycles; this is
the existing focused measurement, not whole-process leak qualification.
ASan/UBSan emits no diagnostics with `detect_leaks=0:abort_on_error=1` and
`halt_on_error=1`; no leak-sanitizer result is claimed.

`evidence/final-commands.json` and `final-exit-codes.json` record commands and
outcomes. `final-inputs-before.json` and `final-inputs-after.json` are identical:
SHA256 `9908130255e082a3326678c277a50244ba70c03378d0c623f8f9ad649b16055d`.
Output and source verification logs are retained beside them. The manifest
pins the isolated project/staged/UI `.v` inputs, heap header, UI `v.mod` and
compiler executables across the final checks.

The combined namespace includes the worktree, both UI copies, earlier/failed
attempts and scratch. Its largest observed size was 82,048 KiB during the
sanitizer build, within the explicitly authorized temporary 110 MiB cap;
lossless compression reduced it to an observed 66,224 KiB, below the normal
80 MiB cap. These are discrete measurements, not continuous peak monitoring
or a filesystem quota. Space checks remained above the required 1 GiB floor.
The audit artifact checksum manifest is `EVIDENCE-SHA256SUMS` (1,012 files),
SHA256 `cc9f15a44a4d6675224a6d76c0ed44d6e1095d7b563263a0b2e9cc245cecf06c`.
It covers the retained logs, inputs, compressed build evidence and their
receipts; temporary helper scratch, worktree Git metadata and this report are
excluded. `OWNED-SHA256SUMS` separately records the final three owned files
and the reviewed source diff.

This qualification is host headless Software validation. It does not execute
target guests, administrator authentication, guest graphics or the complete
roadmap section 14 release gate. Project/UI source and compiler executable
hashes are checked; imported compiler sources, third-party code, system headers
and linker inputs are not frozen, so the run is not hermetic or reproducible.
