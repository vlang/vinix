# Personal application data purge

`vinix-package purge-data ID` and the additive SDK 1 `Service.purge_data(id) !`
erase a removed application's data for the calling ordinary account. Root and
alternate installation roots are refused. Uninstall/rollback continue to retain
personal data until this explicit command.

The service holds the package reader lock through deletion, refuses installed
IDs, strictly checks retained generation metadata and probes the leases of every
generation containing that ID. A live lease blocks purge before any personal
files are removed. This is conservative: another account/application using the
same generation also blocks purge. The reader lock prevents reinstall and
collection races; new launches cannot enter a removed application.

The home and `.local/share/vinix-apps` components are opened individually without
following symlinks and must be caller-owned, with no write access for other
accounts. The deletion walk uses directory descriptors, rechecks identities
before unlinking directories, streams filenames and closes each child before
opening the next. Nested symlinks are unlinked without traversing their targets;
FIFOs/sockets are unlinked without opening them. Top-level aliases/special files,
filesystem crossings and excessive directory depth are refused. Missing data is
a no-op. Storage errors or concurrent changes can leave partial cleanup.

[Host assertions](../../tools/packages/pkgcore/purge_test.v) cover nested links,
ordinary data with spaces/punctuation, FIFO/socket removal, all three parent
aliases and the final app alias, wrong ownership, shared parents, invalid IDs,
installed refusal, a live obsolete generation, malformed metadata and a FIFO
lease, top-level special files, replaced directory identity and depth limits.
A 96-branch tree and 128 retained app generations pass with
`RLIMIT_NOFILE=32`. The same assertions pass clang ASan/UBSan with leak detection
disabled. The existing full CLI lifecycle/refusal runner also passes.

[The ordinary-account guest fixture](../accounts/guest/package_purge.v) launches
a signed native app through the real account transport, removes both installed
apps and collects garbage while that app stays alive. Administrator and standard
accounts are refused purge, and their data stays intact. After application exit,
collection retires the old generation and both accounts can purge their own data;
a repeated purge succeeds. Parent/top-level aliases leave outside files intact,
and nested links/FIFOs are safely removed. Installed/root refusals and all existing
isolation, document-grant, stdio, PTY, window and trust/tamper checks remain required.

Build/run the host assertions directly:

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused -gc none \
  -o /tmp/purge-check tools/packages/pkgcore/purge_test.v
/tmp/purge-check
```

Use [the ordinary-launch guest controller](isolated-launch-check.v) with a fresh
state directory as described in [its qualification](isolated-launch-check.md).
The controller additionally requires:

`PACKAGE PURGE installed-root-refusal live-uninstalled-lease retained-data safe-links nested-fifo idempotent-own-account PASS`

Both QEMU TCG guests passed using fresh guest/package/account/authentication/
session builds and retained production kernels/sandboxes: **AArch64 87.0 seconds**,
**x86_64 61.5 seconds**. Functional deadlines apply; these times are not performance
qualification. Both shut down cleanly and each receipt binds nine input/serial
hashes. The current graphical desktop and full runtime catalog were not tested
by this CLI/storage change. Graphical login, publisher enrollment, broader
runtime qualification and catalog migration remain roadmap gates.

The previous qualified AArch64 package service, with this exact guest init and
current account/session programs, fails at the live-generation refusal: its
purge returns success while the uninstalled application remains alive. The
baseline controller accepts only that expected assertion failure. This is a
regression witness, separate from the two passing current-service guests.

- [AArch64 receipt](results/2026-10-13/purge-data-aarch64.json),
  [serial](results/2026-10-13/purge-data-aarch64.serial.txt) and
  [QMP](results/2026-10-13/purge-data-aarch64.qmp.txt).
- [x86_64 receipt](results/2026-10-13/purge-data-x86_64.json),
  [serial](results/2026-10-13/purge-data-x86_64.serial.txt) and
  [QMP](results/2026-10-13/purge-data-x86_64.qmp.txt).
- [Previous-service failure](results/2026-10-13/purge-data-baseline.txt),
  [host checks](results/2026-10-13/purge-data-host.txt) and
  [source/toolchain/artifact ledger](results/2026-10-13/purge-data-toolchain.json).
