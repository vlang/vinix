# Session-cookie transport checkpoint — 2026-11-04

`729b53ccb86de9a31566b91d7e9c864051f3e5a8` implements automatic host-only
session cookies for the built-in NSURLSession HTTP(S) backend. The private
process-lifetime store owns plain bytes, shares cookies between default
sessions, and retires only after workers and callbacks stop. Selection handles
host isolation, default/explicit paths, Secure filtering and HttpOnly network
use. Replacement preserves creation order; nonpositive Max-Age deletes a key.
An explicit Cookie header wins, and disabled automatic handling suppresses
both sending and storage. Path selection and ordering follow
[RFC 6265](https://www.rfc-editor.org/rfc/rfc6265#section-5).

The store is bounded to 1024 records and 4096 bytes per response cookie.
Persistent cookies, Domain attributes, quoted/extended syntax, SameSite and
other unimplemented attributes fail explicitly. Partitioning, nondefault
acceptance policies and explicit main-document policy remain unsupported.
Public/custom cookie-storage APIs and ephemeral configurations remain
unsupported; the native oracle uses isolated ephemeral storage for comparison.

The complete HTTP fixture passes normal and deterministic ASan/UBSan runs,
native Foundation comparisons, and the ARM64 guest (4096 MiB, four CPUs,
child wait status 0). Each execution exercises 24 automatic-cookie runtime
loads across two drained runtimes; host runs also exercise 12 native loads.
Tests cover replacement/deletion, empty values, host/path boundaries, manual
override, copied policies, ordered callbacks, concurrent store/read/delete,
and public-load rejection of unsupported response cookies. Both sanitized
request and StoreKit regression runs pass. The final loopback fixture uses
lowercase localhost after an initial uppercase-LOCALHOST guest failure;
case-insensitive cookie matching is checked separately. No resolver fix is
included.

The first game capture is retained as rejected evidence. Following critically
low host disk space, its standalone runtime differs from the frozen build hash
and its serial lacks fixture markers. The saved auditor rejects it. The
preparation copy still matches the recorded runtime hash. A complete typed
inventory and independent inventory check preserve the failed capture; no
historical check was relaxed or failed evidence repaired in place.

The fresh capture passes startup inspection and all 46 game-probe fixtures.
Fortnite gets past request-profile validation and stops at:

```text
V panic: iOS: URL session distinct request/configuration timeouts are not implemented
```

The stopped task has not reached worker dispatch. Actual cookie exchange is
verified by the focused fixtures. Original cooked content is retained, with
advertising skipped, a 60-second desktop observation window, an 8192 MiB guest,
one CPU and a 2 GiB application budget. The peer records 17 builds, 16 polls,
one node, zero images, closed=false and supervisor_kill=false. All six budget
event counters are zero. Application exit is 1; capture exit is 0. The final
budget charge (377604 bytes) is measured after exit and is not peak footprint.
All 339 saved-auditor corruption controls pass. The unchanged saved auditor
passes seal and independent check, including complete resource/guest-binary
comparisons; the supplemental fresh StoreKit media check also passes. The
sealed capture passes an independent check against its complete typed receipt.
The next work is native characterization and implementation of request versus
configuration timeout policy; the unequal values are not recorded by this panic.

Observed progress remains four of eight launch gates (load/bind, +load,
initializers and application entry). This count does not measure remaining
engineering effort. A frame, menu, login and playable match remain unverified.
The Metal device factory still returns nil; no command-buffer/AIR execution
backend exists. Advertising remains skipped. The probes use the dictionary
checkpoint's pinned kernel and do not validate concurrent kernel changes.

```text
CACHE: /Users/alex/Library/Caches/vinix-ios
WORK: CACHE/audio-category-20261027-work
Focused bundle: CACHE/session-cookies-evidence-20261104
Focused source: 729b53ccb86de9a31566b91d7e9c864051f3e5a8
Source tar SHA-256: 7735e5da8051c5fd82b250f26741d05b57ee02a3b56764b2ec0a79fc61acd44a
Typed receipt: CACHE/session-cookies-evidence-20261104.inventory.json
Receipt SHA-256: d69306af527f730966d3622b1b7874b822f3fb4ef5beed23442cfabe87ee93db
Failed capture: CACHE/session-cookies-probe-20261104-r1
Failed typed receipt: CACHE/session-cookies-probe-20261104-r1.inventory.json
Failed receipt SHA-256: 744c750f1b5c0b5b6a6f01e8533c7fd2ac20b5ab303e59c230415d071f768e67
Fresh capture: CACHE/session-cookies-probe-20261104-r2
Capture source: 6ba379aa97cf7ada6820e40f1737194f473246ad
Manifest SHA-256: 70d5dd487a19b819e6c580a2dad707a76813d272a5cf8d6b4ade5c679e4de47b
Fresh typed receipt: CACHE/session-cookies-probe-20261104-r2.inventory.json
Fresh receipt SHA-256: 2422d1d4e962012ff17d2a16c5de8fb60370747286d35e4f29ece94157772dfa
Runtime SHA-256: 45f434c0144350ff26105ddd2108957fd260a083599731d46cd50eff6dd9e55b
Serial SHA-256: 3de88c479729922cffc84c4d63d22ff7b30ba20bfc8a178e89b710d5063e68e2
Capture source tar SHA-256: a1518183ef74b6e89fb456b887f7d577aad33b113103758928044df93f050c09
Superseded focused attempts: CACHE/session-cookies-superseded-20261104.tar.gz
Archive SHA-256: dadf2b89d057c73048be51bc5accec3108dd01eb73ab826cfc4503722baa3d19
Prior: CACHE/dictionary-variadic-20261028
Prior manifest SHA-256: c1163dfbb2bf9b0f096eba6123246028b00a43902ebd9963b115909b999e3dbb
```

The superseded focused archive passed fresh extraction and complete byte/type/
mode comparisons before those expanded attempts were retired. The current
focused bundle and both game captures remain expanded in persistent storage.
The temporary audit RAM disk was detached. Historical auditors still require
their complete bundles.
