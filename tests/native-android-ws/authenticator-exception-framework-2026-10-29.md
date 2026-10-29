# Authenticator exception framework successor, 2026-10-29

The explicit `--auth-exception` builder profile applies the private caught-exception
diagnostic from `298c3d1cd` to the sealed application-restrictions framework. It
changes only `AbstractAccountAuthenticator.vinixHandleException()` and retains all
2,104 classes, including the transport and default response. Historical profiles
remain unchanged. This is a host framework build; guest behavior and Google
authentication remain unverified.

The profile pins the baseline at
`/Users/alex/.local/state/vinix/android/combined-account-webview-application-restrictions-framework-2026-10-28-r1`,
manifest `8907c1f11d8886b47358b458a8026d8351c6feac44d78346d6d426208b8ffe15`,
JAR `d4e8678bf5deda99358defd912e64e4fcba92fec4ad3b87b39fc9f7e9f6ebf32`.
Only the request and base provider sources are needed. The existing retained
`framework_replace_method` helper replaces the selected method; class metadata,
other methods and all other classes must remain unchanged before and after DEX
roundtrip. The JAR check permits only its `classes.dex` member to change.

The full producer recorded revision
`298c3d1cd6cc9948de7bb580c22c8a435da380aa`. Its exact working builder source is
retained with SHA-256
`4d669294217525c41f45840f0f76d64c9c36fcf6e948994bbcd6fbaf7f8f3128`.
The profile selftest exercises the required method change and rejects additions,
deletions, substituted classes and changes to the retained transport/default
response. Independent source review also checked the minimal provider closure.

Artifacts are relative to `/Users/alex/.local/state/vinix/android` (`S`):

- Builder, source and guarded command evidence (`B`):
  `S/auth-exception-framework-builder-2026-10-29-r1`.
- Completed framework (`P`):
  `S/combined-account-webview-auth-exception-framework-2026-10-29-r1`.
- Complete in-place evidence seal and fresh readback:
  `S/auth-exception-framework-sealed-2026-10-29-r1`.

| Check | Result | Seconds | Peak sampled RSS, bytes |
| --- | --- | ---: | ---: |
| Builder compile | Pass | 2.622 | 334,036,992 |
| Full builder selftest | Pass | 0.281 | 1,245,184 |
| Full narrow producer | Pass | 71.808 | 505,626,624 |
| Evidence seal and inline full check | Pass | 1.653 | 23,773,184 |
| Fresh-process complete seal readback | Pass | 0.842 | 24,231,936 |

All passing guards exited zero with complete process cleanup; time reports record
zero swaps. Limits were 600 MiB aggregate RSS, 300 seconds and a 1 GiB disk
reserve. Compile/selftest allowed 512 MiB observed shared-volume growth, the
producer 1 GiB, and seal/readback 64 MiB. The producer observed 625,496,064 bytes
global growth; shared-volume measurements do not isolate its own allocation.

The producer completed exact class/method/JAR deltas, DEX roundtrip, full input
rechecks and its complete output inventory readback. Two additional independent
builder `--check` commands were interrupted by the 64 MiB shared-volume growth
guard after 3.221/2.465 seconds (95,907,840/71,200,768 bytes observed growth).
Both record exit 125, child 137 and complete cleanup; neither extra check passed.
Their original receipts/logs remain in `B`, with no further retry or cap change.
The later independent seal readback did complete for both entire roots.

An initial compile guard invocation was rejected before dispatch because its log
and receipt were inside the selected generated root. The corrected invocation
selected `B/tools` as that root, leaving limits unchanged. `B` retains an explicit
post-event provenance note; no original command log or receipt was produced for
that pre-dispatch configuration rejection.

| Retained artifact | SHA-256 |
| --- | --- |
| `B/tools/builder` | `13302d54dc3b56010c033185611e8abdea61659d8c54d8f20494429c043b0257` |
| `P/sha256.json` | `4aa0c09e05c0d4fe3180a909648ebb344881ec1d2d6e60bba5d959148d93a284` |
| `P/api-impl.jar` | `0daae54d7755b255ed3335f58d8cafd6da4d03c8c95343ebb0f174d166da6916` |
| `P/classes.dex` | `6cf2173aedc5adbf187aed5db4c37a8a95a413cc35343272cd45c88f2734d615` |
| `B/compile.guard.json` | `90e46c8eb60de5c13c79c4bd15ad2a7247e310f1b7f85d9d4b5249ec03e7f812` |
| `B/selftest.guard.json` | `ce81fa84631617dba10c6fd5eddb53d4a90303e0f4e4f6dc56046abf84457454` |
| `B/produce.guard.json` | `6219a3f040bbad692f28cf2cc1637432bbe9c2b955541c42ab268be364cf9d26` |

The seal binds both closed roots and 7,495 entries at
`S/auth-exception-framework-sealed-2026-10-29-r1/sealed/manifest.json`, SHA-256
`3ca7985fd3ffae66fa3f61f68965f660d264509597b680523d7fca4e1544e879`.
The adjacent seal/check guard pins are
`85d26df739211ec3566116c86f7c14b5803c3a60fe635d5896705c85611c0b7c` and
`38ec9053d5454899b03bcceea711474f27bb7d0f91ffcd69ddf8fdc40f55ac6a`.
Keep the complete bundles unchanged; this report does not replace them.
