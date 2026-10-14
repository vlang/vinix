# Captured package source traversal

`pack` captures its root with the shared prepared-root admission before creating
repository output. Empty/NUL paths, invalid roots and a leaf directory alias
refuse, including aliases with trailing separators. Parent aliases retain
ordinary path semantics. Renaming the admitted root cannot redirect traversal
to a replacement namespace.

Every child opens read-only relative to its captured parent, with no-follow,
nonblocking and close-on-exec flags. Directory enumeration is sorted and
bounded. Special files and symlinks refuse. Each regular descriptor supplies
length, executable mode, hash and copied bytes; parent-relative identity, length
and executable mode are rechecked around hashing, copying and existing-object
reuse. Copied object bytes must also match their captured hash. The shared
bounded hash reader retains its sentinel, interrupted-read handling and size
checks; the ordinary pathname API retains its final named-identity check.

Limits are 128 descendant directory levels, 32,768 visited entries including
empty directories, 16,384 entries per directory, 16,384 regular files, 4 GiB per
file and 64 GiB total payload.
File and cumulative lengths are admitted before reading each file. These limits
bound source work beyond the manifest's regular-file count. Stable ordinary
inputs retain exact metadata, including traversal order, executable bits, empty
files and duplicate/shared read-only payloads.

Publishers must control output parents, serialize writers, stabilize source
contents and keep output outside the source. Captured descriptors do not freeze
same-user in-place writes or authenticate upstream contents. A refused walk
does not replace the package manifest; object copies already completed and
partial `.new` files may remain for inspection/retry. Existing manifests remain
available. This is a publisher-input boundary, not a new transactional publisher
workspace or a catalog/runtime release qualification.

The [public probe](pack-source-check.v) forks each unsafe `pack` call under a
three-second alarm. Seven root forms check early refusal/output absence; tree
symlinks, FIFOs and 129 nested directories check refusal before manifest
publication. Ordinary/slashed roots must produce identical manifests with
sorted payloads, empty files, executable bits and a shared read-only inode.
`--before` requires the baseline's alias/slashes acceptance, NUL output creation
and excessive-depth acceptance.

The [core assertions](../../tools/packages/pkgcore/pack_source_test.v) replace
roots and captured child directories and mutate regular files at open, size,
hash-block, post-read, post-hash, post-copy and cache-reuse checkpoints. Aliases,
FIFOs, new/missing inodes, growth, shrinkage and executable-mode changes must
refuse without reading external content or replacing a manifest. Correcting
the input permits ordinary retry. A same-size rewrite between hash and copy
fails digest verification. Entry/file/byte budgets test exact and overflow
boundaries; 64 successful/failed walk cycles use a 32-descriptor limit. This
does not claim heap retention.

The [distribution driver](distribution-check.v) discovers the assertions and
runs the public probe. A focused [guest controller](pack-source-runtime-check.v)
builds both programs and a small init on either target. Its 300-second functional
deadline requires both checks, the combined source marker and clean guest shutdown.
Receipts pin kernel, init, both executables and serial output. No network,
desktop, release credentials or application runtime are needed.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/pack-source-core tools/packages/pkgcore/pack_source_test.v
/tmp/pack-source-core
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/pack-source-check tests/packages/pack-source-check.v
/tmp/pack-source-check /tmp/new-pack-source-qualification
V=/path/to/v v -path '@vlib|@vmodules|.|tests/hardware-platform' \
  run tests/packages/pack-source-runtime-check.v --arch aarch64 \
  --kernel /build/aarch64/kernel --state-dir /tmp/pack-source-arm
```

Use a new directory and the corresponding kernel for each architecture. The
usual [hardware controller options/toolchains](../hardware-platform/README.md)
apply. Broader roadmap 14 release gates remain open.

## Recorded results, 2026-10-14

Eight regression runners passed: source traversal, hashing, local copying, copy
outputs, root import, catalog assembly, distribution and release. Source
traversal, hashing and local copying passed clang ASan/UBSan with leak detection
disabled and undefined behavior fatal. The signed CLI lifecycle, new source
probe and existing prepared-root/copy-output probes passed. The maintained
distribution driver compiled. The ledger records 32 successful compile/run
results.

The baseline accepts a root alias with trailing slashes and 129 descendant
directories, and creates output for a NUL-suffixed root. The final probe refuses
all ten unsafe root/tree cases; all seven root failures precede output-parent
creation. Stable ordinary/slashed manifests match the baseline bytes. Core
checks cover root capture, two directory replacements, 49 file-stage mutations,
same-size content change detection, retry, work/byte budgets and descriptor
retirement.

Focused QEMU TCG guests completed and shut down cleanly: AArch64 reported 96.3
seconds and x86_64 177.4 seconds in a 300-second diagnostic run.
Both assertion executables were rebuilt from current sources against retained
committed kernels. Each receipt pins five artifacts/logs. These focused checks
do not qualify the full runtime workflow, graphical login, release enrollment
or the advertised catalog migration.

Evidence:

The initial x86_64 attempt and an identical-input fresh retry reached public
probe completion but timed out at 121.6 and 120.7 seconds while the core runner
was pending. A third fresh machine reused the identical four built boot inputs
and completed under a 300-second diagnostic allowance. Both failed attempts
remain in the serial/QMP/report evidence and attempt ledger. The original
120-second x86_64 budget remains unqualified; AArch64 passed its initial
120-second run. This new fixture now uses a 300-second functional deadline,
calibrated to the full mutation/retry matrix. No full Linux runtime or existing
performance deadline was changed.

- [before](results/2026-10-14/pack-source-before.txt)
- [after](results/2026-10-14/pack-source-after.txt)
- [host checks](results/2026-10-14/pack-source-host.txt)
- [individual results](results/2026-10-14/pack-source-host.json)
- [signed CLI](results/2026-10-14/pack-source-cli.txt)
- [sanitizers](results/2026-10-14/pack-source-asan.txt)
- [AArch64 receipt](results/2026-10-14/pack-source-aarch64.json)
- [AArch64 serial](results/2026-10-14/pack-source-aarch64.serial.txt)
- [AArch64 QMP](results/2026-10-14/pack-source-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/pack-source-x86_64.json)
- [x86_64 serial](results/2026-10-14/pack-source-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/pack-source-x86_64.qmp.txt)
- [compiler/source/artifact ledger](results/2026-10-14/pack-source-toolchain.json)
- [x86_64 attempts](results/2026-10-14/pack-source-x86_64-attempts.json)
- [x86_64 first report](results/2026-10-14/pack-source-x86_64-first.txt)
- [x86_64 first serial](results/2026-10-14/pack-source-x86_64-first.serial.txt)
- [x86_64 first QMP](results/2026-10-14/pack-source-x86_64-first.qmp.txt)
- [x86_64 retry report](results/2026-10-14/pack-source-x86_64-retry.txt)
- [x86_64 retry serial](results/2026-10-14/pack-source-x86_64-retry.serial.txt)
- [x86_64 retry QMP](results/2026-10-14/pack-source-x86_64-retry.qmp.txt)
