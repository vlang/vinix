# x86 perf QEMU monitor retirement

`run-x86.v` now uses `-serial mon:stdio`. The shared `perfconsole` capture
retires QEMU by writing Ctrl-A X to its foreground terminal. With plain
`-serial stdio`, that escape never reaches a monitor, so a completed workload
can still end in forced termination after the ten-second grace period.
The maintained runner selfcheck now checks the exact monitor arguments.

The unused `C.WIFEXITED` declaration in `tools/sourcecommand/core.v` was also
removed. Its integer return type conflicted with V's boolean declaration when
the x86 runner imported both `sourcecommand` and `hwhost`. This module uses
`waitid` and has no `WIFEXITED` call sites.

`x86-mux-check.v` executes the actual shared `perfconsole.capture` against two
sequential host QEMU processes. They differ only in their serial argument.
Both use `-machine none -nodefaults -display none -S`: no kernel, disk,
firmware or guest workload is supplied. Each capture reaches its half-second
timeout, drains output, and checks that no waitable child remains. An explicit
production-safe check requires exit 0 for the monitor and signal status -9 for
plain stdio, with a fifteen-second bound per capture.

Build and run from a repository checkout, using a fresh external state path:

```sh
v -enable-globals -keepc -cc clang \
  -path '@vlib|@vmodules|tests/desktop-perf|tests/hardware-platform' \
  -o /external/x86-mux-check tests/desktop-perf/x86-mux-check.v
/external/x86-mux-check /external/new-mux-state \
  /absolute/qemu-system-x86_64 /absolute/checkout /absolute/complete-v-root/v
```

The fixture requires actual `df` admission of 2 GiB, a 1 GiB floor between
cases, and a 64 MiB state limit. These observations are sampled checks, not a
filesystem quota. It inventories the selected QEMU, itself, the complete V
root and its maintained source dependencies before and after execution.
Installed host loader and SDK dependencies are not made hermetic.

## Retained host qualification, 2026-10-26

Source base `b05cd0c0e49e49de5db0434e0dc3e58e9767e77c` plus this change.
The retained original V executable has SHA-256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`.
Normal and production x86 runners compiled and each passed 26 selfchecks,
including 15 refusals. The normal runner also passed 18 APFS clone controls.
The maintained monitor fixture compiled and passed:

| Serial argument | Actual capture status | Elapsed | Final child check |
| --- | --- | --- | --- |
| `mon:stdio` | 0 | 0.519 s | `ECHILD` |
| `stdio` | -9 | 10.512 s | `ECHILD` |

The outer controls command exited 0, with its own final `ECHILD` observation.
Every build/control input map before and after has SHA-256
`489580e27e6ffd4600e94d33a966c3089f50d346fc08e21a5285fdeb86efd259`.
The fixture's qualification receipt has SHA-256
`ce6af473af0f51662b4977867911f09fbed89ee491fa9feafea6ffa683e1f19d`.
The retained commands used private `VTMP` and `VMODULES`, the original complete
compiler root and the recorded host environment. They did not use `-nocache`
or the later wait-width overlay; this is no qualification of either profile.
Independent source review found no blocking issue.

Complete attempts remain under
`/Users/alex/Library/Caches/vinix-codex/section14/package-perf-x86-20261026/`.
`mux-host04` includes command arguments, statuses, environments, input maps,
generated C, binaries, source copies and results. Earlier failures remain:
`mux-host01` used an empty capture working directory. Its early refusal is
consistent with the child's `chdir` failure before `execve`; that fixture did
not preserve a child status, so exit 127 is a source-based inference.
`mux-host02` refused a missing input-link target;
`mux-host03` refused an obsolete `tests/hardware` inventory path.

The complete inventory for each quiescent attempt is
`mux-hostNN-seal01/inventory.json`, with SHA-256:

| NN | Inventory SHA-256 |
| --- | --- |
| 01 | `d892671c1bfab488c6e068de330dec05900a53a0d42152148aacbada70907804` |
| 02 | `9bcca78947ff2f274780d79af67b58d12b7f7b5695fb528e5eb70e93a2375830` |
| 03 | `0d0adec59ec24c0557422bd055efba148260af9f8701eced254369a913f968a5` |
| 04 | `667803322634b1c58fe505f109a2154032d2ab9db3a7e4ea50f929b4d341e497` |

Each seal checked its complete file/link/directory inventory after writing.
All four attempts and their seals together occupy 19,340 KiB, below 64 MiB.
These controls qualify host monitor retirement. The six guest performance
scenarios still require a fresh run with the corrected prepared command.
