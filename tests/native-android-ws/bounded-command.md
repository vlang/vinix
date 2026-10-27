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
`rss=BYTES`, `wall_ms=MS`, `output=BYTES`, `growth=BYTES` can tighten those bounds;
`reserve=BYTES` can raise the reserve. Disk readings use bounded `df` output,
avoiding the pinned V library's macOS `statvfs` layout problem. Shared-volume
activity contributes to the observed disk decrease.

The command and ordinary compiler descendants inherit a fresh process group.
RSS is summed from bounded `ps` output about every 100 ms, including descendants
after the leader exits. These are sampled guards: transient peaks between
samples can exceed the limit, and a slow monitor can add its one-second timeout
to detection latency. Output is streamed with a strict file-size cap.

On a guard failure the runner kills the group, reaps its child, and verifies
that the group disappeared. If host policy rejects negative-PGID signals, it
repeatedly lists group members and verifies each PID's group immediately before
signaling it. Cleanup has a two-second deadline. Fixed `ps` and `df` monitors
have separate one-second/output limits and no child processes. Commands must
preserve the inherited process group; a detected descendant that changes group
causes refusal, and `cleanup_complete` describes only the original group.

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
leader with a live stdout-holding descendant, aggregate descendant RSS, and
initial disk-reserve refusal. Each fixture has an alarm, and the checker has a
30-second alarm. No VM, native build or large disk fixture is involved.
