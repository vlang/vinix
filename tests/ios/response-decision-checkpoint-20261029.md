# Deferred HTTP response decisions — 2026-10-29

Implementation and captured source: `32e4014ce`.

The synchronous HTTP transport now accepts an optional response policy after
validated final headers and before body decoding. The borrowed header view
contains status and separate repeated fields, including Set-Cookie. Interim
headers do not reach the policy. Rejecting the policy retires the exchange;
allowing it cannot extend the original deadline or override cancellation,
even with an empty body or body bytes already buffered beside the headers.
The existing transport entry points use the same implementation with no policy.

An owned response-decision gate supplies a copyable block with the measured
signed 64-bit disposition ABI (`v16@?0q8`). Each promoted block owns the gate
and its embedded descriptor. The gate stores no task, response or worker
pointer, so it can outlive the transfer owner's reference safely. One worker
waits per exchange; condition waits observe cancellation at intervals of at
most 50 ms. Close, timeout and cancellation stop that wait. The first valid
application decision remains observable even after transport closure, while
closure prevents it from restarting body delivery. Pending download/stream
conversion and invalid dispositions fail explicitly. Repeated decisions do
not replace the first choice.

Native Foundation comparisons pin these additional contracts:

- A copied response handler can defer allow/deny; no data or completion is
  delivered before that decision in the fixture.
- Allow delivers the body then successful completion. Deny delivers no body
  and completes with error -999 and completed state (3).
- With a response decision outstanding, cancellation remains in state 2 with
  no body/completion during the fixture's 40 ms observation. Invoking the
  saved handler with allow then completes with -999 and no body.

That last contract distinguishes transport shutdown from public task completion
ordering. The future task adapter must preserve it; this gate does not itself
deliver task callbacks. Native contract timeouts or an unsafe completion-block
ABI failure terminate the fixture process rather than letting a native task
retain callback state on an expired V test stack.

Normal and deterministic ASan/UBSan host runs pass the complete HTTP/TLS suite.
The fresh ARM64 Vinix guest passes the runtime suite with child wait status
zero (4096 MiB RAM, four virtual CPUs). Eighteen new loopback HTTP/TLS cases
cover withheld bodies until the policy runs, deferred allow/deny, close,
cancellation, deadlines, cached body cancellation, empty bodies, final 500
status/body, repeated headers and malformed framing. Gate tests cover copy
identity, descriptor lifetime, cancellation/close wakeup, timeouts, first
choice, 512 competing copied-block calls, late calls after owner release and
two drained runtimes. Four unsupported/invalid disposition controls pass.
Existing framing, redirects, methods, uploads, CA/hostname verification,
entropy and cancellation tests also pass. LeakSanitizer is disabled. All
traffic remains on loopback. The complete ARM64 GLES runtime cross-build passes.

The three complete final evidence trees, driver receipts, generated sources,
binaries, certificates, boot media and source snapshot are preserved in a
persistent 64 MiB archive. Fresh extraction passes all three complete
byte/type/permission comparisons using the maintained V evidence tool.
Original trees and historical Fortnite bundles remain intact. Reproduction
generates new one-day test certificates.

```text
CACHE: /Users/alex/Library/Caches/vinix-ios
Host: /Volumes/VinixTaskDelegate20261029/response-decision-host-20261029-r4
Guest: /Volumes/VinixStoreKitQueue20261028/response-decision-guest-20261029-r2
VM: data-http-30605686250
Runtime: /Volumes/VinixStoreKitQueue20261028/response-decision-runtime-20261029-r1
Archive: CACHE/response-decision-evidence-20261029.tar.gz
Archive SHA-256:
3359d53d3af1fc37a858172e3b8804fc3d9c119c29effba9bd3704ade21f7e8f
Guest source.tar SHA-256:
5b8daa61554c11577ac3becfacf7f907a46cf8f9559419616dfbf718e29a16a0
Guest fixture SHA-256:
cab745400209c7bd261db809cac07ae8a437af523ba5a18a4506a360f184613d
Guest serial SHA-256:
54c0a5179135c42b6aad5f94e7ee667f5b8e953607589e90875a6ac0432dd0ff
Runtime SHA-256:
3044f756c54aa20184207aeff571bb1cd72b889029d6a365c46041cd1f298775
Restored: /Volumes/VinixStoreKitQueue20261028/response-decision-restored-20261029
Receipts: CACHE/audio-category-20261027-work/response-decision-*.log
```

Reproduce with frozen V 0.5.2 (`c6bb06f`), maintained
`notification-checks data-http-host FRESH_HOST`,
`notification-vm data-http FRESH_GUEST` and
`notification-vm build-run-ios-gles FRESH_RUNTIME` under the recorded
check-name/toolchain environment and kernel selection in the driver logs.

Fortnite's last verified blocker remains `-[NSURLSessionDataTask resume]` from
the [task-delegate checkpoint](session-task-delegate-checkpoint-20261029.md).
No new game launch is claimed. The HTTP transport and decision block still
need the task worker, request/response adapters and ordered delegate delivery;
`resume` remains explicitly unsupported. Progress remains **4/8 observed
launch gates (50% of the checklist)**, with no frame, menu, login or match
verified. That fraction does not estimate remaining effort or an ETA.
Advertising remains skipped in the recorded game probe.
