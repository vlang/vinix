# Repairing installed package payloads

Install, upgrade and managed deployment previously returned success for identical
roots and manifests without verifying installed payloads. Software's existing
**Repair / install** could therefore leave a missing app or corrupt runtime
unchanged.

Unchanged target packages now require regular installed files with the signed
length and SHA-256. Damaged packages appear as `update` rows in the existing
format-1 review even when their versions stay equal, with full transaction space.
Sorted affected IDs bind the opaque review fingerprint. Apply checks this set
under the writer lock and again after the resolve observer before cleanup or
acquisition. Restored or differently affected packages require fresh review.
Healthy identical targets remain a no-op. Removal and rollback retain their
existing independent recovery rules.

The [public probe](repair-check.v) signs an application, runtime and independent
data package. It exercises reviewed install, upgrade and both root-only and
locked deployment documents through the service, or through a supplied real CLI.
It removes app bytes, corrupts the runtime, checks stale healthy and repair
approvals, trust/policy refusal and bad source diagnostics, then repairs offline
from verified cache. Activation must preserve package metadata, trust history,
catalog and personal data; launcher registration and verification must work.
Healthy retry remains a no-op, rollback refuses the retained damaged generation,
and uninstall still succeeds. A resolve observer also restores one affected
package to check refusal before stage cleanup.

The [core assertions](../../tools/packages/pkgcore/repair_test.v) cover size/hash,
missing files, symlinks, FIFOs and directories, changed manifest/publisher
exclusion, sorted affected IDs and operation isolation. Their tracked build runs
128 healthy/damaged discovery-and-retirement cycles with no retained bytes.
Hashing's three synchronous libc scratch records now stay on the stack instead
of escaping to the heap. This is a measurement of payload discovery, not of the
whole package service.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/package-repair tests/packages/repair-check.v
/tmp/package-repair /tmp/new-repair-work
/tmp/package-repair /tmp/new-repair-cli-work /path/to/vinix-package
```

`--before` exercises the retained previous implementation's false success. The
[target controller](repair-runtime-check.v) runs core assertions and the signed
service probe on both architectures. Writer serialization and controlled parent
directories remain required. Same-authority external writes after verification
remain outside the transaction lock. The original payload-only discovery did not
detect mode-only or launcher-only damage; the
[installation health checks](installation-health-check.md) now cover those faults.
Repair requires approved current catalog metadata and usable verified objects;
it grants no trust, permission or license exception. Broader graphical sessions,
public publisher/catalog release and foreign runtime gates remain open.

## Recorded results, 2026-10-14

The previous service (`aa7569581`) reproduced unchanged install reporting
success while its application and runtime remained damaged. The final probe
passed install, upgrade and both managed deployment formats through the public
service and the real CLI. It verified health-bound approvals, trust/policy/source
refusal, offline repair, identical healthy no-op, retained metadata and personal
data, launcher registration, damaged rollback refusal and clean uninstall.

Ten host assertion runners passed: repair, review, service, deployment,
distribution, state, policy, hash, download recovery and cache promotion. The
tracked helper completed 128 healthy/damaged cycles with zero retained bytes.
The complete signed CLI lifecycle also passed. Core and public probe clang
ASan/UBSan runs passed with leak detection disabled and undefined behavior fatal.
The ledger records 33 successful host compile/run results. No whole-service
allocation measurement is claimed.

Fresh QEMU TCG runs passed on AArch64 (29.5 seconds)
and x86_64 (50.2 seconds), running the core assertions and
public signed-service probe before orderly shutdown. Both use retained committed
kernels; concurrent kernel edits were not rebuilt. Five-artifact receipts pin
kernel, init, both programs and serial output; generated C/build logs are pinned
in the ledger. These are package maintenance checks; broader graphical and
foreign application release gates remain open.

Evidence:

- [previous-implementation control](results/2026-10-14/repair-baseline.txt)
- [host results](results/2026-10-14/repair-host.json)
- [host checks](results/2026-10-14/repair-host.txt)
- [core assertions](results/2026-10-14/repair-core.txt)
- [public repair probe](results/2026-10-14/repair-probe.txt)
- [sanitizers](results/2026-10-14/repair-asan.txt)
- [signed CLI lifecycle](results/2026-10-14/repair-cli.txt)
- [source/artifact ledger](results/2026-10-14/repair-toolchain.json)
- [aarch64 receipt](results/2026-10-14/repair-aarch64.json)
- [aarch64 report](results/2026-10-14/repair-aarch64.txt)
- [aarch64 serial](results/2026-10-14/repair-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/repair-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/repair-x86_64.json)
- [x86_64 report](results/2026-10-14/repair-x86_64.txt)
- [x86_64 serial](results/2026-10-14/repair-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/repair-x86_64.qmp.txt)
