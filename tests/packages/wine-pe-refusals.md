# Win64 producer refusal controls

`wine-pe-refusals.v` runs the actual `wine-pe-check.v` producer against private
V-written compiler stand-ins. It accepts one synthetic AMD64 PE32+ console
header, then requires twelve malformed PE outputs to fail without `proof.json`.
It also compiles private production and non-production producer copies: a source
change after compilation and the non-production binary must both refuse before
creating their requested output directory. Checks use explicit errors and remain
enabled in production builds. The live producer is never edited.

From the repository root, with an existing output parent and a V compiler with
its adjacent `vlib` and `thirdparty` directories:

```sh
V=/absolute/path/to/v
env VEXE="$V" V_MACOS_V3_CALLER_VEXE_PRESENT=1 \
  V_MACOS_V3_CALLER_VEXE="$V" V_MACOS_V3_CALLER_VCHILD_PRESENT=0 \
  V_MACOS_V3_NO_FALLBACK=1 V_C_ERROR_BUG_REPORT_DISABLED=1 \
  "$V" -backend c -keepc -gc none -manualfree -prod \
  -o build/wine-pe-refusals tests/packages/wine-pe-refusals.v
build/wine-pe-refusals "$V" build/wine-pe-refusal-results
```

The runner requires a new output directory. `controls.json` records all fifteen
outcomes, producer/driver/executable/compiler hashes, and the limited scope.
Private sources, generated C, compile logs, each executed argument vector,
stdout/stderr, and the synthetic accepted producer receipt remain beside it.
Both source and compiler hashes are checked again before the report is written.

On 2026-10-23, the production runner passed the synthetic baseline and all
fourteen refusals against producer SHA-256
`1a9a55f2c8ffd677085354dba06a3bac05900e5a6d6baf9398afae6cc0d1f113`,
including its post-capture embedded-source guard. The retained local report is
`build/package-wine-pe-refusals-final3/controls.json`; its sibling files hold the
exact build and invocation commands. This run used V executable SHA-256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`.

These controls test producer admission and refusal behavior. Synthetic compiler
output is not evidence of real Win64 compilation, toolchain reproducibility,
Wine execution, or redistribution permission. The separate real MinGW producer
receipt covers the real compilation step.
