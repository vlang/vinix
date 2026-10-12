# Native core VM controller

The current runner and five saved allocation-campaign copies invoke V directly.
`corevm` implements the CLI, exact result policy, PTY launch, stream forwarding,
shutdown and persistent ARM reboot sequence. The SDK header contains declarations
and types only. No Python is executed or needed to launch the controller.

The 47 general feature markers, two amd64 markers, final markers and four failure
markers retain their original bytes and exact-once policy. ARM keeps 2048 MiB,
the disposable 64 MiB persistent volume, environment overrides, ten-second final
shutdown window and five/two-second retirement grace periods. amd64 keeps the
two-second final-marker window, four-CPU default and inherited environment.
Its result still ignores a nonzero emulator exit after observing all markers,
as the original does. Saved four-level runners retain `max,-la57`; the earlier
two copies and current runner use `max`. The native CLI diagnoses omitted ARM
inputs or ISO before launching. Saved ARM runners retain their original default
root relative to the captured directory; use `--root` for a runnable repository.

The native owner builds argv and environment vectors before fork, performs only
SDK signal/chdir/exec operations in the child, and establishes cleanup immediately
after launch. It observes the leader with `waitid(...WNOWAIT)` and kills its group
before the sole reap. All master reads are on the supervising thread and stop
before retirement. Closing the master after termination and before reaping fixes
an observed macOS teardown stall in an interrupt fixture. The owner also bounds
amd64 shutdown when an emulator ignores SIGTERM.

The independent `test-vm` command reads frozen original source as data, verifies
its SHA256 and derives the marker lists without running Python. It checks every
missing and duplicate marker, each failure marker, original exit/timeout policy,
CLI bounds, empty paths, environment preservation and both CPU models. Real PTY
fixtures split markers across writes, send 256 KiB of preceding output, verify
control-a/x, cover nonzero exits and retired descendants, and check one hundred
launches against an exact descriptor baseline. Native command tests cover ARM
success and failure on the second boot, amd64 PATH lookup and timing, resistant
timeout cleanup, SIGINT/SIGTERM statuses and descendant retirement.

Run the fixture against source recovered from the commit in the receipt:

```sh
git show SOURCE:tests/qemu-core/run_vm.py > /tmp/core-runner-original.txt
V=/path/to/v tests/qemu-core/run-vm --help
V=/path/to/v tests/qemu-core/test-vm /tmp/core-vm-check \
  /tmp/core-runner-original.txt /path/to/compiled/native/run-vm
```

ARM, Rosetta x86 and ARM ASan/UBSan qualification logs and frozen inputs are
retained under `~/.cache/vinix-core-vm-native-20261012`. These are host controller
checks. No fresh kernel build, emulator boot or guest regression is claimed;
the existing guest test program, fixtures, captured logs and production deadlines
are unchanged. Historical JSON records still identify their original Python
paths and hashes; the receipt pins those original Git blobs rather than rewriting
the captured evidence.
