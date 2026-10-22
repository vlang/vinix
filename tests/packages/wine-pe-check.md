# Real Win64 probe producer

`wine-pe-check.v` builds the actual Windows API probe in
`wine-native/program.v`, retaining its V source, generated C, AMD64 PE32+
executable, linker map, PE inspection, literal commands and logs. It uses V's
Windows C backend followed by MinGW GCC with the Unicode console entry point.
The resulting executable must have an executable, non-DLL AMD64 PE32+ console
header. These are explicit error checks and remain enabled in production builds.

```console
$ VEXE="$V" V_MACOS_V3_NO_FALLBACK=1 V_C_ERROR_BUG_REPORT_DISABLED=1 \
    "$V" -backend c -prod -gc none -manualfree \
    -o build/wine-pe-check tests/packages/wine-pe-check.v
$ build/wine-pe-check "$V" /absolute/mingw-install \
    "$PWD/tests/packages/wine-native/program.v" \
    "$PWD/build/new-win64-probe" --local-qualification-only
```

Use a new output directory with an existing parent. `MINGW_ROOT` must contain
`bin/x86_64-w64-mingw32-gcc` and `bin/x86_64-w64-mingw32-objdump`. The V executable
must have its complete `vlib` and `thirdparty` directories beside it. The tool
resolves the output parent before rejecting outputs inside an input tree.

The producer requires a production build whose embedded source matches its
current source file. Before building, it inventories and hashes the compiler, original
program source, producer source and executable, full V library/third-party trees,
and complete supplied MinGW installation. Tree entries include directories and
literal symlink targets; links outside their inventoried root and unsupported
file types refuse. The source is copied into the private output directory.
The producer source is retained beside the program source. Compilation uses a
recorded environment with private home, temporary and module
directories, no ambient compiler flags, and V fallback disabled. The PE linker
timestamp is fixed. After compilation, the complete input inventories must match,
and the retained source must match the original source digest.

`proof.json` records these inputs and hashes all declared outputs, including
before/after inventories, commands, logs and the executable. Failed builds retain
diagnostics but never write a success proof. Existing outputs and missing local
qualification acknowledgement refuse before inventory or compilation.

This is a local producer receipt. Host system libraries, operating-system tools
and all transitive compiler behavior are outside its inventory; it does not claim
a hermetic build, source redistribution closure, Wine execution, or graphical
application qualification. A native Wine check must consume this exact
`program.exe` and retain its own signed-package and execution evidence.

On 2026-10-23, the production producer built a 446,745-byte executable with
the pinned V compiler and MinGW installation, with complete before/after input
equality. The local receipt is
`build/package-wine-pe-qualified-final-3/proof.json`. Independent
[production refusal controls](wine-pe-refusals.md) passed a synthetic-header
baseline and fourteen malformed-output, stale-source and build-mode refusals.
The synthetic controls qualify validation; the separate real receipt qualifies
the compilation step.
