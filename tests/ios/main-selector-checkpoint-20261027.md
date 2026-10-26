# Main-thread selector checkpoint — 2026-10-27

Runtime and audit tools: `31a10cd367df8ad2729f9ac40747aff4c54f72ed`.
Advertising remains skipped.

`performSelectorOnMainThread:withObject:waitUntilDone:` now dispatches the
requested selector with its object argument. Waiting on the main thread runs
inline, including from a main-queue callback; waiting on a worker blocks until
the main thread executes the call. Nonwaiting calls are deferred. Pending
asynchronous work retains its target and argument through execution or shutdown
cancellation. Method lookup includes inherited and built-in implementations.
The method's native type encoding and introspection are also supported.

Validation:

- Shared native Foundation and emulated-runtime cases verify method metadata,
  introspection, inline/deferred/nested execution, worker waiting, main-thread
  affinity, FIFO ordering, built-in targets and target/argument ownership using
  weak references. Runtime cancellation releases pending calls without invoking
  application code; two start/stop cycles return object counts to zero.
- Host tests pass under ASan/UBSan with normal and deterministic hashing and
  assertions enabled. Leak detection is disabled and sanitizer errors are fatal.
  The ARM64 selector fixture, supervisor and application runner build freshly.
  All 14 guest regression fixtures return wait status zero.
- Complete evidence passes seal, independent check and mutation selftest.
  Mutations reject missing or duplicated native/runtime results, failed fixtures
  and builds, changed startup/panic/desktop/exit/memory observations, missing
  fault registers or guest media, altered provenance and unmanifested files.
  Historical evidence checkers remain unchanged.

Fortnite advances past the main-thread selector failure and stops at:

```text
V panic: iOS: unimplemented Objective-C method UIWindow viewWithTag:
IOS-PROBE-DESKTOP: stop=desktop pipe closed handshake=true builds=2 polls=1 closed=false supervisor_kill=false wait=256
IOS-PROBE-BUDGET: final current=27178 events=low 0;high 0;max 0;oom 0;oom_kill 0;oom_group_kill 0;
FORTNITE PROBE: process exit status 1
FORTNITE PROBE COMPLETE
```

Harness status zero means the diagnostic completed. The application exits 1
with raw wait status 256, without a supervisor kill or cgroup OOM. Its desktop
peer validates two tree builds with one root, no images and 336 bytes each.
The second tree's printed line is interleaved with VM tracing; the complete
peer stop record confirms both builds. This peer has no compositor or input
device, so these observations do not qualify a rendered game frame.

The probe retains three loaded/bound images, nine completed Objective-C
`+load` calls, three completed initializer groups, application entry and 13
inline pthread-self translations. A tagged 24 GiB virtual reservation succeeds;
eight process-headroom queries remain positive inside the 2 GiB cgroup. The
sole signal fault is deliberate fixture input, with all 31 ARM64 registers
captured and execution restored.

Progress remains **4/8 observable gates (50% of this checklist)**: load/binding,
Objective-C `+load`, image initialization and application entry are verified.
A rendered game frame, interactive menu, login and playable match remain
unverified. This fraction does not estimate remaining work or time. The prior
UTF-16 diagnostic began with `Fail`; its full message and underlying cause
remain unverified. `--probe-no-ads` binds SKAdNetwork to nil and changes
application behavior.

Complete evidence is preserved outside Git at
`/Users/alex/Library/Caches/vinix-ios/main-selector-verified-20261026`, VM state
`probe-no-ads-4671791`. It contains 1216 runtime-source records, 699 selected
build-input records and 1570 manifest records. Audit-tool
sources are also recorded separately. SHA-256 of `manifest.sha256`:

```text
8897bae68e6d221efa13011a41d46463115a29849f5385f85a443955c2218b41
```

The unchanged Fortnite 42.30.1 executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
Its complete application directory is an APFS clone checked against the prior
manifest. Thirteen fixtures and their generated C (26 files) are reused;
the selector fixture, supervisor and runner are rebuilt. Preserve the complete
prior bundle at `/Users/alex/Library/Caches/vinix-ios/cf-string-input-20261026`,
manifest SHA-256
`294e15b834d314df3333d5d4924c7cb0fe540355c93a4c9cfdf87e9b88483bed`.
Its independent checker passed before preparing this bundle. The prebuilt
kernel is inventoried, not rebuilt. Selected input hashes do not seal complete
compiler, header or host-library closures.

Reproduce from an isolated checkout of the revision above using the frozen
compiler at `build/ios/fortnite/ns-calendar-checks/toolchain/v` and a fresh
external output directory. Set `V_RESOURCE_PATH` to that toolchain directory,
`V_MACOS_V3_NO_FALLBACK=1` and `V_C_ERROR_BUG_REPORT_DISABLED=1`. Compile
`tests/ios/main-selector-run.v` with `-nocache -gc none -cc clang -cflags -O2`,
without `-prod`, preserving assertions. Run `prepare OUT PRIOR`, `fixture OUT`,
`build OUT`, `host OUT`, `probe OUT` and `audit OUT FULL_REVISION`. The audit
exports committed runtime and audit sources and rebuilds its tools. Run
`OUT/main-selector-evidence seal OUT`, `check OUT`, `selftest OUT` and
`hash OUT/manifest.sha256`; keep audit output logs outside the sealed bundle.
Exact commands, statuses, generated artifacts, boot media and serial logs
remain in the complete bundle.
