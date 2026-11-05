# Current retainer host build

The private retainer from
[current-retainer-source-preparation.md](current-retainer-source-preparation.md)
passed host production compilation as `retain-02`. The compiler returned actual
status 0 with the existing strict pointer flags, default collector and retained
generated C. Its log contains ordinary unused notices. The retainer was not
executed for this qualification.

The repository revision before this report was
`8d4f3d0deeb9d78ae3ffb26c7eec39cf1ec2fe0b`. Complete evidence remains under
`/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02/native-consumer-tools-01`.
The compiler argv, exit, log, cleanup and build receipt are retained beside
`retain-02`. Generated C remains at
`scratch/retain-02.61012.12282067958.482949587312.tmp.c`.

The unchanged consumer owner applied its 120-second child limit, sampled
550 MiB free-space floor, inclusive 40 MiB allocated-storage cap and existing
receipt reserve. Its **25 samples** had a largest gap of **1,032,249,125 ns**,
maximum allocated storage of **36,581,376 bytes** and minimum available space of
**29,980,123,136 bytes**. Final consumer allocation was **30,154,752 bytes**, an
increase of 5,349,376 bytes from the recorded pre-build allocation.

The compiler exited naturally, was reaped and left an empty process group;
the final wait returned ECHILD. No kill, held output pipe or resource refusal
was recorded. All sampled `df` children also completed and were reaped. Source
and complete module maps matched before and after; the frozen old-tool-root
check passed after the build. Generated C is 3,798,997 bytes; the executable is
1,155,408 bytes. Static C inspection confirmed the selected current recorded
wrapper delegates through the shared record-pair guard before assembly; this
does not establish runtime API behavior.

The retained `scratch/v3_thirdparty_objs` directory occupies 1,880 KiB across
all existing object/manifest variants; `cache` occupies 0 KiB. Every retained
third-party file predates the `retain-02.argv.json` timestamp, with no newer
retained cache file observed. These are post-build observations, not a bound
on temporary compiler storage or admission for a future producer.

| Artifact | SHA-256 |
| --- | --- |
| Retainer source | `bb582b6b0f097bc0003daea66fdb6906ae06a7abecc4b67f4cea01144b38839a` |
| `retain-02` executable | `209a1c0fd2808c8ca734ba342d3f34fcba3b610d2e22fd3bacd76702b7d0511c` |
| `retain-02.build.json` | `caae830f864f8062440533b00d6649edebde31748e374fee1114312ec4dc8734` |
| `retain-02.monitor/result.json` | `475d8e5ee0303873ef0b3cad508e003663f4d704f6d53ebd887bee4ba723b185` |
| Both complete module maps | `710351295e1be60a49b75f84348493ee85cf1f0777991a8b457ac3f4b83201d4` |
| Retained generated C | `f75d2443e8fdfdac8c2bc14fc1414df53da431498a3f4fc2e8e7f56786a255f6` |

Retainer execution, public API behavior, actual complete consumption checks,
compositor imports, evidence refusals and native runtime acceptance remain
separate gates. This host build establishes none of those acceptance claims.
