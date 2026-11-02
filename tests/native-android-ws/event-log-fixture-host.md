# EventLog write validation fixture

The API-28 fixture exercises the five public static EventLog.writeEvent overloads
for int, long, float, String and Object[]. It checks primitive-int returns and
varargs metadata on the array overload. Its two application classes are Main
and Poison. It supplies no platform class or replacement logging backend.

Valid payloads must return -ENODEV (-19) on this target, which has no binary event
backend. Earlier preparation failures must retain -EIO (-5), while unsupported
processed items must throw exactly IllegalArgumentException with message
`Invalid payload item type`. A nonnegative discarded-write result would fail.
No event storage, logd persistence, payload readback, readEvents implementation,
cross-process identity, Google task completion or authentication is claimed.

Scalar controls include arbitrary tags, GMS tag `0x31ce5`, integer/long extremes,
64-bit values, float signed zero/NaN/infinities, null/empty/Unicode strings and a
6,000-character string. Array controls accept Integer, Long, Float, String and
null, including a null array, an empty array and a repeated mixed payload. They
reject Boolean, Double, Byte, Short, Character, primitive arrays, nested object
arrays and Poison. Poison.toString throws AssertionError and increments a
counter; the error cannot be mistaken for the expected IllegalArgumentException,
and the final counter must remain zero. Every successful or rejected array call
snapshots and rechecks all caller element references, including ignored items.

A 256-element array puts Poison at index 255 to prove that only the first 255
items are processed. Moving it to 254 must throw; restoring the valid element
must recover the unavailable-backend result. The fixture preserves the caller
array after each call rather than relying on an immediate return alone.

The primary API-28 preparation model starts at position 2 with a 4,064-byte budget.
These are observable status-order controls, not a replacement encoder:

| Payload before an invalid final item | Outcome |
| --- | --- |
| ASCII string 4052 / 4053 followed by Integer or Float | IAE / -EIO |
| ASCII string 4048 / 4049 followed by Long | IAE / -EIO |
| ASCII string 4052 / 4053 followed by empty String | IAE / -EIO |
| ASCII string 4051 / 4052 followed by null | IAE / -EIO |
| Single ASCII string 4057, 4058 or 6000 | -ENODEV |
| Those same strings followed immediately by an invalid item | IAE |
| Those same strings followed by Integer and then an invalid item | -EIO |

Null array elements follow the truncatable literal-NULL string path. Prefix 4051
leaves one truncation byte, so the next invalid item is reached; prefix 4052 leaves
zero and causes an earlier encoding failure. Fixed Long records use a different
boundary. Positive string truncation does not itself stop type validation; a
subsequent failed valid append does. These distinctions were independently
reviewed before any build.

Explicit char[] construction preserves NUL and isolated surrogate code units.
Adjacent boundary pairs test ASCII, two-byte units, three-byte units, NUL as two
bytes, isolated high/low surrogates as three bytes and a valid surrogate pair as
four bytes in the target API-28 ART path. The last case follows the audited
ScopedUtfChars/JNI/String.GetUtfLength/CountUtf8Bytes/Convert chain, rather than
assuming the six-byte strict-JNI description. Each boundary uses later invalid
item reachability to distinguish encoding widths; it does not use getBytes or a
second encoder as its oracle.

The complete primary-source audit is retained outside Git at
`S/gms-event-log-audit-2026-11-02-r1`, with
`S=/Users/alex/.local/state/vinix/android`. It includes the API-28 EventLog Java/JNI
sources, event-list writer and payload-limit header, plus the target ART UTF chain.
The installed host liblog's positive discarded binary writes are not used as a
success backend.

The fixture has no worker thread, runtime path or UID hardcode. All checks execute
before its success marker. The source generators are
`eventlogfixture/main.v` and `eventlogfixture/sources.v`; independent source,
register and exception-flow review passed at hashes
`b2474f232a352a97a31e087a12778583bf6d4b5c0d8992449230276c91761f0c` and
`a4df6bdc2b03c8f767c61badfc0d5cbcd9a0822b0220bf254e4c94682ea7a96d`.

The first host builder and signed production attempts passed. Complete frozen
source/tool closure, fresh error-free API-28 assembly and reassembly, both exact
two-class canonical trees, v3 signing with exactly one signer, minSdk 28 and exact
signed-DEX extraction/readback passed. The immutable build records source revision
`460a026d54191e0a8c5e64fc35ea7022981fe2ec`. Complete evidence remains in external
`S/event-log-fixture-2026-11-02-r1` and
`S/event-log-fixture-controls-2026-11-02-r1`; no historical bundle was changed.

| Qualified artifact | SHA-256 |
| --- | --- |
| Signed probe.apk | `22d733567f05b56fe7b40183c83eea5b680b867771620f9440a14939835c2844` |
| Build receipt | `53a2aa229233bdfc0f58402c1bc4a41ecdd04cb42b3b144663e481f929849efd` |
| Production / signed-extracted DEX | `cc1a72d68c8861e5f7fc985af15a57038b1331799e5864541a8f9c90bd94001e` |
| Roundtrip DEX | `01d19ecc2abcd17fe27e2ec9a12b17c14880b614baf61760d451e1307a75b9a5` |
| Both canonical Main classes | `f0c51403c6569767dd9dec4c8cd06ee071bc562526b8ce09cb94f594ba48cba1` |
| Both canonical Poison classes | `66aeefa2a83f925c5253815c38e4f9ddb0ed196e98a6fc8d44e796882196571d` |

The production and reassembled DEX hashes differ; both complete canonical trees
compare equal. Streaming classes.dex directly from the signed APK reproduces the
production hash. Current and frozen generator sources still match the hashes
above. Runtime framework manifest/build/JAR/DEX were separately rehashed before
and after production: the JAR is
`0a331f5595b4b6c1298dd0e944389cbeabe2b93f6e02e536c4d26d5d200967ad`
from `S/combined-account-webview-event-log-framework-2026-11-02-r1`.

Both guard and child exits were zero, reasons empty and cleanup complete. Compile
took 1.336 seconds, sampled aggregate RSS 306,151,424 bytes, detailed maximum
359,120,896 bytes and observed growth 2,617,344 bytes. Production took 5.935 seconds,
sampled aggregate RSS 105,906,176 bytes, detailed maximum 97,976,320 bytes and
growth 4,288,512 bytes. Detailed logs report zero swaps. Limits stayed 600 MiB
aggregate RSS, 300 seconds, 512 MiB observed growth, 1 GiB reserve, 4 MiB output and
shell file-size cap 16777216. The compiler/Java lane was released immediately after
actual production completion. Host qualification does not establish ART execution;
the signed fixture still requires its first ARM run.

The exact success marker is:

```text
EVENT-LOG-PASS five-overloads public-static varargs null-types prefix-255 encoding-boundaries error-order unchanged-arrays unavailable-backend
```
