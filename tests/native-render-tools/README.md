The G17 host, native-fixture and VM commands, the VirtIO/VirGL VM command, and
the production random self-test build runner use this V module. Their maintained
entry points are:

```sh
tests/agx-fake-g17/run
tests/agx-fake-g17/run_encode_native --arch aarch64 --kernel-dir DIR --state-dir NEW
tests/agx-fake-g17/run_vm --timeout 180
tests/virtio-gpu-virgl/run_vm --desktop-startup --timeout 900
tests/krandom/run_native --arch aarch64 --kernel-dir WORKTREE/kernel --v COMPILER --state-dir NEW
```

The G17 commands invoke the existing native verifier, fixture builder and guest
policy directly. Guest executables pass to `tests/kernel-gaps/run-native` with
the original timeout and markers. Child setup no longer uses an interpreter
adapter. Observation reserves the child PID through process-group retirement
and the final reap.

The VirGL controller retains byte marker boundaries, report order, renderer
checks, the 128 KiB recent window, 250 ms reads, ten-second result deadline and
5/2/2-second shutdown phases. V owns the PTY, transcript and scratch directory.
Capture errors and signals complete shutdown before returning. The shared
Unicode 13 formatter retains stage quoting and arbitrary-width integer input.

The random runner requires an isolated git worktree and exclusive state directory
before removing ordinary generated-C objects. It preserves the exact make flags,
merged build log and native guest verdicts; the production kernel is unchanged.

`test-tools.v` compares all 71,944 saved original G17 policy cases, checks VirGL
boundaries, reports, host guards and launch environments, and runs 25 actual
controlled child-process cases. Those cases cover PTY and QMP shutdown, split
markers, large output, failure, nonzero exit, timeout, forced kill, descendants,
integer overflow, SIGINT and SIGTERM, with exact PID/descriptor retirement.
It also checks random build recipes and builds four real static G17 executables
for both architectures, forwarding them to a controlled native boot endpoint.

`qualify.v COMPILER NEW_EVIDENCE arm|x86|san` performs four cold program builds,
the original policy comparisons, process cases, recipe checks and actual static
links. The committed source qualification additionally refreshes the CLI on all
three profiles, tests public help/guards and cold frontends, and runs unchanged
V and frozen C G17 host oracles on ARM and Rosetta x86 with ASan/UBSan.

These checks execute no Python or Vinix guest. They establish host controller,
build-input and cleanup behavior. Actual rendering still requires the matching
guest workload and host GPU; native AGX firmware execution requires hardware.
Seven retired originals total 23,037 bytes and 586 lines at
`1ba937e300b056f303fc4e1889ff7f9c942f0fda`. Source snapshots, binaries, logs,
failures and receipts are retained under
`~/.cache/vinix-render-tools-native-20261013`.
