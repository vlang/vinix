# Wine native checkpoint, 2026-10-23

Runtime qualification remains incomplete. Source base: `513f03f05`, with the
seven maintained source/document hashes captured in the archived checkpoint.
The failed runs predate the nested-loader correction.

- AArch64 attempt 8: signed PE failed before READY with QEMU's internal
  SIGSEGV. The separate translated-fork fixture reproduces an independent
  translator boundary.
- x86_64 attempt 9: an ordinary private-musl `wine --version` probe passed,
  but the signed PE exited 1 with empty output before READY. The same-policy
  server bridge version probe passed; direct raw-server execution failed
  because the global ELF interpreter was absent.
- The production retainer verified x86 input/output provenance and refused
  the failed outcome without creating success output. Evidence controls
  refused the real baseline before running any mutation controls.

The client adapter sets `WINELOADERNOEXEC`, which also skips Wine's early
`--version` handling. Its failing version diagnostic entered initialization;
it does not identify the sole cause of the PE failure. No native Wine,
Calculator GUI, complete corresponding source, redistribution authority, or
guest poweroff is qualified by these runs.

Audit bundle:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-native-513f03f05-2026-10-26-audit`.
The bundle contains the original run and prepared directories, raw checkpoint,
source snapshot, available host logs/tools, and 22,170 recorded input paths
(1,952,245,283 unique input bytes). Eight paths have unavailable historical
versions, listed in `unavailable-input-versions.json`. Its `SHA256.json`
inventory checksum is
`a68963b8f64f906a1289f770bf370fae45c729b7ff3e3cd96bf7f29f99f37ff6`.

Original absolute run directories remain under
`/Users/alex/code/vinix/build/package-wine-native-{arm-8,x86-9}` for historical
checkers. The archive records changed or unavailable historical input versions
separately; no checker was weakened to admit incomplete evidence. This is a
failure checkpoint, not a reproducible-build or successful-retention claim.

The native fixture checks a busy lease at READY and a free lease after all
observed Wine processes retire. The interval after the client exits while a
detached server remains alive is not qualified.
