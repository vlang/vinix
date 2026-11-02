# ComponentName/Messenger ARM pass and missing EventLog failure

The unchanged Messenger fixture **passed on ARM** against the ComponentName
parcel successor. Its request/reply, Message parcel and callback UID assertions
now complete. GMS attaches its authenticator, then exits after missing
android.util.EventLog before Maps can be opened manually. No manual Maps launch,
Sign in, credentials or imagery check occurred; current map rendering and
authentication remain unverified.

Core `eb467cd5a`, producer `38a56c93a`, delivery `10c30911e`,
[SDK/native pair](component-parcel-pair-2026-11-02.md) `878e1e8a7` and
[media profile](maps-component-parcel-stage.md) `b8d9473ee` are committed.
The framework adds ComponentName's parcel contract and creator while preserving
all 23 existing methods, both String fields, manually consumed constructor and
getters. Membership grows to 2,116; the original broadcast native bundle remains
compatible. Prepared manifest is
`9c82d40a0a09ab4255a0cea93af74fb50b568d9ed9feb0a80f6870659a239415`.

Complete evidence remains below `/Users/alex/.local/state/vinix/android`:
`maps-component-parcel-runtime-audit-2026-11-02-r1` (`A`), matching live controls,
both `maps-component-parcel-preparation-2026-11-02-r1` and `-r2`, prepared
`maps-component-parcel-r1`, stopped `maps-component-parcel-vm-2026-11-02-r1`
with four clone sidecars, and
`messenger-binder-v2-api-transfer-live-2026-11-02-r1`.
`A/runtime-result.md` closes the pending plan without changing it or the
independent validation note. The first preparation was refused before spawn by
the original disk-growth preflight, guard125/child-1/pid0. After space recovered,
the unchanged retry passed all 55 module readbacks and complete input rechecks
in 388,076 ms at 92,291,072 bytes sampled RSS, both exits zero and complete
cleanup. Clone/kernel installation then passed in 8,489/46,926 ms. Both attempts
and all historical complete bundles remain required; no resource cap was lowered.

The isolated UID/GID 10150 child 44544 exited zero with six exact input identities
and eleven unchanged checks. Receipt SHA-256 is
`1f99cbb11df64ff3cef25984f03f6409b1ae751a713e12c26e01b42d727a6f75`.
The signed r2 APK remains exactly
`7295339e8b548f3d48091229eb31319be25bf7394a2091ebce6b26263693729a`.
The complete 9,870-byte, 108-line child hashes to
`3e25cb231e7d7ff6b4b0394dbce1385f25c3f3b8c23e2240cb1ab2f069505f5b`:
one exact unchanged PASS at 93, readiness at 102 and normal teardown through 108.
Independent `A/fixture-validation.md` hashes to
`290b6c98bd5bcd2eeb9c5cd1767f847fabc4a85093b4351fd96eed94d9bbd751`.
It confirms local/forced-proxy exchanges, Binder descriptor/identity, transaction
framing, ComponentName/Bundle copies, reply Binder identity, actual UID10150
overwrite, callback looper and field checks, independent Message wire tests,
CREATOR/pooling controls, exceptions and bounded worker cleanup. False transact
is ignored without retry and does not prove delivery. This is a process-local
contract result; kernel IPC and cross-process credentials remain outside scope.
The unchanged zero-removal diagnostic import preserved 32 chunks of the
16,062-byte archive, without strict fixture-protocol extension or health waiver.
The [earlier failed Messenger run](maps-messenger-binder-runtime-2026-11-02.md)
remains a separate preserved failure.

After releasing the fixture mount, the controller ran from 20:11:43 to 20:12:57
UTC. Receipt
`eab3f1d066da9e9199612b8595010a0143dab50b0f33934757948f833a802a79`
records broker 17546, readiness true, failed/exit 1, drain EOF true/status 1,
318,593 bytes, errno zero and zero cleanup survivors. The uncaught
NoClassDefFoundError for android.util.EventLog reaches `clgt.e` source 31 →
`clgt.c` 159 → `clgt.g` 113 → `clgn.run` 13 on lowpool[9]. GMS then calls
System.exit(10), recording native VM status 10. Transport readiness alone does
not establish successful startup or Google authentication.

Automatic export finished with guest input idle. Before stopping the VM, the
unchanged strict collector passed 21 entries, 2,831 chunks and 1,449,180 bytes,
archive `d22a71f62d4f2bbfc367fc0110de614028322594e1b0f5808951f4d6d41e4072`.
Import took 311 ms at 28,983,296 bytes sampled RSS; both exits are zero with
complete cleanup. The full private broker log remains separately at
`A/broker-log-diagnostic/child.log`, 318,593 bytes, SHA-256
`12f987cb0ecbc9916e7f49cbdbcc111dc7bcfc66f018472c5909601c5180ed2d`.
The existing guest-pinned canonical-base64 decoder and fresh readback passed
without modifying original UART or payload bytes. Private logs stay outside the
strict account archive apart from hashes. Failure cleanup removed the live
protected broker session required by the supported Maps desktop launcher.

Owned exclusive 12 GiB/four-CPU VM 90348 started at 20:08:27 UTC. One SIGTERM was
requested at 20:15:06; QEMU records signal 15. The first stop returned 1 on an
ownership race; no second signal was sent. Qualified reconciliation returned
zero, with gone.json at 20:15:15 and an independent empty exit-1 ps query
confirming absence. Final UART equals the immutable after-broker-log full
snapshot, both SHA-256
`0c1355c5ddede226e5c0f2fe200cdecfc341ab9ce6521791cdaff9ad61faac19`.
No compiler or Java ran while the VM was live. Eleven closed roots, including
both preparation attempts, passed complete sealing and a separate fresh-process
readback of all 733 typed entries. The manifest at
`maps-component-parcel-runtime-sealed-2026-11-02-r1/sealed/manifest.json` hashes to
`6a7ce5be1d9f07c3ca9cbf6d88fee9b823b3639db57d10ca9fdf15175a377eee`.
Seal/readback took 15,798/4,052 ms at 27,426,816/13,484,032 bytes sampled RSS,
with 8,839,168/4,694,016 bytes observed shared growth and zero swaps. Both seal
and readback guards/children exited zero with complete cleanup under the original
600 MiB RSS, 900-second, 64 MiB shared-growth and 1 GiB reserve limits.
