# Worker-native authenticator and TLS-v2 fixture profiles

Two additional opt-in profiles in `onboarding-api-run.v` select the worker-native
library `0ef0acd98c148b9b972f754e5fb1e23683e8dc7d0b56f05d2f0a4c7792206136`
and unchanged auth-exception framework JAR
`0daae54d7755b255ed3335f58d8cafd6da4d03c8c95343ebb0f174d166da6916`:

- `--authenticator-worker` reuses the synthetic authenticator APK
  `c4e78b7c46d2d35f63d60bb8d45c3964ede94553f63e3cca9d0bebbcd261a941`.
  This is a compatibility regression on the selected runtime; it does not
  independently exercise GMS command dispatch or prove Google authentication.
- `--maps-network-v2` selects the TLS diagnostic APK
  `abfa8127b920dd7156d3cdee056a98d725411c6b5b2f8cb081149393c0b9c051`.
  Its exact completion marker is `MAPS-NETWORK-V2-PASS observations-complete`.
  The finite `MAPS-NETWORK-V2` records include TLS steps and throwable categories;
  validate them separately with the pinned verifier's `--check-v2 LOG` mode.
  Completion does not establish network or authentication success.

All historical profiles, artifact paths and pins remain unchanged. The old and
new authenticator profiles share a marker because they use the same APK; their
different required native-library hashes distinguish runtime admission. The
selftest permits that shared marker only for the same APK/framework and
distinct nonempty native pins. Duplicate markers within a log still fail.

The new transfer selector `serve --auth-worker-apis` serves exactly
`/auth-worker-api-run`, `/authenticator-exception.apk` and `/maps-network-v2.apk`.
It deliberately reuses the same authenticator APK. Existing HTTP snapshot,
allowlist, size, request and deadline bounds remain unchanged, as do the
runner's readiness/terminal/EOF, clean-exit and complete input-recheck rules.

Host runner compilation/selftest, static AArch64 compilation and host transfer
compilation/selftest passed sequentially under unchanged 600 MiB RSS,
300-second, 512 MiB observed-growth and 1 GiB reserve guards. All commands
exited zero with complete cleanup and zero swaps. The runner rejected 193
malformed/mixed/duplicate/failure cases; the transfer retained its original
HTTP refusal, binary transfer, request and deadline checks. Independent source
review found no boundary regression. Build peak sampled RSS was 332,300,544
bytes for the host runner, 361,086,976 for AArch64 and 366,821,376 for the transfer.
ELF inspection confirmed a static AArch64 executable.

Ready artifacts under `/Users/alex/.local/state/vinix/android` (`S`):

| Artifact | SHA-256 |
| --- | --- |
| `auth-worker-api-run-2026-10-29-r1/run` | `35bb212db62c2734ecf1198deddee04f20a8761d4b3cfb383cd978d4670856e9` |
| `auth-worker-api-transfer-build-2026-10-29-r1/transfer` | `9063b3415e0fb0fd717e3bfb17dd3184ae21c70aee6ff69e37ba540437d788ce` |
| Runner source | `decc0f05b922f41bf67b26e772842e6942ad3d3201db3f355e0fd9a784f17711` |
| Transfer source | `f6b008e02ab7e3b36947bb2a5c94ff353f51b5077dfa405140e0d30bc6227663` |

The recorded checkout before this change was
`cfd38a737f1a2c25cc7694cbe5ba0b6e090a2bdf`; exact modified sources are retained
with their artifact hashes. Frozen sources, outputs and controls remain in the
two artifact roots above, `S/auth-worker-api-run-build-2026-10-29-r1` and
`S/auth-worker-api-transfer-controls-2026-10-29-r1`. The complete four-root,
29-entry in-place seal and independent readback passed. Manifest
`S/auth-worker-api-tools-sealed-2026-10-29-r1/manifest.json` has SHA-256
`4ec0efbc194f496ce21c8d1afd6106ef388ef6546dbfc29f803f95bcebf8edf4`.
Seal controls are outside those closed roots in
`S/auth-worker-api-tools-seal-controls-2026-10-29-r1`.

Use the existing identity, runtime attachment and later broker handoff from
[onboarding-api-run.md](onboarding-api-run.md). In a fresh guest, check for
collisions before provisioning the dedicated `onboarding-probe` UID/GID 10117.
After downloading the three protected inputs and naming the runner `run`:

```sh
/var/lib/auth-worker-input-r1/run --authenticator-worker /opt/vinix-android-aarch64 /var/lib/auth-worker-input-r1/authenticator-exception.apk 10117 10117 /var/lib/auth-worker-auth-result-r1
# Preserve the complete UART interval before starting the next fixture.
/var/lib/auth-worker-input-r1/run --maps-network-v2 /opt/vinix-android-aarch64 /var/lib/auth-worker-input-r1/maps-network-v2.apk 10117 10117 /var/lib/auth-worker-network-result-r1
```

Keep each SERVICE-QUERY export in its own exact UART interval and send no guest
input during export. Release a fixture-created dedicated runtime mount before
starting the broker. Guest validation of these new profiles remains pending.
