# Owned URL-session request and response adapters — 2026-10-29

Implementation and captured source: `a9411ed7d`.

Private adapters now turn a request/configuration into owned transport bytes
and a borrowed HTTP response into an owned NSHTTPURLResponse. Request method,
URL, main-document URL, headers and binary body survive later source mutation,
pool drains and complete Objective-C runtime teardown. Configuration headers
merge case-insensitively, with request fields taking precedence. Captures
require live inputs and exclusion of concurrent source mutation; concurrent
readers of unchanged inputs are supported.

The snapshot records request and configuration policies independently. Its
single-exchange profile reports unsupported protocols, background settings,
proxies, cookies/stores, cache policy, network restrictions, TLS bounds and
timeouts explicitly. Default configurations remain unresolved; this does not
implement shared stores or silently disable their policies. Non-ASCII request
header bytes are preserved but rejected by the transport profile until their
NSString-to-wire mapping is characterized. Task-level policy enforcement and
typed transport-error mapping still need integration.

Response properties join repeated fields with comma-space, including cookies
and authentication fields, and decode wire octets as Latin-1. Both behaviors
are checked against native Foundation over loopback. Raw transport fields stay
separate for future policy processing. Headers and body bytes are frozen before
Objective-C allocation so reentrant constructors cannot invalidate their input.
The NSData adapter adopts its copied buffer. Partial captures and failed
constructions retire their owned storage; malformed or oversized response
fields never produce a partial successful response.

The complete HTTP/TLS suite passes normal and deterministic ASan/UBSan host
runs, the fresh ARM64 Vinix guest (4096 MiB, four virtual CPUs, child wait zero),
and the full ARM64 GLES runtime cross-build. Added checks cover:

- Native configured-session header merging and a binary POST, plus native
  response-field, MIME, encoding and HTTP 500 comparisons.
- 512 snapshots across eight reader threads and two runtime lifetimes; mutation
  of aliased header strings, method, URL, configuration and body after capture;
  weak owners becoming nil; real transfers after the source runtime stops.
- HTTP and trusted TLS response ownership after all parser storage is disposed,
  repeated cookie/authentication fields, non-ASCII octets and drained pools.
- Constructor reentry from another thread, bounded lock checks, caller URL
  retirement, frozen header/body bytes and construction failure cleanup.
- Unsupported policy profiles, nil/uninitialized requests, malformed fields,
  conflicting framing, oversized bodies, invalid final statuses and decoded
  header-size/count bounds. Runtime object counts return to zero.

All previous framing, TLS trust rejection, cancellation, response-decision and
worker shutdown checks also pass. LeakSanitizer is disabled. Traffic is entirely
loopback; no Epic endpoint or fresh Fortnite launch is exercised.

Three complete final evidence trees, driver receipts, generated sources,
binaries, certificates, boot media and a source snapshot are preserved in a
65 MiB persistent archive with a checksum sidecar. Fresh extraction passes all
three complete byte/type/permission comparisons using the maintained V evidence
tool. Originals and historical Fortnite bundles remain intact.

```text
CACHE: /Users/alex/Library/Caches/vinix-ios
DRAM: /Volumes/VinixTaskDelegate20261029
QRAM: /Volumes/VinixStoreKitQueue20261028
Host: DRAM/session-adapters-host-20261029-r8
Guest: QRAM/session-adapters-guest-20261029-r2
VM: data-http-31995964916
Runtime: QRAM/session-adapters-runtime-20261029-r2
Archive: CACHE/session-adapters-evidence-20261029.tar.gz
Archive SHA-256:
01af6129b77d77e03946dfea3f3ebe501147a8560266af835ac90210baec19b2
Guest source.tar SHA-256:
7a3130d1f9fb1c54ba567f1ce4eeac907bb8096a15db7c0170c34ec9508c82dc
Guest fixture SHA-256:
ea799a6127d4ab2520ed83e76d5f05d12adbc3544dc7b1d53415c158304f511a
Guest serial SHA-256:
2243e6b79ff068464110c41b70cc6aa44c648008d515c6b7a4f97e00fdd4d629
Runtime SHA-256:
b72edc42d66bea2addef3257c5e42dc79951b5ed97b11996914a90e49eb5f5ca
Restored: QRAM/session-adapters-restored-20261029
Receipts: CACHE/audio-category-20261027-work/session-adapters-*.log
```

Reproduce with frozen V 0.5.2 (`c6bb06f`), maintained
`notification-checks data-http-host FRESH_HOST`,
`notification-vm data-http FRESH_GUEST` and
`notification-vm build-run-ios-gles FRESH_RUNTIME`. The driver receipts record
the toolchain, kernel and check-name environment; fresh runs generate new
one-day certificates.

Public `NSURLSessionDataTask resume` remains explicitly unsupported. The next
step connects task lifecycle, these adapters, the
[transport workers](session-workers-checkpoint-20261029.md) and ordered delegate
delivery while preserving the
[pending-response cancellation contract](response-decision-checkpoint-20261029.md).
Fortnite's last verified boundary is still `resume` from the
[task-delegate checkpoint](session-task-delegate-checkpoint-20261029.md):
**4/8 observed launch gates (50% of the checklist)**. No frame, menu, login or
match is verified. This fraction is not an effort estimate or ETA. Advertising
remains skipped in the recorded game probe.
