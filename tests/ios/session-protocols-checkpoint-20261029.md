# Built-in URL-session protocol routing — 2026-10-29

Implementation and captured source: `b407513e7`; selector-query race fix:
`8b414d958`.

NSURLSession data tasks now select the built-in HTTP(S) backend with an
untouched default configuration or an explicit nil/empty `protocolClasses`
list. Native Foundation loopback tests establish that all three retain
built-in HTTP handling. Routing preserves the configuration copy and does not
manufacture private Foundation protocol class identities. The default
`protocolClasses` getter remains explicitly unsupported. Nonempty custom
lists and the remaining unsupported transport policies still fail explicitly.

The complete HTTP/TLS suite passes normal and deterministic ASan/UBSan host
runs and a fresh ARM64 Vinix guest (4096 MiB, four virtual CPUs, child wait
zero). New coverage performs 18 runtime loads across two drained runtimes:
default/nil/empty lists with HTTP, trusted HTTPS and rejected HTTPS. It checks
ordered response/data/completion callbacks, body bytes, terminal state/error,
unchanged configuration ownership and complete object/block retirement. Three
fork controls use public `resume` to reject custom protocols, cookies and cache
before connecting; clearing the original custom list cannot alter the session
copy. TLS fixture trust is private to tests; production uses `/etc/ssl/cert.pem`.

Required StoreKit regression testing exposed an ASan use-after-free in
`objc_responds`: another thread could grow the object table during its unlocked
capability-flag lookup. The fix snapshots those flags under the existing
object-table lock and releases it before selector discovery or other locks.
The final StoreKit suite passes both sanitizer runs. A new regression races
four capability readers with two allocation-table writers across two drained
runtimes; the existing eight-writer observer test also passes. The pre-fix
deterministic failure is retained separately as failure evidence. This does
not establish safety for every runtime concurrency path. LeakSanitizer is
disabled. The complete ARM64 GLES runtime build passes.

A fresh Fortnite probe used original cooked content, advertising skipped,
8192 MiB guest RAM, one virtual CPU, the retained 2 GiB process budget and
desktop guards. All 46 guest fixtures pass, including the freshly rebuilt
StoreKit fixture and selector-growth regression. These are separate from the
new HTTP/TLS guest suite above. The game passes the protocol-profile boundary
and stops at:

```text
V panic: iOS: URL session request transport profile is not implemented: cookies
```

The game's six budget event counters are zero. Desktop handshake succeeds with
13 builds, 12 polls and no supervisor kill. App exit is 1; capture exit is 0.
The unchanged complete auditor passes seal/check and all 339 corruption
controls; the supplemental check verifies the freshly built StoreKit fixture
inside the guest media. No historical checker was changed or weakened.

Progress remains **4/8 launch gates (50% of the checklist)**: loading/binding,
`+load`, initializers and application entry. A game frame, menu, login and match
are unverified. This fraction is not an engineering completion or time estimate.
The next observed boundary is session cookie policy/storage; it must be
implemented without discarding the request or configuration policy.

Five complete standalone evidence trees, including the pre-fix failure, are
preserved in a 118 MiB persistent archive. Fresh extraction passes all five
complete byte/type/permission comparisons. The complete game capture is also
preserved in a separate 2.0 GiB version-3 delta archive against the pinned
persistent dictionary checkpoint. Archive verification, full reconstruction
and comparison with the original tree pass. The restored copy passes its
unchanged saved auditor at the original recorded path, including the
supplemental StoreKit media check. The original capture is returned to that
path and the complete restored copy is retained separately.

```text
CACHE: /Users/alex/Library/Caches/vinix-ios
WORK: CACHE/audio-category-20261027-work
RAM: /Volumes/VinixSessionProtocols20261029
QRAM: /Volumes/VinixStoreKitQueue20261028
HTTP host: RAM/session-protocol-host-20261029-r3
StoreKit host: RAM/session-protocol-storekit-host-20261029-r3
Pre-fix failure: RAM/session-protocol-storekit-host-20261029-r1
HTTP guest: RAM/session-protocol-guest-20261029-r2/data-http-31152130125
Runtime: RAM/session-protocol-runtime-20261029-r2
Standalone archive: CACHE/session-protocol-evidence-20261029.tar.gz
SHA-256: ca1aacaa25e448c094548d09b7750bb4adda3d8341be0a5e975c4337206bd289
Standalone restored: QRAM/session-protocol-standalone-restored-20261029
Source tar SHA-256: 792d8e5f149e951b1d5b0c9c12cddbd6df86c1b7ce50f8f2f6f7e1e1cbd68f60
Game capture: RAM/session-protocol-probe-20261029
Game VM: probe-no-ads-132916
Game manifest SHA-256: e2dfeed037a6b5b4626ab0f6817b4856742712865374b1a9e4393977bf68b184
Game serial SHA-256: cce87c043d189ce4cc3c5a12d98048c69f6ae8b39286efca5745f80f1a3a88b0
Game runtime SHA-256: 9f2c7d4de22d59aa03dc2d6c195eb84290332949fa3e9f1509fb0580843530d7
Game StoreKit fixture SHA-256: 84e97c640f9d3276628ae829c315afd61b199376e4f1790908fc635a39dae6b3
Game archive: CACHE/session-protocol-probe-20261029-archive
Archive inventory SHA-256: ab6679ad6314162c6de454d0534c4ebd64fd584ccbb14271f9f6e98c98f0c708
Prior: CACHE/dictionary-variadic-20261028
Prior manifest SHA-256: c1163dfbb2bf9b0f096eba6123246028b00a43902ebd9963b115909b999e3dbb
Game restored: RAM/session-protocol-probe-restored-20261029
Restored audit: WORK/session-protocol-restored-audit-20261029.log
Saved auditor receipt: QRAM/session-protocol-restored-supplemental-check-20261029/historical-check.log
Receipts: WORK/session-protocol-*.log
```

Reproduce with frozen V 0.5.2 (`c6bb06f`), maintained
`notification-checks data-http-host` / `storekit-purchase-host` and
`notification-vm data-http` / `build-run-ios-gles`, each with fresh external
output. The full capture uses `storekit-operation-probe COMPLETE_PARENT
FRESH_OUT FRESH_STOREKIT_HOST --queue-copy`, then the saved auditor's seal/check
and negative-controls modes and the probe's `check-queue` mode. Receipts record
toolchain/kernel inputs and commands. Build the maintained
`evidence-delta-archive.v` helper with `-cflags -O2` for complete archive and
typed-inventory checks.
