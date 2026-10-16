# Launch-service lifecycle

The service's private `PreparedLaunch` owns its state-directory path, loaded
configuration, decoded installed state and generation lease. Failed lock,
configuration, state or lease admission closes partial ownership. Every runner
defers complete cleanup until validation or synchronous child completion.
Reset uses an empty policy instead of allocating the normal permission defaults.
Repeated close resets the lease to `-1`, so it cannot close a descriptor reused
by unrelated work. Public service/launch APIs and serialized formats are unchanged.

Reader acquisition still precedes configuration loading, and generation lease
admission still precedes reader release. Preparation returns without holding
the reader. A root caller retains no generation lease and its ordinary child
repeats admission; an ordinary caller holds the admitted lease through its run.
Closing one snapshot leaves a sibling's fields/lease valid. Caller-built
configuration snapshots remain borrowed by the Config-taking APIs.

Both architecture models exercise 1000 small preparations and 16 preparations
with 64 installed packages, repositories, allowlist entries and pins. Each closes
twice and retains zero bytes. Native ASan/UBSan exercises the same ownership
assertions. The fixture checks source replacement, independent storage, writer
admission after reader release, exclusive lease refusal while either sibling is
alive, final exclusive admission and descriptor reuse after close.

Nine refusal paths cover relative roots, a busy writer before broken
configuration, malformed configuration, missing application, malformed state,
missing/FIFO/hard-linked/busy generation leases. Each repeats 1000 times in the
tracked build with zero retained bytes. Files and activation remain unchanged;
restoring each input permits preparation and writer admission again. Root
qualification forks UID 1000 for ordinary preparation and lease failures.

Matched host probes use unchanged production sources from `b6d50e8c1` and the
same V fixture/options. Accepted previous tuples explicitly retire decoded
configuration/state and close the lease. Errors/messages are retired too.
Five preparations and five malformed-configuration refusals each retained 415
bytes of directory storage. Missing-ID, malformed-state and missing/FIFO/
hard-linked-lease refusals each retained 19,215 bytes, including configuration
abandoned after lease failure. All seven final probes retain zero. These byte
counts include this fixture's temporary pathname lengths.

The first tracked guest run exposed a separate 4096-byte allocation per root
refusal in the pinned standard library's `os.executable`. Generated C showed its
fixed path buffer moved to an unretired heap allocation. Linux session launch
now reads `/proc/self/exe` with 4097 bytes of stack scratch, accepts at most
4096 returned bytes and clones only the returned identity. Failure to read a
bounded kernel identity produces an explicit diagnostic; it does not fall back
to the caller's argv. Other host platforms retain their existing lookup. A
two-result ownership fixture compares with the existing executable identity and
tracks repeated reads/retirements. The old Linux lookup is used only once as an
unmeasured reference in that fixture.

The disposable guest explicitly opts into a real-root fixture; normal native
test invocations never configure the host installation. Its tracked worker
checks all five internal launch modes 1000 times as root and UID 1000 through
`Service.run_mode`. Root refuses an unspecified launch account. The ordinary
account refuses policy/window admission after taking a generation lease.
Every call retains zero bytes and releases its lease before return. No account
session, application or private data is created. These refusals qualify complete
service cleanup before execution; they do not qualify successful child/process
storage, full graphical login or new foreign runtime compatibility.

The existing service, coordination, state-schema, plan ownership, command,
context, session, installed-namespace and registration-parent fixtures also run.
No kernel change is involved. Roadmap 14's production publisher, advertised
catalog, graphical session/display and broader runtime/filesystem gates remain
open.

## Recorded results, 2026-10-16

All **39 focused compile/run checks** passed: ten core pairs, two harness pairs, tracked and
ASan/UBSan pairs, previous/current comparison pairs, four CLI/driver checks
and three guest-tool builds. All seven final matched probes retain zero.

Fresh QEMU TCG guests passed with clean shutdown and eight verified artifact
hashes each: AArch64 **79.8 seconds**, x86_64 **34.6 seconds**. Each service
worker was built with `-gc none -manualfree -d track_heap`; its required markers
confirm that preparation, refusals and both real-root credential paths ran with
tracking enabled. Per-program harness options add those flags only to this
worker; the init and four companion workers retain normal static-musl flags.
Deadlines qualify functionality rather than performance.

To repeat the native allocation fixture from the repository root:

```sh
v -nocache -no-skip-unused -gc none -manualfree -d track_heap \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/launch-service \
  tools/packages/pkgcore/launch_service_test.v
/tmp/launch-service
```

The guest controller is `tests/packages/launch-service-runtime-check.v`; it sets
the tracked worker flags itself and requires a built kernel. The retained V
comparison fixture is copied as `launch_service_comparison_test.v` into an
isolated `pkgcore` copy with the same module lookup. Add
`-d launch_service_baseline` only for the previous production sources.

- [matched preparation probes](results/2026-10-16/launch-service-baseline.txt), [V comparison fixture](results/2026-10-16/launch-service-comparison.v)
- [host results](results/2026-10-16/launch-service-host.json), [summary](results/2026-10-16/launch-service-host.txt)
- [core assertions](results/2026-10-16/launch-service-core.txt)
- [tracked allocations](results/2026-10-16/launch-service-memory.txt)
- [sanitizers](results/2026-10-16/launch-service-asan.txt)
- [signed CLI lifecycle](results/2026-10-16/launch-service-cli.txt)
- [source/toolchain/artifact pins](results/2026-10-16/launch-service-toolchain.json)
- [initial AArch64 executable-scratch retention](results/2026-10-16/launch-service-aarch64.before.serial.txt), [x86_64 retention](results/2026-10-16/launch-service-x86_64.before.serial.txt)
- [AArch64 receipt](results/2026-10-16/launch-service-aarch64.json), [report](results/2026-10-16/launch-service-aarch64.txt), [serial](results/2026-10-16/launch-service-aarch64.serial.txt), [QMP](results/2026-10-16/launch-service-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/launch-service-x86_64.json), [report](results/2026-10-16/launch-service-x86_64.txt), [serial](results/2026-10-16/launch-service-x86_64.serial.txt), [QMP](results/2026-10-16/launch-service-x86_64.qmp.txt)
