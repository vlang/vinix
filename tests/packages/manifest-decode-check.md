# Bounded owned publisher manifests

`pack` source templates and packed publisher inventories now use the bounded
stored-manifest reader instead of generic typed JSON decoding. Returned fields
own their strings and nested arrays; partial and refused values retire their
storage. Callers retain the existing `close_decoded_package` contract.

The pre-change warmed probe retained **10 bytes over ten minimal-template
reads**, **10 bytes over ten complete-inventory reads**, and **7,280 bytes over
ten truncated-inventory refusals**, after retiring returned values/errors. The
same probe retains zero in all three cases after bounded decoding. Original
sources, executable, generated C and before/after output are retained and pinned.

Source templates keep omitted package, dependency and payload defaults, including
SDK 1, window protocol zero, false booleans and empty fields/collections. Even
omitted dependency IDs and payload members retain their decoder defaults; normal
package validation still runs in the publisher before a manifest is emitted.
`pack` replaces template `files` with the captured source inventory, including
when a template contains `[{}]`. Packed inventories require all canonical fields
and nested declarations, with only legacy `window_protocol` optional at zero.

The shared reader keeps distinct presence masks: policy pins still require their
ID, stored/signed manifests still require complete declarations, and only source
templates permit all omitted defaults. Source admission uses the same bounded
field lengths/counts as inventories. Types, escaped duplicate keys, unknown
fields, null collections, malformed UTF-8, noncanonical/overflowing integers and
trailing data refuse. Permission validation retains distinct SDK grants and its
specific SDK diagnostic when a permission list exceeds the supported grant set.
Specific bounded-reader/schema diagnostics replace generic JSON decoder messages.
Canonical publisher bytes and signatures are unchanged.

Metadata remains limited to 8 MiB, with 16,384 payloads, 64 arguments, 128
dependencies and 128 associations. Both template and inventory paths accept the
exact metadata size and limit-minus-one; one byte over and each nested overflow
refuse. Unsigned payload sizes and nonnegative SDK/protocol integers retain their
full typed ranges at decoding; semantic package validation retains its separate
limits. Complete source/inventory records on both metadata architectures qualify
1,000 read/retire cycles with one and 64 payloads, independently owned results,
retired input buffers and exact canonical reproduction. Default and refusal
cycles also require zero retained bytes, including every truncated prefix.

The 16,384-payload case exceeds the allocation tracker's 16,384-live-record table.
It runs with one live owner, outside tracking, natively, under ASan/UBSan and in
both guests. Guest cases use fresh workers and streamed fixture inventories;
ordinary functional runners use 64 cycles while allocation runners use 1,000.
Invalid pack input preserves source bytes and leaves the destination absent;
restoring a valid template publishes its captured payload with unchanged bytes.

Shared-reader regression checks cover signed indexes, stored state, configuration
and policy pins; publisher checks cover traversal, workspace locking, catalogs,
prepared roots, release and signed CLI workflows. A dedicated manifest guest
suite includes every manifest case, the signed-schema service fixture and
configuration/policy ownership checks. The original repository suite is unchanged.

An initial combined repository/manifest suite passed on AArch64 but its x86_64
run reached the existing five-minute deadline in the prior index fixtures,
before manifest assertions ran. The dedicated suite keeps the same deadline,
resource limits and manifest assertions while avoiding unrelated long-running
status/index ownership fixtures. The combined-run reports and timeout serial/QMP
logs are retained and pinned; that timeout does not count as qualification.

This qualifies manifest decoding, not complete `pack`/publication or other
publisher-recipe lifetimes. Production publisher enrollment, catalog migration,
graphical login/display integration and wider foreign-runtime qualification
remain open for roadmap 14 acceptance.

## Recorded results, 2026-10-16

All **46 focused compile/run checks** passed: fourteen core and one protocol pairs, three tracked-allocation pairs, two ASan/UBSan pairs, four signed CLI/driver checks and two guest-tool builds.

Fresh dedicated QEMU TCG guests passed with clean shutdown and six verified artifact hashes each: AArch64 **115.4 seconds**, x86_64 **64.8 seconds**. These deadlines qualify functionality, not performance.

- [before/after manifest probe](results/2026-10-16/manifest-decode-baseline.txt)
- [host results](results/2026-10-16/manifest-decode-host.json)
- [host summary](results/2026-10-16/manifest-decode-host.txt)
- [core assertions](results/2026-10-16/manifest-decode-core.txt)
- [tracked manifests, signed indexes and configuration](results/2026-10-16/manifest-decode-memory.txt)
- [sanitizers](results/2026-10-16/manifest-decode-asan.txt)
- [signed CLI](results/2026-10-16/manifest-decode-cli.txt)
- [initial diagnostic assertion](results/2026-10-16/manifest-decode-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/manifest-decode-toolchain.json)
- [aarch64 receipt](results/2026-10-16/manifest-decode-aarch64.json)
- [aarch64 report](results/2026-10-16/manifest-decode-aarch64.txt)
- [aarch64 serial](results/2026-10-16/manifest-decode-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/manifest-decode-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/manifest-decode-x86_64.json)
- [x86_64 report](results/2026-10-16/manifest-decode-x86_64.txt)
- [x86_64 serial](results/2026-10-16/manifest-decode-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/manifest-decode-x86_64.qmp.txt)
