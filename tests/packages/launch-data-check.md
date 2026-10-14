# Preparing private application data

The baseline launch accepted an app-data symlink, created `tmp` in its target
and changed the target from `0755` to `0700`. The reproduction reaches the real
launch path after validating its installed state and payload. On the host the
sandbox executable is absent; the unsafe filesystem changes happened before
that failed spawn. The synthetic payload contains invalid ELF bytes.

Launch now shares inventory and purge's captured account-home traversal. Each
data component is opened relative to an already captured descriptor with
`O_DIRECTORY`, `O_NOFOLLOW`, `O_NONBLOCK` and `O_CLOEXEC`. Creation uses `mkdirat`
with mode `0700`. Existing home and parent modes remain unchanged. Ownership and
shared writable modes are checked before using a component; app data and its
temporary child must stay on their respective parent filesystems. Both entries
are validated before `fchmod` makes the captured data/tmp directories private.
Trust, payload and document admission still precede data preparation.

Failure preserves the unsafe entry and its external target. Correcting it permits
retry with existing contents intact. Newly created ordinary parents may remain
after a later error; this preparation is not a data transaction. These checks
do not mediate another unsandboxed process of the same account concurrently
moving paths during path-based sandbox setup.

[Host assertions](../../tools/packages/pkgcore/launch_data_test.v) cover private
owned creation, idempotence, retained app/tmp contents, inventory, purge and
recreation; aliases and dangling links, FIFOs and regular files at every data
component; app/tmp sockets; unsafe modes, wrong ownership, invalid home/ID input;
and refusal before the real launch path mutates an alias target. Child refusal
probes have two-second deadlines. Repeated success and failure run under a
32-descriptor limit, followed by a restored-directory retry. Existing purge,
inventory, document, context, command, window, session, coordination and signed
distribution checks remain separate regressions. ASan/UBSan disables leak
detection; descriptor checks do not establish whole-service heap retention.

The V [guest controller](launch-data-check.v) builds a fresh service, account/
session/authentication tools, guest init and small SDK-1 [probe](launch-data-probe.v)
around a retained target kernel and production sandbox. The focused scenario
uses both actual administrator and standard accounts with supplementary groups.
It checks the isolated caller identity, private data/tmp, planted home-parent,
app and tmp aliases, special/foreign/shared entries, refusal before probe output,
preserved external targets, corrected-entry relaunch, offline reinstall with
retained data, and account-local purge. The marker set and ten input/serial
artifact hashes are required in each successful receipt.

```sh
V=/path/to/v V_MACOS_V3_NO_FALLBACK=1 /path/to/v -nocache \
  -path '@vlib|@vmodules|tests/hardware-platform' \
  -o /tmp/launch-data-check tests/packages/launch-data-check.v
V=/path/to/v VFLAGS=-nocache V_MACOS_V3_NO_FALLBACK=1 \
  VINIX_HWTEST_TCG=1 VINIX_LAUNCH_DATA_SANDBOX=/path/to/native/sandbox \
  /tmp/launch-data-check --arch aarch64 --kernel /path/to/kernel \
  --state-dir /tmp/launch-data-arm --scenario packages-launch-data --timeout 240
```

Use matching x86_64 inputs for the other architecture. The existing
[distribution driver](distribution-check.v) includes the new host assertion file.
This qualifies the exercised application-data paths, not graphical login,
display brokerage, public publisher enrollment or the wider runtime catalog.

Twelve native core assertion runners, three ASan/UBSan runners, the full signed
CLI lifecycle and real HTTPS regression passed. Both fresh TCG guests passed
with actual account isolation and explicit QMP guest shutdown: AArch64 in
30.295 seconds and x86_64 in 31.759 seconds. The retained kernels and sandbox
artifacts are identified in each receipt.

Initial guest build attempts exposed a V cross C callback-signature inference
problem and a probe C declaration mismatch. Moving the conditional outside the
callback argument and matching the standard-library declarations allowed fresh
builds with default unused pruning. Progress/recovery and real HTTPS checks
passed after the callback adjustment. Initial diagnostics are retained separately.
The x86_64 boot uses an explicitly selected, hash-validated retained Limine cache.

- [Host and CLI/HTTPS results](results/2026-10-14/launch-data-host.txt), [sanitizers](results/2026-10-14/launch-data-asan.txt).
- [Baseline and initial build attempts](results/2026-10-14/launch-data-baseline.txt).
- [AArch64 receipt](results/2026-10-14/launch-data-aarch64.json), [serial](results/2026-10-14/launch-data-aarch64.serial.txt), [shutdown](results/2026-10-14/launch-data-aarch64.qmp.txt).
- [x86_64 receipt](results/2026-10-14/launch-data-x86_64.json), [serial](results/2026-10-14/launch-data-x86_64.serial.txt), [shutdown](results/2026-10-14/launch-data-x86_64.qmp.txt).
- [Source/compiler/artifact ledger](results/2026-10-14/launch-data-toolchain.json).
