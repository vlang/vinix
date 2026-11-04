# Frame baseline preflight refusal

The read-only preflight on 2026-10-26 exited with actual status 1 and the
24-byte output `state inventory mismatch\n`. The original baseline remains
refused. No new seal, rerun, source change, output copy or qualification was
performed. The cause of the mismatch has not been established.

The original root is
`/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-device33-20261026`.
Its original manifest is the adjacent
`frame-peer-baseline-device33-20261026-seal-01/complete/inventory.json`, SHA256
`b826fe4f36b1599c3bbb31c3d5749cae3e32b6944f2220f20ea14d60672b8fe9`.
The unchanged original checker is
`/Users/alex/Library/Caches/vinix-codex/section14/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal`,
SHA256 `fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6`.
Its maintained source, `tests/kernel-allocs/frame-page-seal.v`, has SHA256
`8cd5e58df42e07760d0e1b73c49807b0ee2c7e353412e7d54aca34a7597577d4`.
All three hashes were checked before invocation and remained equal afterwards.
The manifest header named the exact original root, format and scope.

The literal invocation was `gtimeout --signal=TERM --kill-after=5s 300s`
followed by the original checker and `check ROOT MANIFEST`, under an empty
environment populated only with recorded HOME, USER, LOGNAME, PATH, LANG and
LC_ALL. The fresh external receipt directory is
`/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-device33-preflight-20261026-01`.
It retains actual argv/environment, input pins, log, status, observations and
postflight output. Source context was main revision
`19bb95f17160ac47e24be71d621bbd5028a656cd`; no scanner was built or run.

Admission showed 48,086,172 KiB available, above the 2 GiB requirement.
The first postlaunch sample occurred approximately 35.6 seconds after launch,
when the checker had already finished. This exceeded the required five-second
sampling interval; continuous live-floor and log-limit supervision was not
established. The receipt records that limitation and does not treat the
observed interval as the exact child duration. Postflight showed 48,284,200 KiB
available, and no matching checker, baseline or timeout process was observed.
No private-group retirement, sole waiting or raw ECHILD claim is made.

The final receipt directory occupied 36 KiB allocated and 9 KiB apparent,
below the 8 MiB state cap. The final log was 24 bytes, below its 2 MiB cap.

| Receipt | SHA256 |
| --- | --- |
| `check.log` | `2396750f3e91843921d63bd2203d57cada58133d4e964a978146f318b83d4d94` |
| `status.json` | `515bc895146492ec5f431d75dfef14c75f792d814298c83aced01a5e30c3a0e5` |
| `argv.json` | `08288f646b43b5f52dca003d7bff2279d31b0acda2ce45c8a63aa4685e404398` |
| `environment.json` | `43848bf646121c4e7a743103416ffe2bf29661c752c0ae6e28cddd4736f70ffb` |
| complete eight-file `checksums.sha256` | `d37ccea14a1dc26f437c03a990fa393bd0472827ea6f598ae0fcea41385f4810` |

Any replacement baseline requires a genuinely fresh build and its own
unchanged original complete audit. The source-only proposal is recorded in
`fresh-frame-plan.md`; it does not grant a build or guest qualification.
