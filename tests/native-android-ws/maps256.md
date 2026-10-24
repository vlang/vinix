# Maps256: map, search and route preview; missing automated result

Manually reviewed screenshots show the unchanged signed Maps APK progressing
past onboarding to a rendered map, Paris search suggestions, Paris place details
and photos, and driving directions from Eiffel Tower to Paris: **19 minutes,
6.1 km**. Route preview displays **“Head toward Pont d’Iéna”**. The final
next-step click has no subsequent screenshot, so advancing that instruction was
not verified. Some action chips display extra square indicators; subsequent
inspection traced these to synthesized checkbox indicators on styled CheckBox
subclasses. GPS, sign-in and voice navigation were not verified.

The suite was configured for 900 seconds, but did not publish `results.json`.
Its harness log ends with a missing-result panic and QEMU termination. The
cause of the publication failure is unestablished. There is no completed
automated classification or demonstrated 900-second endurance pass. Serial
output reaches the native backend and contains neither the previous
thread-priority permission failure nor a recorded application exit. Account
provisioning and the production credential launch path are retained; this run
emitted no independent post-drop process credential tuple.

The prelaunch source revision is
`52d20c9ca4743379f27841b6436acc1e615a4ae7`. The external bundle is
`/Users/alex/.local/state/vinix/android/maps256-2026-10-24`. Its immutable
73-entry prelaunch `frozen-inputs.json` has SHA256
`7b602e16397db66cb23df41e421238656d0e1d493f29e2fb71683d7c33e1fb64`.

The assertion-enabled [`maps256-evidence.v`](maps256-evidence.v) retains every
ordinary raw run file, supplemental harness and driver logs, the complete
109-file runtime, private post-run boot and firmware media, frozen source and
receipt inputs, and matching compiler binaries. It verifies the original APK
bytes, all 106 baseline runtime files, production build and credential fixture
receipts, lossless account provisioning, and the complete actual FAT archive
against the retained runtime. Hidden files, symlink targets and empty
directories are inventoried; unexpected special files are rejected. This
partial-run checker preserves the historical completed-run checkers’ contracts.

The final 348-entry `sha256.json` has SHA256
`2d664ac6bf11a10fcb84fd96493c6084ba17ff9b6d56b2523b32f24b004bc196`.
The retained auditor source has SHA256
`4a1f348caa9f7d5f5a142c558e90b09bb875310117248af53641377fffe1a87f`.
The retained boot and firmware hashes also match Maps257’s independent
prelaunch clones.

Rebuild and check from the repository with assertions enabled:

```sh
/Users/alex/code/v/v -cflags -O2 -o /tmp/maps256-evidence \
  tests/native-android-ws/maps256-evidence.v
/tmp/maps256-evidence check \
  /Users/alex/.local/state/vinix/android/maps256-2026-10-24 \
  2d664ac6bf11a10fcb84fd96493c6084ba17ff9b6d56b2523b32f24b004bc196
```

Sealing passed all source, receipt, runtime, raw-output and actual-media checks.
Negative tests rejected an authentic manifest-only partial bundle and an
all-zero manifest pin. The tree self-test retained a hidden file, dangling
symlink and empty directory, omitted an actual `qmp.sock` socket, and rejected
a FIFO named `qmp.sock` and an unexpected socket. A separate `-prod` build
exited 2 before input access. The separate full recheck passed and removed its
extraction scratch.

Logs are retained beside the bundle as `maps256-2026-10-24-seal.log`,
`maps256-2026-10-24-check.log`, `maps256-2026-10-24-negative.log`,
`maps256-tree-test-2026-10-24.log` and
`maps256-prod-guard-2026-10-24.log`. Negative and tree fixtures remain in
`maps256-2026-10-24-negative/` and `maps256-tree-test-2026-10-24/`.
