# Disabled-AppStandby ARM pass and null Messenger binder failure

The signed usage-inactive regression **passed on ARM** with unchanged health
checks. GMS advances beyond the missing inactivity query, then exits from its
service main looper when a GMS binder wrapper dereferences a null Binder.
No manual Maps launch, Sign in, credentials or imagery check occurred; current
map rendering and authentication remain unverified.

Core `a2fbc6b5c`, producer `6bcc38b11`, fixture `11d8ae664`, delivery `57803645e`,
[SDK/native pair](usage-inactive-pair-2026-11-02.md) `c34f65cd6` and
[media profile](maps-usage-inactive-stage.md) `359f6d24e` are committed.
The sole new UsageStatsManager query returns false because AppStandby restrictions
are disabled, without claiming application activity history or permission.
All 70 native-consumed canonical classes and the retained native bundle remain
compatible; two pinned raw formatting differences remain documented separately.
Prepared manifest is
`8685761d98b7e3d395bde91d2ec2e7db9c23fa60aa4472aaa47d821d9ae2245c`.
All 53 module readbacks and complete input rechecks passed in 326,640 ms at
83,755,008 bytes sampled / 86,081,536 bytes detailed RSS, zero swaps and both
exits zero with complete cleanup. Clone and frozen-kernel installation passed
before boot under the original limits.

Complete evidence remains below `/Users/alex/.local/state/vinix/android`:
`maps-usage-inactive-runtime-audit-2026-11-02-r1` (`A`), matching live controls,
separate `maps-usage-inactive-preparation-2026-11-02-r1`, prepared
`maps-usage-inactive-r1`, stopped `maps-usage-inactive-vm-2026-11-02-r1` with
four clone sidecars, and `usage-inactive-api-transfer-live-2026-11-02-r1`.
`A/runtime-result.md` closes the pending runtime-plan without changing it or the
independent validation note. Historical complete bundles and original auditors
remain required.

The isolated UID/GID 10149 child 51080 exited zero with six exact input identities
and eleven unchanged checks. Receipt SHA-256 is
`7a5484468e8eef471fafb89eb885fc907e0b3d1dbc3deeabe599ad650c151e6c`.
The complete 10,079-byte, 120-line child hashes to
`532878951f5cbe1c35c1f8ce7c0c56feef3371d553b1af520763a9dfd119ff73`:
one full PASS at line 103, readiness at 114 and normal teardown through 120.
Independent `A/fixture-validation.md` hashes to
`1bd5ca5f369b3763309680fca669bfaa1f9fdbe26453360943db6b968e1d7a5a`.
It verifies 1,568 actual disabled-policy calls over typed Activity/application
managers and the public constructor, including own/GMS/Maps/unknown, null,
empty and Unicode arguments. Exact manager types and legacy null string-service
discovery remain checked. No history, installation, foreground state or usage
access is inferred. Unchanged zero-removal diagnostic import preserved 32 chunks
of the 16,235-byte fixture archive, without new strict fixture-protocol qualification.

After releasing the fixture mount, the controller ran from 18:29:55 to 18:30:51
UTC. Receipt
`69f0701fb7424150c413645d0a62aab4350fa15343c97d82a77603a7ae969983`
records broker 16315, readiness true, failed/exit 1, drain EOF true/status 1,
328,647 bytes, errno zero and zero cleanup survivors. The native failure record
is `ANDROID-SERVICE-EXIT phase=6 reason=1 status=1`, followed by
`ANDROID-SERVICE-FAIL main looper`. Its NullPointerException calls
`Binder.getInterfaceDescriptor()` on null through `djdu.getInterfaceDescriptor`
source 3 → `cxzk.a` 9 → `bjbu.onBind` 126 → `VinixServiceBinding.connect` 42.
The exact SDK's retained Messenger.getBinder body returns constant null;
implementing proper Messenger/Binder/Message behavior remains separate work.
An earlier Base64 null-array stack remains in the full log; its causal role is
not established by this service-exit record. Readiness alone does not establish
successful initialization or Google authentication.

Automatic export completed with guest input idle. Before stopping the VM, the
unchanged strict collector passed 21 entries, 2,831 chunks and 1,449,096 bytes,
archive `fefc9a4c88c29e4fc6992a4fdc32f6802fcd60228b7e61aa9b5cc9f96c78b6b1`.
Import took 292 ms at 29,212,672 bytes sampled RSS; both exits are zero with
complete cleanup. The separate full exact private broker log,
`A/broker-log-diagnostic/child.log`, is 328,647 bytes, SHA-256
`da2718ca39b161ce3f51c5d3e821afc3cca6609b42525e1be232e5090b3e71de`.
The existing guest-pinned canonical-base64 decoder and fresh readback passed
without modifying original UART or payload bytes. Private logs stay outside the
strict account archive apart from hashes. Failure cleanup removed the live
protected broker session required by the supported Maps desktop launcher.

Owned exclusive 12 GiB/four-CPU VM 70815 started at 18:27:13 UTC. One SIGTERM was
requested at 18:33:00; QEMU records signal 15. The first stop returned 1 on an
ownership race; no second signal was sent. Qualified reconciliation returned
zero at 18:33:11; gone.json and an independent empty exit-1 ps query confirm
absence. Final UART equals the immutable after-private-log full snapshot, both
SHA-256 `3e52148ba4c262fc4eaa5a2c09a6290da8173e74521730e1262a51d633d60809`.
No compiler or Java ran while the VM was live. Ten closed roots passed complete
evidence sealing and a separate fresh-process readback of all 688 typed entries.
The manifest at
`maps-usage-inactive-runtime-sealed-2026-11-02-r1/sealed/manifest.json` hashes to
`79c86422c2451d966879d1c4109ee95125ac900b01230fe5a5b3c6cdbc6c92fa`.
Seal/readback took 8,323/3,637 ms at 15,581,184/13,402,112 bytes sampled RSS,
with 5,218,304/4,997,120 bytes observed shared growth and zero swaps. All
guard/child exits are zero with complete cleanup under the original 600 MiB RSS,
900-second, 64 MiB shared-growth and 1 GiB reserve limits.
