# Local V Win64 calculator probe

The V source in [wine-calculator/program.v](wine-calculator/program.v) builds a
real AMD64 PE32+ program with standard USER32 display/button controls. Its
fixed 64-byte calculator handles digits, clear, four immediate arithmetic
operators, equals, chained operations and replacement after equals. Input is
bounded to 63 bytes plus a terminator; division by zero displays zero, matching
the existing calculator probe. Controls use USER32's default font.

The [retained host report](results/2026-10-23/wine-calculator-host.json) qualifies
host arithmetic and V ownership plus the real PE producer receipt. It does not
qualify window painting, pointer/keyboard input, Wine execution, GUI close,
publisher trust or a hermetic build. The existing real-PE receipt admission
checks observed sources, tools, literal commands, PE header and retained output
hashes. Its ordinary-file artifact inventory is retained separately in the
ignored build output; the tracked report binds its digest.

The host test file uses explicit panics, so checks remain active under `-prod`.
Normal, production and ASan/UBSan runs each pass four tests:

- Fifteen button sequences cover arithmetic, clear, chaining, repeated equals,
  negative results, fractional division and input replacement.
- One thousand digit presses preserve the input bound and terminator. All 240
  unsupported byte values leave the complete calculator state unchanged; clear
  resets the complete state.
- Largest/smallest normal finite doubles, exponent/fractional/zero output and
  overflow formatting preserve fixed-buffer bounds and termination.
- Ten thousand cycles, each with three arithmetic sequences and six formatting
  operations, retain zero tracked V bytes and records under `-gc none
  -manualfree`. This measures V allocation ownership; C runtime formatting and
  Windows resource usage have separate lifetimes.

A fourth production build changes addition into subtraction in its private
source copy. The explicit result check rejects that build. It demonstrates
that the production test command still enforces the arithmetic oracle.

The pinned V compiler promotes mutable test locals onto the heap, so tests
explicitly own and free their calculator fixtures. Generated PE C was also
inspected: `CalculatorWindow context`, the Win32 message/class records and
`output`'s written-byte scalar stay on the stack. The callback borrows the
window context only while the message loop is active; normal destruction clears
the userdata pointer, and every exceptional return detaches and destroys the
window before returning. The class is unregistered after window cleanup.
Button handling uses fixed arrays and borrowed text views, with no per-button
`memdup` or dynamic array construction in the generated application functions.
These are source/generated-C lifetime checks, not executed Win32 teardown proof.

From the repository root, using the qualification toolchain:

```sh
export VEXE="$PWD/build/package-https-runtime-work/toolchain/v"
export V_MACOS_V3_CALLER_VEXE="$VEXE"
export V_MACOS_V3_CALLER_VEXE_PRESENT=1
export V_MACOS_V3_CALLER_VCHILD_PRESENT=0
export V_MACOS_V3_NO_FALLBACK=1
export V_C_ERROR_BUG_REPORT_DISABLED=1
CALCULATOR_ROOT="$PWD/build/package-wine-calculator-worktree"
"$VEXE" -backend c -cc /opt/homebrew/opt/llvm/bin/clang -prod \
  -gc none -manualfree -o build/package-wine-calculator-producer \
  "$CALCULATOR_ROOT/tests/packages/wine-pe-check.v"
build/package-wine-calculator-producer "$VEXE" \
  /opt/homebrew/Cellar/mingw-w64/14.0.0_3 \
  "$CALCULATOR_ROOT/tests/packages/wine-calculator/program.v" \
  "$PWD/build/package-wine-calculator-pe-new" --local-qualification-only
"$VEXE" -backend c -cc /opt/homebrew/opt/llvm/bin/clang -prod \
  -gc none -manualfree -keepc -o build/package-wine-calculator-check \
  "$CALCULATOR_ROOT/tests/packages/wine-calculator-check.v"
build/package-wine-calculator-check "$VEXE" \
  /opt/homebrew/opt/llvm/bin/clang "$CALCULATOR_ROOT" \
  "$PWD/build/package-wine-calculator-host-new" \
  "$PWD/build/package-wine-calculator-pe-new" \
  "$CALCULATOR_ROOT/tests/packages/wine-pe-check.v"
```

Both output directories must be new. Keep the program source unchanged while
the producer runs. The host driver requires `-prod` for embedded source capture;
all its guards use explicit errors. It freezes host sources before compilation,
records literal compile/run argument vectors, generated C, executables and
logs, and compares complete selected source/compiler inventories before/after.
The PE admission child is freshly built from the frozen module sources and
never executes the PE. The full host receipt and `real-artifacts.json` remain
under `build/package-wine-calculator-host-2`; the real PE producer output is
`build/package-wine-calculator-pe-5` for the retained qualification.
