# Locked deployment mirror qualification

A catalog mirror resolves current versions. That is unsuitable for an
organization lock retaining an older approved runtime: the exported payload set
may omit files required by that pinned version. The deployment-specific
review/apply commands resolve only the authenticated format-2 lock's complete
package/runtime closure and publish its exact bytes as `_deployment.json` with
the verified repository objects.

The input is captured once, so parsing, hashing and copying refer to one document
snapshot. Confirmation binds its filename and exact digest in a separate domain,
along with configuration, signed metadata, requested roots, resolved packages
and destination filesystem identity. Whitespace changes require a new review.
Disk accounting includes the document and metadata overhead; ordinary consumers
can read it. A leading underscore reserves its name against all repository IDs,
including on case-insensitive host storage. Installed state remains unchanged.

The host deployment runner checks older pinned app/runtime versions despite a
newer advertised catalog, clean offline reproduction after removal of upstream,
byte-for-byte lock preservation, readable modes, stale filename/content,
cross-command fingerprint rejection, malformed/empty/root-only/wrong-target
locks, missing versions, organization permissions and lock ordering. Fault hooks
verify that corrupt payloads never publish a partial document/tree, and that
replacement of the input after admission does not change exported bytes. A
repository named `deployment.json` checks the reserved filename on the host.

CLI assertions check literal paths with spaces, semicolons and dollar signs,
progress, document hashes, and admission before configuration reads while busy.
The public presentation envelope requires its source path/hash and every nested
mirror field, validates the closure, and retires nested ownership on double close.
Its assertion runner also checks exercised safety with ASan/UBSan; leak detection
is disabled, so this does not certify the underlying JSON decoder's lifetime.

```sh
v run tests/packages/distribution-check.v --direct-tests --cross
v -no-skip-unused -path '.|tests/hardware-platform|@vlib|@vmodules' \
  -o /tmp/linux-check tests/packages/linux-runtime-check.v
V=/path/to/v VINIX_HWTEST_TCG=1 \
  VINIX_LINUX_SANDBOX=/build/target-root/usr/bin/vinix-sandbox \
  VINIX_MUSL_COPYRIGHT=/build/musl-COPYRIGHT \
  /tmp/linux-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-locked-mirror-arm
```

Repeat with matching x86_64 inputs and a fresh directory. The Linux guest
publishes a newer runtime missing its application library while preserving the
known working version in authenticated metadata. Exporting the old organization
lock includes that original library and runtime; a clean offline client enrolls
the original key, refreshes local metadata, reviews/applies the media's lock and
verifies exactly version 1.0.0. The main system continues to advertise version
1.1.0 and independently exercises update, loader failure, lock restore, sandbox
execution and rollback. Export emits completion without installed activation.

The final 2026-10-13 distribution driver passed 28 assertion runners, SDK context
heap retirement, CLI/PTY/Software fixtures and both target staging builds. No
desktop typecheck or desktop heap run was needed for this service/protocol change.
The final new protocol assertion runner passed clang ASan/UBSan with
`ASAN_OPTIONS=detect_leaks=0` and `UBSAN_OPTIONS=halt_on_error=1`.

Final QEMU TCG workflows passed using the reserved filename and fresh
service/init/account/session binaries. Eleven hashes per target are checked
against retained kernel, sandbox, payload/library/loader and program inputs;
QMP records guest shutdown:

- [AArch64 receipt](results/2026-10-13/locked-mirror-aarch64.json),
  [serial](results/2026-10-13/locked-mirror-aarch64.serial.txt) and
  [QMP](results/2026-10-13/locked-mirror-aarch64.qmp.txt): 41.7 seconds.
- [x86_64 receipt](results/2026-10-13/locked-mirror-x86_64.json),
  [serial](results/2026-10-13/locked-mirror-x86_64.serial.txt) and
  [QMP](results/2026-10-13/locked-mirror-x86_64.qmp.txt): 47.6 seconds.
- [Host results](results/2026-10-13/locked-mirror-host.txt) and
  [compiler/source ledger](results/2026-10-13/locked-mirror-toolchain.json).

Earlier build attempts stopped when the shared disk filled; one x86 guest passed
functionally but could not write its receipt. The final runs completed normally.
An initial capitalized document name collided with a lowercase repository ID on
the host's case-insensitive storage; the reserved underscore name fixes this.
Owned unpinned helpers and build intermediates were removed to recover space,
preserving qualified binaries, roots, logs, receipts and recorded witnesses.
Generated standard-library C warnings and other compiler notices remain in local
build logs. None of the earlier attempts supplies the final passing evidence.

Qualification covers functional host/headless presentation and QEMU guests,
using retained kernel/native-sandbox inputs with fresh service/init/account/
session programs. It does not qualify public publisher enrollment, physical
removable storage, power-cut durability, graphical brokerage or Wine/Apple APIs.
Mirrors retain signed index expiry and anti-replay behavior; consumer publisher
enrollment and license/firmware policy remain explicit. The wider roadmap gate
remains open.
