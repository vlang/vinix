# Foreground observation qualification, 2026-11-05

The performance owner now measures both allocated and apparent charged-root
usage, counts each hard-link occurrence, and reserves 1 MiB inside the unchanged
ceiling for its journal and final receipts. Samples are scheduled one second
from their actual starts; gaps and complete probe/journal windows over five
seconds refuse qualification. Checked append writes replace the growing JSON
array. Raw cap/floor observations, reconstructed completion times, final
post-cleanup sampling and late-start diagnostics remain in the external state.

The change uses source base `62b5825d87d8efe1a6a4d99220effd796767ed1f`.
Tested `foreground-supervise.v` SHA256 is
`fe07e6d462b0d4ff96f432ecf0185658a2a43a882316001b6abfb5cf431a09f4`.
Independent source and lifetime review passed. The final production bootstrap
used pinned V `ff75a301…c4c5`, clang23, `-prod -nocache -keepc` and
`-Werror=incompatible-pointer-types`, with a cleared coherent compiler
environment and private module/cache/temp paths. Actual bootstrap exit was 0.

Fresh `owner-03` rebuilt normal and production owners; each passed all 45 owner
controls and 16 ARM controls. These include real success/nonzero exits, timeout,
output and signal refusals, descendant retirement, journal failure cleanup,
timing/size boundaries and a 2.2-second quiet child with independently
reconstructed complete sample windows. A 65 MiB sparse fixture exercises the
64 MiB size helper; a synthetic observation tests the unchanged full-budget
reserve refusal. No oversized file crosses the outer 512 MiB phase allowance.
The production owner also passed all six limit admission controls.

Raw source copies, generated C, executables, argv/environments, logs, maps and
receipts are retained at
`/Users/alex/Library/Caches/vinix-codex/section14/perf-observer-host-20261105-01`.

| Receipt or executable | SHA256 |
| --- | --- |
| `owner-03/qualification.json` | `d286dfd5d022d5a9ee1b2e657886703e64307166188a881771c1de578fd58d3e` |
| Equal complete owner input maps | `1d56817bf3436e05376070fdbd0b5a4dc23ce74f05d8c904dfcb06e14f1633d3` |
| `bootstrap-02/foreground-supervise` | `07a99472537d59741c4d5d336cefac14332e79ab7711ea0f35eabe72af008c10` |
| `owner-03/normal/foreground-supervise` | `aac24bec34eaad43ab76772dfa3c20924c6634d3f371dc59120081030637eb00` |
| `owner-03/production/foreground-supervise` | `70a0b5e9db3d2cabc390f09144b3d007de6f88cd13460c08c33dfb678ef64d19` |
| `limits-01/result.json` | `83e7473bf39a4b365a2580fbd09f97182a31bc1b33fff7f979428ec6ebfcb5df` |

Actual outer exits were 0. Complete before/after owner maps and the tested
production source copy matched independently. The largest recorded sample
start gap was 1,032,281,542 ns; the largest complete window was 199,455,666 ns.
Final worktree/state usage was 55,260 KiB allocated and 51,919 KiB apparent,
including previous attempts, below the 512 MiB allowance. Recorded endpoint
free space exceeded the 2 GiB admission/1 GiB continuation floors. Direct
bootstrap observation is limited to its endpoints. Live owner sampling covers
the owned child and cleanup, excluding later input inventories/result writing.

`owner-01` refused missing sparse-checkout referents before controls. Their
tracked directories were then included without changing the tested source.
The pre-amendment `owner-02` passed but retains an explicit qualification
limitation: its 513 MiB sparse fixture could transiently exceed the outer
allowance. Its result is preserved and does not replace `owner-03`.

The final report and the owner-control count documentation were written after
the equal maps were captured. This is host qualification only; the whole host
directory has not been sealed. No guest, kernel memory/performance result or
complete host SDK/loader closure is claimed.
