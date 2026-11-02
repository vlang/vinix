# Stable physical display-size fixture host qualification

Host qualification passed on 2026-11-02. ARM execution is pending. This signed,
one-class fixture calls `DisplayManager.getStableDisplaySize()` directly and
requires physical framebuffer dimensions distinct from the app's surface size.
It preserves the existing per-app `Display.getRealSize` and `getRealMetrics`
semantics instead of using them as physical-screen expectations.

The build started at source revision
`824c6e2cad2f1010eb594c1eef4702448370b550`. Exact generator source copies and
hashes are retained in the external receipt:

| Source | SHA-256 |
| --- | --- |
| `stabledisplayfixture/main.v` | `0022d5e4011a7bd92a88ed0fb05a3447a2babd7505f53c9fbb2bf82e0cfa7bf9` |
| `stabledisplayfixture/sources.v` | `f4adcd0ff09972a8bf4b7980491ac34e6e935a583b41646f0d64a337522a0951` |

Complete host evidence is outside Git:

- `/Users/alex/.local/state/vinix/android/stable-display-fixture-2026-11-02-r1/`
- `/Users/alex/.local/state/vinix/android/stable-display-fixture-controls-2026-11-02-r1/`

The signed `probe.apk` SHA-256 is
`e29dc54e644e94a5a0a4040858cdca452ee8ebc83e29052c78e4b91b55e9d13c`.
The `build.json` SHA-256 is
`df67d985a9fe27f6d352b083dfb47e5699a1e7590f9c85b4354e119f982c59a2`.
The production and signed-extracted `classes.dex` SHA-256 is
`39ee46a25a619ad80b2c8ad73f3d9f74e3d2e08b240b8532bb6b7c4b5c0eb1a3`.

The generator reuses the qualified PendingIntent fixture's signed build flow.
It passed error-free API-28 Smali assembly, two canonical DEX/Smali roundtrips,
exact one-class membership, v3 signature verification, package/activity
badging, duplicate ZIP-member rejection, exact single-DEX membership, signed
DEX extraction equality, and final input/tool membership readback. The receipt
preserves all command outputs, tool/input hashes, source/executable copies and
output hashes. Compilation took 1.720 seconds with a 353,320,960-byte reported
peak RSS. Signed production took 6.493 seconds with a 97,583,104-byte peak sampled
aggregate RSS. Both exited zero with complete process cleanup and zero swaps.
The original 600 MiB aggregate RSS, 300-second wall, 512 MiB disk-growth,
1 GiB reserve and 4 MiB output limits and `ulimit -f 16777216` remained enforced.

The builder takes the usual six tool/output arguments followed by four
canonical positive dimensions: physical width/height, then surface width/height.
This build uses `1024 768 64 64`, also recorded as explicit receipt fields. These
are declared fixture expectations. ARM acceptance additionally requires
independent guest framebuffer/QMP evidence for the physical size and runner
configuration evidence for the 64-by-64 surface; host assembly alone establishes
neither physical geometry nor native API functionality.

The runtime probe obtains DisplayManager from real Activity and application
contexts, makes four direct stable-size calls and retains all four returned
Points. It checks all six pairs for reference inequality, verifies configured
physical dimensions, mutates two caller-owned Points to negative sentinels and
checks that other results and later queries retain their values. Existing
real-size/metrics APIs must retain configured surface dimensions before and
after the queries. No global Display fields are changed. All assertions and UI
setup precede the sole success marker:

```text
STABLE-DISPLAY-PASS physical-size window-size fresh-points mutation-isolation
```

The failure marker is `STABLE-DISPLAY-FAIL`; the package and Activity are
`org.vinix.bootstrap` and `org.vinix.bootstrap.Main`. This fixture needs the new
framework declaration and its coupled native library. It does not test
framebuffer absence/invalid metadata, desktop resizing, Google applications,
accounts, network access or authentication. Existing PendingIntent fixture
sources and evidence are unchanged. See the [runner instructions](stable-display-fixture-run.md)
for the separate guest launch and evidence-collection procedure.
