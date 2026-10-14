# Package lock and launch lease admission

The previous reader opened the package lock and launch generation lease without
`O_NONBLOCK`. Replacing either with a FIFO stalled the call before it could
report damaged state. The bounded baseline probes reproduce both stalls; their
two-second alarms terminate the children with wait status 14. Writers could also
chmod and lock an existing FIFO without checking its type.

All package lock opens now use `O_NONBLOCK`, `O_NOFOLLOW` and `O_CLOEXEC` and
inspect the captured descriptor with `fstat` before chmod or flock. Launch leases
use the same regular-file check and acquire their shared lock nonblockingly.
The older Config-taking launch API shares the service's reader admission. Failed
lease admission closes the descriptor and its independently decoded state.

Read-only entry points consistently require a lock beside active state, cached
catalogs or retained trust history. A missing lock cannot silently turn existing
state into an unlocked read. Fresh-image status, policy, repository listing and
Software views remain available without creating a store. Malformed entries are
preserved; recovery requires stopping workers/applications before restoring
trusted coordination files, then retrying verification.

The [core assertions](../../tools/packages/pkgcore/coordination_test.v) exercise
FIFOs without peers, directories, live/dangling links, sockets, missing files and
exclusive holders in bounded child probes. They check fresh-image reads and
missing-lock refusal before damaged retained metadata is parsed. Under a
32-descriptor limit, 128 valid reader/writer/lease cycles preserve exclusion,
128 malformed reader/writer cycles and 128 malformed lease cycles retire their
descriptors, and restored files permit normal admission. This measures descriptor
lifetimes; it does not measure whole-service heap retention.

The maintained [CLI lifecycle fixture](distribution-cli.v) applies two-second
deadlines to malformed-lock probes for status, verification, planning, Software
view, policy, repository review and mutation. Failures must return exit 1 without
a panic. Activation, catalog/history/state hashes, cached objects, abandoned
stages and external link targets remain unchanged. Restoring each lock permits
successful payload verification, followed by the normal signed deployment,
offline mirror, rollback and removal workflow.

Run the core assertions with the pinned V compiler:

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/package-coordination tools/packages/pkgcore/coordination_test.v
/tmp/package-coordination
```

Sanitizers use clang ASan/UBSan with leak detection disabled and undefined
behavior fatal. Maintained staging validates static service/session/Linux SDK
runner output and target ELF machines on AArch64 and x86_64. These checks do not
qualify guest execution, power-cut durability or graphical login. Public publisher
enrollment, catalog migration and wider runtime acceptance remain roadmap gates.

Fourteen distinct core assertion runners passed across the broad run and final read-only followup. The complete signed CLI lifecycle, final sanitizer runner and both maintained target stages passed. The original bounded FIFO failures and corrected fixture-diagnostic attempt are retained separately. Compiler notices and generated-C warnings remain in private build logs.

- [Host, CLI and target results](results/2026-10-14/coordination-host.txt).
- [Baseline and initial attempt](results/2026-10-14/coordination-baseline.txt), [final sanitizer results](results/2026-10-14/coordination-asan.txt).
- [Source/compiler/artifact ledger](results/2026-10-14/coordination-toolchain.json).
