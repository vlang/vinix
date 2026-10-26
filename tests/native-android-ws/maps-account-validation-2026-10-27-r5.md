# Maps account deployment: GMS framework startup failure

The r5 retry loaded the separately packaged browser client and attached the
Google Play Services authenticator transport. GMS subsequently exited with
`NoSuchFieldError` for `android.content.pm.ApplicationInfo.deviceProtectedDataDir`
(`Ljava/lang/String;`) in `GmsApplication.attachBaseContext`. Google account
login remains unverified; no credentials were supplied.

The private startup log was inspected locally through the guest Terminal.
`broker-startup-exception-type.png` records the missing field. It also shows
an earlier SQLite exception, `no such column: secret`; the retained context
screenshots place that exception earlier in `attachBaseContext`. That message
alone does not establish a SQLite provider defect. Private broker logs remain
excluded from the controller export, which retains their hashes.

The controller receipt covers 2026-10-26 21:45:45–21:47:14 UTC: broker PID
37807, `service_ready=true`, exit 1 and zero cleanup survivors. Both
`auth_init.failures` and `browser_init.failures` are empty, with neither
truncated. Readiness denotes authenticator transport attachment, not account
authentication. The broker was started explicitly after the initial automatic
launch encountered the preserved SQLite library hardlink guard. The controller
recorded its audited single-link replacement without changing library bytes.

The unchanged strict collector accepted 21 entries, 1,439,719 archive bytes
and 2,812 chunks, archive SHA-256
`b0516b60951c8de9f97053a3d06e1984dd7d11c16e80a3f2a8db7710ad0b75a6`.
The final post-stop collection is
`maps-account-collected-final-2026-10-26-r5-retry1`; its import binds final
UART SHA-256
`36b1115c7e285ea95ef9ed17fbea35dad1c321f915fa828b48ea31d12609b0eb`.
The earlier collection remains in `maps-account-collected-2026-10-26-r5-retry1`.
Collection integrity passed; the guest result is failed.

The immutable original stage is `maps-account-r5`, complete manifest SHA-256
`9a8bf61bd526d7ec020d45920367d45e90a2ef4692c6d8fa8b87de801a14c5ca`.
[Staging provenance](maps-account-stage.md) records its selected framework,
JNI, account, browser-client, browser, launcher, controller and fixture inputs.
The retry booted only the exact 1,914-file clone `maps-account-vm-r5-retry1`,
after the previously audited P_PIDFD kernel patch. The original stayed intact.

The first r5 VM, `maps-account-vm-r5`, disappeared before a controller result.
Its observed-absence receipt attributes no exit status or cause. The retry
used runner source `1733801d2`, which retains normal QEMU daemon diagnostics
in private `qemu.log` without enabling trace output. That log was empty during
the startup failure. This does not establish the first VM's termination cause.
Owned retry PID 69235 was stopped cleanly at 22:22:40 UTC; the stop and absence
receipts and `maps-account-r5-retry1-stop.log` remain with the evidence.

All named artifacts are below `/Users/alex/.local/state/vinix/android/`.
The independently checked runner closure is
`maps-account-daemon-runner-closure-2026-10-27/sha256.json`, SHA-256
`711c05cc23e68cf81039e37ea0d3d5a92fb52bed8ab083cedaef79cf6153de2f`.
It retains exact source, compiler, used/rebuilt runner bytes, build commands
and passing self-tests. Its stated scope excludes a recursively hermetic
standard-library, host toolchain or QEMU rebuild closure.

The final quiescent runtime evidence is sealed in
`maps-account-r5-runtime-sealed-2026-10-27-r1`: 64 roots and 4,426 typed
entries, manifest SHA-256
`f7da25f9394998d280ffbeeb92d774d225cf4984526a4968b926810f5030831b`.
Streaming seal and a separate complete recheck both passed. Measured maximum
RSS was 19,103,744 bytes for sealing and 22,052,864 bytes for the separate
check. The inventories and plan created about 2.08 MiB without copying images.
`maps-account-r5-stream-execution.json`, SHA-256
`32fc4fb08522f52d9760fee3031439fb37f6f1ed53aa65aa47e450c873452f0a`,
binds the commands, logs and memory measurements. Original complete producer
bundles remain required by their historical checkers; this seal supplements
them and does not establish an application pass or a VM termination cause.
