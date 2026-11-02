# Messenger Binder request/reply fixture

The signed API-28 fixture exercises actual framework Messenger endpoints,
Message parceling and queued request/reply delivery in one process. It contains
six application classes: Main, ReadyHandlerThread, EndpointHandler,
ReplyHandler, ForcedBinder and ThrowingParcelable. It supplies no platform class
and does not claim cross-process credentials, Google task completion or
authentication.

Two Messengers for one Handler must expose the same cached Binder, compare
equal and use its identity hash. Different Binder identities compare unequal;
null and unrelated objects compare unequal. A Messenger reconstructed from the
local Binder forwards to the real endpoint. Same-Parcel Messenger CREATOR and
static nullable helpers retain the exact strong Binder or null and return typed
Messenger arrays.

ForcedBinder inherits the unchanged framework Binder.transact implementation,
returns null from queryLocalInterface to force the real Messenger proxy, checks
the android.os.IMessenger token, transaction code 1, Message presence 1,
FLAG_ONEWAY and null reply, rewinds the live input Parcel and forwards through
the real endpoint's Binder.transact. This is an instrumented in-process
transport, not evidence of kernel IPC or a remote caller identity.

Three actual request/reply exchanges cover local Handler, local IBinder
constructor and forced proxy paths. The worker checks what 1, both integer
arguments, Parcelable ComponentName, Bundle component/tag strings, replyTo
Binder and sendingUid before returning. Proxy Message/object/Bundle identities
must be distinct copies; local identities must be retained. Replies carry what
3, a result sentinel and sequence, preserved Bundle strings and a checked UID.
The endpoint overwrites forged request/reply UID payloads with the actual Binder
caller UID 10150 before enqueue. These are in-process fixture identity checks.

All queued request/reply Message field and clone assertions run inside callbacks
before CountDownLatch signals. Main reads counters and captured failures after waits, without reading
queue-owned Message fields after dispatch/recycling. The actual Looper/thread
identity proves worker dispatch rather than inline calls on the sender thread.
Wrong tokens must throw SecurityException, unknown transactions return false and
local null sends throw NPE. Queue barriers under the shared deadline check that
these controls did not enqueue callbacks. A throwing transport preserves the
exact RemoteException; a controlled nonforwarding transport returns false and
the API-28 proxy ignores it without retry. Its callback absence is checked after
a barrier and is not a general claim that false transact results prove delivery.

Message controls test constructor/newly obtained pool UID -1, obtain/copyFrom UID
preservation, typed CREATOR arrays, null object/data/reply and exact API-28 wire
order. An independently written payload and a writer-to-manual-reader check cover
what, args, Parcelable presence/object, 64-bit when, Bundle, same-Parcel reply
Binder and claimed UID before Handler overwrites it. Callback/plain-object
payloads and a Parcelable throwing ClassCastException require the exact wrapped
RuntimeException text; an ordinary Parcelable SecurityException keeps identity.
Fresh test Parcels have finally cleanup. No recycled Parcel is inspected or
reused. The proxy's own finally recycling is covered by the coupled framework
source proof, not by undefined recycled-object probes.

ReadyHandlerThread publishes its Looper from onLooperPrepared through a timed
latch. A single eight-second deadline is set before Thread.start. All callback
and barrier waits use its remaining time. The fully constructed thread stays in
a dedicated register outside the protected test range. Cleanup quits the
captured Looper directly, joins for at most one second, checks termination and
preserves the primary exception with suppressed cleanup failures. No fixture
calls HandlerThread.getLooper or HandlerThread.quit. PASS follows cleanup.

Independent source/register/exception-flow review passed. The Message-control
proposal is preserved at `S/messenger-fixture-message-controls-proposal.v`,
SHA-256 `2a9bc03ec1668439570d12524bc41cdcabab14c6cab93e1aa6c9d1e0225c1d7d`.
Integration split overlapping typed/finally ranges and removed direct reads of
a recycled Message; pool reset is checked on a newly obtained object.

The first builder compiled successfully, but strict r1 production rejected
assembler diagnostics for missing long-type L suffixes. No APK was produced.
The complete failed fixture/control roots remain unchanged. Exactly four test
literals gained L suffixes, preserving their intended values, before a fresh
r2 builder and production run passed. No assertion, runtime or compiler limit
was relaxed.
The retained r1 production guard/log hash to
`aec3039fac4d84cbe188a463cbc4bf2e91c166f5ee2f561a410c0945c12324f0` and
`7a41d9f44d5110b1db1efc8b266d0be01a050f2071b3b589fbc0e9631e0e114f`.

Paths use `S=/Users/alex/.local/state/vinix/android`. Complete r1/r2 roots are
`S/messenger-binder-fixture-2026-11-02-r{1,2}` and matching
`S/messenger-binder-fixture-controls-2026-11-02-r{1,2}`. The immutable r2 build
records source revision `147d9c296be9470284a544eecaf5bc80b7adc7bb`, with current
and frozen main.v/sources.v hashes
`7c6b7413346d44ea96b32aa5d40b6c7639abc599039e9f7a4e0aa4ad1e3f7519` and
`27cd0f0663bc97270fcfca1d1e0daa0e9de3963636c14e7bdf49caae3df4773d`.

| Qualified r2 artifact | SHA-256 |
| --- | --- |
| Signed probe.apk | `7295339e8b548f3d48091229eb31319be25bf7394a2091ebce6b26263693729a` |
| Build receipt | `cee3f0da1d4131154d88de8ccff5fdb330b998fd3522ec792a5f4eac1724d973` |
| Production / signed-extracted DEX | `25a57ac6b12604eea53c48300d5f447a144e80bebac50c98f8571f9059b6eaf3` |
| Roundtrip DEX | `d84a1690a55071f0f775b6bd2394a9426f043e5ec8eefc11b0469329acfc8e2d` |
| Both canonical Main classes | `85f96095524a8e84229485833240efc81ac1bb1bfecbec3893642983a53818e9` |

R2 host checks passed exact six-class membership, source/tool input freeze and
final readbacks, API-28 assembly/reassembly, equality of all six canonical classes,
source-bound assertions, v3 signature with one signer, minSdk 28 and exact signed
DEX extraction. The production and roundtrip DEX hashes differ; both canonical
trees compare equal. Host qualification does not establish ART verification or
execution of the assertions; another ARM run is required.

R2 compile/production guard and child exits were zero, reasons empty and cleanup
complete. Compile took 1.330 seconds, sampled RSS 344,817,664 bytes, detailed
maximum 362,512,384 bytes and observed growth 26,890,240 bytes. Production took
6.280 seconds, sampled RSS 88,817,664 bytes, detailed maximum 105,349,120 bytes
and growth 1,810,432 bytes. Both report zero swaps. Limits stayed 600 MiB aggregate
RSS, 300 seconds, 512 MiB observed growth, 1 GiB reserve, 4 MiB output and shell
file cap 16777216. R1 compile/failed production also stayed within these caps,
with full cleanup and zero swaps. The compiler lane was released after r2 actual
completion.

The terminal marker is:

```text
MESSENGER-BINDER-PASS endpoint-identity local-proxy queued-reply token-oneway cloned-payload sending-uid parcel-copy-reset null-errors bounded-worker
```
