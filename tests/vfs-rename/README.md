# Concurrent rename replacement

This native V fixture runs a writer and reader as UID/GID 1000 in a private
mode-0700 tmpfs directory. Each of two phases replaces a mode-0600 destination
4,000 times with complete eight-byte files. The reader counts failed opens and
incomplete or mixed data, and enumerates the directory during replacement.
The second phase fills the directory to exercise map growth and collision
shifts. Both phases retain an old descriptor past the kernel's five-second
retirement grace period, then require its original content, owner, permissions
and zero link count. Missing destination names or listings fail the run.

Build kernels in separate worktrees, with the dependency symlinks described
in the repository's `AGENTS.md`. Run each with a fresh artifact directory:

```sh
V_C_ERROR_BUG_REPORT_DISABLED=1 USE_TCG=1 tests/kernel-gaps/run-native \
  --no-network --arch x86_64 --kernel-dir /path/to/x86-worktree/kernel \
  --state-dir /path/to/fresh-x86-result \
  --source tests/vfs-rename/renamefixture/core.v --expect 'RENAME REPLACE: PASS'

V_C_ERROR_BUG_REPORT_DISABLED=1 USE_TCG=0 tests/kernel-gaps/run-native \
  --no-network --arch aarch64 --kernel-dir /path/to/arm-worktree/kernel \
  --state-dir /path/to/fresh-arm-result \
  --source tests/vfs-rename/renamefixture/core.v --expect 'RENAME REPLACE: PASS'
```

The ARM command uses HVF on macOS; use TCG on hosts without acceleration.
Both commands use the maintained V guest controller and a declaration-only
musl ABI header. The only privileged setup creates and transfers the private
directory before dropping groups and UID/GID. The workload adds no permissions.

On 13 October 2026, the original focused x86 probe found 468 `ENOENT` errors
in 4,000 replacements on isolated commit `9b01dbca2`. The complete fixture
also failed on that kernel: directory enumeration lost the continuously
existing `current` entry (site 22). The kernel SHA-256 was
`aab1de81485a74deb8b4fb766a61c6b9502b426867b900a896ad7cc1cc0368d3`.
The retained controls are `build/development17-20261013/rename-x86-current-before`
and `rename-x86-final-before`.

Publishing the destination without deleting its key removed the common gap,
but an intermediate kernel still recorded two missing opens in the crowded
phase. V map insertion, deletion and compaction also need synchronization
with ordinary path lookup and directory enumeration. The final fix protects
these map accesses with a short lock, publishes replacement and deletes source
under one acquisition, and keeps backend hooks, reparenting, notifications
and grace retirement outside that lock. New directory dot entries are
initialized before publication. Procfs and sysfs keep their existing locks.

The final fixture passed both phases on both architectures:

| Guest | Sparse reads | Crowded reads | Missing/open/data errors | Retained result |
| --- | ---: | ---: | --- | --- |
| x86_64 TCG | 8,256 | 8,096 | 0 / 0 / 0 | `rename-x86-synced-c` |
| AArch64 HVF | 12,608 | 11,008 | 0 / 0 / 0 | `rename-arm-synced-c` |

Both kernels were built from isolated `9b01dbca2` plus the six filesystem
changes. Final kernel hashes are
`abbf8e176bd68c45191c3c6274052e1bca262ed7b95a20b4d05449134dec10f1`
(x86_64) and
`2033980d61274fd37a0b69ad3df04aca261162de0a40a8c5d9f37ffeb6573c2d`
(AArch64). An independent review checked lock ordering and inode/resource/parent
lifetimes. The allocation allowlist audit still fails on the unchanged baseline
and final kernels; all 182 reported file/kind counts match. The allowlist was
not expanded.

The final AArch64 kernel also passed the complete
`ops,churn,cache,idle,apps,drag` desktop harness run. All 36 syscall rows kept
zero bytes per operation after reclamation; each of four 300-process churn
rows kept zero bytes per run. The cache phase wrote 32 MiB and recorded a
16-MiB page cache. Idle, application launch and drag scenarios completed with
their required process counts. Results and screenshots are retained in
`build/development17-20261013/rename-desktop-perf-synced.json` and
`rename-desktop-shots-synced`.

The final kernels also passed the scheduled native Go CI gate on AArch64
(`rename-arm-ci-synced`, 22 validated records) and the account/job/build plus
authenticated HTTP gate on x86 (`rename-x86-http-synced-b`, 19 records). An
earlier x86 HTTP run, `rename-x86-http-synced`, failed a connection with errno
103; its failed receipt remains retained separately from the rename controls.

These results qualify this regular-filesystem replacement and map-access fix.
The separate overlay replacement gap and failed-backend destination loss are
covered by [the overlay fix and native qualification](../overlay-rename/README.md).
Overlay retention and durable whiteouts, full OCI/runtime, service and server-load
acceptance remain open.
