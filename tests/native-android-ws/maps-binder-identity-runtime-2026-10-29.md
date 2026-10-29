# Maps Binder identity runtime, 2026-10-29

The fresh Binder identity image passed the standalone authenticator API regression
and the standard JSSE TLS-v3 observations on ARM. The account broker then exited
before Maps account testing. This run provides no Maps UI, login, imagery or
account-flow exercise of the Binder identity fix. The Maps export was rejected
by both strict and diagnostic collection; broker-status and exception findings
below are explicitly GUI observations.

Artifacts are relative to `/Users/alex/.local/state/vinix/android` (`S`):

- Prepared image (`P`): `S/maps-binder-identity-r1`.
- Preparation controls (`E`): `S/maps-binder-identity-prepare-2026-10-29-r2`.
- Live clone, now stopped (`VM`): `S/maps-binder-identity-vm-r1`.
- Runtime controls and derivations (`A`): `S/maps-binder-identity-runtime-audit-2026-10-29-r1`.
- Completed fixture transfer (`T`): `S/binder-identity-api-transfer-live-2026-10-29-r1`.

The [stage contract](maps-binder-identity-stage.md) completed preparation with all
50 dependency seals, seven overlay files and 24→25 modules. Clone verification
rechecked 87 files, source/copy/source inventories, and inode kinds, modes and
sizes. Frozen kernel
installation preserved all 25 modules. One 12 GiB, four-CPU VM used default QEMU
user networking, runner `06cdf596adae105d363a99792b732808deb611db72fe4d87af1a5bc8500fb0fd`,
and frozen kernel `a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151`.

| Host phase | Seconds | Peak sampled RSS, bytes | Observed global growth, bytes |
| --- | ---: | ---: | ---: |
| Prepare | 575.680 | 69,599,232 | 1,364,713,472 |
| Clone | 15.798 | 23,969,792 | 32,681,984 |
| Kernel install | 150.992 | 30,474,240 | 952,504,320 |

Each guard and child exited zero with completed cleanup under 600 MiB aggregate RSS,
900 seconds, 4 GiB observed shared-volume growth and a 1 GiB reserve. Global
free-space changes do not isolate producer allocation. Installed boot SHA-256
before guest execution was `80f182023a29097d95ce68fe1a6c87e19c1d94e35e91c7d3923d2b8444985945`.

## ARM fixtures

Both [fixture profiles](binder-identity-fixture-run.md) selected UID/GID 10117 and
the exact framework JAR `3f2e3220d6c38feb885044fdb4806d4d3ca7736352bbcc7813e2ee6510463636`
and native DSO `6a87d8c2fd003c55cb572ab397342d0c39aa54376ffe7a5a2ba2fa4592099eae`.
Each had one exact pass marker, one readiness marker, clean EOF/exit and unchanged
input pins. The authenticator fixture proves synthetic base-API compatibility;
it does not independently drive the broker worker.

The maintained TLS-v3 checker accepted all 14 ordered records for
`mobilemaps.googleapis.com`:

| Observation | Result |
| --- | --- |
| IPv4 TCP and JSSE handshake | Succeeded; handshake step 9 |
| Correct hostname verifier | Accepted, `verified=1` |
| Offline wrong-hostname control | Rejected, `verified=2` |
| IPv6 TCP | Timed out; TLS/verifier phases skipped |
| Normal hostname socket constructor | Succeeded through IPv4 |

No HTTP request was sent. These results do not establish Maps' TLS-factory choice
or tile delivery. Each fixture export used a separate exact UART interval and
unchanged zero-removal diagnostic reconstruction; no strict import was claimed.
All seven derivation/check guards passed. Full proofs and hashes remain in
`A/auth-derivation/validation.md` and `A/network-derivation/validation.md`.

## Broker observations and rejected Maps export

Private capture `VM/identity-broker-failure-private-01.png` displays controller
start/end times 17:33:05/17:33:48 UTC, both trace flags enabled, failed status,
`service_ready=true`, `broker_exit=1`, `cleanup_survivors=0` and empty account-handoff
records. No Maps account action followed. These are manual screen observations,
not fields from an imported Maps receipt.

Captures 01 and 03 show `PrintStream.println` in `Service.onCreate()` and
`Service.attachBaseContext()` within `DiskWriteViolation` stacks. They establish
those logging violations, without proving a unique cause of broker exit.

Strict collection rejected `noncanonical frame whitespace`. The unchanged
zero-removal planner and historical reconstructor also rejected the export.
The metadata audit found a carriage return inside chunk 993's header and an
index jump over chunk 995: 2,813 recognized chunks versus 2,814 declared.
`metadata_ready=false`; no valid Maps archive or imported receipt exists.
No normalization, removal or repair occurred. The complete 2,232,011-byte
after-Maps interval remains pinned by SHA-256
`99a81170ae2d902d9760e2af2c00aebcf1f602437d13cde79f094e72648a00a5`.
Rejected outputs and the classifier's evidence remain in `A`.

## Closure and evidence

The runner requested SIGTERM for owned VM PID 48269 at 17:41:50 UTC and recorded
its absence at the same timestamp. `T/result.json` records all three asset
downloads completed successfully. All runtime and transfer roots were closed
before sealing.

| Artifact | SHA-256 |
| --- | --- |
| `P/sha256.json` | `5140b0afe5ced3c5a17f8566547cd23941d46ae228b75f2ed5ee3ba5cb4f2854` |
| `VM/kernel-patch.json` | `29ac2759a3d5f88ff3272db534b36f00efe77e79f5d4622793d69f0c12e3181d` |
| Authenticator exported receipt | `d4fe58c5265c4551679e98aa3cfc7e3154c88afad073105b1f8a105d1e345f77` |
| TLS-v3 exported receipt | `624a0da9ad33276c69388b68a9d0042274616e2215254199a8499dc7ea999a3d` |
| Rejected Maps metadata audit | `82e06a7213a64b745aec2be510bb8af0c2ebbecd15ccf9c650c7c2c4e8d0dcb9` |

The complete seal covers nine direct roots: `P`, `E`, `VM`, `A`, `T` and the four
original clone sidecars `VM-clone.json`, `VM-clone-tool`, `VM-clone-source.v` and
`VM-clone-sources/`. Regular-file roots preserve their original bytes, modes and
paths. It contains 562 entries at
`S/maps-binder-identity-runtime-sealed-2026-10-29-r1/sealed/manifest.json`, SHA-256
`6557546b8750e259a37d82b8f210ec56aac3709c841189eb96b3d3f9116015dd`.
Seal and independent fresh-process full readback passed after 7.896/3.706 seconds
at 23,986,176/22,937,600 bytes sampled RSS. Both used unchanged 600 MiB RSS,
900-second, 64 MiB global-growth and 1 GiB-reserve guards, with exits 0/0,
completed cleanup and zero swaps. Keep all original roots unchanged; this report
does not replace the complete evidence.
