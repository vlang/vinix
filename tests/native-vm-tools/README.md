These commands compile native V host controllers directly:

```sh
tests/browsers/run_vm --firefox --timeout 1800
tests/browsers/run_vm --libreoffice
tests/browsers/run_vm --steam
tests/activity-monitor/run --arch aarch64 --kernel /path/to/worktree/kernel
tests/activity-monitor/run --arch x86_64 --kernel /path/to/worktree/kernel
tests/pointer-scroll/run --kernel-dir /path/to/worktree/kernel
```

The browser controller preserves all seven hosted application profiles, their
feature and failure markers, default memory/deadlines, launch environment,
128 KiB recent window, ten-second result wait and 5/2-second shutdown stages.
Its final report checks the entire captured byte stream. The office and Steam
shell entry points use this controller directly.

Activity Monitor retains its existing C guest fixtures, static build recipes,
isolated boot environment, merged serial log, final cleanup output and original
`ACTIVITY-CHECK DONE failures=0` verdict. The x86 initramfs is written in V as
USTAR, retaining the original member order, executable bytes and mode.

Pointer scrolling builds the unchanged V fixture, writes its private initramfs,
waits for readiness and sends the same left/right/up/down button press/release
events. Its QMP connection parses one JSON greeting, skips asynchronous events
while awaiting replies and preserves returned errors. Readiness and per-axis
deadlines remain 120 and ten seconds. The serial log is published after cleanup
on both success and failure.

PTY and pipe owners reserve each leader PID through private group retirement
and the sole reap. Signals and capture errors still retire those owners. The
pipe API merges stderr and changes directory through SDK spawn actions, with
no shell or interpreter adapter.

`qualify.v COMPILER NEW_EVIDENCE arm|x86|san` performs five cold builds and checks
1,280 marker combinations against frozen original profile data, defaults,
exclusions, launch environments, 100 actual port retirements, 27 controlled process cases and three real static
guest ELF/initramfs builds. Process cases include split/large output, nonzero
exit, descendants, timeout, escalation, integer overflow, SIGINT/SIGTERM, real
Unix QMP, BOM-prefixed JSON, malformed replies, EOF and exact PID/descriptor
retirement. Another 100 actual serial-EOF/QMP races check failure logs and
retirement. Existing QMP and archive/decoder regressions also run.

Qualification executes no Python or Vinix guest. It checks native host control,
protocol, build and lifetime behavior; the application and kernel verdicts need
their actual guest workloads.

`tests/roblox-windows/run` also invokes this native controller. Its complete
download, manifest, ZIP, layer, PTY/FIFO, upload, XWD/PNG and verdict path is in
`vmhost/roblox_*.v`. `qualify-roblox.v COMPILER NEW_EVIDENCE arm|x86|san`
checks two cold builds, frozen original package/XML data, duplicate ZIP entry
identity, Unicode/path/cache/error fixtures, twenty concurrent real uploads,
an unfinished request, actual streamed curl responses and twelve real owned
PTY/FIFO cases including EOF, timeout, escalation, descendants and signals.
Three complete controlled CLI runs check preparation, refresh, native USTAR,
upload/frame/report output, empty timeout failure and exact child retirement. The native ZIP reader
supports the stored/deflated formats used by deployment packages; unsupported
methods fail explicitly. HTTP connection and stalled-transfer limits remain
60/120 seconds through curl. No Python, proprietary client or Vinix guest runs
during qualification.
