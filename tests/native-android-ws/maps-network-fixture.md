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
