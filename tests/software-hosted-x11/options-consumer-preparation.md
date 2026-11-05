# Launch options consumer tool preparation

`prepare-options-consumer.v` derives the fixed consumer build owner from the
retained `build-supervision-03.v`. Its only owner-source change is
`output_root` from `native-supervision-host-01` to `native-consumer-tools-01`,
checked by an exact occurrence count and inverse replacement. It preserves both
source versions and independently copies the qualified supervision-control
runner. It does not compile or execute an owner itself.

The older tool root, including its failed attempts, is retained unchanged under
a 31 MiB read-only aggregate reservation. New bootstraps, tools, temporary C,
logs and receipts share a separate 40 MiB scope. The derived owner retains the
original 120-second child limit, 550 MiB available-space floor, 4 MiB admission
headroom, 64 KiB final-receipt reserve, module comparisons and child cleanup.
This path derivation introduces no new supervision behavior.

## Recorded preparation, 2026-11-05

The repository revision before this report was
`bb1d786a66164ae05e3753fb90149f9775216eca`. Exact source and artifact pins below
identify this preparation separately from concurrent repository changes.
Complete raw evidence remains outside Git in
`/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02/native-consumer-tools-01`.

The preparer and derived owner passed strict production bootstrap with actual
exit status 0 and empty compiler logs. Their literal argv, coherent qualified
compiler environment and observer-recorded command statuses are retained as
`{preparer,owner}-bootstrap-01.{argv.json,environment.json,observer-exit.json}`.
These command-status records do not establish native child-group cleanup.
The source-only preparer returned actual status 0 and its exact PREPARED marker;
`source-preparation-01` retains both owner sources and the result receipt. The
generated one-line diff was inspected. Complete old-root metadata, paths,
content and link comparisons passed before preparation, after preparation and
after owner bootstrap; their logs remain alongside the bootstrap evidence.

| Artifact | SHA-256 |
| --- | --- |
| Maintained preparer source | `73a746be9e2a13eac417452462307f748af0b8b3acab7d1036a455e72b0d1d26` |
| Original owner source | `0cc0e57c3b0a7a4912aa9104c14293f0d82b6153cce792e63b8fa35c1cf332f1` |
| Derived owner source | `8729e2a69374afaa028576205e0b4941cbc05b7a9e4febae5619d3637421a940` |
| Derived owner executable | `32bd164c24dca1046601e0b5c0654d09510a1408704666cd30b19a72eb4c6a44` |
| Original and copied `supervision-check-01` | `50f096c4a5bc6ab5be9a9cb8ebcec074c66ea1621db71f047ea7f34d7a3db36e` |
| `source-preparation-01/result.json` | `f2e88c13639205426a1a72fc18ef37d2ea3180cd2baad689866cd0b8508cc44b` |

The generated compact retainer from
[compact-retention-preparation.md](compact-retention-preparation.md) subsequently
passed strict production compilation under this owner, with actual outer and
child status 0. `retain-01.build.json` is
`6d4eb66eeb057036a24c5f39edadb5e95e6d49c8fa4646bcd3b7aebf48302e75`;
the executable is
`ae59378de694734edadd65a193626b0e22b6ea27b63e8f6df4f07105d6bb3b4d`.
Its complete compact module maps matched before and after. The monitor recorded
natural child completion, reaping, an empty child process group and ECHILD,
without kills. The largest sampled allocation was 14,991,360 bytes and the
owner's final namespace allocation was 8,880,128 bytes. Complete frozen old-root
checks also passed immediately before and after this compile.

Evidence-check compilation, the final supervisor's 13 controls, native guest
execution and the 89 evidence refusals remain pending. No original target input
admission, compact import or native acceptance is claimed by this preparation.
