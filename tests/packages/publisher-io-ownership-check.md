# Publisher filesystem scratch ownership

Publisher workspace admission, source/output containment, locking and durability
now retire their temporary storage in manual-free builds. Native stat records
remain on the stack for synchronous calls. Physical paths use independently
owned strings and explicitly release libc's resolution buffer. Relative output
paths preserve filesystem `alias/..` semantics during containment checks.

Lock admission uses a no-follow directory stat and releases the physical path,
private-directory path and lock-file path on every exit. Existing owner/mode,
private ordinary-file, single-link, descriptor/name identity and nonblocking
exclusion checks remain enforced before and after acquiring the lock. Durability
still verifies the captured descriptor and named entry before and after flushing,
including file size, and retries interrupted flushes.

Packing also builds its manifest path in one string expression, releasing the
previously discarded interpolation suffix. Public APIs and manifest/CLI bytes
are unchanged. The changes do not establish snapshot semantics for concurrent
owner edits, change retained object/partial recovery, or introduce a new package
transaction format.

The [helper fixture](../../tools/packages/pkgcore/publisher_io_ownership_test.v)
measures **17 cases × 128 calls = 2,176 calls** under
`-d track_heap -gc none -manualfree`. Cases cover source capture, workspace
admission, missing output ancestors, absolute/relative containment, `alias/..`,
workspace/flush aliases, writable workspace refusal, successful and busy locks,
hard-linked lock refusal, file/directory durability and failed flushing. Each
case requires zero retained bytes and allocations after its result or error is
retired. Source contents and absent output trees remain unchanged.

The [packing fixture](../../tools/packages/pkgcore/pack_ownership_test.v) now also
requires zero retained bytes and allocations across **80 complete calls** into
an existing workspace: 1/32-file success, refusal after locking, and a 32-file
late hash refusal, sixteen attempts each. Its **816 cold/cache source walks**
remain zero. Independent replies, literal declarations and production CLI JSON,
saved manifest/object recovery and exact retry remain covered.
The complete-call fixture initializes the repository, child directories, lock
and cached objects before measurement; first creation of these is excluded.

Before this change, the host helper probe retained 144 bytes for source capture,
4,384 for workspace admission, 1,824 for outside-source checking, 816 for contained
output refusal, 6,064 for locking, 5,776 for busy-lock refusal, 720 each for
file/directory durability and 432 for failed flushing. The preceding packing
qualification retained 12,896 bytes on success and 12,152 on refusal. The new
measured existing-workspace boundaries require zero for both bytes and allocations.

These measurements exclude fixture setup and first-time workspace construction.
They do not qualify complete `pack-root`, profile/catalog/release construction,
all service allocations, kernel heap behavior or media power-loss recovery.
The six section 14 acceptance gates, including production publisher/catalog
migration, graphical sessions and broader foreign runtime/device coverage,
remain open.

The [host controller](publisher-io-ownership-check.v) runs **59 build/test checks**:
production CLI, twenty functional suites, literal CLI maintenance, two tracked
fixtures, five clang ASan/UBSan suites and the tracked native-profile regression.
All five publisher profiles, signed catalog/composition/release maintenance,
captured copy/import, atomic metadata and interrupted durability remain covered.
Sanitizer leak detection is disabled; the separate heap tracker measures retained
V allocations.

The [guest controller](publisher-io-ownership-runtime-check.v) builds ten programs
for each target. It requires all 17 zero-retention helper markers, all five
zero-retention complete packing markers, twelve source-walk markers, every
process result, five fresh publisher workspace case processes and shutdown.
Its receipts pin the unchanged kernel, PID 1, ten assertion executables and raw
serial output. Packaged structural fixtures are not executed as applications.

```sh
v -o /tmp/publisher-io-check tests/packages/publisher-io-ownership-check.v
V=/path/to/reviewed/v /tmp/publisher-io-check /build/new-publisher-io-host

v -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/publisher-io-runtime tests/packages/publisher-io-ownership-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/publisher-io-runtime --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-publisher-io-arm
```

Repeat with `x86_64`, its kernel and a fresh state directory. Cross compilers,
sysroot and Limine follow the
[hardware controller requirements](../hardware-platform/README.md).

## Recorded results, 2026-10-17

All **59 host build/test checks passed**, including all five ASan/UBSan suites,
production pack/root JSON, signed CLI maintenance, every publisher profile and
the tracked native-profile regression. All **2,176 helper calls**, **80 complete
cached packing calls** and **816 cold/cache source walks** retained zero bytes
and allocations on the host and both targets after retiring results/errors.

Fresh QEMU TCG runs passed AArch64 (**104.8 seconds**) and x86_64 (**55.2 seconds**).
Each completed ten assertion programs, including five fresh workspace case
processes, and requested shutdown. No final host or guest qualification attempt
failed. The unchanged kernels are identified in the artifact receipts.

The native profile's separate whole-build probe now retains **165,933 bytes /
648 allocations**, down from the preceding **246,276 bytes / 883 allocations**.
Its metadata owner still retains zero. This improvement does not close complete
profile construction ownership or the broader section 14 acceptance gates.

- [Helper baseline](results/2026-10-17/publisher-io-ownership-baseline.txt) and
  [original fixture](results/2026-10-17/publisher-io-ownership-baseline.v).
- [Host receipt](results/2026-10-17/publisher-io-ownership-host.json),
  [check summary](results/2026-10-17/publisher-io-ownership-host.txt),
  [functional checks](results/2026-10-17/publisher-io-ownership-core.txt),
  [helper memory](results/2026-10-17/publisher-io-ownership-memory.txt),
  [packing memory](results/2026-10-17/publisher-io-ownership-pack.txt),
  [helper sanitizer](results/2026-10-17/publisher-io-ownership-asan.txt),
  [literal CLI](results/2026-10-17/publisher-io-ownership-cli.txt) and
  [native regression](results/2026-10-17/publisher-io-ownership-native.txt).
- AArch64 [receipt](results/2026-10-17/publisher-io-ownership-aarch64.json),
  [report](results/2026-10-17/publisher-io-ownership-aarch64.txt),
  [serial](results/2026-10-17/publisher-io-ownership-aarch64.serial.txt) and
  [QMP](results/2026-10-17/publisher-io-ownership-aarch64.qmp.txt).
- x86_64 [receipt](results/2026-10-17/publisher-io-ownership-x86_64.json),
  [report](results/2026-10-17/publisher-io-ownership-x86_64.txt),
  [serial](results/2026-10-17/publisher-io-ownership-x86_64.serial.txt) and
  [QMP](results/2026-10-17/publisher-io-ownership-x86_64.qmp.txt).
- [Source/compiler/artifact ledger](results/2026-10-17/publisher-io-ownership-toolchain.json)
  and [V retention/verifier](results/2026-10-17/publisher-io-ownership-retain.v).
  Run the verifier with `--verify` from this repository to check retained local
  hashes. Rebuild the baseline at commit `55bc8a5c0` with the retained original
  fixture copied into `tools/packages/pkgcore` and flags
  `-d track_heap -d publisher_io_baseline -gc none -manualfree`.
  Whitespace checks recognize raw serial CR with `core.whitespace=cr-at-eol`.
