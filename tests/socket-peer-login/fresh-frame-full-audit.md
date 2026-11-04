# Fresh frame complete-state qualification

The fresh x86 frame build passed the unchanged original full seal, primary
full check and root-owned independent full check on 2026-11-04. Each actual
outer exit was zero with exact original and native PASS markers. Kernel
source base is `9acefa77bee69247c837e97987a2377536aa41cc`, checkout
`b262bf48f44b6cd1e9f3b73a7d8b0a079bc98943`; the preceding build is recorded in
[`fresh-frame-native-build.md`](fresh-frame-native-build.md).

| Invocation | Actual final tool | Samples | Maximum gap/window |
| --- | --- | --- | --- |
| Original full seal | `1f7d1e` | 28 | 1,018/283 ms |
| Primary full check | `5a6d4c` | 6 | 1,012/102 ms |
| Root independent check | `163448` | 7 | 1,011/204 ms |

Seal/check deadlines remained 600/300 seconds through final PASS, with zero
retirement grace, five-second native sampling/window/final-tail guards and
the 2 MiB live/final audit-child log bound. Direct checker leaders recorded
ECHILD/ESRCH after their owners reaped them. No broader descendant cleanup
claim is made. The root invocation used the separately qualified independent
source/binary `c5d164a9…`/`30a9b507…`, with fresh `native-check-02` state.

The original checker/source remained pinned to
`fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6` /
`8cd5e58df42e07760d0e1b73c49807b0ee2c7e353412e7d54aca34a7597577d4`.
The raw root stayed frozen; all audit writes were outside it. Fixed-input
before/after comparisons passed for each invocation, and the manifest remained
unchanged across both checks. The root check measured maxima of 94,244 KiB
allocated/104,449 KiB apparent and a 29,051,200 KiB minimum free floor.

The complete raw bundle remains outside Git at
`/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-fresh-20261026`.
Its complete inventory is retained separately at
`/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-fresh-20261026-seal-01/complete`.

- `inventory.json`: `918073b63294c83608ef2d08b7420929c1d5148fc0464df4798a95459d71e8d9`.
- `inventory.sha256`: `449aebdb7a1606ad1ae2ea3702980d4cc1235cc5fd6c7cd036655f78e737dc04`.

In its parent directory, `frame-full-first-two.handoff.json` has SHA256
`df9b994726595e5746b5012812786a00ca0ae98745435bcaf6ea8c5b7cbece8a`;
the root-owned `frame-root-check-02.outer-status.json` has SHA256
`89a6a77d33753be33b67e9b8d464c16062f011eb47cea847fccf340e4b406f1b`.
Raw observations, statuses, markers and the complete original bundle remain
required for verification. No missing-evidence exception or historical repair
was introduced. Guest/performance boots and consumer migration remain pending.
