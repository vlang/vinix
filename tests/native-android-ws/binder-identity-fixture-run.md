# Binder identity runtime fixture profiles

The explicit `--authenticator-binder-identity` and `--maps-network-v3` runner
profiles require the Binder identity framework and native library together.
The authenticator profile reuses the signed base API fixture; it checks
compatibility on that runtime and does not independently drive the broker
worker or authenticate a Google account. The network profile uses standard
JSSE sockets and records handshake and hostname-verifier outcomes separately.
Validate its finite observations with the maintained network checker's
`--check-v3 LOG` mode. Completion alone is not network or authentication success.

The transfer selector `serve --binder-identity-apis` exposes only
`/binder-identity-api-run`, `/authenticator-exception.apk` and
`/maps-network-v3.apk`. Historical profiles, paths and artifact pins are retained.
The shared authenticator marker is permitted only for the same APK on distinct
exact framework/native pin pairs; runtime admission verifies those inputs before
ART starts. Mixed or duplicated fixture markers still fail.

The runtime pair is framework JAR
`3f2e3220d6c38feb885044fdb4806d4d3ca7736352bbcc7813e2ee6510463636`
and native library
`6a87d8c2fd003c55cb572ab397342d0c39aa54376ffe7a5a2ba2fa4592099eae`.
The TLS-v3 APK is
`bd07eddf7594fd6cc6b90b984baf7ee5855af0fc56ee0322fbc45ea318cf393a`.
Its generator, signature and complete canonical DEX evidence are described in
[maps-network-fixture.md](maps-network-fixture.md).

Independent source review passed. All host and cross-build checks passed
sequentially under unchanged 600 MiB aggregate RSS, 300 second, 512 MiB observed
shared-volume growth and 1 GiB reserve limits. Every guard recorded exit zero
and complete cleanup; time reports recorded zero swaps. The runner selftest
rejected 289 malformed, mixed, duplicate and failure cases, including 14 actual
child-process CLI refusals for the new selectors. Transfer selftests retained
the existing HTTP, snapshot, pin, binary and deadline cases and added nine
actual malformed-selector/port refusals with no output directory creation.
ELF inspection confirmed a static AArch64 executable without an interpreter.

| Check | Seconds | Peak sampled RSS, bytes |
| --- | ---: | ---: |
| Host runner compile | 2.853 | 335,495,168 |
| Runner selftest | 0.494 | 19,824,640 |
| AArch64 runner compile | 3.358 | 365,379,584 |
| Host transfer compile | 2.453 | 358,252,544 |
| Transfer selftest | 0.424 | 6,144,000 |

Artifacts below are relative to `/Users/alex/.local/state/vinix/android` (`S`).

| Artifact | SHA-256 |
| --- | --- |
| `binder-identity-api-run-2026-10-29-r1/run` | `29975834bca029b057df515c1210d9121e481c8b999bbcb2f4f7af8495b6c922` |
| `binder-identity-api-transfer-build-2026-10-29-r1/transfer` | `a8766490700a546cb562fdd0ed427d6ad9e9b025ba6744f962e7b01fd7ad9b23` |
| Runner source | `67f3600eadaf95467a75962856fd91671b94da6f8196d203711729dce47360de` |
| Transfer source | `bd82c7f1855e57f7bfdb743aa49e49a61fb6763bb4d5ce0c8ea49c2f3934bd9e` |

Runner controls and frozen source are in
`S/binder-identity-api-run-build-2026-10-29-r1`; transfer controls are in
`S/binder-identity-api-transfer-controls-2026-10-29-r1`. Recorded checkout
revisions were `938078b43a6f9514cdcbbf607e87dd8c991bfac7` for the runner and
`d23f73bd05bcbdbe9eafeb00b156802669cceeda` for the transfer; exact modified
sources are retained with the hashes above.

The four complete closed roots are sealed in
`S/binder-identity-api-tools-sealed-2026-10-29-r1/manifest.json`, SHA-256
`e794dd0ef39034a8f26508161cf7c7b717ee4fc2f850cea7f190523df6aba686`.
The seal, inline check and independent fresh-process complete readback passed
for 30 entries under the unchanged 600 MiB RSS, 300 second, 64 MiB observed
growth and 1 GiB reserve limits. Both guards exited zero with complete cleanup
and zero swaps; controls remain outside the closed roots in
`S/binder-identity-api-tools-seal-controls-2026-10-29-r1`.

In a fresh guest, use the protected fixture identity and runtime attachment
procedure in [onboarding-api-run.md](onboarding-api-run.md), then:

```sh
/var/lib/binder-identity-input-r1/run --authenticator-binder-identity /opt/vinix-android-aarch64 /var/lib/binder-identity-input-r1/authenticator-exception.apk 10117 10117 /var/lib/binder-identity-auth-result-r1
# Preserve the complete UART export before sending the next guest input.
/var/lib/binder-identity-input-r1/run --maps-network-v3 /opt/vinix-android-aarch64 /var/lib/binder-identity-input-r1/maps-network-v3.apk 10117 10117 /var/lib/binder-identity-network-result-r1
```

Keep each export in its own exact UART interval. Release the dedicated fixture
runtime mount before starting the account broker. Guest validation of these
profiles and Google login remain pending.
