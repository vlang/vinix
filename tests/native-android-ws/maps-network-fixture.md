# Real ART network observations

`maps-network-fixture.v` builds a signed `org.vinix.bootstrap/.Main` APK and
checks its finite output. It observes `mobilemaps.googleapis.com:443` through
the actual ART APIs: ordered `InetAddress.getAllByName`, independent timed
`Socket.connect` for each returned address, verified TLS on connected sockets,
and a separate normal `Socket(String, int)` constructor. It sends no HTTP
requests or credentials. These observations do not qualify Maps imagery or
Google authentication.

```sh
maps-network-fixture OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER
maps-network-fixture --self-test
maps-network-fixture --check GUEST_STDOUT_LOG
```

Each phase runs in a daemon worker observed for three seconds. Direct TCP also
sets a three-second connect timeout; TLS sets a three-second read timeout.
The host constructor has no timeout parameter, so its observation deadline
does not prove the underlying constructor stopped. The fixture retains at most
eight addresses, with a 60-second unfinished-process watchdog. After completion,
the Activity remains alive for the existing runner's READY → terminal marker →
stdin close → clean EOF protocol. Process shutdown closes pending workers and
sockets. TLS uses the installed trust manager, existing `VinixSSLSocket` SNI
method and default hostname verifier, with no permissive override.

Public records contain only canonical integers:

```text
MAPS-NETWORK stage=4 index=0 family=4 status=1 error=2 errno=103
```

| Stage | Observation |
| --- | --- |
| 1 | Begin |
| 2 | DNS result; index is retained count |
| 3 | Address family in returned order |
| 4 | Independent direct TCP result |
| 6 | Verified TLS result, or skipped after unsuccessful TCP |
| 5 | Normal host constructor result; family is its successful peer family |
| 9 | Complete; index repeats retained count |
| 8 | Unfinished process watchdog failure |

Families are 0 (unavailable), 4 and 6. Status is 0 (operation returned),
1 (caught throwable), 2 (observation deadline), or 3 (DNS list truncated to
eight / TLS skipped). Error classifications 1–10 are socket timeout, connect,
unknown host, TLS handshake, TLS peer verification, other SSL, other socket,
security, other I/O and other throwable. `errno` is bounded to 0–4095 and found
within at most four cause-chain entries; zero also means unavailable. The
checker JSON calls that field `system_errno`. Throwable text and IP address
strings are excluded from public records.

The exact terminal marker is:

```text
MAPS-NETWORK-PASS observations-complete
```

That marker and a successful checker mean complete observations; individual
operations may have failed. The checker requires exact fields, ranges, ordered
address/TCP/TLS results, matching families, all terminal observations, complete
LF lines and one final marker. It rejects malformed extensions, CRLF, partial
lines, reordering and duplicate markers. Unrelated runtime lines are not copied
to its output.

Host validation on 2026-10-29 passed compilation, parser/reader self-test, signed
APK creation, v1/v2/v3 signature verification, byte-identical DEX roundtrip and
equality between the signed APK member and original DEX. Final source SHA-256:
`98c248f9dbf25f86492bf7a5d21586502aefbfb22b24ae28808d48d8437003d8`.
Artifacts under `/Users/alex/.local/state/vinix/android`:

- `maps-network-fixture-build-2026-10-29-r1`: source/compiler closure, command
  receipts, logs, checker and roundtrip. The initial host `errno` macro build
  failure and superseded lifecycle build remain preserved; final checks use
  `tools/maps-network-fixture-r3`.
- `maps-network-fixture-2026-10-29-r1/probe.apk`, SHA-256
  `f66dfd858b52c1b7da9c2bac635106cc33a956a425860b86527cdc909e88ad43`.

Final compile / self-test / APK build took 3.886 / 0.231 / 1.250 seconds,
with sampled peak aggregate RSS 368,852,992 / 1,245,184 / 86,065,152 bytes.
All guards exited zero with complete cleanup under 600 MiB RSS, 300 seconds,
512 MiB observed shared-volume growth and a 1 GiB reserve. Limits were not
raised. These are host checks; real ART execution remains pending.

