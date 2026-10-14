# Prepared publisher root admission

`pack-root`, `pack-catalog` and the Native, SQLite and FFmpeg profile builders
share one source-root capture. Empty/NUL paths fail before any open. Trailing
separators are stripped while preserving `/`, so they cannot make `O_NOFOLLOW`
follow a leaf directory symlink. The root opens read-only with directory,
nonblocking, no-follow and close-on-exec flags; `fstat` requires a directory.
Callers retain the descriptor through import and close it on every exit.

Root admission precedes destination-parent creation, disk checks and private
staging. Failed admission leaves publisher output absent and source files
untouched. Ordinary directories with redundant separators still work and
produce identical canonical package/catalog metadata. Parent aliases keep
ordinary path semantics. Descriptor capture binds the original namespace when
a pathname is later replaced; publishers must still stabilize the root's
contents. It does not authenticate upstream inputs or freeze concurrent writes.
Existing source pins, inventory/ELF checks and signing/publishing rules retain
their separate roles.

The [public probe](prepared-root-check.v) tests seven path forms through each of
`pack_root` and `pack_catalog`: NUL suffix, leaf alias with/without trailing
slashes, empty, missing, ordinary file and FIFO. Forked three-second alarms make
blocking regressions fail promptly. The baseline accepts four unsafe imports
(NUL and alias/slashes in each API) and creates catalog output parents for all
seven cases, even when the root is rejected later. The fixed code must refuse
all fourteen before creating those parents. Ordinary/slashed imports must still
produce identical metadata. `--before` requires the previous implementation.

The [core assertions](../../tools/packages/pkgcore/prepared_root_test.v) cover
all five publisher entry points, preserved source contents/modes, descriptor
flags, `/` and redundant root separators, and continued access to an original
namespace after its pathname becomes an alias to another root. Guest absolute
links still resolve inside that original root. Sixty-four success/refusal cycles
run under a 32-descriptor limit; these checks do not claim heap retention.

The [distribution driver](distribution-check.v) discovers the core assertions
and runs the public probe. A focused [guest controller](prepared-root-runtime-check.v)
builds both assertion executables and a small init, then requires the public
probe's completion, the combined admission/capture marker and clean shutdown.
This checks the publisher-input boundary on both architectures without extending
the full Linux runtime workflow's timing or graphical/catalog release claims.
Receipts pin the kernel, guest init, public probe, core assertions and serial log.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/prepared-root-core tools/packages/pkgcore/prepared_root_test.v
/tmp/prepared-root-core
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/prepared-root-check tests/packages/prepared-root-check.v
/tmp/prepared-root-check /tmp/new-prepared-root-qualification
V=/path/to/v v -path '@vlib|@vmodules|.|tests/hardware-platform' \
  run tests/packages/prepared-root-runtime-check.v --arch aarch64 \
  --kernel /build/aarch64/kernel --state-dir /tmp/prepared-root-arm
```

Use a new state directory and repeat with `--arch x86_64` and its kernel. The
usual [hardware controller options/toolchains](../hardware-platform/README.md)
apply. The scenario has a 120-second functional deadline. It needs no network,
desktop, application runtime, release key or account database.

## Recorded results, 2026-10-14

Ten publisher regression runners passed: root admission, import, catalog,
composition, Native/SQLite/FFmpeg profiles, profile inventories, release and
publisher schema. Root admission, import, catalog and the Native profile passed
clang ASan/UBSan with leak detection disabled and undefined behavior fatal.
The maintained distribution driver compiled; the signed CLI lifecycle and
public root probe passed. The ledger records 34 successful compile/run results.

The baseline accepts four unsafe imports and creates catalog parents even for
rejected roots. The final probe refuses all fourteen cases before output-parent
creation. Ordinary/slashed package manifests and catalog locks match the baseline
bytes. All five entry points also pass early-refusal checks without source/mode
changes.

Both focused QEMU TCG guests passed and shut down cleanly: AArch64 reported 28.4
seconds; x86_64 reported 51.9 seconds, within their unchanged 120-second deadlines.
Each receipt pins five artifacts/logs, with both assertion programs rebuilt from
current sources against retained committed kernels. These focused runs qualify
publisher input admission and descriptor behavior. They do not rerun or extend
the full Linux runtime workflow, its timing budget, broader catalog migration
or graphical login/runtime qualification.

Evidence:

- [before](results/2026-10-14/prepared-root-before.txt)
- [after](results/2026-10-14/prepared-root-after.txt)
- [host checks](results/2026-10-14/prepared-root-host.txt)
- [individual results](results/2026-10-14/prepared-root-host.json)
- [signed CLI](results/2026-10-14/prepared-root-cli.txt)
- [sanitizers](results/2026-10-14/prepared-root-asan.txt)
- [AArch64 receipt](results/2026-10-14/prepared-root-aarch64.json)
- [AArch64 serial](results/2026-10-14/prepared-root-aarch64.serial.txt)
- [AArch64 QMP](results/2026-10-14/prepared-root-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/prepared-root-x86_64.json)
- [x86_64 serial](results/2026-10-14/prepared-root-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/prepared-root-x86_64.qmp.txt)
- [compiler/source/artifact ledger](results/2026-10-14/prepared-root-toolchain.json)
