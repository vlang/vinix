# Failed runtime evidence closure, 2026-11-05

The previously pending atomic transcript gates, post-run kernel audit and
failed-bundle preservation checks from
[the paired checkpoint](paired-heap-checkpoint-20261105.md) are complete.
The failed atomic run is preserved and its runtime bundle is now quiescent,
with two matching complete literal inventories. Atomic runtime qualification,
memory flatness and Section 14 remain open.

Let `C=/Users/alex/Library/Caches/vinix-codex/section14`,
`R=C/perf-six-x86-20261105-01`, and
`I=C/perf-runtime-host-20261105-01/failed-runtime-inventory-01`.
All raw evidence remains outside Git. Nothing in the failed VM state or the
accepted observation-host evidence was rewritten. `R/finalization-01.json`
was the final planned write inside R; inventories and review receipts are in I.

After fresh admission recovered above 2 GiB, the unchanged full/legacy
checkers and qualified nonqualifying observer each returned actual status 1
for the partial atomic serial: no DONE marker and 10 of 44 measurements
missing. Their executable and serial pins matched before/after. The original
atomic complete-kernel auditor then returned actual status 0 with the exact
marker, unchanged manifest/source pins, equal before/after maps, original group
absence and ECHILD. Its final audit receipt records 21 samples, maximum start
gap 1.023824750 seconds and complete window 0.353091375 seconds.

The failed runtime owner remains status 1 and its child status remains
unavailable after the observer floor refusal. The outer owner's complete
`inputs-before.json` and `inputs-after.json` do exist and are byte-identical.
The adapter's separate `prepared-atomic-01/after-inputs.json` and
`results/status` remain absent. The historical host-after receipt saying the
audit was pending stays unchanged; `atomic-gates-01/status.json` binds the
later completed audit. No completion or after-map was manufactured.

The qualified literal helper returned actual status 0 for the primary capture.
An independent reviewer reran it into a fresh I file after fresh resource
admission. Both complete manifests are byte-identical: 937,758 bytes,
7,162 entries, root mode 16877. Binary/source/finalization pins stayed unchanged.
This is a trusted quiescent tree inventory of regular-file hashes, modes,
paths and literal symlinks. It is distinct from the unchanged original complete
kernel auditor; it supplies no atomic runtime or memory-flatness acceptance.

| Retained artifact | SHA256 |
| --- | --- |
| R/atomic-gates-01/status.json | `0e120ccb3e0c2f3378c9a0edec017694cc92e9792eef13bcea9d6c665260a802` |
| R/audit-atomic-after-run-01/audit.json | `2e37fb3b50abca8f2b37d2de82a58e6529d943f2b210d3e5c3cb030bdca12c73` |
| R/run-owner-atomic-01/inputs-before.json and inputs-after.json | `1e81b425fa5d17571040df69d743f72a4dffdd2c17aaf77b2d7600626d3920d3` |
| R/prepared-atomic-01/results/serial.log, unchanged | `82feae53df6df19bd6ad80db72333267444fbef880afa045a4e6c951620df66b` |
| R/run-owner-atomic-01/supervisor.json, unchanged | `46ef3d04679002441299b74c919645e29770b371801cdf56b7759ad01bddf722` |
| R/finalization-01.json | `4dd96ca4796256c7802bb59e5a99f8992c5b74d6657fcf88687dc07e36829b27` |
| I/primary.tsv and independent.tsv | `03ce6150f13b2f25454f5fc163d82b1ad8483006372b7261cc0a9a4cfd92ff93` |
| I/independent-review.json | `12a1ec7f34710f7493d337f0a6480f518975c081016eb156292d3c7a03ba323a` |
| I/status.json | `dd3380f3f7db3a3b03f1351c065fb0bc39b089a4603e77400a6a76ae4ffb9282` |
| C/matched-peer-frame-atomic-fresh-20261026-seal-01/complete/inventory.json | `e82671ca13c4d46b18d1d9762d661f4f392be0ee888d0fb20d1de21f540c54f0` |
| Qualified literal-manifest executable | `30a48af5d270e03950314a66b1376a3b311ef100f0f6d59d01d388d048991001` |
| Qualified literal-manifest source | `bc406265573aff340b0000d58b7cc8f6733ea4993ba5bcde5d237fc611062e47` |

The literal executable is
`C/literal-manifest-host-20261105-01/production-03/literal-manifest`;
qualification is recorded in [literal-manifest-check.md](literal-manifest-check.md).
The independent capture endpoint measured 2,437,549 KiB apparent and
1,814,756 KiB allocated across the exact charged W/S/R roots, with
41,127,512 KiB free. Existing ceilings and admission/continuation floors were
unchanged.

A separate proposed retry at `C/perf-six-x86-retry-20261105-01` keeps all W/S,
frozen old R and new R2 failures charged together. The reviewed forecast rounds
existing roots to 2,457,600 KiB, allows 1,441,792 KiB for one fresh prepared tree
and retains the full 786,432 KiB remaining reserve: peak 4,685,824 KiB under the
4,718,592 KiB ceiling, with the 1 MiB owner tail reserve inside that ceiling.
The two actual prepared trees measured 1,162,253 and 1,162,201 KiB apparent;
the new tree forecast adds approximately 273 MiB above the larger tree.
Profiles/admission are separate from image preparation. A fresh prepared
receipt, post-preparation audit and concrete guest review remain required;
no retry image or VM is established by this closure report.