Source/report checkpoint `9152d75e3` and both artifact roots are retained in
`maps-network-fixture-evidence-2026-10-29-r1/sealed/manifest.json`, SHA-256
`a1be729ee2de952ec71b86ffbaefd3936d0ae28c01beb9fc44267c8aecd11653`.
The source/compiler closure and copied signing inputs (including the JDK) are
included. Signing inputs matched before/after the build and retained content
matched their originals. Seal and independent complete readback passed for two
roots and 18,207 entries, with zero exit statuses and complete cleanup. The
closed artifact roots must remain unchanged; new guest results belong elsewhere.

## Opt-in TLS substeps v2

The v1 guest observation `status=1,error=10` means an unclassified TLS-probe
throwable. The probe casts the factory result to `VinixSSLSocket` before its
handshake, so that result alone does not establish a transport or handshake
failure. V2 retains those same operations and adds fixed diagnostics:

```sh
maps-network-fixture --tls-diagnostics-v2 OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER
maps-network-fixture --check-v2 GUEST_STDOUT_LOG
```

V2 uses prefix `MAPS-NETWORK-V2 ` with the six original fields followed by
`step=0..9`, and terminal marker
`MAPS-NETWORK-V2-PASS observations-complete`. Step is zero outside TLS and for
skipped TLS; a timeout at step zero means the worker had not entered its first
TLS operation. A positive value identifies the last operation attempted:

| Step | TLS operation |
| --- | --- |
| 1 | Obtain default factory and cast to `SSLSocketFactory` |
| 2 | Wrap the connected plain socket with that factory |
| 3 | Cast the returned socket to `VinixSSLSocket` |
| 4 | Set the existing SNI hostname |
| 5 | Set the read timeout |
| 6 | Start handshake |
| 7 | Obtain session |
| 8 | Obtain default hostname verifier |
| 9 | Verify the fixed hostname |

Additional fixed error values are 11 `ClassCastException`, 12 `NoSuchMethodError`,
13 `NoClassDefFoundError`, 14 `VerifyError`, 15 `UnsupportedOperationException`,
16 `NoSuchMethodException`, 17 `AbstractMethodError` and 18 other `LinkageError`.
The original classifications remain unchanged. No exception message, class-name
string, certificate or address is exported. V2 does not change factory selection,
socket arguments, address policy, trust policy or network requests.

The default v1 emitted Main, NetworkTask and NetworkDeadline sources remain
byte-identical to their pinned originals; the host self-test checks all three
hashes. Its original artifacts and checker remain sealed unchanged. V2 checks
also cover extended-class bounds, malformed steps, pre-start timeout, canonical
complete lines and duplicate markers. Peer review identified the valid timeout
at step zero before signing; that case is now accepted and tested.

The v2 source SHA-256 is
`9a419c4104e5f32c8d81afba895856141cfc5beb7e29a356182e50d790e924a8`.
Under the same external state directory, retained build inputs and checks are
`maps-network-tls-v2-fixture-build-2026-10-29-r1`; its final tool is
`tools/maps-network-fixture-r2`. Signed APK
`maps-network-tls-v2-fixture-2026-10-29-r1/probe.apk` has SHA-256
`abfa8127b920dd7156d3cdee056a98d725411c6b5b2f8cb081149393c0b9c051`.

Compilation, self-test, v1/v2/v3 signature verification and equality of the
signed APK's DEX member passed. The raw DEX roundtrip comparison differed in
encoding; complete canonical disassembly before and after reassembly matched.
Both comparison receipts are preserved, without changing the v1 checks.
Final compile / self-test / APK build took 5.275 / 0.263 / 4.357 seconds with
sampled peak aggregate RSS 372,654,080 / 1,245,184 / 89,702,400 bytes. Their
guards exited zero with complete cleanup under the unchanged limits. V2 ART
execution remains pending; these checks identify no TLS or networking fix.

The v2 source/report checkpoint is `f7d636b40`. Both complete artifact roots,
including source/compiler/signing closure and all comparison receipts, are bound
by `maps-network-tls-v2-fixture-evidence-2026-10-29-r1/sealed/manifest.json`,
SHA-256 `9da362cccb824a80af9162a7413789edd383939c9bcd660c6d0877f5bb520a54`.
The seal and a separate complete readback passed for two roots and 18,208
entries. Closed roots remain immutable; runtime output belongs elsewhere.
