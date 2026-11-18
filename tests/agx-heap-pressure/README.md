# Explicit collection under allocation pressure

`v run tests/agx-heap-pressure/run.v` exercises the production heap, channel,
cache-barrier helper and buffer allocator with ASan/UBSan, `-gc none -manualfree`
and a host transport. Heap factories are extracted from the manager's actual
G13 private and GPU-read-only constructor expressions. The buffer helper's
external `page_size` binding is renamed to avoid a V global/local collision in
the host closure runtime; its control flow is copied unchanged.

The 256 cases cover both classes, both firmware ABIs, 4 KiB and 16 KiB PMM
granules, two release orders, threshold and sub-threshold garbage,
immediate and delayed acknowledgements, failed doorbells, timeout, state and
fault transitions, and full or corrupt rings.
Three repeated allocation failures must preserve metadata addresses, pending
counts/bytes, live pins and FIFO/hole order. Explicit prefix collection must
permit only the collected range's reuse. Successful barriers permit reuse of
their captured prefixes. The heap allocator must return all 672 new physical
allocations when VA placement fails. Two fixed-map refusals check the backing
rollback at each PMM granule. Both paths request 16 KiB physical alignment.
The default heap control checks its four-page alignment and pressure retry.

`AGX_PRESSURE_C` and `AGX_PRESSURE_BINARY` retain host artifacts outside Git.
`--manager-source FILE` and `--allocator-source FILE` select alternatives.
`counterexamples.v RUNNER BASELINE_DIRECTORY FRESH_OUTPUT` compiles the original
two sources plus five wrong-policy/guard cases. Every binary must fail at the
unacknowledged-reuse assertion; compilation failure does not count. Fixtures
are removed before either successful or failed exit.

`check.v --native CURRENT_ARM_C BASELINE_ARM_C` verifies the original
pressure-policy change against its retained source and native build. It checks
the exact allocation guard (including deferred unlock), stack-only constructor,
scalar default and two class selections. Fourteen heap, backing, barrier and
teardown bodies must match. It resolves interned strings by value and renames only
numbered C return/array temporaries, preserving variable identity and uses.
`--selftest` rejects six mutations, including a wrong temporary alias.
`AGX_PRESSURE_DIAGNOSTICS` names an existing external directory for a failed
allocation-body comparison. Historical x86 and allocation checkers are reused
unchanged.

`qualify.v STATE` checks the preceding bundle's native runner source hashes,
prepares an isolated worktree and overlays both production sources. Its copied
`native` runner uses two jobs. `evidence.v --seal STATE` validates all results,
preserves the complete bundle, records its typed inventory and verifies a full
archive restoration. After committing the checksum report, `--bind STATE COMMIT`
checks exact paths and committed bytes; `--cleanup STATE` retires only the
private worktree and verified restoration.

Explicit map rollback and eager teardown GC remain separate collection paths.
These tests establish an allocation-pressure policy, not a global cache-lifetime
guarantee or native scheduler/firmware behavior. See
[the report](../../docs/m1-agx-heap-pressure.md).
