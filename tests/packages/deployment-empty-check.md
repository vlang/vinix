# Empty deployment removal

An explicitly empty deployment now plans removal without reading authenticated
catalog metadata. Format 1 requires `packages: []`; format 2 additionally requires
`locked: []`. A lock with surplus pins refuses. Generic `review deploy` and
`apply FINGERPRINT deploy` with no IDs use the same empty target and retain their
separate review identity. Nonempty deployments still authenticate their catalog.

The retained pre-change regression installs a signed Linux application, runtime
and architecture-independent data dependency, then damages the catalog and replay
history while offline. Empty deployment review fails with `invalid cached
repository metadata`. The fix only changes planning: public commands still read
validated configuration and coherent persistent state under the store lock, and
shared activation still checks review identity and disk space before recovery
cleanup and staging an immutable generation.

Core tests exercise both formats on both configured architectures with an absent
repository, missing cache objects, damaged then missing catalog/history,
tightened allowlist/version/permission/license/firmware policy and revoked
publishers. Reviews disclose every removed package's historical metadata and
reserve space for staging. Damaged removed payloads do not prevent removal.
Activation clears the full app/runtime/data closure and launcher/association
registrations, preserves personal data and the previous generation, and repeated
empty deployment is a no-op. Rollback refuses withdrawn policy/trust and damaged
retained payloads; restoring admission and integrity allows rollback without
repository or cached objects.

Separate assertions cover file/generic fingerprint separation, stale policy,
invalid configuration/state, writer exclusion, surplus pins and nonempty catalog
authentication. Refusals preserve abandoned-stage evidence. An interrupted empty
stage leaves the old generation active; a reviewed retry recovers it and activates
the empty set. An initialized empty store does not acquire payloads or create an
active generation. Public reviews still require an existing coordination lock;
direct writers can initialize the store without authenticating a catalog.
The normal lifecycle runs under ASan/UBSan as well.

The signed CLI fixture covers both formats and configured architectures, generic
and file confirmation, surplus/nonempty refusals, complete app/runtime removal,
retained data, no-op and newly authorized rollback. Fresh AArch64 and x86_64 QEMU
administrator scenarios require ordinary administrator and standard-user reviews
of both empty formats, password/role refusal, authenticated file confirmation,
stale refusal, retained data and authenticated rollback. They use frozen kernels.
These functional fixtures do not qualify graphical login/display brokering,
catalog migration or broader foreign runtime compatibility; roadmap 14 remains
open for those acceptance requirements.

## Recorded results, 2026-10-16

All **32 focused compile/run checks** passed: ten core and one protocol pairs, two ASan/UBSan pairs, four CLI/driver checks and two guest-tool builds.

Fresh QEMU TCG guests passed with clean shutdown and eight verified artifact hashes each: AArch64 **51.403 seconds**, x86_64 **108.278 seconds**. These functional deadlines are not performance qualification.

- [baseline regression](results/2026-10-16/deployment-empty-baseline.txt)
- [host results](results/2026-10-16/deployment-empty-host.json)
- [host summary](results/2026-10-16/deployment-empty-host.txt)
- [core assertions](results/2026-10-16/deployment-empty-core.txt)
- [sanitizers](results/2026-10-16/deployment-empty-asan.txt)
- [signed CLI](results/2026-10-16/deployment-empty-cli.txt)
- [initial fixture attempt](results/2026-10-16/deployment-empty-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/deployment-empty-toolchain.json)
- [aarch64 receipt](results/2026-10-16/deployment-empty-aarch64.json)
- [aarch64 report](results/2026-10-16/deployment-empty-aarch64.txt)
- [aarch64 serial](results/2026-10-16/deployment-empty-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/deployment-empty-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/deployment-empty-x86_64.json)
- [x86_64 report](results/2026-10-16/deployment-empty-x86_64.txt)
- [x86_64 serial](results/2026-10-16/deployment-empty-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/deployment-empty-x86_64.qmp.txt)
