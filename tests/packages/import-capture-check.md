# Prepared-root source consistency

Prepared-root materialization now rechecks file/directory identity and executable
bits, plus each file's length, before publishing a package. Rechecks resolve
the source through the retained guest-root descriptor. Guest-absolute aliases
therefore retain their guest meaning, and replacing the host root pathname does
not redirect validation or copying.

Previously, an import could copy through an already-open file after its name had
been replaced, or traverse a replaced directory through later child lookups.
Length checks alone also allowed a same-size rewrite between admission and copy.
The importer now compares both the captured descriptor and a freshly resolved
source. It compares each directory's sorted names after copying its subtree.
Unpinned imports hash admitted files before copying and compare the materialized
bytes with that digest. Catalog imports instead retain their locked inventory
digest and executable/length admission.

Handled refusals remove private import staging before `pack` can create the
repository. After restoring stable inputs, retry produces the same canonical
manifest. These checks preserve the existing traversal/file/byte limits, link
resolution, stripped special modes and licensing metadata. Publishers must still
stabilize their prepared inputs: this is not an atomic filesystem snapshot.

## Assertions

The [core fixture](../../tools/packages/pkgcore/import_capture_test.v) checks:

- A captured root renamed and replaced by a host alias, with a guest-absolute
  directory alias inside it. Both the first import and retry use original bytes.
- 49 file mutations across open, sizing, hash blocks, end of hash, pre-copy,
  copy blocks and end of copy. Ordinary replacement, a guest alias, FIFO,
  disappearance, growth, truncation and changed executable bits all refuse.
  Every case retries under a 32-descriptor limit and checks descriptor counts,
  private-workspace cleanup, absent publisher output and unchanged target bytes.
- Multi-block same-size rewrites during hashing and copying, including a rewrite
  after hashing. Digest comparison rejects each changed materialization.
- Directory replacement before or during subtree copying, including ordinary
  directories, guest aliases, FIFOs and disappearance. Added, removed or renamed
  directory entries refuse too; stable retries preserve canonical bytes.
- Equivalent pinned/unpinned declarations, empty files, executable payloads with
  setuid stripped, changed pinned contents and exact retry.
- Injected failures at nine checkpoints, with descriptor/private-workspace
  cleanup, preserved source bytes and successful public retry.

The [host driver](import-capture-check.v) builds the real package CLI and runs
17 assertion suites, signed CLI maintenance and three ASan/UBSan suites. This
includes traversal bounds, direct packing, root/recipe admission, catalog plans,
composition, release and all five publisher profiles. Sanitizer leak detection
is disabled; complete import/packer heap retention is outside this check.

The [guest controller](import-capture-runtime-check.v) builds six assertion
programs: source consistency, traversal bounds, ordinary imports, direct packing,
catalogs and signed releases. It requires all six consistency markers, successful
exits from every program and guest-initiated poweroff. Baseline/panic/failure
output refuses the run. Each receipt pins nine artifacts: kernel, PID 1, the six
programs and raw serial output.

## Reproduction

```sh
v -o /tmp/import-capture-check tests/packages/import-capture-check.v
V=/path/to/reviewed/v /tmp/import-capture-check /build/new-import-capture-host

v -no-skip-unused -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/import-capture-runtime-check tests/packages/import-capture-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/import-capture-runtime-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-import-capture-arm
```

Repeat for `x86_64` with its matching kernel and a new state directory. The
controller requires an explicit QEMU TCG opt-in, kernel and fresh state path.
`--list` creates no guest. Cross-toolchain setup follows the
[hardware controller requirements](../hardware-platform/README.md).

## Qualification, 2026-10-16

All **43 host build/run checks passed**, including all three ASan/UBSan suites.
Four controller list/input/existing-directory guards passed. Both fresh guests
completed every required marker and guest-initiated QMP shutdown within the
180-second deadline: **AArch64 92.3 seconds**, **x86-64 47.8 seconds**.

- [Host receipt](results/2026-10-16/import-capture-host.json),
  [all checks](results/2026-10-16/import-capture-host.txt),
  [source consistency assertions](results/2026-10-16/import-capture-core.txt) and
  [signed CLI regression](results/2026-10-16/import-capture-cli.txt).
- [Source consistency sanitizer](results/2026-10-16/import-capture-asan.txt),
  [traversal sanitizer](results/2026-10-16/import-capture-limits-asan.txt) and
  [catalog sanitizer](results/2026-10-16/import-capture-catalog-asan.txt).
- [AArch64 receipt](results/2026-10-16/import-capture-aarch64.json),
  [serial](results/2026-10-16/import-capture-aarch64.serial.txt) and
  [QMP](results/2026-10-16/import-capture-aarch64.qmp.txt).
- [x86-64 receipt](results/2026-10-16/import-capture-x86_64.json),
  [serial](results/2026-10-16/import-capture-x86_64.serial.txt) and
  [QMP](results/2026-10-16/import-capture-x86_64.qmp.txt).
- [Source/toolchain/artifact ledger](results/2026-10-16/import-capture-toolchain.json)
  and [V evidence verifier](results/2026-10-16/import-capture-retain.v).

The verifier checks every guest artifact hash, all assertion/process markers,
guest shutdown and the unchanged kernel hashes from installed-root Software
qualification. This increment changes no kernel code. These publisher and
maintenance checks do not qualify additional applications, graphical runtimes,
physical-device crash behavior or a production release catalog. Those section
14 acceptance requirements remain open.
