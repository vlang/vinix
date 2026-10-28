# HTTP transport prerequisite — 2026-10-29

Implementation: `874373858`; extended request coverage: `4b7a72a91`.
The existing NSData loader now shares a bounded HTTP/1.1 exchange with the
future URL session backend. The exchange accepts common request methods,
custom fields and binary bodies, and returns owned response fields/body with
the HTTP status. Repeated response fields remain separate. Redirect responses
are returned to the caller; NSData retains its six-request redirect policy,
2xx requirement and HTTPS downgrade rejection.

The transport uses verified TLS, a shared socket deadline, 16 MiB body and
64 KiB header limits, and at most 128 fields. It rejects conflicting origin or
framing fields and unsupported compression, uploads with transfer coding,
Expect/Upgrade, tunneling and unsupported methods. The existing URL parser's
DNS/IPv4 ASCII profile remains. Resolver timeouts still belong to the platform.
Session scheduling, cancellation, redirect decisions and delegate delivery
remain separate work. **`NSURLSessionDataTask resume` is still unsupported.**

Normal and deterministic ASan/UBSan host runs pass, including native Foundation
comparisons and the existing NSData regression suite. Tests cover binary POST,
65,540-byte uploads spanning TLS records, PUT/PATCH/DELETE, matching mixed-case
framing fields, HEAD/304 without bodies, 404/500 response bodies, informational
responses, chunked framing, repeated Set-Cookie fields, owned result lifetimes,
excessive response fields, invalid requests, redirects, timeout, trusted TLS,
CA/hostname rejection, mutable data and concurrent loads. LeakSanitizer is
disabled. The final runtime cross-compiles to an ARM64 Vinix ELF; generated C
also confirms explicit retirement of the request builder header and buffer.

The persistent 33 MiB archive contains the complete final host results and
cross-build output. A fresh extraction passes byte/type/permission comparisons
for both trees. This is host/build evidence; no guest execution or additional
Fortnite advance is claimed for this transport change. The latest game capture
remains the [task-delegate checkpoint](session-task-delegate-checkpoint-20261029.md):
**4/8 observed launch gates**, with no verified frame, menu, login or match.

```text
Cache: /Users/alex/Library/Caches/vinix-ios
Host: /Volumes/VinixStoreKitObservers20261028/http-transport-host-20261029-r7
Cross-build: /Volumes/VinixStoreKitObservers20261028/http-transport-runtime-20261029-r2
Archive: CACHE/http-transport-host-runtime-20261029-r7.tar.gz
Archive SHA-256:
c86e2da0cd1f5132fd014039e0b01d1f7246c26dd59e83c849dcae35bf735be3
Normal/deterministic host log SHA-256 (same output):
b87faa72d1a22f7b2257d93097b7a38b628d9f1fccb754ceeaa852d9e4afdb09
Cross-built runtime SHA-256:
8e76d6fe948ce913119399eccb21bc9663c43f8356420afbea7f0fb7dbb1b404
Restored: /Volumes/VinixStoreKitQueue20261028/http-transport-restored-20261029-r7
Receipts: CACHE/audio-category-20261027-work/http-transport-*-20261029*.log
```

Reproduce host validation with the frozen runner:
`notification-checks data-http-host FRESH_EXTERNAL_OUT`.
The maintained source is [ns_data_http_test.v](../../compat/ios/runner/ns_data_http_test.v).
Message-body precedence follows [RFC 9112, section 6.3](https://www.rfc-editor.org/rfc/rfc9112.html#section-6.3).
