# NSString C-string output checkpoint — 2026-10-27

Source and audit tools: `98a8d9571fedb2c2a816024f9b6e5a6c484c6672`.
Advertising remains skipped.

`NSString` and `NSMutableString` now implement `cStringUsingEncoding:` for
UTF-8, ASCII and ISO Latin-1. Tests compare exact bytes, embedded NULs,
terminators and NULL results for unrepresentable characters against native
Foundation. Latin-1 composes representable adjacent accents without
decomposing aliases such as the Angstrom symbol. Mutable input is copied
under the runtime lock; an autoreleased NSData holder owns the returned
buffer until the pool drains, independently of receiver mutation or release.

Fortnite advances past this method with the original cooked content and
stops at:

```text
V panic: iOS: unimplemented Objective-C method NSNumber numberWithBool:
```

Native Foundation and runtime host tests pass twice under AddressSanitizer
and UndefinedBehaviorSanitizer. They cover selector metadata, direct IMP
calls, conversion failures and eight concurrent workers. Runtime tests also
cover mutable snapshots and UTF-8/UTF-16 constants, finishing two lifetimes
with zero live runtime objects. All 18 guest regression fixtures exit
successfully, including the new C-string output fixture. The intentional
fault captures all 31 ARM64 registers and restores execution; window
protocol and child memory-budget checks pass.

Three images load, nine Objective-C `+load` calls and three initializer
groups complete, and the application reaches entry. A tagged 24 GiB virtual
reservation succeeds. Available process memory remains positive within the
enforced 2 GiB child budget; final OOM counters are zero. A fresh VM uses
8 GiB RAM and an 1800-second startup limit; this run required no retry.

The game exits with status 1. Its desktop peer reports a broken pipe, three
tree builds, two polls and no supervisor kill. The first application tree
has one node, zero images and 336 bytes; later exchanges interleave other
serial output. The peer has no compositor or input device. **No rendered
game frame is verified.** Progress remains **4/8 observable gates**:
load/bind, `+load`, initialization and entry. Frame, menu, login and playable
match remain unverified. This fraction does not estimate remaining effort
or time.

The complete external bundle passes seal and an independent check using the
checker rebuilt from the committed source. Its selftest rejects 42 changed
guest observations, 16 changed host observations, unsafe IPA members,
malformed manifests and missing/changed/extra resources. The checker
extracts and hashes guest resources and binaries. Historical checkers remain
unchanged. Evidence:

```text
/Users/alex/Library/Caches/vinix-ios/string-cstring-output-20261027
VM state: probe-no-ads-1005000
manifest.sha256 SHA-256:
ae2ae265786b6695007ea04737392fec89df547333cad7f86f736825598541b5
IPA SHA-256:
47a17e723f8fae91595ac897d8f59cd3b453c43113a20bb1ff31ab656167332e
Executable SHA-256:
6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
```

Preserve the entire bundle and its complete prior bundles:

- `/Users/alex/Library/Caches/vinix-ios/string-normalization-20261027`,
  manifest hash `9f6b40523391339940642c4e8ffa0f8db38a61540f7beeaa86e743f6325321b7`.
- `/Users/alex/Library/Caches/vinix-ios/cooked-content-20261027`, manifest hash
  `fb54d1e1768eead6fee86b62b7f3023752b8f97e0846f71471e78d04d5edcd36`.

The original IPA, application and 95 resource files (1,831,863,828 bytes) are
reused unchanged. Seventeen prior fixture binaries and their generated C
files are reused and checked against the prior manifest; they validate the
guest environment, while the new fixture and host tests contain the current
runtime. The runtime and supervisor are rebuilt. This selected resource
overlay is not a complete installation. The prebuilt kernel is inventoried,
not rebuilt; selected input hashes do not seal complete compiler/header/
library closures. Failed host expectation experiments remain preserved
separately within the bundle. Successful probe status records completed
capture; the game's status 1 records the unsupported selector above.

To reproduce, compile `tests/ios/string-cstring-output.v` with the frozen V
compiler without `-prod`, then run `prepare OUT PRIOR`, `fixture OUT`,
`build OUT`, `host OUT`, `probe OUT`, `audit OUT FULL_REVISION`, `seal OUT`,
`check OUT` and `selftest OUT`. Exact commands, statuses, sources, original
inputs, build artifacts, boot media and serial logs are preserved in the
bundle.
