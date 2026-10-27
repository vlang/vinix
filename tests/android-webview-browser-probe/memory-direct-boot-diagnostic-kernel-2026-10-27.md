The kernel patcher accepts two separate successor profiles. `--maps-controller-memory`
requires the sealed service-query base, the exact r7 controller and identical
desktop alias, a three-file overlay and ten preserved modules. `--maps-direct-boot`
requires the sealed memory stage, the exact new framework, a six-file overlay
and eleven preserved modules. Each appends only its named diagnostic overlay.
Historical profiles and the frozen PIDFD kernel installation path are unchanged.

The memory receipt allows only two controller-alias input changes and
`inputs_sha256` at deployment top level. The direct-boot receipt allows only
one headless JAR input change, five deployment input changes, and the existing
restricted top-level deltas. JAR, DEX, framework manifest and framework-build
receipt pins bind the sealed producer. Generated headless-input and Maps build
receipt digests remain stager declarations checked by complete sealed-stage
audits; the patcher does not decode their deployed bytes.

Focused negatives reject changed/missing identities, required inputs and module
pins; old path/seal combinations; missing, changed or extra deltas; unsafe,
linked, duplicate, missing or extra inventory members; and cross-profile receipts.
All focused and historical hash, inventory, configuration, module and FAT tests
pass. Added ten- and eleven-original-module FAT fixtures check kernel readback,
all eleven/twelve resulting modules, preserved firmware/configuration and once-only
installation. These use temporary baselines; actual external stage installation
is root-session work.

Independent read-only review by `printf_path` passed both final profiles, producer
pins and the three final memory-base pins. The small memory manifest and stage
receipt were directly hashed; their boot and overlay declarations agree. Actual
patch execution hashes those media bytes. No media rehash was needed for source
review.

The sole Boehm host build passed in 9.41 seconds with 401,375,232 bytes maximum
RSS. Complete self-tests passed in 11.00 seconds with 28,213,248 bytes maximum
RSS. Both used zero swaps. Entry source, local dependencies and compiler hashes
matched before/after. The source parent was
`aebf5a280d2c4c7e3e1761fa22fc3ef3c1d8e7b3`.

| Artifact | SHA256 |
| --- | --- |
| Entry source | `305af9eddf1545a1d3a06646dea537022f329b2624ff3c1738b6f36c15d023bb` |
| Host executable | `f49a25579612ea70edaa28e51e5748e6c3f963de7cd48cb2069bebc94558449e` |
| Service-query base manifest | `4d4850aa0f4204999e0d8d9c0cdd3ef0466b4d67c9b26ea371005e4cc93e0b9b` |
| r7 controller manifest | `680942c83d4877b8258e5f53ac454aebc3c021331470a002754bc1647ae1e890` |
| r7 controller executable | `9c213a85235b802fc3b068ff2d195ea207ba82ded7fe6cdee408e0bd55921c0c` |
| Memory base manifest | `944007c40fff691ad3c2973970ad5e840aea7bff7370bda5486377c274a1fd21` |
| Memory base boot | `b534f94cede89e250f710d367fae062bd1c71c6024dabd85c5aa2444aa010b00` |
| Memory overlay | `6fbaafd334d0008b548df7557b65aa6cf99ae08be7fa584ed46789657ac51b13` |
| Direct-boot framework manifest | `a3445b78a7c4049fa71ee0f81469dca7da2236c36788500cd8bd3c8bb0b81552` |
| Direct-boot JAR | `bf3853c98155e420162dc8d1759735a497e8d8bb9724cd9eb7f209c4edb04c0d` |
| Direct-boot DEX | `3742f3915d4989ced425914e1fe4f6f662bd32566183534a849f8ad8ccd07213` |
| Direct-boot framework build receipt | `017232d7cef0527e639c3689cca3cc87502746aaa9608760d6bb7f362cbbd2f4` |

The immutable tool audit is
`/Users/alex/.local/state/vinix/android/maps-direct-boot-kernel-patcher-2026-10-27-r1`.
It retains source, both local dependency files, executable, commands,
qualification and build/self-test logs. Its sibling `-seal` binds all 11 typed
entries with manifest SHA256
`898f33cc197dc60fc934d83ca139c97a6e227ce5611bb53ddde77bf44e4c1faf`.
Creation, internal verification and a separate unchanged-sealer check passed.
The original complete base/producer bundles, compiler, standard library, SDK
and frozen kernel build remain required; the small audit is not their closure.

For a complete, sealed, unlaunched direct-boot-stage clone:

```sh
/Users/alex/.local/state/vinix/android/maps-direct-boot-kernel-patcher-2026-10-27-r1/patch-kernel --maps-direct-boot FRESH_CLONE /Users/alex/.local/state/vinix/android/pidfd-wait-kernel-build-2026-10-26-r1/kernel-aarch64-r2 1e9077779aaed08188e6f8111ca9ceb27b479517ece736a58157049f004fb36d
```

Use `--maps-controller-memory` only for the separate memory-stage clone. This
change ran no VM, copied no SDK and rebuilt no kernel. Google account sign-in
and Maps rendering remain unverified by these host tests.
