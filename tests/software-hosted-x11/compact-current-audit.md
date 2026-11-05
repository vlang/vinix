# Current complete compact inventories

The fixed `compact-import.v --current-audit` profile qualified the currently
retained complete compact target and bootstrap roots on 2026-11-05. It uses
the existing `nativeguard` process owner with a 120-second child/final-tail
limit. A later import phase has 780 seconds; both phases share the existing
256 MiB cumulative allocation ceiling, its 2 MiB pre-final reserve, and
2 GiB admission / 1 GiB live available-space floors. No import or guest ran.

Complete raw evidence is outside Git at
`/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02`.
The producer is `compact-current-audit-01`; its observer is
`compact-current-audit-observer-01`. Every new output remains outside the
historical roots. The historical tool namespace and every failed attempt are
retained and charged.

The unchanged original auditor first checked both original historical
manifests. Both actual exits were 1 with exactly `state inventory mismatch`.
These refusals remain refused. The same auditor then sealed each complete
current root to a fresh external inventory and passed a separate full check.
The bounded canonical comparison found no content, permission, owner, size,
path, type or link-target changes:

| Root | Entries | Device / inode / time differences | Fresh complete inventory SHA-256 |
| --- | --- | --- | --- |
| `targets01` | 3,755 | 3,755 / 58 / 100 | `9ab4265863021ce59410851dbeabe4de2cafb86ab07f335f6fe9959a47022753` |
| `target-bootstrap01` | 25 | 25 / 3 / 9 | `ea4c3b1fb221baeacb97ad9a605841f5d7acf3a7385723fbd792c368c2d74591` |

Both complete original inventories and full per-field difference reports remain
available. This establishes current recorded metadata explicitly; it makes no
cause-of-change or unchanged historical metadata claim. The original bundle,
original manifests, original auditor and auditor source were not rewritten.

The strict production bootstrap `compact-import-bootstrap-01/compact-import-04`
returned zero with an empty compiler log. Its source is
`919a40413995a882c494a6d8831750b0d64373cda057487d464214f08932e7a0`;
the executable is
`e6c440ef7667b4a52939c8602490dd52c1de239f23131ae9b5d5e6c35df16717`.
It used the qualified wait-status compiler overlay, coherent private compiler
environment, strict incompatible-pointer diagnostics and no `-keepc`. Sources,
executable, literal argv, environment, observed compile status and logs remain
retained. All prior generated C and failed artifacts remain present.

Before consuming evidence, the actual production child passed all 23 explicit
comparison controls. Their independent source, qualification and preserved
bootstrap-03 compatibility failure are described in
[compactdiagnosis/QUALIFICATION.md](compactdiagnosis/QUALIFICATION.md).
Both executed diagnosis sources are embedded and pinned separately from the
unchanged historical five-module map. Complete producer/observer maps matched
before and after, as did original input maps and the frozen old-tool inventory.

The owner returned actual zero with 87 samples. The largest sampled cumulative
namespace was 53,444,608 bytes; the final allocation was 53,501,952 bytes and
available space was 37,171,273,728 bytes. Its child exited naturally, was reaped,
had an empty group and ended with wait `-1` / ECHILD, without kills. Every
sampled `df` child also completed and was retired. These are sampled namespace
observations, not exclusive physical accounting or quotas.

The fresh manifests require a separate explicit current-metadata proof profile.
The historical `compactproof.check_audits` branch still selects its original
manifests and refuses current metadata. Future consumer builds, import
qualification, the final supervisor controls and native Launch options
acceptance remain pending.
