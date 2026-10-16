# Bounded prepared-root recipe decoding

`decode_root_recipe` now uses the bounded stored-metadata primitives after its
existing schema scan. Its result owns the manifest and selector buffers; callers
retain the existing `close_decoded_root_recipe` contract. Partial records and
complete records rejected by selector validation retire their storage.

The warmed pre-change probe retained **10 bytes over ten one-selector reads**,
**30,160 bytes over ten 16-selector reads**, and **7,030 bytes over ten truncated
recipe refusals**, after retiring returned values/errors. Borrowed validation of
the 16-selector recipe alone retained **22,500 bytes over ten calls**. The same
four probes retain zero after bounded decoding and allocation-free overlap
comparison. Baseline sources, executables, generated C and output are pinned.

An intermediate reader still allocated its field-name arrays when fixed literals
were converted to the member reader's dynamic-array parameter. Its probe retained
4,670 and 28,370 bytes for the positive inputs. Shared constant key arrays remove
that allocation; the final probes and expanded tracked fixture require zero.
No compiler, allocator or standard-library change is involved.

The omitted recipe format remains 1. Nested package, dependency and payload
omissions retain the source-template defaults, including SDK 1, zero window
protocol, false booleans and empty fields/collections. `manifest` and `entries`
remain required, as do both selector fields. Full unsigned payload integers are
preserved. Complete package validation remains in the publisher.

Admission limits are 8 MiB, 1,024 selectors, 1,024 bytes per source/destination
and the existing nested manifest field/count bounds. Unknown and escaped duplicate
keys, null/type errors, invalid UTF-8/Unicode escapes, noncanonical/overflowing
numbers, incomplete JSON and trailing data refuse. Bounds apply during decoding,
before source-root access or workspace creation. Bounded-reader diagnostics
replace generic decoder errors; selector semantic diagnostics remain unchanged.

Equal destinations and parent/child paths refuse in either order. Similar names
such as `a/b` and `a/bc` remain distinct, including Unicode paths. Comparisons use
the slash boundary directly and borrow caller fields; no path prefix is allocated.
Catalog imports share this validator, while their pinned-lock decoder is unchanged.

The fixture covers both metadata architectures with one and 64 selectors over
1,000 tracked read/retire cycles, independently owned results, retired input and
exact canonical reproduction. The full 1,024-selector boundary also requires zero
retained bytes. Default inputs, every truncated prefix and 24 refusal categories
retire their storage; all refusal categories run 1,000 tracked cycles. Borrowed
overlap checks run 1,000 times per equal/parent/child/component/Unicode case.

The 16,384-payload template exceeds the tracker's 16,384-live-allocation table,
so it uses one live owner outside tracking. It runs natively, under ASan/UBSan and
in both guests, with streamed inventories and fresh guest workers. Functional
one/64-selector and refusal runners use 64 cycles; full-bound cases run once.
Exact 8 MiB and 1,024-byte selectors pass; limit-plus-one and nested overflow
cases refuse. Invalid imports preserve source bytes, an existing workspace and
an absent destination; restored input captures payloads and publishes unchanged
canonical manifest bytes.

Host regressions cover prepared-root admission, schema, import, all three fixed
publisher profiles, catalogs, composition, stored/signed metadata and the signed
CLI. Dedicated guest suites include the recipe groups, publisher-schema fixture
and import fixture. Frozen kernels are copied before boot; successful receipts
pin the kernel, init, three fixtures and serial log, with clean QMP shutdown.

This qualifies recipe decoding and selector validation after returned values and
errors are retired. Complete import/copy/publication lifetimes and generic pinned
catalog decoding are outside this allocation measurement. Production publisher
enrollment, catalog migration, graphical login/display integration and broader
foreign-runtime acceptance remain open for roadmap 14.

## Recorded results, 2026-10-16

All **40 focused compile/run checks** passed: fourteen core pairs, two tracked-allocation pairs, one ASan/UBSan pair, four signed CLI/driver checks and two guest-tool builds.

Fresh QEMU TCG guests passed with clean shutdown and six verified artifact hashes each: AArch64 **50.1 seconds**, x86_64 **27.3 seconds**. Deadlines qualify functionality, not performance.

- [before/after recipe probe](results/2026-10-16/root-recipe-baseline.txt)
- [host results](results/2026-10-16/root-recipe-host.json)
- [host summary](results/2026-10-16/root-recipe-host.txt)
- [core assertions](results/2026-10-16/root-recipe-core.txt)
- [tracked recipes and manifests](results/2026-10-16/root-recipe-memory.txt)
- [sanitizers](results/2026-10-16/root-recipe-asan.txt)
- [signed CLI](results/2026-10-16/root-recipe-cli.txt)
- [intermediate residual](results/2026-10-16/root-recipe-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/root-recipe-toolchain.json)
- [aarch64 receipt](results/2026-10-16/root-recipe-aarch64.json)
- [aarch64 report](results/2026-10-16/root-recipe-aarch64.txt)
- [aarch64 serial](results/2026-10-16/root-recipe-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/root-recipe-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/root-recipe-x86_64.json)
- [x86_64 report](results/2026-10-16/root-recipe-x86_64.txt)
- [x86_64 serial](results/2026-10-16/root-recipe-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/root-recipe-x86_64.qmp.txt)
