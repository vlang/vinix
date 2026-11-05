# Current proof guard and provenance controls

The private candidate prepared by
[prepare-current-proof.v](prepare-current-proof.v) passed strict production
compilation and the eight historical plus seven current control categories.
These are host reader, provenance, record, token and shared record-pair guard
checks. Their audit callback receipts are synthetic. They do not execute the
public assembly path, import a compositor or qualify native Launch options.

The repository revision before this report was
`322bbb927f2413a72c9edf70e7c835aeaa0bb358`. Complete raw evidence remains under
`/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02/native-consumer-tools-01`.
The maintained main `compactproof` package is unchanged. Candidate source and
preserved historical inputs are identified by
[current-proof-source-preparation.md](current-proof-source-preparation.md).

`compactproof-check-02` compiled with `-prod`, strict pointer checks and the
default collector. The actual compiler child returned 0 with an empty log.
The control child returned 0 with both exact PASS markers and successful
category results. The current fixture exported **132 fixed roles plus six
callback receipt roles**; its canonical record is **36,699 bytes**, below the
unchanged 64 KiB limit. Historical/current record separation and explicit
refusals remained active in production. No normal-build result is claimed.

Both phases used the unchanged qualified consumer owner, its 120-second child
limit, 550 MiB sampled free-space floor and inclusive 40 MiB allocated-storage
cap with the existing receipt reserve. Independent receipt review found:

| Phase | Samples | Largest sample gap | Largest sampled allocation | Lowest sampled available space |
| --- | --- | --- | --- | --- |
| Build | 22 | 1,029,020,625 ns | 18,665,472 bytes | 38,131,798,016 bytes |
| Controls | 8 | 1,046,435,583 ns | 15,056,896 bytes | 37,366,644,736 bytes |

Both owned children exited naturally, were reaped and left empty process
groups; final waits returned ECHILD. No kills, held output pipe or monitor
refusal was recorded. All sampled `df` children also completed and were reaped.
Complete frozen old-tool-root checks passed after the build and controls.
All four module maps before/after the two commands are identical. The recorded
consumer allocation after qualification was 15,093,760 bytes. Retained generated
C is 1,958,184 bytes; the executable is 527,872 bytes.

| Artifact | SHA-256 |
| --- | --- |
| `compactproof-check-02` executable | `246b4cb824e85b819338f65cce5d7ee5ca68f137bc3900291ceda719444f3f8a` |
| `compactproof-check-02.build.json` | `461d1fb3e0199e97a66f8a47389f6802547548df1401b10542d5d3e7ca771876` |
| `compactproof-check-02-controls.run.json` | `656880024d84c5a496a12293351c56676e20d6698c7c3e4c09b1f5fc33c9ac6e` |
| Build monitor `result.json` | `b3d183dfca6c994cbaafcba3de619405ba57bd01239b354c45ad62bbd6b5e783` |
| Controls monitor `result.json` | `45110b70f4ed10f2d6de1a83697eb90b710b042c55c0d337add56df6031dd0e2` |
| All four module maps | `710351295e1be60a49b75f84348493ee85cf1f0777991a8b457ac3f4b83201d4` |
| Controls `result.json` | `985d5a811ded63a22ea45a6dccb60ff748e31b460fac0f6db349dcaa47c20449` |
| Synthetic current `record.json` | `b24fd3a3587e9f3c679aa4dab69f8174f948dfad3e856977a0893ce586f346d2` |
| Retained generated C | `77b629c217aaa292bcfaff24089e7f84bf589502fec29691c305c818bcbfcbc1` |

Public-wrapper integration, actual whole-root pre/post checks, imports,
controller and retainer qualification, evidence refusals and both native guests
remain separate acceptance gates. The shared-guard controls establish no public
assembly, import, audit-execution or native acceptance claim.
