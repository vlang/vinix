# Authenticator exception and network observation runners

The new explicit `onboarding-api-run.v` profiles pin the auth-exception framework
JAR `0daae54d7755b255ed3335f58d8cafd6da4d03c8c95343ebb0f174d166da6916`
and native library `cce3eb926d3bc8b2b3c9e9a4f0d42cc4ab6bfdc23b0532beb2c42f5f9b384791`:

- `--authenticator-private-exception`: synthetic regression APK
  `c4e78b7c46d2d35f63d60bb8d45c3964ede94553f63e3cca9d0bebbcd261a941`.
- `--maps-network`: observation APK
  `f66dfd858b52c1b7da9c2bac635106cc33a956a425860b86527cdc909e88ad43`.
  Its marker is `MAPS-NETWORK-PASS observations-complete`. This establishes
  completion, not DNS, TCP, TLS or Google authentication success. The public
  receipt states that limit; validate the finite record sequence separately
  with `maps-network-fixture --check LOG`.

Historical profiles and pins remain unchanged. The new profiles preserve exact
terminal/readiness checks, bounded output, stdin closure, drained EOF, clean
child exit and complete input rechecking. They also pin and recheck the native
library at `usr/lib/art/libvinix-android-native.so`.

The transfer's explicit `serve --auth-exception-apis` profile serves exactly
`/auth-exception-api-run`, `/authenticator-exception.apk` and `/maps-network.apk`.
Historical profiles, snapshot verification, loopback binding, GET-only allowlist,
deadlines, request limit and file-size bound remain unchanged.

Artifacts are under `/Users/alex/.local/state/vinix/android` (`S`):

| Artifact | SHA-256 |
| --- | --- |
| `auth-exception-api-run-2026-10-29-r1/run` | `49e53828402f44c5c45afb8dd611bbf6198b4046da19d37db2c6d0195c1fd0e1` |
| `auth-exception-api-transfer-build-2026-10-29-r1/transfer` | `99a2b93b269045d22af0448c625e6d7d4e0edf3e08b7c2e63579fc06c510e990` |
| Runner source | `2be91a6aee8ea5033b2b2eb1822be51dde7f06b86a25ea2d7f86ac9c3af70f93` |
| Transfer source | `b32ff8ed42365ab2ebcb1dc7bea4353e217ceec7a8a13c5085ae129bda4c6b2b` |

Host runner build/selftest, static AArch64 build, host transfer build/selftest
all passed under unchanged 600 MiB RSS, 300-second, 512 MiB observed growth and
1 GiB reserve guards, with complete cleanup and zero swaps. Runner selftest
rejected 123 malformed, mixed, duplicate, incomplete and failure cases; transfer
selftests covered strict profile allowlists and the original HTTP refusal and
deadline cases. Peak sampled RSS was 360,300,544 bytes for the host runner,
370,081,792 for AArch64 and 355,729,408 for the transfer build. ELF inspection
confirmed a static AArch64 executable. Independent source review approved the
unchanged boundaries and completion-only network scope.

Exact sources, binaries, tool identities and guard receipts are retained in the
two artifact roots above and `S/auth-exception-api-run-build-2026-10-29-r1`.
The recorded source checkout was `292ef1ebc32746007b76b5c8df129611f3a43d93`;
modified source identities are pinned above. The complete three-root, 28-entry
seal and separate full readback passed. Manifest
`S/auth-exception-api-tools-sealed-2026-10-29-r1/manifest.json` has SHA-256
`0b8cc1ea193bd2c31d34686fa460b32ded1d0612aff62a1153f6f0496faea843`.
Seal controls remain outside these closed roots in
`S/auth-exception-api-tools-seal-controls-2026-10-29-r1`.

Use the identity provisioning, runtime attachment and later broker handoff in
[onboarding-api-run.md](onboarding-api-run.md). For a fresh guest, check that
`onboarding-probe` and UID/GID 10117 are unused before creating that dedicated
identity. Download the three URLs into a fresh protected input directory, name
the runner `run`, set it executable, and run as root:

```sh
/var/lib/auth-exception-input-r1/run --authenticator-private-exception /opt/vinix-android-aarch64 /var/lib/auth-exception-input-r1/authenticator-exception.apk 10117 10117 /var/lib/auth-exception-auth-result-r1
# Preserve the complete UART interval before starting the next fixture.
/var/lib/auth-exception-input-r1/run --maps-network /opt/vinix-android-aarch64 /var/lib/auth-exception-input-r1/maps-network.apk 10117 10117 /var/lib/auth-exception-network-result-r1
```

Each run exports only `child.log` and `receipt.json` through the unchanged
SERVICE-QUERY framing. Preserve separate exact UART intervals and perform no
guest input during each export. Guest validation of these profiles remains
pending; these host results establish neither Maps sign-in nor network success.
