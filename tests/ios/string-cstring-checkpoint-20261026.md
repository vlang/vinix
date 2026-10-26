# C-string factory checkpoint — 2026-10-26

Implementation commit: `28749c0569b74e1b164cde21179ccba1137afea7`.
Evidence tools and inventoried source revision:
`b25fba5a4c42f2655d1a814b340abeba3173fa90`. Advertising work remains skipped.

`NSString` and `NSMutableString stringWithCString:encoding:` now decode
NUL-terminated ASCII (encoding 1) and UTF-8 (encoding 4) inputs into owned,
autoreleased strings. Class-method metadata (`@32@0:8r*16Q24`), signatures,
direct IMP calls and selector discovery agree. Inputs are bounded at 16 MiB;
the factory copies caller storage, and mutable results support later mutation.

The native inspector records 1,056 unique observations: two class signatures,
1,020 single-byte cases and 34 extended cases. Native encoding 1 maps all 255
nonzero bytes through Latin-1; encoding 4 rejects isolated high bytes except
`a9`, which becomes U+FFFD. The runtime reproduces these observations, consumes
one leading UTF-8 BOM and preserves later BOMs. Tests cover multibyte text,
malformed and truncated sequences, replacement-byte combinations, empty input,
copied stack storage, mutable factories and selector scope. The single-byte
matrix already covers the truncated `c2` case; it is not repeated in the
extended matrix. The evidence checker requires every exact case once.

Native and runtime host fixtures pass under ASan/UBSan with normal and
deterministic Swift hashing. Eight workers exercise factory and direct IMP
calls; two runtime lifetimes end with zero tracked live objects. Sanitizer leak
detection is disabled. All eleven ARM64 guest builds pass: init, C-string
factory, receipt, CFString output, search paths, home directory, inline
pthread-self, dictionary snapshots, Blocks byref, VM probe and game runner.
All nine guest regression fixtures finish with wait status zero.

The unchanged Fortnite 42.30.1 executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The C-string factory panic is gone. All three images bind/register, nine
`+load` calls and three initializer groups return, and application entry is
reached. The next observed stop is:

```text
V panic: iOS: unimplemented Objective-C method NSString floatValue
```

Progress remains **4 of 8 observable gates (50% of this checklist)**: image
loading/binding, `+load` completion, initializer completion and application
entry pass. A rendered frame, interactive menu, login and playable match remain
unverified. This fraction does not estimate remaining engineering effort or
time. The explicit `--probe-no-ads` diagnostic binds SKAdNetwork to nil and
changes application behavior; these results do not establish a normal launch.

All 13 inline pthread-self reads are translated. The exact 24 GiB tagged
virtual reservation succeeds at `0x800998c4000`; errno 22 is stale after
success. This does not commit 24 GiB of physical memory. Seven headroom queries
return 663,208,870 or 662,676,006 bytes. The final application cgroup has zero
`oom`/`oom_kill` events under a 2 GiB limit. The only fault is the deliberate
signal fixture, which captures all 31 ARM64 registers and restores execution.
The application exits 1 (wait status 256); the complete diagnostic harness exits
zero.

Complete evidence is preserved outside Git at
`/Users/alex/Library/Caches/vinix-ios/string-cstring-20261026`.
It contains 1,181 source records, 696 selected input records and 1,546 manifest
records, including application/frameworks, generated C, sanitizer objects, TLS
archives, tools, command/status logs and complete guest media.
`probe-no-ads-state.txt` selects `probe-no-ads-1160166`.
SHA-256 of `manifest.sha256`:

```text
911924675d2015f133ebc6a8384ec824dfbd45cf9170adc7b97ba1f8b55db885
```

The C-string evidence tool's seal, independent check and selftest pass. It
rejects changed encoding/output/metadata, missing or repeated native cases,
missing C-string validation and failed waits, as well as the inherited
receipt/CFString/VM/search-path/startup mutations, missing media, altered logs
and unmanifested files. Historical checkers remain unchanged. CFString
static/native observations are inherited from source
`0607e5a5ba82b9ac0dbd7c8034ff40d765546890` and complete bundle
`/Users/alex/Library/Caches/vinix-ios/cf-string-output-20261026`, whose manifest
SHA-256 is `4e3cb335b8b506cb371070ba391c2e9ae289e02e1c52d8ac774eb2d7016ecf56`.
Receipt host/native observations are inherited from source
`48d373e4860ea8896c3a33c618a71181c57b219c` and complete bundle
`/Users/alex/Library/Caches/vinix-ios/bundle-receipt-20261026`, whose manifest
SHA-256 is `d10cf1facae48d47a06894efb71b8f7883f67bc25494d8d1c0b4fd0d126cafea`.
Both provenances are recorded in `inherited-evidence.txt`. The prebuilt ARM64
kernel is inventoried; concurrent kernel edits were not rebuilt. Selected
input hashes do not seal complete compiler, header or host-library closures.

Reproduce from the inventoried revision using the frozen compiler at
`build/ios/fortnite/ns-calendar-checks/toolchain/v`, with `V_RESOURCE_PATH`
pointing to that toolchain and `V_MACOS_V3_NO_FALLBACK=1`. Compile
`notification-checks.v`, `notification-vm.v`, `string-cstring-run.v`,
`image-initializers-input-inventory.v` and `string-cstring-evidence.v` with
`-nocache -prod -gc none -cc clang` and the `tests/ios` module path. Preserve
the application/frameworks and inherited CFString and receipt observations
with their provenance. In a new external bundle, run the notification wrapper's
`string-cstring-host`, `string-cstring-inspector-build` and
`string-cstring-inspect` modes, then the checkpoint runner's `build` and `probe`
modes. The runner sets the 2 GiB cgroup budget and gzip level 9. Capture
source/input inventories using the full revision above, then run the evidence
tool's `seal`, `check`, `selftest` and `hash` modes.
