# Application SDK context qualification

The additive [application context](../../tools/packages/SDK.md#application-context-interface)
exposes the installed app/runtime snapshot through fifteen environment values.
The MIT-licensed V helper decodes owned strings, validates the generation
namespace and provenance fields, reports declared permissions and checks the
ordinary application's `HOME`/`TMPDIR`. It grants no additional paths or promises.

`appsdk/context_test.v` checks independent ownership, canonical encoding, literal
paths, all four supported app-kind metadata labels, explicit runtime versions,
maximum u64 counters, malformed/missing fields, bounds, traversal, mixed
generations and repeated/unknown permissions. `pkgcore/context_test.v` checks
that all launch modes derive the same fifteen values from installed app/runtime
records, including different app/runtime index sequences, while staying within
the sandbox environment limit.

`sdk-context-memory.v` runs 100 decode/load/encode/refusal/double-close cycles
after warmup with `-gc none -manualfree -d track_heap`. Consumed error objects and
owned context/vector storage are retired; the final tracker reports zero retained
bytes. The distribution driver runs this fixture and both assertion runners.
The final separate memory run also verifies cleanup after a mismatched `HOME`.
The application helper assertion runner also passes clang ASan/UBSan with
`ASAN_OPTIONS=detect_leaks=0`; that run checks exercised safety, not leak freedom.

The V guest controller builds fresh target service/account/session/init and the
updated static V `package-hello` example, using the retained native sandbox and
kernel tuple. It generates a fixture key, publishes/enrolls a local repository,
and installs direct native apps plus an app with an explicit immutable V runtime.
The example reads an explicitly granted document with literal spaces/semicolon/
dollar-sign bytes. Reading the same path as an argument without a grant fails.

Each ordinary probe verifies UID/EUID 1000, empty supplementary groups, installed
app/runtime versions and paths, current generation, publisher/key/sequence and
declared permissions. Forged ambient ID/generation values on the root caller do
not reach the application. New launches are checked after reviewed upgrade and
rollback. A held process keeps and reloads its original context after a later
upgrade, uninstall and garbage collection. Its old immutable app/runtime remain
readable while leased; after exit GC removes that generation and preserves
ordinary-owned personal data. The saved before/after context bytes match exactly.

```sh
v -no-skip-unused -path '.|tests/hardware-platform|@vlib|@vmodules' \
  -o /tmp/context-check tests/packages/sdk-context-check.v
V=/path/to/v VINIX_HWTEST_TCG=1 \
  VINIX_CONTEXT_SANDBOX=/build/target-root/usr/bin/vinix-sandbox \
  /tmp/context-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-context-arm
```

Repeat for x86_64 with its sandbox/kernel and a fresh directory. Normal
hardware-platform cross-toolchain, firmware and Limine settings apply. Passing
receipts record nine hashes: kernel, native sandbox, guest init, service,
account/session tools, native SDK example, manifest and serial log. The
functional deadline is 300 seconds and the guest must power off cleanly.
Set `VINIX_CONTEXT_EXAMPLE` to an existing matching-target ELF executable to
qualify that exact SDK example binary instead of rebuilding it in the controller.

The standalone V example builder also builds both static ELF targets with the
explicit SDK module path and SDK/V/musl redistribution notices. Its earlier
attempt retained unused OS capture functions and signal glue that could not link
with the pinned compiler. The final build uses the same pruning and signal-glue
settings as the guest fixture builder.

The full 2026-10-13 distribution driver passed 26 assertion runners, SDK context
heap retirement, CLI/PTY/Software checks and both target staging builds, including
the SDK license notice. The final SDK helper assertions pass ASan/UBSan, and the
later mismatched-HOME memory case also passes with zero retained tracked bytes.
The standalone builder's generated standard-library C emits GCC warnings retained
in its build log; the resulting example executables are exercised below.

The first successful controller-built example runs passed on both targets.
Final runs use the exact static GCC-built example objects produced by the
standalone package builder, after independently checking their package inventory
hashes. Both final guests print every required marker and power off cleanly:

- [AArch64 receipt](results/2026-10-13/sdk-context-aarch64.json) and
  [serial log](results/2026-10-13/sdk-context-aarch64.serial.txt): 23.5 seconds.
- [x86_64 receipt](results/2026-10-13/sdk-context-x86_64.json) and
  [serial log](results/2026-10-13/sdk-context-x86_64.serial.txt): 25.0 seconds.
- [Host results](results/2026-10-13/sdk-context-host.txt) and
  [compiler/source ledger](results/2026-10-13/sdk-context-toolchain.json).
- Standalone example manifests for [AArch64](results/2026-10-13/sdk-context-example-aarch64.json)
  and [x86_64](results/2026-10-13/sdk-context-example-x86_64.json), with the
  qualified binary and SDK/V/musl notice pins. These are unsigned publisher inputs.

These checks cover native package execution and application metadata. They do
not qualify Wine/Apple/Linux application APIs from a kind label, graphical
login/display brokerage, public publisher enrollment or power-cut durability.
The wider catalog and roadmap acceptance gate remain open.
