# Stored configuration and generation decoding

Stored configuration and installed state now use an internal bounded reader
instead of the generic JSON decoder. Completed results own their strings and
arrays; refusals retire partial nested packages, repositories, policy defaults
and array growth. Public SDK signatures and the saved schema remain unchanged.

Parsing rejects unknown or duplicate keys, including escaped duplicates, wrong
types, trailing data, invalid UTF-8, malformed surrogate pairs and collection
overflow. Integers must use unsigned decimal spelling without leading zeros,
fractions, exponents or overflow. Existing writers already use that spelling.
The 8 MiB envelope, 4,096 repositories/packages/roots, 16,384 payloads per package
and existing field/policy limits apply during decoding. Semantic validation still
checks provenance, architecture, dependencies, runtime entrypoints and closure.
Legacy configuration and partial-policy defaults remain supported; stored package
declarations remain complete except for the optional window-protocol extension.

The pre-change native tracker measured 2,034 bytes retained by ten configuration
decode/close cycles and 5,223 by ten state cycles. An intermediate decoder probe
left 40 bytes in state validation's traversal queue: typed pushes cloned IDs,
while cleanup retired only the queue buffer. The queue now borrows IDs from the
state for the synchronous validation call.

Repeated public snapshot/save/audit calls also exposed temporary root/path strings
and stat buffers that escaped to the heap. Those paths now retire their owned
strings and pass stack scratch to synchronous native stat calls. Exclusive atomic
publication retains its descriptor, inode, link-count, parent-identity and durable
flush checks. Missing activation paths still represent fresh state; other stat
failures refuse. System-root trust checks refuse symlinks, including dangling
ones, and retire failed decode inputs and mismatched-architecture configurations.

The maintained allocation tests require zero retained bytes for 1,000 complete
configuration and state cycles, every truncated prefix, 1,000 late-refusal cycles,
and 1,000 nested dependency/argument/payload-array cycles. Large 4,096-entry
functional fixtures run outside the tracker's 16,384-live-record limit. Existing
construction checks continue to cover 1,000 exports, comparisons and selections.
The isolated-store public fixture requires zero retained bytes across 100
snapshot/save/audit/existing-file-refusal cycles, with returned results closed.
It also checks unchanged activation, state/configuration bytes, cache and generation
contents, damaged offline catalog/history, revoked policy, repeated close, literal
UTF-8 paths and absence of temporary files.

Native allocation assertions and ASan/UBSan cover these lifetimes. The signed CLI
checks and fresh frozen-kernel guests cover functionality on AArch64 and x86_64.
This qualifies the listed paths and fixtures; it does not establish allocation
freedom for all service operations or system-root callers. Publisher enrollment,
catalog migration, graphical login/display integration and broader foreign-runtime
acceptance remain separate roadmap-14 gates.

## Recorded results, 2026-10-16

All **50 focused compile/run checks** passed: fourteen core and three protocol pairs, two native tracked-allocation pairs and two ASan/UBSan pairs, six CLI/driver checks and two guest-tool builds.

Fresh QEMU TCG guests passed with clean shutdown and nine verified artifact hashes each: AArch64 **53.9 seconds**, x86_64 **62.9 seconds**. These functional deadlines are not performance qualification.

- [baseline regression](results/2026-10-16/stored-decode-baseline.txt)
- [host results](results/2026-10-16/stored-decode-host.json)
- [host summary](results/2026-10-16/stored-decode-host.txt)
- [core assertions](results/2026-10-16/stored-decode-core.txt)
- [tracked decoder and public allocations](results/2026-10-16/stored-decode-memory.txt)
- [sanitizers](results/2026-10-16/stored-decode-asan.txt)
- [signed CLI](results/2026-10-16/stored-decode-cli.txt)
- [intermediate regressions](results/2026-10-16/stored-decode-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/stored-decode-toolchain.json)
- [aarch64 receipt](results/2026-10-16/stored-decode-aarch64.json)
- [aarch64 report](results/2026-10-16/stored-decode-aarch64.txt)
- [aarch64 serial](results/2026-10-16/stored-decode-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/stored-decode-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/stored-decode-x86_64.json)
- [x86_64 report](results/2026-10-16/stored-decode-x86_64.txt)
- [x86_64 serial](results/2026-10-16/stored-decode-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/stored-decode-x86_64.qmp.txt)
