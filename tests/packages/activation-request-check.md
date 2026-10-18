# Owned activation, rollback and deployment requests

Public transaction, rollback and deployment results own all fields independently.
Use `State.close()` after consuming a reply; repeated close of one owner is
harmless. This includes service and explicit configuration-taking transactions
and rollback, document deployment, reviewed apply and unchanged results.
Internal activation states and caller-built states still borrow their inputs.
The CLI closes successful public maintenance replies.

Service requests retire their loaded configuration and directory. Transactions
retain an explicit prepared-plan owner, and release catalogs, solver buffers and
decoded current state after cloning the reply. Rollback also releases the
admitted source state; deployment releases its decoded document. Source storage
stays live through staging, validation, publication, callbacks and the final
activation check. A no-op takes the same independent-reply path.

Staging paths, acquired cache paths, desktop registrations, progress messages,
URLs and temporary activation names have explicit lifetimes. Directory creation
uses the existing owned mkdir-p implementation. Partial-download validation,
promotion and resume-size observations use synchronous stack `stat` records.
Only absent entries (`ENOENT`) skip partial/activation-name inspection failures.
The file transport retains bounded copy, no-follow and captured-output checks.

The [request fixture](../../tools/packages/pkgcore/activation_request_test.v)
measures 64 complete calls after two warmups in each of 92 cases across both
architecture declarations: **5,888 measured requests**. Tracking begins after
fixture/reset preparation and ends after reply or error disposal. Successful
install, upgrade, no-op, repair, removal, rollback, file download, resume and
format-1/2/empty deployment cases accompany offline, missing-source, stale-review,
disk-space, dependency, damaged metadata/history, revoked rollback, counter,
unsafe-stage, writer-contention and configuration refusals. A fixture callback
also damages prepared or published metadata. Refusals preserve the active
pointer; interrupted stages and failed published generations remain available,
while preflight refusals preserve abandoned recovery data.

An independent lifetime probe retires configuration, a sibling reply and the
whole fixture before reading nested Unicode names, dependency bounds, arguments,
permissions, MIME declarations, protocols, payloads and publisher identities.
It checks transaction, no-op, repair, rollback and empty/pinned deployment replies.

The original-source fixture measures two calls per case. Fresh service installs
retained 120,526/120,520 bytes for the AArch64/x86_64 declarations; explicit
installs retained 112,832/112,828. Service rollback retained 158,674/158,664;
writer contention and malformed configuration each retained 128. The original
borrowed replies could not be closed independently. These scoped totals include
unretired request/reply storage; they are not whole-process leak rates.

The [host driver](activation-request-check.v) performs 55 fresh compile/run
checks: the complete fixture with and without allocation tracking, ASan/UBSan,
eleven related service, rollback, deployment, admission, download, cache, repair,
stage, review and copy suites normally and under sanitizers, plus both real CLI
lifecycle runs. Sanitizer leak detection is disabled; scoped V allocation
tracking supplies the retained-byte claim. This does not measure whole-process
or kernel heap usage.

```sh
v -nocache -o /tmp/activation-request tests/packages/activation-request-check.v
V=/path/to/reviewed/v /tmp/activation-request /build/new-activation-request
```

The [native controller](activation-request-runtime-check.v) runs every case in
its own creator process on both architectures. It also runs independent-lifetime,
service, rollback, empty-deployment and generation-admission controls. The parent
checks file reservations after all 97 children against one fixed initial baseline
plus 128 KiB using the existing strict
[counter reader](collectionstress/budget.v), with at most 30 one-second waits.
Those observations and waits are outside measured requests. Kernels are pinned
prebuilt inputs; QEMU TCG has a 1,800-second deadline per target.

Recorded on 2026-10-18 with frozen V 0.5.2 `826e96f`, compiler SHA-256
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`:

| Check | Result | Elapsed |
| --- | --- | --- |
| Host compilation, normal/sanitized fixtures and CLI lifecycles | All 55 checks passed | 1,447.664 s total |
| AArch64 native requests, lifetime and regression controls | Passed | 1,353.3 s |
| x86_64 native requests, lifetime and regression controls | Passed | 1,145.7 s |

Each tracked host and native request run measured 5,888 complete calls with
zero retained tracked V bytes in all 92 scopes. Both guests completed all 97
reservation checks against the fixed 133,120-byte ceiling. The largest settling
wait was ten polls on each target; observation and waiting remain outside
measured requests.

The [host summary](results/2026-10-18/activation-request-host.txt) and
[receipt](results/2026-10-18/activation-request-host.json) retain commands, timings
and compiler/source/artifact hashes. The
[normal request log](results/2026-10-18/activation-request-request-run.txt),
[sanitizer log](results/2026-10-18/activation-request-request-sanitize-run.txt) and
[paired original baseline](results/2026-10-18/activation-request-baseline.txt)
preserve the scoped measurements.

Native [AArch64](results/2026-10-18/activation-request-aarch64.txt) and
[x86_64](results/2026-10-18/activation-request-x86_64.txt) reports have raw
[AArch64 serial](results/2026-10-18/activation-request-aarch64.serial.txt) and
[x86_64 serial](results/2026-10-18/activation-request-x86_64.serial.txt) evidence
and QEMU command logs alongside them. The
[retention helper](activation-request-retain.v) requires every case, control and
reservation observation and preserves serial line endings. Its
[ledger](results/2026-10-18/activation-request-ledger.json) binds saved evidence,
original sources, generated C, deployed binaries, prebuilt kernels and the V-only
media adapter. Run it with `--verify` to check retained hashes.

Live HTTPS repetition, production catalog migration, graphical session acceptance
and broader foreign-runtime gates remain separate; section 14 stays open.
