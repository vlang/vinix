# Receiver-permission fixture V2 host qualification

The first ARM run of the r2 APK rejected Main before onCreate. Its complete
10,164-byte child log hashes to
`560a7b3fec84caa94e227fb52bbbe529d7b898114e074629691c08f15c07a266`
and is preserved at
`/Users/alex/.local/state/vinix/android/maps-broadcast-permission-runtime-audit-2026-11-02-r1/failed-child-diagnostic/child.log`.
ART reported Main.run offset 0xD1: register v3 had Conflict type where the cleanup
call required DynamicReceiver. The r2 fixture did not execute permission or
callback assertions; the observed failure was not a callback deadlock.

V2 constructs the receiver in scratch register v5, then publishes it to the
dedicated cleanup register v3 only after its constructor returns. Across every
outer catch path, v3 is null or a fully constructed DynamicReceiver. The thread
is fully constructed before the protected range, the registration flag remains
an integer, and cleanup consumes only those stable resources and the caught
Throwable. Metadata mutation/finally remains in its separate method.

The eighth APK class, ReadyHandlerThread, publishes its Looper and signals a latch
from onLooperPrepared. Startup and every callback barrier share the eight-second
deadline set before Thread.start. Startup uses a timed latch wait and the captured
Looper; no fixture class invokes HandlerThread.getLooper. Cleanup quits the
published Looper directly and uses a one-second join, avoiding quit's indirect
unbounded getLooper call. Startup failure can report a still-live thread after
the bounded join; it preserves the original error and does not claim cleanup
success.

All permission assertions from the original fixture remain: actual dynamic and
primary-manifest callback counts/payloads, the fixture-owned requested signature
permission, null/legacy delivery, denied unknown/unrequested/non-signature/tree
cases, fake Context/PackageManager grant controls, null-Intent ordering and public
metadata mutation/restoration. Every denial is checked after a queued handler
barrier. There are fifteen non-null-Intent two-argument delivery cases, three
null-Intent failures and the direct legacy case; cumulative counts finish at
seven per receiver. No private authority set or
platform class stub is supplied. Sender-permission registration, category/data,
export rules and cross-process routing remain outside scope. SDK and native
artifacts are unchanged; this is a fixture successor.

Fresh r3 compile and production passed API-28 assembly, both disassemblies around
reassembly, equality of all eight canonical classes, exact membership, live
reference assertions, compiled manifest declarations, v3 signature and signed
DEX extraction. New guards require receiver publication after construction,
deadline publication before Thread.start, eight classes and no getLooper or
HandlerThread.quit invocation. Original source/tool inputs were rehashed and
match the frozen copies. Independent source, typed-flow and artifact reviews
passed. Host assembly does not establish ART verification or ARM execution;
another ARM run is required.

Compile and production guard/child exits are zero, reasons empty, cleanup complete
and swaps zero under the unchanged 600 MiB aggregate RSS, 300-second, 512 MiB
observed-growth, 1 GiB reserve, 4 MiB output and shell file cap 16777216 limits.
Compile elapsed 1.380 seconds, sampled RSS 322,863,104 bytes and detailed maximum
369,508,352 bytes. Production elapsed 5.994 seconds, sampled RSS 88,719,360 bytes
and detailed maximum 108,429,312 bytes. The compiler/Java lane was released after
actual completion. Earlier closed r1/r2 bundles remain untouched.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Artifact | SHA-256 |
| --- | --- |
| `S/broadcast-permission-fixture-2026-11-02-r3/probe.apk` | `8c6446247e9660eb58c54a166c839abe4e372403620d727fa004bafd847d41a3` |
| Build receipt | `bfee2ae4d948f893bcc0b1c9a92fe3d27a187a5cdbe2718c8510976dd13fe691` |
| Production / signed-extracted DEX | `6047d5f0d0c030a2ddb5f2c02dc2049824231c270fdff11aec9945d7c8056e6f` |
| Canonical roundtrip DEX | `89774bc85f5bb52bea18c61d4c214d82d6d0d66a422617f0f66c71d3676fc460` |
| Both canonical Main classes | `284dbc3dbbded479b7cacd6d953c7e194bb0e39f80c2428e4c0d80679f6706b3` |
| Both canonical ReadyHandlerThread classes | `fa514b04c7a746055deffbb240e0e4fed0d680c44b55bf6ac920e707837150eb` |

Complete inputs/artifacts remain in the r3 fixture root and matching
`broadcast-permission-fixture-controls-2026-11-02-r3`. The immutable build receipt
records source revision `8d9b867939c7a624be5d9c6a6113a1485fe2fb3e`.
Its distinct marker permits additive delivery tooling without relabeling r2:

```text
BROADCAST-PERMISSION-V2-PASS actual-delivery signature-owned null-legacy denied-permissions fake-grants immutable-authority metadata-restored async-barriers bounded-startup
```
