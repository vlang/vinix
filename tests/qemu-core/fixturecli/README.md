The eight maintained syscall fixture comparisons and `compile-fixtures` invoke
V directly through this shared command layer. It retains host/prepare/native
modes, architecture defaults, compiler selection, guest defines, eager help,
option prefixes and mutually exclusive actions. Signal, touch and restart
retain the original helper-specific guest build; the other comparisons retain
their direct build. Argument errors exit 2 and build/OS failures exit 1 with
native diagnostics.

The existing `fixturehost` policies own immutable oracle provenance, staging,
generated headers, compilation, allocator-import guards and evidence receipts.
Recovered C remains outside the checkout. Normal generation stages only the
eight maintained V fixtures and does not recover the C oracle. The independent
fixture assertions and source ranges remain unchanged.

The base/memory generator and comparison and the futex comparison also use this
layer. Base generation defaults to ARM64 and retains `--module-only`; the base
host comparison uses the compiled host architecture and `--native-headers`.
Futex retains prepare/guest/native modes and derives its syscall number from the
selected target SDK. Its seven paired diagnostic rows must match exactly before
publishing the host verdict. These commands supersede the pending Python tools
and the last callers of `oracle_support.py`/`_fixture_native.py`.
The fixture bodies remain pending integration into the normal guest runner.
The six command/controller test files passed on ARM64, Rosetta x86-64 and
ASan/UBSan after this extension. Fresh base/memory and futex host comparisons
passed on both host ABIs and in a sanitized command process; both futex guest
targets linked. Oracle sources, declarations, source receipts and host logs
matched the saved independent controls, accounting only for the prior base
header-placement fix. All three cold entries passed help, protected-output and
cleanup checks; both standalone host commands passed. No new guest boot is
claimed for these pending fixture bodies.

Run `v -cc cc test tests/qemu-core/fixturecli tests/qemu-core/fixturehost`.
Set `VINIX_QEMU_FIXTURE_TOOL` to a prebuilt `test-intfixture` and
`VINIX_QEMU_FIXTURE_GENERATOR` to a prebuilt `compile-fixtures` to include command
checks for validation order and refusal to stage into the maintained checkout.

Qualification passed the five command/controller test files on ARM64, Rosetta
x86-64 and ASan/UBSan. All eight immutable-C/V host comparisons passed with
their sanitizer and allocator guards on both host architectures; all sixteen
paired guest binaries cross-built for AArch64/x86-64. Every fresh shell entry
passed help and temporary-directory cleanup checks, followed by a complete
standalone host comparison and normal generator run. No Python was run.
These checks cover host tools and target builds; they add no new guest-boot
result to the existing kernel regression evidence.
