# Native independent policy guests

These commands compile and invoke V directly:

```sh
tests/alloc-track/run-native --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR
tests/alloc-track/run-guest --arch aarch64|x86_64 --kernel-dir DIR --state-dir DIR
tests/kernel-print/run-native --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR [--prod]
tests/stack-protector/run-diagnostic --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR [--c-reference FILE]
tests/krandom/run-hooks --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR [--c-reference FILE]
tests/krandom/compile-hooks --arch aarch64|x86_64 OUTPUT COMPILER [FLAGS...]
tests/hypervisor/run-abi
```

The five guest commands accept `--timeout SECONDS` (default 600) and the added
`--build-only` mode. The live tracker retains support for an existing state
directory; independent policy builds require fresh directories. Sources,
generated objects and receipt hashes remain available after failure. The
console's production flag, original C reference options, complete printf ABI
assembly, strict warning flags and borrowed native cursors remain.

The native compiler APIs replace the retired console/diagnostic helpers and
random-hook producer. Console preparation binds the current panic-terminal
hook to the existing independent recorder. Diagnostic staging is retired on
success or failure; both architecture profiles and forced compiler failures
pass the private-owner check in `check-diagnostic-api.v`. The random compiler
retains caller flags, uses distinct
core/ABI objects, and produces one relocatable object for the existing V host
test launcher. Extensionless and hidden output names in dotted directories
retain their original stem rules.

All seven command binaries and their CLI checks pass on fresh ARM, Rosetta x86
and ARM ASan/UBSan hosts. The actual public hypervisor ABI oracle and native
hook compiler also pass on those profiles. Sixteen static guest builds cover
both architectures, both console modes, live and independent tracker fixtures,
and V/original C diagnostic and hook controls. ELF machine IDs, receipt hashes
and every captured input hash are independently checked. Seven cold fronts
pass outside the checkout, along with invalid arguments and state preservation.
The existing random/rekey, SHA-256 and erasure host test files all pass through
the native compiler. No Python was run.

Fourteen real QEMU guest cases pass on prepared ARM and x86 kernels: independent
tracker, debug/production console, and V/original C diagnostic/hook fixtures.
The live tracker is cross-built; its in-kernel allocation-site coverage still
requires an `ALLOC_TRACK=1` kernel. These runs establish fixture integration
without new production kernel builds, kernel retention measurements or VMX
execution. The maintained builder can be repeated with
`build-support/run-v-tool.sh tests/native-guest-tools/check-policy-builds.v`.

Qualification uses the isolated V 0.5.2 `c6bb06f` compiler documented by the
[policy host tools](../native-policy-tools/README.md). Local logs, frozen
originals and manifests are under `/tmp/vinix-policy-guest-qualification-*`;
guest logs are `/tmp/vinix-policy-guest-real-*.log`. Maintained commands do not
depend on those directories.
