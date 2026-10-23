# Local PE receipt admission

`wineadapter.admit_local_pe_proof(directory, program_source, producer_source)`
validates a local `wine-pe-check.v` producer receipt before its PE can become a
Wine qualification input. This is local artifact provenance, not publisher
authentication, redistribution permission, PE instruction validation, or a Wine
execution result.

The admission reads bounded metadata through an open directory, verifies the
canonical format-1 schema, exact producer environment and three literal build
commands, complete compiler/MinGW input inventories, unchanged before/after
inputs, copied source bytes, and all fourteen ordinary output files. It checks
the AMD64 PE32+ console header on the same executable bytes used for its digest.
Canonical input paths, disjoint toolchain roots, and input/output separation are
mandatory. Compiler-tree links may resolve only within their own tree. Output
links, extra receipt input/output rows, changed files and malformed or resealed
metadata refuse admission. Other files in the producer's working directory are
outside the declared fourteen-output set.

The returned `LocalPeProof` owns its executable string and artifact map. Read
both fields before `close()`. Closing twice is safe; reading either field after
close is invalid. Callers retain the returned hashes alongside their own native
receipt. File descriptor and final directory identity checks detect changes
during capture; this is a local stable-input contract, not a hermetic build or a
guarantee against every adversarial concurrent filesystem mutation.

The focused host check uses synthetic, never-executed PE files. Normal,
production, and ASan/UBSan builds each run 1,000 complete successful admissions
and double closes with zero retained tracked V bytes and file descriptors.
The descriptor check counts `/dev/fd` entries and first verifies that it detects
a live descriptor above a deliberately freed descriptor slot.
Every truncated JSON prefix, malformed Unicode, and schema, input, output,
command, canonical-path, NUL, alias, overlapping-root and PE-header refusal is
also measured. A production build with the literal command comparison disabled
must fail the fully resealed command control. All checks use explicit errors or
panic conditions, since the pinned V compiler removes `assert` under `-prod`.

The optional real producer check admits the existing receipt once and retains
all returned artifact pins. It never executes that PE. See the retained
[host result](results/2026-10-23/wine-pe-admission-host.json) for exact sources,
compiler, backend, generated C, binaries, argv, logs and full inventory hashes.
The driver captures every V source in `wineadapter`, `pkgprotocol`, and `appsdk`,
the heap tracker, and the complete compiler `vlib` and `thirdparty` trees before
and after qualification. It verifies copied source hashes before compiling;
only the copied test's header path and the declared disabled-guard negative
control are transformed. Host OS headers and libraries are outside this
inventory, so the report does not claim a hermetic host toolchain.

Run from the repository containing these files. `OUT` must not exist:

```sh
VINIX_ROOT="$PWD"
VINIX_V="$VINIX_ROOT/build/package-https-runtime-work/toolchain/v"
VINIX_CC=/opt/homebrew/opt/llvm/bin/clang
OUT="$VINIX_ROOT/build/wine-pe-admission-host-new"
export VEXE="$VINIX_V" V_MACOS_V3_CALLER_VEXE="$VINIX_V"
export V_MACOS_V3_CALLER_VEXE_PRESENT=1 V_MACOS_V3_CALLER_VCHILD_PRESENT=0
export V_MACOS_V3_NO_FALLBACK=1 V_C_ERROR_BUG_REPORT_DISABLED=1
"$VINIX_V" -backend c -cc "$VINIX_CC" -prod -gc none -manualfree \
  -path "$VINIX_ROOT|@vlib|@vmodules" \
  -o "$VINIX_ROOT/build/wine-pe-admission-check" \
  tests/packages/wine-pe-admission-check.v
"$VINIX_ROOT/build/wine-pe-admission-check" \
  "$VINIX_V" "$VINIX_CC" "$VINIX_ROOT" "$OUT"
```

To include a real local producer receipt, append its directory, the exact
program source, and the exact `wine-pe-check.v` source to the final command.
`proof.json` contains the complete inventory; `summary.json` is the compact
retained report. The driver itself requires `-prod` for embedded source capture
and explicitly checks that its source still matches its compiled bytes.
