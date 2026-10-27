# NSString path component checkpoint — 2026-10-27

Source and audit tools: `042caa5161ba3a2dbc29307365c9cad8233457c9`.
Advertising remains skipped.

`NSString lastPathComponent` now returns an independent, autoreleased
string for immutable and mutable receivers. It matches measured macOS
ARM64 Foundation behavior for empty paths, root, repeated/trailing slash
separators, dots, tildes, backslashes, long paths, embedded NULs and Unicode.
It preserves decomposed text and slash-like Unicode characters without
normalization. Mutable and constant string contents are copied under the
runtime lock before constructing the result.

Fortnite 42.30.1 advances past the NSString selector with the original
cooked content and stops at:

```text
V panic: iOS: unimplemented Objective-C method NSBundle bundleIdentifier
```

Native Foundation and runtime host tests pass twice under AddressSanitizer
and UndefinedBehaviorSanitizer. They check signatures, selector availability,
direct IMP calls, exact contents and UTF-16 length, mutable-source
independence, retained-result lifetime and eight concurrent workers. Runtime
tests also cover UTF-8/UTF-16 constants and two lifetimes ending with zero
live runtime objects. All 21 guest fixtures exit successfully, including
the new path-component fixture. The intentional fault captures all 31
ARM64 registers and restores execution; the UIKit window protocol and
child memory-budget checks pass.

Three images load, nine Objective-C `+load` calls and three initializer
groups complete, and application entry is reached. A tagged 24 GiB virtual
reservation succeeds. Available process memory stays positive within the
enforced 2 GiB game budget; final OOM counters are zero. This fresh VM uses
8 GiB RAM and an 1800-second startup limit and required no retry.

The game exits with status 1. Its desktop peer reports a broken pipe,
21 tree builds, 20 polls and no supervisor kill. The first application tree
has one node, zero images and 336 bytes; some later exchanges interleave
serial output. The peer has no compositor or input device. **No rendered
game frame is verified.** Progress remains **4/8 observable gates**:
load/bind, `+load`, initialization and entry. Frame, menu, login and playable
match remain unverified. This fraction does not estimate remaining effort
or time.

The audit rebuilt the input inventory and checker from the committed source.
Its selftest rejected 45 guest-log mutations and 16 host-log mutations,
unsafe IPA entries, malformed manifests and missing/changed/extra resources.
The bundle seal passed, including extraction and hash comparison of the
guest's packaged resources and binaries against the saved inputs. The
checker rebuilt from committed source independently verified the complete
sealed manifest, results and extracted guest inputs successfully.

Evidence location:

```text
/Users/alex/Library/Caches/vinix-ios/string-path-20261027
VM state: probe-no-ads-771500
Manifest SHA-256:
8e496b665f244be1ca75105da9321454caf2a5641de48107dca679a61dee0d3a
IPA SHA-256:
47a17e723f8fae91595ac897d8f59cd3b453c43113a20bb1ff31ab656167332e
Executable SHA-256:
6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
```

Preserve the entire bundle and its complete prior bundles; historical
checkers remain unchanged:

- `/Users/alex/Library/Caches/vinix-ios/url-resource-20261027`, manifest hash
  `47833ab8fbe22105f61c1d6c538c1df838894aeafa8e4cab417320b3aa481ff0`.
- `/Users/alex/Library/Caches/vinix-ios/number-bool-20261027`, manifest hash
  `e828567b1a29104c2ff993b492e5e699bc448f7ef76bfc4993913d9a7162dc30`.
- `/Users/alex/Library/Caches/vinix-ios/string-cstring-output-20261027`,
  manifest hash `ae2ae265786b6695007ea04737392fec89df547333cad7f86f736825598541b5`.
- `/Users/alex/Library/Caches/vinix-ios/string-normalization-20261027`,
  manifest hash `9f6b40523391339940642c4e8ffa0f8db38a61540f7beeaa86e743f6325321b7`.
- `/Users/alex/Library/Caches/vinix-ios/cooked-content-20261027`, manifest hash
  `fb54d1e1768eead6fee86b62b7f3023752b8f97e0846f71471e78d04d5edcd36`.

The original IPA, application and 95 resource files (1,831,863,828 bytes) are
reused unchanged. Twenty prior fixture binaries and their generated C are
checked against the prior manifest; they validate the guest environment,
while the new fixture and host tests contain the current runtime. The
runtime and supervisor are rebuilt. This selected resource overlay is not
a complete installation. The prebuilt kernel is inventoried, not rebuilt;
selected input hashes do not seal complete compiler/header/library
closures. The initial fixture build rejected an unregistered build mode;
that failure and the replaced tool-build logs remain preserved under
`first-fixture-failure`. The mode was registered and the tools and fixture
rebuilt successfully before probing. Native observation logs are preserved.
Successful probe status records completed capture; the game's status 1
records the unsupported selector above.

To reproduce, compile `tests/ios/string-path.v` with the frozen V compiler
without `-prod`, then run `prepare OUT PRIOR`, `fixture OUT`, `build OUT`,
`host OUT`, `probe OUT`, `audit OUT FULL_REVISION`, `seal OUT`, `check OUT`
and `selftest OUT`. Exact commands, statuses, sources, original inputs,
build artifacts, boot media and serial logs are preserved in the bundle.
