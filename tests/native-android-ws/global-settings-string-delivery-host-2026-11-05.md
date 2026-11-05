# Global String-write fixture delivery and host evidence

The additive `--global-settings-string` runner and
`serve --global-settings-string-api` transfer selectors deliver the
[signed Global String-write fixture](global-settings-string-fixture-host.md)
with the [successor SDK](global-settings-string-sdk-2026-11-05.md) and
[qualified retained native library](global-settings-string-native-host.md).
Historical selectors, pins, protocol rejection rules and shared-APK exceptions
remain preserved. The new profile requires distinct runner/APK routes and
identities, with no shared-artifact exception.

All five delivery phases passed: host runner compilation/self-test, static
ARM runner compilation, and transfer compilation/self-test. The runner rejected
5,717 malformed, mixed-profile and failure cases. Transfer tests include six
new route/path/hash collision controls, malformed selector/port refusals and
the existing pinned binary snapshot, GET-only, traversal, request-limit and
absolute-deadline checks. Saved ELF readback confirms AArch64 EXEC with no
dynamic section. These are host results; image preparation and ARM execution
remain separate, and no successor GMS, Maps or authentication result is claimed.

Builds used predecessor revision `5176b25198306e1978620c79970a72e1bb5b3e8a`
plus the exact runner/transfer changes committed with this report. The frozen
sources match the reviewed checkout byte for byte, with SHA-256 respectively
`aa47520d9bc893259cd725dcf9c34d894fb9ae945a523e7551253aad233d026b`
and `29ef14eb87dbafb1594f44bc5418ec83acab76fbfd47efa8b8205f7c9bccc60e`.

Paths use `S=/Users/alex/.local/state/vinix/android`:

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Signed fixture | `global-settings-string-fixture-2026-11-05-r1/probe.apk` | `faee136b4cdb500ff165b7b7aceb6649f8af27054593a5905a64f217553c806a` |
| Static ARM runner | `global-settings-string-api-run-2026-11-05-r1/run` | `7dedaf0f25f4eb3daa9a6af9f94b6d65329dded9d90645fa2d1f37c195010ae7` |
| Framework JAR | `combined-account-webview-global-settings-string-framework-2026-11-05-r1/api-impl.jar` | `9207dab7a6a37e09fb049bb636ba6ebad3e63e43bfe7fd95821f67fc2aebeeb7` |
| Native DSO | `current-native-build-2026-11-04-process-packages-r1/native/libvinix-android-native.so` | `b69c62304448c1aa0fd5f0cc660acf81cfdd8614b280dad691f53a07d8abcc5f` |
| Host transfer | `global-settings-string-api-transfer-build-2026-11-05-r1/transfer` | `0ed1dcacda2a9879115f86152489dd81ec564683eb081149101733a32d7265ba` |

Complete runner snapshots, compiler input lists and guards are in
`S/global-settings-string-api-run-build-2026-11-05-r1`; executables are in
`S/global-settings-string-api-run-2026-11-05-r1`. Transfer snapshots, executable,
input list and self-test outputs are in
`S/global-settings-string-api-transfer-build-2026-11-05-r1`; guards/logs are in
`S/global-settings-string-api-transfer-controls-2026-11-05-r1`.

| Phase | Elapsed ms | Sampled RSS bytes | Observed shared growth bytes |
| --- | ---: | ---: | ---: |
| Host runner compilation | 2,123 | 345,817,088 | 2,629,632 |
| Host runner self-test | 1,519 | 37,683,200 | 647,168 |
| Static ARM runner compilation | 2,578 | 379,273,216 | 17,006,592 |
| Transfer compilation | 2,526 | 445,169,664 | 44,859,392 |
| Transfer self-test | 2,190 | 13,156,352 | 32,608,256 |

Every guard/child exited 0/0, with empty reason and complete cleanup, under
600 MiB RSS, 300 seconds, 512 MiB growth, 1 GiB reserve, 4 MiB supervisor
output and the recorded stricter 16 MiB shell file cap.

The complete 21-root, 8,036-entry host evidence seal and separate fresh
readback passed. Preserve
`S/global-settings-string-host-sealed-2026-11-05-r1`, including `roots.txt`,
both guards/logs and `sealed/manifest.json`, SHA-256
`8da9212328d1c2f1f23eabaa92911e84cdc65cfd4c805dca5ac5c76c05badc96`.
Seal/readback exited 0/0 with empty reasons and complete cleanup in
1,147/1,294 ms, sampled RSS 27,213,824/23,494,656 bytes and observed shared
growth 3,645,440/2,527,232 bytes. Both retained 600 MiB RSS, 900 seconds,
64 MiB growth, 1 GiB reserve and 4 MiB output. The seal binds complete external
roots, including the failed SDK/native-auditor attempts; it establishes storage
integrity, without replacing the original complete bundles or their auditors.

Before ARM execution, independently verify that account
`global-settings-string-probe`, UID/GID 10158, mount
`/opt/global-settings-string-runtime`, input paths and output
`/var/lib/global-settings-string-r1` are unused. Require a dedicated read-only
runtime mount with `nosuid,nodev,wxallowed` and without `noexec`. Start the
qualified transfer only when the guest is ready to fetch:

```text
S=/Users/alex/.local/state/vinix/android
"$S/global-settings-string-api-transfer-build-2026-11-05-r1/transfer" serve --global-settings-string-api FRESH_HOST_OUTPUT 55549
```

Fetch `/global-settings-string-api-run` to
`/opt/input/global-settings-string-run` and `/global-settings-string.apk` to
`/opt/input/global-settings-string.apk`. Verify both qualified hashes and final
permissions before the intended invocation:

```text
/opt/input/global-settings-string-run --global-settings-string /opt/global-settings-string-runtime /opt/input/global-settings-string.apk 10158 10158 /var/lib/global-settings-string-r1
```

The exact required success marker is:

```text
GLOBAL-SETTINGS-STRING-PASS public-static virtual-insert global-uri fresh-values exact-null-empty-unicode-Strings one-call provider-result SQLException narrow-exception-identity null-resolver bounded-worker
```

Require receipt profile `global-settings-string`, the selected UID/GID, all
six exact input identities, all eleven unchanged checks, sole exact PASS and
native READY, drained EOF and clean exit. Preserve 180/20-second deadlines,
the 4 MiB child log cap and 8,192-byte line cap. Keep guest input idle through
export END, retain complete UART, derive one exact fixture interval and apply
the unchanged zero-removal reconstruction and child extraction. A failed
fixture prevents separate GMS startup in that run. Release the fixture mount
after a validated pass before separate GMS/Maps execution; require stable GMS
before launching Maps through its desktop icon.
