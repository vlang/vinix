# Desktop performance and startup smoke tests

`run` invokes the native V controller to compare static AArch64 desktop builds in
one QEMU boot. It measures each
scenario for every build and alternates build order between rounds. The default
scenarios are `idle,apps,pointer,drag`; use `--scenarios` to select a subset.

```sh
tests/desktop-perf/run new=/path/to/vinix-desktop \
  --scenarios=idle,apps,drag --rounds=1 --settle=3 --seconds=5 \
  --shots=/tmp/vinix-perf-shots --json=/tmp/vinix-perf-results.json
```

`--initramfs=PATH` selects a cached desktop image. `VINIX_KERNEL_DIR` selects an
existing kernel build. The harness stages the requested desktop binaries through
the guest overlay and keeps its serial log, JSON, and requested screenshots. It
removes temporary VM disks and overlay files after a run, including failures.
A missing measurement, malformed metric, missing completion marker, timeout,
guest error, or panic fails the run while preserving partial results.

Use `--scenarios=ops,churn,cache` to measure kernel retention without a desktop.
`ops` warms a full 200-operation cohort on tmpfs and EXT2, then repeats it and
waits 13 seconds on both snapshots for cascading deferred reclamation. `churn`
uses one native observer to warm and run
each short program 300 times, validate its exit and compare memory and slab
objects/pages without adding shell diagnostic helpers to the after snapshot.
Tracking kernels also print `PERF-SITE` allocation chains. See
[memory-retention qualification](../memory-retention/README.md).
These scenarios need a cached image containing all four churn programs and
their libraries; a missing program or unsuccessful child exit fails the run.
The default timeout accounts for the longer warmup and reclamation waits.

The optional native scenarios are:

| Scenario | Requested clients | Minimum measured processes |
| --- | --- | --- |
| `utilities` | Preview, Console, System Information | 4 |
| `storage` | Archive Utility, Disk Utility, Backup | 4 |
| `productivity` | Notes, Reminders, Grapher | 4 |
| `tools` | Color Meter, Calculator, Notes | 4 |
| `workflows` | Dictionary, Text Editor, Calendar, Files | 5 |

Counts include the compositor. These scenarios install the native executable
aliases in the guest so older cached images can launch the current clients.
They open the applications and leave them idle for startup, rendering, CPU and
memory checks. Review `--shots` output alongside the measurements. Application
operation and persistence checks also run in `desktop/tools/test-new-utilities.sh`.

`workflows` requires `--dictionary-data=DIR`, pointing to already-prepared local
`dictionary.vnd` and `LICENSE.WordNet`. The harness checks regular files, the
portable format header, payload length and size bounds, then copies both files
unchanged into `/usr/share/vinix/dictionary` through the VM overlay. This supplies
the offline lexicon even when a cached initramfs predates Dictionary. The harness
never prepares or downloads dictionary data.

```sh
tests/desktop-perf/run new=/path/to/vinix-desktop \
  --scenarios=idle,apps,workflows,drag --rounds=1 --settle=3 --seconds=5 \
  --dictionary-data=build/dictionary/staged \
  --initramfs=/path/to/cached-desktop-initramfs.tar \
  --shots=/tmp/vinix-workflow-shots --json=/tmp/vinix-workflow-results.json
```

The desktop image builders prepare these assets. See
[Dictionary data preparation](../../build-support/dictionary/README.md) for the
pinned archive and preserved license.

Preparation, PTY supervision, Unix QMP, pointer workers, transcript validation,
partial JSON and summary policy run in V. A separate reader continuously drains
serial output while QMP replies or pointer workers are waiting. Shutdown joins
the workers and reader and retires the guest process group before closing their
resources. Interrupts preserve cleanup and the captured transcript.

Saved allocation-benchmark directories have native `run` fronts. They select
their original libc overlay and eight scenarios, including the historical
35-row operation contract; the current operation workload has 36 rows. The saved
v6 preparation also has native `pipeline`, `run-driver` and `validate-completed`
fronts, preserving captured manifests and validating results against the serial
transcript. Running a saved workload requires its matching frozen `measure.c`
and initramfs from the original preparation; those external inputs are not
bundled in the captured result directories. Existing payloads and logs remain
unchanged.

Run `tests/desktop-perf/run-host-tests.sh` for native report, controller, saved
driver and resource checks. `sh -n tests/desktop-perf/perf-init.sh` checks the guest
script without booting QEMU. See [native qualification](native-tools.md) for the
tested boundaries and the limits of host fixture evidence.

The retained `run-arm.v` and `run-x86.v` adapters generate their PID1 through
`perfproducer.generate_init`, using the maintained freestanding V module path.
The initializer uses native C-width libc calls and stack shell arguments.
Its copied source and generation argv/log join the prepared input pins.
The ARM initializer needs libc only; the sampler keeps its existing link recipe.

`init-check.v` builds the unchanged production initializer plus a syscall-wrapped
probe for console errors, existing `/root`, mount diagnostics and shell handoff:

```sh
v -cc cc -path 'tests/desktop-perf|tests/hardware-platform|tests/linuxkpi|tools|@vlib' \
  -o /external/init-check tests/desktop-perf/init-check.v
/external/init-check build /path/to/v /path/to/vinix /path/to/support /external/fresh-build aarch64
/external/init-check check /external/native/serial.log aarch64
/external/init-check controls /external/native/serial.log aarch64
```

Use `x86_64` for the other architecture. ARM support supplies `sdk` with the
musl/GCC layout used by the compatibility fixtures; the host selects clang or
`x86_64-linux-musl-gcc` from PATH. The generated `probe` runs as PID1 with
`ppollsignal-host.v native` and `VINIX_COMPAT_CASE=perfinit`, using that host's
retained launcher support and an explicitly selected kernel. The probe wraps
mount and exec calls: it checks the initializer contract, without qualifying
real disk mounts, a running shell or desktop performance. See the
[current build and guest receipts](../../docs/linux-performance-harness-builds.md).
