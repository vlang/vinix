# Complete catalog builder ownership

`pack-catalog` retires its complete call storage after process-wide JSON metadata
initialization: temporary-filesystem paths, independently packed manifests,
manifest-name verification, copied object-map keys and handled importer errors.
Manifest paths are constructed in one allocation. `CatalogInfo.close()` remains
idempotent and preserves the published workspace and canonical catalog bytes.

Recursive publisher flushing now owns its directory enumeration, child paths and
error storage on success and refusal. Enumeration opens before allocating names;
directory inspection uses a stack record. It preserves existing traversal and
durability behavior, including refusal when a directory alias reaches the
no-follow durability boundary. This is a storage-lifetime change, not a new
directory-alias policy.

The [complete-call fixture](../../tools/packages/pkgcore/catalog_builder_ownership_test.v)
measures **280 calls across 35 cases**, eight attempts each under a 32-descriptor
limit. The recipe has both architectures, five packages, exact runtime bounds,
permissions, associations, literal arguments and explicit proprietary/firmware
metadata. Six file selectors produce five unique objects; runtime selectors
resolve guest-absolute aliases. Synthetic text payloads are never executed.

Frames include metadata admission, disk checks, all imports, staged verification,
publication and reply/error disposal. Fixture preparation, public JSON warm-up
and default-option retries are outside tracking. Checkpoint callbacks retire
their environment/path scratch and use native file writes. Every case requires
zero retained tracked V bytes/allocations, stable descriptors, preserved source,
concurrent and recovery data, and exact canonical retry.

Cases cover normal/nested publication, missing/malformed/schema/architecture and
closure refusals, missing/aliased roots, both disk budgets and query failure,
creation, each of five partial imports, ready-stage refusal, missing/changed/
non-executable/directory payloads, changed/extra manifests, changed/missing objects,
changed staged catalog, captured input declarations, occupied/concurrent targets,
published directory-flush failure and replaced stage roots with cleanup refusal.
The canonical catalog SHA-256 remains
`a5fac25e7915d6a796c04f427d79e0a7eab7ebbcff09a5ea79bb1ddcd4ea9158`.

The [flush fixture](../../tools/packages/pkgcore/publisher_flush_ownership_test.v)
measures **192 recursive cycles** across success, ordinary-file refusal and
nested directory-alias durability refusal. Existing
[planning checks](catalog-plan-check.md) measure **1,792 attempts** across
metadata, budgeting and partial-plan refusals.

The [host driver](catalog-builder-check.v) runs **29 build/test checks**:
production CLI compilation, three tracked suites, four ASan/UBSan suites,
six ordinary suites and the distribution CLI regression. These cover catalog
construction, all 144 catalog/composition staging substitutions, signed release
and offline lifecycle consumption, captured prepared-root imports and packing.
LeakSanitizer is disabled; V retention uses the independent tracker. Inputs,
commands, timings and log/binary hashes are journaled; resume verifies them.

The [guest controller](catalog-builder-runtime-check.v) runs the tracked flush
fixture, ordinary catalog/planning regressions and **ten selected complete-call
cases (80 measured frames per guest)** on aarch64 and x86_64. Each selected case
runs in a fresh process: complete, unresolved closure, source alias, third/fifth
partial import, missing payload, changed manifest/object, published flush failure
and replaced stage root with checkpoint refusal. Ten six-second resource pairs
precede the builder cases; required markers and clean poweroff must complete
within 900 seconds. Guest planning is functional coverage; the 1,792 tracked
planning attempts are measured by the host suite.

```sh
v -nocache -o /tmp/catalog-builder-check tests/packages/catalog-builder-check.v
V=/path/to/reviewed/v /tmp/catalog-builder-check /build/new-catalog-host

v -nocache -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/catalog-builder-runtime tests/packages/catalog-builder-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/catalog-builder-runtime --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-catalog-arm
```

Repeat for x86_64 with its matching kernel and a new state directory. The retained
baseline uses the identical fixture and original catalog/transaction sources at
`2459df53a` in an isolated module copy; only zero-retention assertions are skipped.
Replies are closed on both versions. Cold JSON initialization, complete release
builder ownership, production catalog migration, graphical sessions and real
application/runtime compatibility remain separate acceptance gates. Section 14
stays open.

## Recorded results, 2026-10-18

| Target | Result | Time | Evidence |
| --- | --- | --- | --- |
| aarch64 | PASS | 210.453 s | [receipt](results/2026-10-18/catalog-builder-aarch64.json), [serial](results/2026-10-18/catalog-builder-aarch64.serial.txt) |
| x86_64 | PASS | 223.89 s | [receipt](results/2026-10-18/catalog-builder-x86_64.json), [serial](results/2026-10-18/catalog-builder-x86_64.serial.txt) |

All **29 host build/test checks passed**, including the three tracked suites,
four ASan/UBSan suites, all 144 staging substitutions, signed offline lifecycle
and distribution CLI regressions. The
[host receipt](results/2026-10-18/catalog-builder-host.json) retains inputs,
commands, timings and artifact hashes; the
[summary](results/2026-10-18/catalog-builder-host.txt) lists every check.
The [CLI log](results/2026-10-18/catalog-builder-cli.txt) covers authenticated
enrollment, reviewed deployment, offline mirrors, rollback and uninstall after
publisher revocation.

Each guest passed 192 tracked flush cycles, ordinary catalog/planning regressions,
ten selected complete-call cases, canonical retries and clean poweroff. All
140 denial samples per guest were zero. These bounded observations do not claim
kernel allocation freedom. Existing kernels are pinned. The x86_64 run uses an
isolated V plain-USTAR media adapter for its exact pre-gzip kernel; production
image tooling is unchanged. Toolchain, sysroot, firmware and Limine requirements
follow the [hardware harness](../hardware-platform/README.md).

The [baseline](results/2026-10-18/catalog-builder-baseline.txt) retained
**48 allocations** per successful measured call; its byte count depends on
fixture paths. The identical
[fixture](results/2026-10-18/catalog-builder-baseline.v), original catalog and
transaction sources, and
[compile command](results/2026-10-18/catalog-builder-baseline-command.json) are
retained. The [journal guards](results/2026-10-18/catalog-builder-journal-check.txt)
reject changed inputs/artifacts and existing fresh-run directories before
compilation; an intact completed journal resumes with original timings and pins.

The [retention helper](results/2026-10-18/catalog-builder-retain.v) verifies
the baseline source anchor, receipts, zero-retention markers, preservation
outcomes and resource samples before saving evidence. Its
[ledger](results/2026-10-18/catalog-builder-toolchain.json) pins source, compiler,
host/guest artifacts, baseline dependencies, the local media adapter and reports.
Builds use `-nocache` with V 0.5.2 `826e96f`, compiler fallback disabled. The
compiler SHA-256 is
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.
