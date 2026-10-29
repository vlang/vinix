# Guest TLS entropy and cancellable transport — 2026-10-29

Implementation and final source: `2e937b7a4`. Native session callback contracts
were added in `59a0c9c9a` and pass again in the final host runs.

The first full guest HTTP suite exposed two entropy failures. The bundled
musl TLS library defaults to `/dev/random`, which Vinix does not expose. The
connection DRBG failed with -52; its replacement OS callback then exposed a
separate library-wide PSA initialization failure (-1). Connections now use the
existing checked, chunked `getentropy` reader. Linux library initialization
configures mbedTLS's documented platform source as `/dev/urandom` before TLS
workers start, covering PSA too. The entropy callback has an explicit 32-bit
C return type. Secure source failures remain failures; CA and hostname
verification remain required. Optional TLS diagnostics report stage, error
and verification flags without request or body contents.

The synchronous exchange now accepts a borrowed atomic cancellation cell.
Its owner must keep that cell alive until return. Cancellable socket waits
poll at most 50 ms per interval; cancellation never closes a descriptor from
another thread. Reads, cached body bytes, writes and TLS handshake retries
observe the cell. Cancelled or partial responses return failure. DNS resolution
still uses its platform timeout and cannot be interrupted by this cell.

Normal and deterministic ASan/UBSan host runs pass with diagnostics enabled.
The fresh ARM64 Vinix guest passes the complete HTTP suite with child wait
status zero. It verifies trusted TLS, hostname/CA rejection (flags 4 and 8),
close-notify, downgrade rejection, framing, redirects, binary/mutable data,
concurrent loads, methods, status bodies and header bounds. Eleven in-flight
cancellation cases cover HTTP/TLS stalled headers, fixed-length, EOF and
chunked partial bodies, 16 MiB uploads, and a stalled TLS handshake. They
return before the fixture's delayed peer completion; a pre-cancelled exchange
also fails immediately. A 513-byte OS entropy fill preserves both canaries
and invalid buffer requests fail. LeakSanitizer is disabled.

Native Foundation tests pin per-selector task/session delegate fallback for
response, data and completion callbacks on the supplied operation queue.
A completion-only task delegate leaves response/data delivery with the session
delegate. Cancellation before resume delivers error -999 with task state 3.
These native contracts do not implement the corresponding Vinix task methods.

The complete runtime cross-build passes. A persistent 64 MiB archive preserves
the final host, guest and runtime build trees, source snapshot, commands,
generated sources, binaries, certificates and boot media. Fresh extraction
passes complete byte/type/permission comparisons for all three trees. Earlier
failed attempts remain separate and are not qualification evidence. Certificates
are one-day loopback fixtures; reproducing a run generates fresh ones.

```text
Cache: /Users/alex/Library/Caches/vinix-ios
Host: /Volumes/VinixStoreKitObservers20261028/http-transport-control-20261029-r6
Guest: /Volumes/VinixStoreKitQueue20261028/http-control-guest-20261029-r6
VM: data-http-34410953666 (4096 MiB, four virtual CPUs)
Runtime: /Volumes/VinixStoreKitQueue20261028/http-control-runtime-20261029-r1
Archive: CACHE/http-control-evidence-20261029.tar.gz
Archive SHA-256:
d00e76581ded2cdf04653b90f1008820e6d0b09cb53a9d7a8a564d003eff15b1
Guest source.tar SHA-256:
4a0240cce62265bac07dcedc5312d25ee35a477b7b70ab77937a4339870b9b9d
Guest fixture SHA-256:
1d31b8b6e287a68cdbab313fd6ba165cee40f1b416331803b7f66436e6f74fe8
Guest serial SHA-256:
64052dccbd8bff289fefd218eb2fbbebe13c055f50d1eb71ba9c2203112cc0fc
Cross-built runtime SHA-256:
6dd624dcd9a5e637097b7fc254059ec5dddc6fbe231224cfcb4b6d9349ba24aa
Restored: /Volumes/VinixStoreKitQueue20261028/http-control-restored-20261029
Receipts: CACHE/audio-category-20261027-work/http-*-20261029*.log
```

Reproduce with frozen `notification-checks data-http-host FRESH_HOST` and
`notification-vm data-http FRESH_GUEST` under the recorded check-name/toolchain
environment. The guest runner stages a fresh test certificate and loopback
hosts entry. All network test traffic stays on loopback.

Fortnite's last observed blocker remains **`-[NSURLSessionDataTask resume]`**.
Task workers, response decisions, error conversion and callback delivery still
need integration. No new game capture or external Epic networking is claimed.
Progress remains **4/8 observed gates**, with no verified frame, menu, login
or match. Earlier evidence: [queue executor](operation-queue-checkpoint-20261029.md),
[transport](http-transport-checkpoint-20261029.md), and
[last game capture](session-task-delegate-checkpoint-20261029.md).
