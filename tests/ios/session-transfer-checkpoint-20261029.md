# Bounded URL-session data-task resume — 2026-10-29

Implementation and captured source: `844a4b334`.

Session-created NSURLSessionDataTask objects now implement public `resume`
(`v16@0:8`) for the supported HTTP(S) request profile. Transfers use the owned
request/response adapters and independent transport workers. Response, data
and terminal callbacks run in order on the supplied delegate queue, with
per-selector fallback from task delegate to session delegate. HTTP 500 bodies
remain successful HTTP responses rather than fabricated transport errors.

Repeated resume/cancel calls are idempotent. Cancellation signals the owned
worker; no queued callback borrows its cancellation cell or exchange context.
An owned response-decision observation preserves Foundation's pending-handler
contract: the worker can retire after cancellation while public completion
still waits for the handler. Late decisions cannot revive body delivery.
Terminal error/state publication excludes a racing cancellation, including one
from an NSError constructor. Task delegates retire after completion; later
assignments are not cleared again during operation cleanup.

Upload and decoded-body counters now update their native backing fields
atomically, including partial bytes retained after framing errors. Shutdown
joins transports, discards callback operations and disconnects pending
observations before object/image teardown. Cleanup and final retirement have
autorelease pools. Generated C inspection caught and removed an escaping
exchange-context allocation; the final context has explicit allocation/free.

The complete HTTP/TLS suite passes normal and deterministic ASan/UBSan host
runs and a fresh ARM64 Vinix guest (4096 MiB, four virtual CPUs, child wait
zero). Added lifecycle tests perform 35 loopback exchanges per run, covering:

- Typed/public resume metadata, binary GET/POST bodies, HTTP 500 and trusted
  TLS, response/data/completion order and per-selector delegate fallback.
- Eight concurrent callers, repeated resume/cancel, mutation of the source
  and current requests after capture, and two complete runtime lifetimes.
- Deferred allow/deny, cancellation while a handler is pending, worker
  retirement before its late invocation, duplicate handler calls and
  cancellation inside data callbacks and NSData/NSError constructors.
- Nil delegates, trust rejection, timeout and malformed responses; partial
  receive counters and completed uploads surviving a later response error.
- Shutdown with queued response, copied pending handler and queued terminal
  work; weak owners, blocks and transfer storage retiring without callbacks.

Fresh base-task, data-task, pre-resume cancellation and StoreKit host regressions
pass both sanitizer runs. Resume metadata and explicit rejection expectations
were updated deliberately; suspension and unconfigured base-task transfers
remain unsupported. The complete ARM64 GLES runtime build passes. LeakSanitizer
is disabled. Focused transfer tests use loopback; public resume always uses
`/etc/ssl/cert.pem`, with a private fixture helper for the local test CA.

This remains a bounded, buffered backend. Default/custom protocol selection,
shared cookie/cache policy, proxies, authentication challenges, redirects,
distinct request/configuration timeout policy, suspension, conversion and
session invalidation are still explicit unsupported boundaries. Exact DNS,
socket and framing diagnoses are not invented: unknown transport causes use
NSURLErrorUnknown, while cancellation, timeout and TLS failure have their known
codes. Native DNS cancellation still waits for the platform resolver timeout.

A fresh Fortnite probe used the original cooked content, advertising skipped,
8192 MiB guest RAM, one virtual CPU, the retained 2 GiB process budget and
desktop guards. Its 45 inherited fixtures passed; these are separate from the
newly compiled transfer guest above. The game enters the new resume
implementation and stops at:

```text
V panic: iOS: URL session request transport profile is not implemented: protocols
```

All six budget event counters are zero. The desktop handshake succeeds with
13 builds, 12 polls and no supervisor kill. App exit is 1; capture/check exit
is 0. The unchanged complete auditor passes seal/check and all 339 corruption
controls. The game still verifies **4/8 launch gates (50% of the checklist)**:
loading/binding, +load, initializers and application entry. No game frame,
menu, login or match is verified. This fraction is not an effort estimate.

Seven complete standalone evidence trees are preserved in a 171 MiB persistent
archive. Fresh extraction passes all seven full byte/type/permission
comparisons. The complete game capture is preserved in a separate 2.0 GiB
version-3 delta archive against the pinned persistent dictionary checkpoint.
It passes archive verification, complete reconstruction and comparison, and
its unchanged saved auditor at the original recorded path. The restored tree
was then retained separately; a further complete comparison passes after the
original bundle and persistent archive are returned to their recorded paths.
No historical checker was changed or weakened, and all originals remain.

```text
CACHE: /Users/alex/Library/Caches/vinix-ios
WORK: CACHE/audio-category-20261027-work
DRAM: /Volumes/VinixTaskDelegate20261029
QRAM: /Volumes/VinixStoreKitQueue20261028
RAM: /Volumes/VinixSessionTransfer20261029
Host: DRAM/session-transfer-host-20261029-r8
Regressions: DRAM/session-transfer-{base,data,cancel}-regression-20261029-r3
StoreKit host: DRAM/session-transfer-storekit-host-20261029-r3
Guest: QRAM/session-transfer-guest-20261029-r2/data-http-38094793250
Runtime: QRAM/session-transfer-runtime-20261029-r2
Standalone archive: CACHE/session-transfer-evidence-20261029.tar.gz
SHA-256: c71aa1fa84c2c5e4af9b720a7b1c0d561e24e78cf3ea0f3a17f37c53af0692ee
Standalone restored: RAM/standalone-restored
Game capture: CACHE/session-transfer-probe-20261029
Game VM: probe-no-ads-132916
Game manifest SHA-256: cfe4ee4200b30ff5427a77fbd8c4862ae6f2a4aa47f8b79420132cdafabdaf72
Game serial SHA-256: bdee0fb3f1865c05f902cfee636ddba39307455e5e1e3647acc32c6d28d253f6
Runtime SHA-256 (standalone and game): 20ee1e7d52f6e40363854600632d306f8ebc57ab37d25e11159ac8b3498c227d
Game archive: CACHE/session-transfer-probe-20261029-archive
Archive inventory SHA-256: 4aa793ff5d8a0a36506e9bf3da94e87ba2b4e36616640b7700b0617dd3c1c8fb
Prior: CACHE/dictionary-variadic-20261028
Prior manifest SHA-256: c1163dfbb2bf9b0f096eba6123246028b00a43902ebd9963b115909b999e3dbb
Game restored: RAM/probe-restored
Receipts: WORK/session-transfer-*.log
```

Reproduce with frozen V 0.5.2 (`c6bb06f`) and maintained
`notification-checks data-http-host`, the task/data-task/cancellation/StoreKit
host modes, and `notification-vm data-http` / `build-run-ios-gles`, each with
fresh external output. The receipts record the kernel/toolchain environment
and commands. Fresh tests generate new one-day certificates. The full capture
uses `storekit-operation-probe COMPLETE_PARENT FRESH_OUT FRESH_STOREKIT_HOST`
with the recorded pinned parent, followed by the saved auditor's seal/check
and negative-controls modes. Build evidence helpers with `-cflags -O2`.

The next observed startup boundary is session protocol-profile support; it
must be implemented without silently discarding the remaining session policies.
