# URLSession timeout checkpoint — 2026-11-04

`72a68afe3e768707f40caee60952ad16fc89058a` implements request timeout
precedence and separate inactivity/resource clocks. An unset request timeout,
including initialization with the default 60 seconds, inherits the session's
configuration. An explicit setter overrides it even when setting 60. Copies
preserve that distinction without rewriting public request getters.

HTTP and TLS progress rearm the inactivity clock while the resource deadline
stays fixed. The TLS BIO uses its documented opaque context to carry the stream
clock. The native model separates waiting for additional data from the total
resource limit: [request timeout](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/timeoutintervalforrequest),
[resource timeout](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/timeoutintervalforresource).
Supported intervals are 1 ns–24 hours for inactivity and 1 ns–7 days for the
resource. DNS retains the resolver's platform timeout.

While a response handler is deferred, the worker can receive the bounded body;
data and terminal callbacks remain gated on the handler. Network errors and the
resource limit cannot be revived by a late allow, and cancellation/denial takes
precedence. An inactivity timer cannot falsely expire a body already received.
The first decision is published before terminal work can be queued. Existing
full-body batching and the 16 MiB response bound remain in effect.

The complete HTTP fixture passes normal and deterministic ASan/UBSan runs.
Each host execution compares 18 native cases and exercises 42 runtime loads
across two drained runtimes. The ARM64 guest passes all 42 timeout loads,
including HTTP/TLS progress, stalls, resource caps, delayed response decisions,
cancellation, initializer/setter differences, copies, later input mutation,
public getters and zero live objects/blocks. Request and StoreKit regression
fixtures also pass both sanitized runs. Native subsecond resource timers can
coalesce, so the deferred-resource case holds the handler for two seconds.

The new Fortnite capture passes startup inspection and 46 game-probe fixtures
(45 reused and one freshly built StoreKit fixture). It passes the timeout
blocker and now stops at:

```text
V panic: iOS: unimplemented Objective-C method FIOSView setClearsContextBeforeDrawing:
```

Original cooked content is retained, advertising is skipped, and the launch uses
an 8192 MiB guest, one CPU, a 2 GiB application budget and a 60-second desktop
observation window. The application exits before controlled close. The peer
records 22 builds, 21 polls, one node, zero images, closed=false,
supervisor_kill=false and wait=256. All six budget event counters are zero.
Application exit is 1; capture exit is 0. Final budget charge is 439192 bytes
after exit, not peak footprint. All 339 auditor corruption controls pass.
The unchanged saved auditor passes seal and independent check, including
resource and guest-binary comparisons. The supplemental StoreKit media check
passes. The complete typed inventory passes independent verification.

Progress remains four of eight observed launch gates: loading/binding, +load,
initializers and application entry. There is no verified frame, menu, login or
playable match, and this fraction is not an estimate of engineering effort.
The Metal device factory still returns nil, with no command-buffer/AIR execution
backend. The next observed runtime work is UIView's clearsContextBeforeDrawing
property. The pinned dictionary-checkpoint kernel is used; concurrent kernel
changes are outside this validation.

```text
CACHE: /Users/alex/Library/Caches/vinix-ios
WORK: CACHE/audio-category-20261027-work
Focused bundle: CACHE/session-timeout-validation-20261104-r5
Source: 72a68afe3e768707f40caee60952ad16fc89058a
Focused source tar SHA-256: a6a5deced8b2840a8b60b64560dbfe284b37dfc9e49f6545f77d5f2f60d7835e
Focused receipt: CACHE/session-timeout-validation-20261104-r5.inventory.json
Focused receipt SHA-256: 0cc1c17270fa8f83ce8ab12b81315371359900e1067b20cb0875c6ef56267e88
Capture: CACHE/session-timeout-probe-20261104-r1
VM state: probe-no-ads-132916
Manifest SHA-256: 272fdf4cd4b62706587afa6b59caed45fd3f98c7f23370da2f95368cf740c3f2
Capture receipt: CACHE/session-timeout-probe-20261104-r1.inventory.json
Capture receipt SHA-256: b5c0ea80e54a52e1829fa3a9e4dc773e3b798179f4690492cf000ecd8a7660e0
Runtime SHA-256: 5d8693dd69fab3a487e1c82f46e98ec15b822e05a2fc2bb8beded8d445b2f883
Serial SHA-256: b68500cb4f1e36d7e25d1428a819d4de18e83c4f9f46081f1e2e1c770d47e938
Prior: CACHE/dictionary-variadic-20261028
Prior manifest SHA-256: c1163dfbb2bf9b0f096eba6123246028b00a43902ebd9963b115909b999e3dbb
```

Both complete bundles remain expanded outside Git in persistent storage.
The focused bundle passes independent typed-inventory verification. Historical
checkers require complete evidence; no historical validator was relaxed.
