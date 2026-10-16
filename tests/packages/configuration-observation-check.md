# Repository and policy observation ownership

`repository_configuration(root)` now transfers its independently decoded
architecture and repository records into the returned document, retires unused
policy/launch-account storage and frees its directory path. Returned
`RepositoryConfiguration` documents support `.close()`, including repeated close
of one owner. Caller-built documents can borrow fields and keep their existing
caller-managed lifetime. The CLI retires its result after emitting the existing
human or JSON output.

`Service.policy()` keeps its independently owned canonical `PolicyDocument`,
whose existing `.close()` contract is unchanged. It now retires the decoded
source configuration and directory path on every return. A shared helper keeps
the fresh and locked read paths consistent. The CLI also retires policy reads.
Mutation, review, authorization, replay admission and transaction lifetimes are
unchanged.

Both reads still acquire the package reader lock before decoding configuration
when durable state exists. They never load catalog/history or initialize a fresh
package store. Configured legacy curve-invalid keys remain visible for revocation;
listing does not enroll them. Policy output remains sorted and reports the stored
offline setting, even when the service has a command-specific offline overlay.
Wire fields, scope, ordering and bytes keep their existing contracts.

The pre-change tracker measured 25,570 retained bytes over ten repository
reads/retirements and 38,500 over ten policy reads/retirements. Original source,
fixture, executable, generated C and failing assertion output are retained.
The new fixture requires zero retained bytes over 1,000 complete calls of each
reader, 1,000 legacy-default pairs, growing 64-record pairs and six separate
1,000-cycle refusal scenarios: malformed schema, missing configuration, a leaf
alias, a FIFO, an unsafe lock and an active writer. Restoring valid inputs permits
successful retry. Busy locks take precedence over malformed configuration.

Functional checks cover both metadata architectures, independent repository and
policy arrays/strings, repeated close, returned fields surviving source replacement,
exact protocol round trips, unchanged stored bytes and the full 4,096 repository/
policy-pin limits. The maximum fixture runs outside the tracker's 16,384-live-record
table; its source configuration and canonical policy legitimately coexist with
more live allocations. Catalog/history FIFOs stay unopened and unchanged; activation,
cache objects and generation inventories remain untouched.

An initial expanded assertion compared canonical policy output to an unsorted
constructor default. Its source and failure output are retained; the corrected
fixture compares against the canonical default and reruns all growth cases.

Native tracking and ASan/UBSan cover these public reader lifetimes. The signed CLI
maintenance suite and frozen-kernel guests cover the existing repository/policy
flows. This does not qualify all administration reads/mutations, strict history
listing, system-root lifetimes, public publisher enrollment, catalog migration,
graphical login/display integration or broader foreign runtimes. Roadmap 14's
wider acceptance gate remains open.

## Recorded results, 2026-10-16

All **36 focused compile/run checks** passed: ten core and three protocol pairs, one native tracked-allocation pair and one ASan/UBSan pair, four signed CLI/driver checks and two guest-tool builds.

Fresh QEMU TCG guests passed with clean shutdown and six verified artifact hashes each: AArch64 **62.9 seconds**, x86_64 **36.8 seconds**. These functional deadlines are not performance qualification.

- [baseline regression](results/2026-10-16/configuration-observation-baseline.txt)
- [host results](results/2026-10-16/configuration-observation-host.json)
- [host summary](results/2026-10-16/configuration-observation-host.txt)
- [core assertions](results/2026-10-16/configuration-observation-core.txt)
- [tracked public configuration allocations](results/2026-10-16/configuration-observation-memory.txt)
- [sanitizers](results/2026-10-16/configuration-observation-asan.txt)
- [signed CLI](results/2026-10-16/configuration-observation-cli.txt)
- [initial fixture attempt](results/2026-10-16/configuration-observation-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/configuration-observation-toolchain.json)
- [aarch64 receipt](results/2026-10-16/configuration-observation-aarch64.json)
- [aarch64 report](results/2026-10-16/configuration-observation-aarch64.txt)
- [aarch64 serial](results/2026-10-16/configuration-observation-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/configuration-observation-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/configuration-observation-x86_64.json)
- [x86_64 report](results/2026-10-16/configuration-observation-x86_64.txt)
- [x86_64 serial](results/2026-10-16/configuration-observation-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/configuration-observation-x86_64.qmp.txt)
