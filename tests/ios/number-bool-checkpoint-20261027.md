# NSNumber BOOL checkpoint — 2026-10-27

Source and audit tools: `9a184dc246ee251734ab0a0b024d476a71409b0d`.
Advertising remains skipped.

`NSNumber numberWithBool:` now returns the cached CFBoolean objects with
native Foundation's ARM64 argument normalization, selector metadata and
direct IMP behavior. The framework cache owns these +0 results until
runtime shutdown. Cache construction is serialized, and NSNumber equality
uses numeric values.

Fortnite 42.30.1 advances past this factory with the original cooked content
and stops at:

```text
V panic: iOS: unimplemented Objective-C method NSURL setResourceValue:forKey:error:
```

Native Foundation and runtime host tests pass twice under AddressSanitizer
and UndefinedBehaviorSanitizer using macOS ARM64 Foundation as the oracle.
They cover argument normalization, metadata,
direct IMP calls, CFBoolean identity, values, copying, ownership and eight
concurrent workers racing initial construction. Runtime tests finish two
lifetimes with zero live runtime objects. All 19 guest regression fixtures
exit successfully, including the new BOOL fixture. The intentional fault
captures all 31 ARM64 registers and restores execution; window protocol and
child memory-budget checks pass.

Three images load, nine Objective-C `+load` calls and three initializer
groups complete, and application entry is reached. A tagged 24 GiB virtual
reservation succeeds. Available process memory remains positive within the
enforced 2 GiB game budget; its final OOM counters are zero. This fresh VM
uses 8 GiB RAM and an 1800-second startup limit and required no retry.

The game exits with status 1. Its desktop peer reports a broken pipe, three
tree builds, two polls and no supervisor kill. The first application tree
has one node, zero images and 336 bytes; later exchanges interleave serial
output. The peer has no compositor or input device. **No rendered game frame
is verified.** Progress remains **4/8 observable gates**: load/bind, `+load`,
initialization and entry. Frame, menu, login and playable match remain
unverified. This fraction does not estimate remaining effort or time.

The complete external bundle passes seal and an independent check using the
checker rebuilt from committed source. Its selftest rejects 43 changed
guest observations, 16 changed host observations, unsafe IPA members,
malformed manifests and missing/changed/extra resources. The checker
extracts and hashes guest resources and binaries. Evidence:

```text
/Users/alex/Library/Caches/vinix-ios/number-bool-20261027
VM state: probe-no-ads-1612083
manifest.sha256 SHA-256:
e828567b1a29104c2ff993b492e5e699bc448f7ef76bfc4993913d9a7162dc30
IPA SHA-256:
47a17e723f8fae91595ac897d8f59cd3b453c43113a20bb1ff31ab656167332e
Executable SHA-256:
6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
```

Preserve this entire bundle and its complete prior bundles; historical
checkers remain unchanged:

- `/Users/alex/Library/Caches/vinix-ios/string-cstring-output-20261027`,
  manifest hash `ae2ae265786b6695007ea04737392fec89df547333cad7f86f736825598541b5`.
- `/Users/alex/Library/Caches/vinix-ios/string-normalization-20261027`,
  manifest hash `9f6b40523391339940642c4e8ffa0f8db38a61540f7beeaa86e743f6325321b7`.
- `/Users/alex/Library/Caches/vinix-ios/cooked-content-20261027`, manifest hash
  `fb54d1e1768eead6fee86b62b7f3023752b8f97e0846f71471e78d04d5edcd36`.

The original IPA, application and 95 resource files (1,831,863,828 bytes) are
reused unchanged. Eighteen prior fixture binaries and their generated C are
checked against the prior manifest; they validate the guest environment,
while the new fixture and host tests contain the current runtime. The
runtime and supervisor are rebuilt. This selected resource overlay is not
a complete installation. The prebuilt kernel is inventoried, not rebuilt;
selected input hashes do not seal complete compiler/header/library
closures. Failed host compile and expectation experiments remain preserved
within the bundle. Successful probe status records completed capture; the
game's status 1 records the unsupported selector above.

To reproduce, compile `tests/ios/number-bool.v` with the frozen V compiler
without `-prod`, then run `prepare OUT PRIOR`, `fixture OUT`, `build OUT`,
`host OUT`, `probe OUT`, `audit OUT FULL_REVISION`, `seal OUT`, `check OUT`
and `selftest OUT`. Exact commands, statuses, sources, original inputs,
build artifacts, boot media and serial logs are preserved in the bundle.
