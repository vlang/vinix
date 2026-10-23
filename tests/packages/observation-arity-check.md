# Read-only package CLI operand admission

`vinix-package view`, `updates`, `status`, `list` and `verify` accept no
operands. `info` requires exactly one package ID. Invalid operand counts return
exit status 1 before configuration, catalog or installed-state reads, with
`COMMAND takes no arguments` or `info requires one package ID` after the usual
`vinix-package:` prefix. Global option parsing and its errors still come first.

This matters for callers that accidentally pass an ID to `verify`: the command
does not support verification scoped to that ID. A valid `verify` continues to
inspect the complete installed closure. The change also prevents a missing or
corrupt configuration from obscuring an `info` operand error. Search still
accepts multiple literal words as its query, and the existing read-only command
responses and service authority are unchanged.

The V-only [observation-arity-check.v](observation-arity-check.v) driver builds
the actual normal and production package CLIs from a private source copy. Each
CLI runs 75 refusal cases: one and two unwanted operands on the five commands,
missing and extra `info` operands, text and JSON output options, and
`--progress verify` with an unwanted ID. Every case runs against a missing,
corrupt and valid installation root and must produce the exact early arity
diagnostic. Another 21 valid-arity controls per CLI check existing configuration
errors, empty installed state, the fresh-image enrollment view, one-ID lookup
and multiword search. The entire fixture tree is checked after every result;
the missing root stays absent and no package store is initialized in the valid
root.

Run from the repository root with a new output directory:

```
env V_MACOS_V3_NO_FALLBACK=1 V_C_ERROR_BUG_REPORT_DISABLED=1 \
  V_MACOS_V3_CALLER_VEXE_PRESENT=1 V_MACOS_V3_CALLER_VCHILD_PRESENT=0 \
  V_MACOS_V3_CALLER_VEXE="$PWD/build/package-https-runtime-work/toolchain/v" \
  VEXE="$PWD/build/package-https-runtime-work/toolchain/v" \
  build/package-https-runtime-work/toolchain/v -backend c -keepc -gc none \
  -manualfree -prod -path "@vlib|@vmodules|$PWD" \
  -o build/observation-arity-check tests/packages/observation-arity-check.v
build/observation-arity-check \
  "$PWD/build/package-https-runtime-work/toolchain/v" \
  "$PWD/build/observation-arity-qualified"
```

The driver requires `-prod` to bind its embedded source; all checks use explicit
errors and remain enabled in production. It inventories selected project
sources before copying/building and verifies the original inventory, copied
bytes and V/host clang executables again afterward. It retains literal arguments,
build logs, generated C, CLIs, all replies and artifact hashes. `-backend c`
selects the target-compatible backend and `-keepc` retains its generated C.
The CLI builds explicitly select the installed Homebrew clang executable. The
checks run on the host; they do not qualify target execution, package
mutation, publisher trust or the complete SDK. Imported vlib/thirdparty, host C
headers, linker and transitive toolchain inputs are not frozen, so this is not a hermetic
or reproducible-build qualification.

The retained result is
[cli-observation-arity.json](results/2026-10-23/cli-observation-arity.json).
