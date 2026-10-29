# Maps authenticator worker runtime, 2026-10-29

The worker runtime advanced GMS Add account past the earlier main-thread blocking
failure. It now ends with `SecurityException: Only 0p apps are allowed to call
this API.` before returning a login interaction. The synthetic authenticator
fixture passed on ARM. Google authentication and usable map imagery remain
unverified; this run does not validate the subsequent caller-identity fix.

Artifact paths below are relative to `/Users/alex/.local/state/vinix/android/`
(`S`). The stage is `maps-auth-worker-r1`, profile commit `cfd38a737`, recorded
producer revision `ee5946e194875d5c80d8079c5806cd393860cfa2`, inventory SHA-256
`0e90067339cacf85987da7d0cae72a95f2a67b6455f601275ca10ba1af40783b`.
Producer evidence is preserved at
`S/maps-auth-worker-stage-sealed-2026-10-29-r1/sealed/manifest.json`, SHA-256
`2066058dc1508d55bfaa94133463bf933c3dc2a7d08089fc84908702cd2d4edc`.

The [worker change](authenticator-worker.md), commit `553980683`, was deployed
with native library SHA-256
`0ef0acd98c148b9b972f754e5fb1e23683e8dc7d0b56f05d2f0a4c7792206136`;
its native producer manifest is
`048602ab4aa188111bad295a5af9d1b47c6cceee0fd82f0eb73858689b22a921`.
The guest retained the caught-exception framework. The live VM is
`maps-auth-worker-vm-r1` (`VM`), with controls and results in
`maps-auth-worker-runtime-audit-2026-10-29-r1` (`A`). It used one 12 GiB/four-CPU
VM, the frozen kernel and the recorded `user-default` network backend.

## Fixtures and account flow

Both fixture receipts select the intended profiles, UID/GID 10117, pinned worker
native library and framework, and wait status zero. The authenticator log has
one `AUTHENTICATOR-BASE-PASS` and one native readiness marker. The v2 network
observation checker accepted its complete finite sequence. IPv4 TCP and the
hostname-based socket constructor connected. Its TLS step failed with error 11,
step 3: the fixture's forced `VinixSSLSocket` cast failed before handshake. This
is a fixture assumption failure, not a TLS transport or certificate failure.
IPv6 TCP timed out, and its TLS probe was skipped.

The exact fixture UART intervals were preserved and processed by the unchanged
no-removal planner, diagnostic reconstructor and bounded child-log extractor.
These are diagnostic derivations, not strict SERVICE-QUERY imports. All seven
derivation/check guards passed. Full profiles, pins and archive/log hashes are
recorded in `A/fixture-validation.md`. The three-file transfer completed and its
server exited; its closed evidence is
`S/auth-worker-api-transfer-live-2026-10-29-r1` (`T`).

The broker was ready before Maps was launched through the desktop. Sign in at
14:45:48 UTC opened the dialog; Add account at 14:45:56 returned to onboarding.
`VM/worker-handoff-private-01.png` captures the new exception through `aqxf.i`,
`akhj.i`, `akgu.addAccount` and the framework transport. The public receipt has
untruncated stages 1 and 2 for operation 2, followed by stage 9 / event 2 /
code 1, with no interaction offer. No credentials were supplied.

The separate [GMS identity audit](gms-0p-auth-check.md) establishes that the check
uses `Binder.getCallingUid()` through `bpbx.T` and `dgyj.a`. Retained GMS code
clears caller identity before invoking the local delegate. In the deployed
framework, `Binder.clearCallingIdentity()` returns zero and
`restoreCallingIdentity()` only returns, leaving the worker's synthetic broker
identity active. This identifies a caller-identity compatibility gap; the nested
GMS trust predicate and certificate validity are not established by this audit.

Skip reached the main Maps screen. At 14:53:51,
`VM/worker-map-main-01.png` still showed a beige background without imagery.
Search, directions and a timed route hold were not repeated in this run.

## Shutdown and complete evidence

The controller ran from 14:41:12 to 14:54:28 with onboarding and TLS tracing
enabled. It recorded service ready, no preparation error,
`user-stopped-no-authentication-claim`, broker exit 137 after explicit stop and
two cleanup survivors. The count does not distinguish running workers from
zombies. Host space falling below 1 GiB prompted shutdown; full native/image
builds remained held. The later seal had sufficient space for its unchanged
64 MiB growth allowance and 1 GiB reserve.

Clone and kernel guards passed. Kernel installation took 99.754 seconds with
31,703,040 bytes peak sampled RSS, under 600 MiB RSS, 900 seconds, 4 GiB observed
growth and a 1 GiB reserve. The complete Maps export passed strict collection
under 600 MiB RSS, 300 seconds, 64 MiB growth and a 1 GiB reserve, with exit zero,
complete cleanup and 28,508,160 bytes peak sampled RSS. Its exact 2,241,767-byte
UART interval has SHA-256
`4491871c0541e95b22c5c9329c26909f94e030a83ce2306efbb2bd57c14d8762`.

Owned VM PID 72279 received the SIGTERM request at 14:55:31. The runner reported
a transient ownership mismatch after signaling; reconciliation confirmed absence
at 14:55:45.

| Retained artifact | SHA-256 |
| --- | --- |
| `A/maps-strict-results/results/receipt.json` | `8c3a1b3864299c847404e1d48c45ea47974c2b0dbcf857c939af25bfdc3001cd` |
| `VM/worker-handoff-private-01.png` | `ca5cf26decc5b6e65dd8dbe379a4dac4fd6c83be2e2376f4581e90e78d77eefd` |
| `VM/worker-map-main-01.png` | `f3f7db38ad889b3427f1a43e069ffe46dfa32f39d18780d86f235a6b1d40fb25` |
| `VM/kernel-patch.json` | `18f8a262a86c5a5af80ef7a7ae59c60ebd05a457e5694263079f0fb0f1894be5` |
| `VM/stop.json` | `bf9bfa7f3c06ffff9f819538180cb436cc7939f63af902ba255c8e6f9c84b53d` |
| `VM/gone.json` | `d0ec071300ce7cbacc2964cf1d31a3affeb7f72ddf33f968bae6604a756d4248` |

The three closed roots `VM`, `A` and `T` are preserved by
`S/maps-auth-worker-runtime-sealed-2026-10-29-r1/sealed/manifest.json`, SHA-256
`5d0f13cdf08f56bd2b80896a621e4c32f9b660eede51d04b9db67f42a09b4cd2`.
The seal and independent fresh-process complete readback passed for 415 entries,
with exit zero, complete cleanup and zero swaps under 600 MiB RSS, 900 seconds,
64 MiB observed growth and a 1 GiB reserve. They took 3.263/1.809 seconds and
peaked at 13,975,552/13,582,336 bytes sampled RSS. Preserve the complete external
bundle; this report does not replace it.
