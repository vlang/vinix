# Service lifecycle runtime fixture profile

The explicit `--service-lifecycle` runner profile selects the signed Service
construction, attachment and StrictMode callback regression, using the new
Service framework and terminal-exit diagnostic native library. The fixture's
entry remains `org.vinix.bootstrap/Main`. Its terminal marker is:

```text
SERVICE-LIFECYCLE-PASS constructors attach-base-context create destroy no-disk-callback policy-identity duplicate-attach null-attach real-write-control restored-original
```

The transfer selector `serve --service-lifecycle-api` exposes exactly
`/service-lifecycle-api-run` and `/service-lifecycle.apk`. Historical selectors,
artifact paths and pins remain unchanged, including the earlier TLS-v3 runtime
pair. The runner retains exact input admission, one pass/ready marker, complete
EOF drain and clean exit requirements. This fixture does not establish GMS
startup or Google authentication.

The completed framework JAR is
`7017b4845f91cb1c37057f6e8da07476b9b1b44c523827acaf00baad2432fe74`.
The diagnostic native DSO is
`ea8b899971ac96335c1f53a32eb3dee8e5e8f87600c0bcd5b7edaa683b9a8136`.
Earlier profiles retain their original native hashes and runtime pairs.
The signed fixture APK is
`d15082450bbc70efc761ec8403e5544e40a98efe3f0a3d69b75b9d142e25b283`.

Independent source and artifact review passed. Host runner, static AArch64
runner and transfer checks passed sequentially under unchanged 600 MiB aggregate
RSS, 300 second, 512 MiB observed shared-volume growth and 1 GiB reserve limits.
All five guards recorded exit zero and complete cleanup; time reports recorded
zero swaps. The runner selftest rejected 347 malformed, duplicate, mixed-profile
and failure cases, including 21 actual CLI refusals across the explicit Binder,
TLS-v3 and Service selectors. Transfer selftests retained the HTTP, snapshot,
pin, binary and deadline cases and added nine actual Service selector/port
refusals without creating output directories. ELF inspection confirmed a static
AArch64 executable without an interpreter.

| Check | Seconds | Peak sampled RSS, bytes |
| --- | ---: | ---: |
| Host runner compile | 1.280 | 332,431,360 |
| Runner selftest | 0.749 | 18,989,056 |
| AArch64 runner compile | 1.685 | 364,085,248 |
| Host transfer compile | 1.389 | 355,696,640 |
| Transfer selftest | 0.435 | 9,732,096 |

Artifacts below are relative to `/Users/alex/.local/state/vinix/android` (`S`).

| Artifact | SHA-256 |
| --- | --- |
| `service-lifecycle-api-run-2026-10-29-r1/run` | `0d259a0e76d6ccff48b6d053264de4eb7bb49fc47c59b179b2150e03153b61de` |
| `service-lifecycle-api-transfer-build-2026-10-29-r1/transfer` | `ffdbbcbf65e23b09e6839bd3a3d06ed8aeab9a1a17e99ea14edf61d3c917eff7` |
| Runner source | `1a5e8df5581fb72502a0f672f7e66c8d6f980a9762c9c25d456dc82bdfe7b378` |
| Transfer source | `bd3e5d4319f36f08607a7c81c5c15cbef2df58c511f156bd341f24ce7e243f15` |

Frozen sources and runner controls are in
`S/service-lifecycle-api-run-build-2026-10-29-r1`; transfer controls are in
`S/service-lifecycle-api-transfer-controls-2026-10-29-r1`. Both builds recorded
checkout revision `63bf5f005ff5f0dea01ec5c9c60f24bea0f7190d`; the exact modified
sources are retained with the hashes above and match the committed source.

The four complete closed roots are sealed in
`S/service-lifecycle-api-tools-sealed-2026-10-29-r1/manifest.json`, SHA-256
`11f70a06dc6a461e25c6b468cad6debcc8b209eb25aacc9850d80cc78e19db55`.
Seal, inline check and independent fresh-process full readback passed for
34 entries under unchanged 600 MiB RSS, 300 second, 64 MiB observed growth and
1 GiB reserve limits. Both guards exited zero with complete cleanup and zero
swaps. Their controls are outside the closed roots in
`S/service-lifecycle-api-tools-seal-controls-2026-10-29-r1`.

Start the loopback transfer with a fresh external output directory and selected
port (`0` asks the host for an available port, reported in `ready.json`):

```sh
/Users/alex/.local/state/vinix/android/service-lifecycle-api-transfer-build-2026-10-29-r1/transfer serve --service-lifecycle-api FRESH_EXTERNAL_DIR PORT
```

In a fresh guest, follow the protected fixture identity and runtime attachment
procedure in [onboarding-api-run.md](onboarding-api-run.md). Fetch
`/service-lifecycle-api-run` as `/var/lib/service-lifecycle-input-r1/run` and
`/service-lifecycle.apk` as `/var/lib/service-lifecycle-input-r1/service-lifecycle.apk`,
then run:

```sh
/var/lib/service-lifecycle-input-r1/run --service-lifecycle /opt/vinix-android-aarch64 /var/lib/service-lifecycle-input-r1/service-lifecycle.apk 10117 10117 /var/lib/service-lifecycle-result-r1
```

Preserve the complete UART export in its exact interval and require the clean
runner exit before releasing the dedicated fixture runtime attachment for the
account broker. These host checks do not establish ART execution. Service guest
validation, Maps startup and Google login remain pending on this runtime pair.
