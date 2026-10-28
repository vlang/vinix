# URL-session task diagnostic checkpoint — 2026-10-29

Diagnostic implementation: `6f52af314`; captured runtime/source: `58fa460c0`.
Unsupported task operations now identify their Objective-C class and selector.
This adds diagnostics; task transfers and lifecycle operations remain unsupported.

The native and runtime data-task and existing task suites pass normal and
deterministic ASan/UBSan runs. All 47 guest fixtures pass. The unchanged
historical auditor, supplemental StoreKit/data-task media checks and 339
negative controls pass. The complete bundle is retained on persistent storage;
archive restoration and deletion qualification are not claimed.

This launch stops at a different startup path:

```text
iOS: unimplemented Objective-C method NSURL getResourceValue:forKey:error:
```

It does not identify the preceding capture's unsupported task selector and
does not establish that task resume works. Application exit is 1; capture exit
is 0. All six application budget event counters are zero; final usage is
439,192 bytes. The desktop records 12 builds and 11 polls, with no supervisor
kill. Advertising remains skipped.

Progress remains **4/8 observable launch gates (50% of the checklist, not an
effort estimate or ETA)**. Loading/binding, `+load`, initialization and entry
are verified. Frame, menu, login and playable match remain unverified; audio
output and Metal execution/presentation still require backends.

```text
Persistent cache: /Users/alex/Library/Caches/vinix-ios
Complete bundle: session-task-diagnostic-20261029
VM state: probe-no-ads-132916
Manifest SHA-256:
e67da9463bf18904c0d0d96f08dcd81d25b0e8a15000eb25519ab69a2550f84a
Runtime SHA-256:
3cee72033eaf2c5aa09dee16b8607b7883c0b0b570577c06fed8a46b1ed2da53
Serial SHA-256:
813861965a6ffb2e1623f24e13657f70b4bd724799ab1e38a6b175e63ef1ffd7
Receipts: audio-category-20261027-work/session-task-diagnostic-*.log
Additional saved task host suite: diagnostic-base-host/
```

Run `BUNDLE/storekit-operation-probe check-queue ABSOLUTE_BUNDLE
FRESH_EXTERNAL_SCRATCH` from the repository. Keep the complete bundle at its
recorded path. The [data-task checkpoint](session-data-task-checkpoint-20261029.md)
records earlier host, reused fixture and toolchain provenance and limitations.
