# Intent371 ART harness bootstrap

Harness source `6668c29e9e07d6ab89cc04fe58e8ab8a89ac4afa` retains the actual
old367 control from the failed369 regression and boots only the corrected371
framework. It preserves the signed APK bytes, historical paths and semantic
oracle. This report covers host tooling; the ART result has its own report.

Tooling commit `73d1393d0` includes the V generator, bootstrap recorder and
action recorder. Launcher `9f8609211` computes the source pin in V and records
the actual outer action. The canonical-path check rejected an initial `/tmp`
alias before any output or builder invocation; the `/private/tmp` invocation
then exited 0 from 03:57:30 to 03:57:39 UTC on 2026-10-26.

The sealed bootstrap is retained at
`/Users/alex/.local/state/vinix/android/intent-uri371-run-bootstrap-build-2026-10-26`.
It contains the frozen compiler inputs, generated C, exact command argv and
statuses, environment, committed source, recorder source and executable.
Compilation, unchanged semantic self-test and the original290 complete audit
exited 0. Before and after closures contain the same 270 files. The baseline
is the corrected369 bootstrap; its separate qualified367 receipt is retained.

| Input or artifact | SHA-256 |
| --- | --- |
| Harness source | `e6de49d024b706ffc34f6169b3a1a31f725708d3bbfd7425657513d9c6d2e707` |
| Harness executable | `4c192b967eb30a27caa5fa08d5d5c0ff15e4136e89134390d91c7704ef4488b6` |
| Bootstrap manifest, 655 files | `0056ca7608c43d61612f24caeb251c502e41c1f6b28db22ba249710084691421` |
| Bootstrap recorder source | `863004aa49d84602d4a83e20c81f6ff46f7c2dec298d11565ddb77efd22aa0a0` |
| Bootstrap recorder executable | `6eaaf95fdd1d724b82714b37cc5ceceb475899e17d4c21482f3a60a9a8494b72` |
| Corrected369 bootstrap manifest | `0de15d5f6e3f96dabba630779e3b17e34c8c50fff33ddd8a705d8a14191b591a` |

The sole independent bootstrap reader also exited 0. It reran original290 on
all 655 files and checked the exact 270-file closure, all 13 command argv and
statuses, recorder pins and copied qualified367 receipt. Evidence is adjacent
at `intent-uri371-run-bootstrap-peer-readback-2026-10-26` under the same state
directory. Reader `705b90368` ran original290 from 03:59:10 to 03:59:11 UTC.
Complete receipt SHA-256 is
`c4aac06796ac5b1ac31a80fe2473548f5f891a824d118b3b4a71ad28dc46e1e1`;
command SHA-256 is
`4d8446e9b65ceb099bd4677c91e09e764cdb147d50e6b6bc5cf77350f08581c5`.

The action recorder build is retained separately at
`intent-uri371-action-recorder-build-2026-10-26`. Its actual compilation exited
0 with identical 270-file closures. Source SHA-256 is
`cb0dafd546e714bbeb3157a49f420b758e5d98221e9de1b3891396e722c46819`;
executable SHA-256 is
`b2d0fdd9791b7f25b509b3ac7145759ce2f69076387c7b1f5b2f9d1945a64997`.
It accepts prepare, new, qualify and seal actions, preserving nonzero child
statuses before rejecting failures. It cannot launch an old guest. This
helper build has bounded source and receipt review, separate from the sealed
bootstrap's complete audit. Reader `5ad91fbd4` exited 0 at 04:03:36 UTC,
checking all 270 live closure entries and four exact command argv and statuses.
Its adjacent receipt is
`intent-uri371-action-recorder-peer-readback-2026-10-26/receipt.json`, SHA-256
`95eb1d7041786b34827b70b238cc11cd4bddb00fed5a95d58f50e704a0d7569f`.

Outer launch receipts remain adjacent as
`intent-uri371-run-bootstrap-launch-2026-10-26-before.json`,
`intent-uri371-run-bootstrap-launch-2026-10-26-command.json` and `.log`.
Its exact launcher source and executable are retained in the matching
directory, with pins in those receipts. Original369 evidence is unchanged.
