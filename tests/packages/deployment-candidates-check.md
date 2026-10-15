# Locked deployment candidate matching

Locked deployment planning now indexes the approved pin IDs and scans the
authenticated catalog once. A pin matches only the exact ID, version,
architecture, repository and publisher key. The matcher then checks its minimum
signed sequence and the complete canonical manifest digest. Unrelated variants
cannot replace a pin. Multiple exact matches refuse as ambiguous; a saturating
counter prevents duplicate counts from wrapping. Returned candidates preserve
pin order and borrow manifest fields from the authenticated catalog.

The prior matcher allocated a catalog-sized filter for every pin and left those
buffers allocated. Its loop was extracted unchanged into a private helper for
the retained baseline probe. **Ten matches of 16 pins in a 256-entry catalog
retained 23,578,480 bytes**. Matching now owns one pin-sized result array, a
pin-index map and a small counter array. Scratch and rejected results are freed;
the caller retires the successful candidate array after resolution. Authenticated
catalogs are also retired if planning fails, including policy/solver and surplus
closure refusals. Successful plans retain their existing borrowed manifest
lifetime; this is not whole-service memory qualification.

Manifest digesting now frees the four canonicalization buffers, reuses a
`noslices` JSON byte buffer, appends the required LF, and explicitly frees the
SHA-256 context, its state and checksum. An intermediate probe still retained
54,560 bytes because the SHA-256 convenience function left its context/checksum
allocated; its executable, generated C and log are retained. The final tracked
runner retains **zero bytes over 1,000 success, absent-pin, changed-digest,
sequence-floor and ambiguous-match cycles**, including repeated digest buffer
growth. Inputs are prepared before measurement and remain caller-owned.

Assertions cover a 32,768-entry catalog and 4,096-pin lock, unrelated catalog
growth beyond that fixture, excessive pins, empty locks, reordered pins/catalogs,
exact and wrong variants, duplicate pins and 257 duplicate exact candidates.
Sequence renewal may preserve an exact manifest; an insufficient sequence or
changed manifest refuses. A literal SDK-1 JSON fixture checks the exact digest
bytes, sorted files/dependencies/permissions/associations, retained launch argument
order and caller field preservation. Existing snapshot, saved-document, audit,
deployment/mirror and transaction assertions also run. The matcher adds no new
total advertised-catalog limit; only exact pins reach the normal solver.
ASan/UBSan run both the tracked matcher/digest assertions and the signed
deployment lifecycle, including catalog cleanup on rejected planning and intact
returned manifests after successful candidate-buffer retirement.

The signed CLI fixture exports older installed versions while the catalog also
advertises newer variants. On both configured architectures, sequence, digest,
version, architecture, repository and key substitutions fail review, reviewed
apply and direct deployment without changing state bytes, activation, catalog,
trust history or object/generation names. The unchanged reviewed lock then
activates exactly its older pins, verifies and rolls back. The full existing
CLI lifecycle runs alongside these checks.

Fresh AArch64 and x86_64 administrator guests require an additional exact-pin
marker. Ordinary administrator and standard users review a valid installed
lock and refuse changed sequence/digest and missing-version deployment/mirror
reviews while preserving installed state and configuration. They use frozen
kernels. These checks do not qualify graphical login or broader native/foreign
application catalogs; roadmap 14's wider acceptance gate remains open.

The initial AArch64 guest passed the new exact-pin checks, then failed the
unchanged disconnected-worker completion assertion at `package_admin.v:107`.
Its controller output, guest binaries, generated C and logs are retained. The
fresh retry uses the same timeout after host checks completed; a successful
retry does not establish the cause of that initial failure.

Run the maintained allocation assertions with the reviewed V toolchain:

```sh
V_MACOS_V3_NO_FALLBACK=1 V_C_ERROR_BUG_REPORT_DISABLED=1 /path/to/v \
  -nocache -no-skip-unused -gc none -manualfree -d track_heap \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/deployment-candidates \
  tools/packages/pkgcore/deployment_candidates_test.v
/tmp/deployment-candidates
```

## Recorded results, 2026-10-16

All **32 focused compile/run checks** passed: nine core and one protocol compile/run pairs, a native allocation pair and two ASan/UBSan pairs, four CLI/driver checks and two guest-tool builds.

Both fresh QEMU TCG guests passed with clean shutdown and eight verified artifact hashes each: AArch64 **39.888 seconds**, x86_64 **64.643 seconds**. These are functional deadlines, not performance qualification.

- [baseline regression](results/2026-10-16/deployment-candidates-baseline.txt)
- [host results](results/2026-10-16/deployment-candidates-host.json)
- [host summary](results/2026-10-16/deployment-candidates-host.txt)
- [core assertions](results/2026-10-16/deployment-candidates-core.txt)
- [tracked allocations](results/2026-10-16/deployment-candidates-memory.txt)
- [sanitizers](results/2026-10-16/deployment-candidates-asan.txt)
- [signed CLI](results/2026-10-16/deployment-candidates-cli.txt)
- [initial attempts](results/2026-10-16/deployment-candidates-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/deployment-candidates-toolchain.json)
- [aarch64 receipt](results/2026-10-16/deployment-candidates-aarch64.json)
- [aarch64 report](results/2026-10-16/deployment-candidates-aarch64.txt)
- [aarch64 serial](results/2026-10-16/deployment-candidates-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/deployment-candidates-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/deployment-candidates-x86_64.json)
- [x86_64 report](results/2026-10-16/deployment-candidates-x86_64.txt)
- [x86_64 serial](results/2026-10-16/deployment-candidates-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/deployment-candidates-x86_64.qmp.txt)
