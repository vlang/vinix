# Bounded host build command

Compile `bounded-command.v` with normal V garbage collection enabled. Invoke it
without a shell around the target command:

```text
bounded-command root=/external/fresh-build log=/external/build.log receipt=/external/build.exit.json -- /absolute/builder ARG...
```

The generated root may be absent; its parent must exist. The log and receipt
must be fresh files outside that root. Exclusive creation preserves existing
evidence, and the receipt survives a producer that removes its generated root.

Defaults are 2 GiB aggregate sampled RSS, 300 seconds, 1 GiB free disk reserve,
512 MiB observed free-space decrease, and 4 MiB merged stdout/stderr. Explicit
`rss=BYTES` and `output=BYTES` can tighten those bounds; `reserve=BYTES` can
raise the reserve. An explicit `wall_ms=MS` can select up to 900 seconds for
complete input and readback audits; its default remains 300 seconds. An explicit
`growth=BYTES` can select a budget up to 8 GiB; its default remains 512 MiB.
Before spawning, free space must
cover the whole reserve plus the growth budget, with overflow-safe arithmetic.
For example, `growth=8589934592` requires at least 9 GiB free with the default
reserve. The reserve and observed growth limits remain enforced during the run.
Disk readings use bounded `df` output, avoiding the pinned V library's macOS
`statvfs` layout problem. Shared-volume
activity contributes to the observed disk decrease.

The command inherits a fresh process group. A nested group is supervised when
its leader is observed as a descendant and its group did not exist before the
command started. Its members remain supervised after their parent exits; an
observed empty group is retired. Joining the guard's group or an existing
unowned group causes refusal. RSS is summed across all supervised groups and
descendants from bounded `ps` output about every 100 ms. These are sampled
guards: a group created and orphaned entirely between samples cannot be proven
by ancestry, transient peaks between
samples can exceed the limit, and a slow monitor can add its one-second timeout
to detection latency. Output is streamed with a strict file-size cap.

At completion or guard failure the runner rescans descendants, kills all owned
groups, reaps its child, and verifies that every owned group disappeared. The
receipt lists all discovered groups. If host policy rejects negative-PGID signals, it
repeatedly lists group members and verifies each PID's group immediately before
signaling it. Cleanup has a two-second deadline. Fixed `ps` and `df` monitors
have separate one-second/output limits and no child processes. Unowned groups
are never signaled; if a descendant joins one, cleanup is reported incomplete.

Successful commands preserve their exit code; guard refusal returns 125. The
JSON receipt records arguments, limits, sampled peak, disk readings, output
length, child status and cleanup status. It never embeds command output.

Run the small real process controls with a freshly compiled checker and a new
external result directory:

```text
check-bounded-command /absolute/bounded-command /external/fresh-controls
```

The controls cover literal arguments, exit 37, merged output, absent generated
root, exclusive evidence creation, output overflow, wall timeout, an exited
leader with a live stdout-holding descendant, aggregate descendant RSS,
successful nested groups, cleanup of nested members after the original leader
exits, combined RSS across nested groups, and
initial disk-reserve refusal. They verify the unchanged 300-second default,
accept an explicit 900-second limit, reject larger values before spawning, and
exercise real timeout cleanup with short limits. They also verify the default
growth budget, accept an explicitly backed 8 GiB budget, reject larger values,
and check capacity
boundaries and integer overflow without writing a large disk fixture. The
maximum-budget acceptance control requires 9 GiB free. Each fixture has an alarm,
and the checker has a 30-second alarm. No VM, native build or large disk fixture
is involved.

The 2026-10-28 full control run passed in 5.38 seconds against sources based on
`fb745db92`. Production builds peaked below 342 MB RSS with zero swaps; the
control run's aggregate sampled peak was 85.6 MB, with cleanup complete. The
900-second control verifies configuration acceptance; short timeout controls
verify enforcement. Exact source snapshots, binaries, logs, receipts and a
SHA-256 manifest are retained outside Git at
`~/.local/state/vinix/android/long-audit-guard-2026-10-28-r1`.
