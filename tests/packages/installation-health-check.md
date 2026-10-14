# Installed permissions and desktop launcher repair

Payload hashes alone previously made an executable with no execute bit, an
executable data file, or a missing/altered desktop launcher look healthy. Verify
and identical install could return success without restoring those properties.

Installed payloads now require mode 0755 for signed executable files and 0644
for other files, including absence of special permission bits. The captured
file descriptor admits and rechecks the mode, with the final pathname identity
check enforcing the same mode. Cache/publisher source verification remains
independent of installed modes. Applications also require canonical generated
desktop launcher/MIME bytes in an ordinary leaf file at mode 0644. Data/runtime
packages have no launcher requirement. Staging sets launcher permissions
explicitly, so umask 077 produces the same usable installation.

Install, upgrade and both managed deployment formats bind mode/launcher faults
to the existing affected-package IDs, review rows and disk estimate. Verify and
rollback enforce the same installation rules. Launch checks payload modes before
execution. Discovery is read-only; repair stages new files rather than changing
permissions through existing aliases. A valid regular hard-linked launcher is
readable; repair of its mode/content stages an independent inode. Per-user MIME
defaults and personal data stay outside the generation.

The [public service/CLI probe](installation-health-check.v) signs an app, runtime
and architecture-independent data package. Eight cases alter app/runtime/data
modes, delete or change a launcher, substitute a symlink or hard link, or change
launcher mode. Every case preserves signed payload bytes, checks Verify refusal,
stale healthy/restored approvals and same-version update rows, then repairs from
cache with the upstream objects removed. Initial install and repair run under
umask 077. Outside bytes/modes, catalog, replay history and private app data must
survive; healthy retry is a no-op. Rollback refuses the damaged old generation,
then succeeds after explicit restoration, and uninstall removes registration.
The direct service also restores a mode in its resolve observer to check refusal
before cleanup. `--before` reproduces false Verify/install success on the prior
service for executable permissions and a missing launcher.

The [core assertions](../../tools/packages/pkgcore/installed_health_test.v) cover
captured mode changes at all hashing checkpoints, special bits retained by the
host filesystem, cache isolation, canonical UTF-8/multiple/empty-MIME launcher
bytes, missing/symlink/FIFO/directory/content/mode refusal and runtime/data
exclusion. The tracked build requires zero retained bytes over 128 healthy and
registration-damaged discovery cycles. Canonical launcher assembly and expected
hashing have explicit scratch ownership. This measures discovery, not the whole
service.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/installation-health tests/packages/installation-health-check.v
/tmp/installation-health /tmp/new-installation-health
/tmp/installation-health /tmp/new-installation-health-cli /path/to/vinix-package
```

The [target controller](installation-health-runtime-check.v) runs core assertions
and the signed service probe on both architectures. Controlled parent directories
and writer serialization remain required. Same-authority writes after checks,
extra unlisted files, ACLs, owner/directory repair and system-wide XDG/user-default
rebuilding are outside these checks. The service does not trust/reconstruct
corrupt installed metadata from launcher text. Broader graphical-session,
foreign-runtime and public publisher/catalog release gates remain open.

## Recorded results, 2026-10-14

The previous service (`0c9e21ad9`) reproduced Verify and unchanged install
reporting healthy success for a non-executable app and a missing launcher. The
final public service and real CLI passed all eight installation fault cases,
including runtime/data modes, altered launchers and symlink/hard-link aliases.
They repaired offline from verified cache under umask 077, preserved unrelated
bytes/modes and app data, refused stale approvals and damaged rollback, then
allowed rollback after explicit restoration and clean uninstall.

Ten host assertion runners passed: installed health, payload repair, hashing,
service, registration, review, deployment, distribution, state and SDK context.
The tracked discovery test retained zero bytes over 128 healthy/damaged cycles.
Core and public-probe clang ASan/UBSan runs passed with leak detection disabled
and undefined behavior fatal. The signed CLI lifecycle passed; the ledger
records 33 successful host compile/run results. Whole-service allocation freedom
is not claimed.

Fresh QEMU TCG runs passed on AArch64 (19.5 seconds) and
x86_64 (31.9 seconds). Each ran core assertions and the
signed service probe, then shut down within its 300-second allowance. Both use
retained committed kernels; concurrent kernel edits were not rebuilt. Receipts
pin kernel, init, both programs and serial output; generated C/build logs are
pinned in the ledger. These qualify package installation health, without claiming
graphical sessions or foreign API/runtime acceptance.

Evidence:

- [previous-implementation control](results/2026-10-14/installation-health-baseline.txt)
- [host results](results/2026-10-14/installation-health-host.json)
- [host checks](results/2026-10-14/installation-health-host.txt)
- [core assertions](results/2026-10-14/installation-health-core.txt)
- [public repair probe](results/2026-10-14/installation-health-probe.txt)
- [sanitizers](results/2026-10-14/installation-health-asan.txt)
- [signed CLI lifecycle](results/2026-10-14/installation-health-cli.txt)
- [source/artifact ledger](results/2026-10-14/installation-health-toolchain.json)
- [aarch64 receipt](results/2026-10-14/installation-health-aarch64.json)
- [aarch64 report](results/2026-10-14/installation-health-aarch64.txt)
- [aarch64 serial](results/2026-10-14/installation-health-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/installation-health-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/installation-health-x86_64.json)
- [x86_64 report](results/2026-10-14/installation-health-x86_64.txt)
- [x86_64 serial](results/2026-10-14/installation-health-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/installation-health-x86_64.qmp.txt)
