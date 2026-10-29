# Independent URL-session transport workers — 2026-10-29

Implementation and captured source: `63bf5f005`.

A private executor now runs blocking transport work on four dedicated native
threads, with up to 64 queued contexts. It leaves dispatch's callback workers
available while transfers wait for response decisions. Every submission owns
its context through exactly one cleanup, including capacity rejection and
shutdown rejection. Cleanup and run receive autorelease pools; application
cleanup executes outside the runtime and executor locks. The cancellation
cell is borrowed only during run and must not escape into queued callbacks.

Queued cancellation skips run; active cancellation signals the worker's cell.
Retired IDs cannot alias work in a later runtime because the process-wide
sequence never resets. Cleanup outcomes distinguish run returning, run skipped
by cancellation, capacity rejection and runtime shutdown. In particular,
`completed` means the private run function returned; it does not mean a public
NSURLSessionTask completed successfully.

Both native execution teardown and objc_stop now stop these workers before
dispatch teardown. Shutdown signals active work, joins the native threads,
then retires queued contexts without running them. Workers keep ownership of
their own socket teardown; another thread never closes their descriptors.
A process-lifetime native TLS key guards shutdown from run/cleanup, including
synchronous rejection cleanup and autorelease retirement. It stores no image
pointer and is reused across runtimes. Executor storage is freed after joins
and callback-queue teardown. Calls require a live initialized runtime.

Normal and deterministic ASan/UBSan host runs pass. The fresh ARM64 Vinix guest
passes the complete HTTP/TLS runtime suite with child wait status zero
(4096 MiB RAM, four virtual CPUs). New checks cover:

- Four blocked workers, 64 queued contexts, one capacity rejection, queued
  cancellation, one cleanup per context and unlocked cross-thread reentry.
- Autoreleased and explicitly owned objects becoming weak-nil; stale IDs
  rejected across two complete runtime lifetimes.
- Twenty-four loopback HTTP/TLS exchanges across allow, cancel and shutdown
  rounds. Each round fills all four transport workers while response operations
  wait on a suspended NSOperationQueue. Resuming that queue delivers decisions
  without starvation. Cancellation allows the transport context/cell to retire
  before the queued completion block runs. Shutdown joins those contexts first,
  then safely discards the queued response blocks and additional queued work.
- Rejection after executor retirement, zero remaining blocks/ObjC objects and
  weak queue/context ownership after shutdown.
- Three bounded negative controls reject shutdown from run, worker cleanup
  and synchronous rejected cleanup before unsafe joins or retirement.

The existing pre-resume cancellation fixture passes both sanitizer runs with
the new shutdown ordering. All prior HTTP/TLS framing, methods, uploads,
redirects, trust rejection, entropy, cancellation and response-decision cases
also pass. The complete ARM64 GLES runtime cross-build passes. LeakSanitizer
is disabled. All test traffic is loopback; no Epic endpoint or game launch
is exercised. Cancellation is cooperative: native DNS resolution still uses
its platform timeout, so joining arbitrary work is not globally time-bounded.

Four complete final evidence trees, driver receipts, generated sources,
binaries, certificates, boot media and a source snapshot are preserved in a
persistent 91 MiB archive with a checksum sidecar. Fresh extraction passes
all four complete byte/type/permission comparisons using the maintained V
evidence tool. Originals and historical Fortnite bundles remain intact.

```text
CACHE: /Users/alex/Library/Caches/vinix-ios
DRAM: /Volumes/VinixTaskDelegate20261029
QRAM: /Volumes/VinixStoreKitQueue20261028
Host: DRAM/session-workers-host-20261029-r2
Cancellation regression: DRAM/session-workers-cancel-regression-20261029-r1
Guest: QRAM/session-workers-guest-20261029-r1
VM: data-http-29679149666
Runtime: QRAM/session-workers-runtime-20261029-r1
Archive: CACHE/session-workers-evidence-20261029.tar.gz
Archive SHA-256:
1cab3f15661b8c19e605f37d68189a7614b9515cb3a60c621f1b595f623b2939
Guest source.tar SHA-256:
1bb7fb7e9beb71edbd93be721bb4ea113fd94386b10c6c699cbd4ead60640a70
Guest fixture SHA-256:
9302ebeea7b706649adb842d77d60fb78b0b7dd03b80940318df5986c31c9f70
Guest serial SHA-256:
087210955683c9de7714cc0a706ddc649bb44abce1708e7cba3fbb3cf3d384c6
Runtime SHA-256:
9cc4ac8703270df4b2b8538266a62414febef45bed5ede59d4f5dbb34e3de1f2
Restored: QRAM/session-workers-restored-20261029
Receipts: CACHE/audio-category-20261027-work/session-workers-*.log
```

Reproduce using frozen V 0.5.2 (`c6bb06f`) with maintained
`notification-checks data-http-host FRESH_HOST`,
`notification-checks session-cancel-host FRESH_REGRESSION`,
`notification-vm data-http FRESH_GUEST` and
`notification-vm build-run-ios-gles FRESH_RUNTIME`. Use the recorded check-name,
toolchain and kernel environment in the driver logs; fresh runs generate new
one-day certificates.

Public `NSURLSessionDataTask resume` remains explicitly unsupported. Task and
request/response adapters still need to connect this executor, the transport
and ordered delegate delivery. They must preserve the pending-response
cancellation contract in the [response-decision checkpoint](response-decision-checkpoint-20261029.md).
Fortnite's last verified boundary remains `resume` from the
[task-delegate checkpoint](session-task-delegate-checkpoint-20261029.md):
**4/8 observed launch gates (50% of the checklist)**, with no verified frame,
menu, login or match. This is not an effort estimate or ETA. Advertising
remains skipped in the recorded game probe; no fresh game result is claimed.
