# Package document grants

Package launches now inspect the resolved document's file type. The pinned V
compiler's `os.is_file` only excludes directories, so the previous admission
check also accepted FIFOs, sockets and devices. Every launch mode now requires a
regular file. Links to regular files remain usable, and original document paths
and literal arguments keep their bytes. Refusal identifies the path and precedes
application data creation and execution.

[The host assertions](../../tools/packages/pkgcore/document_test.v) cover all five
launch modes with both architecture configurations: ordinary, terminal, native
window, literal command and literal terminal command. Regular files and aliases
retain their `rw` grants and normal argument handling. FIFOs, sockets, devices,
directories, missing paths, dangling/cyclic links and links to special targets
fail. Existing command assertions still cover declared permissions, literal
arguments and working folders. Clang ASan/UBSan passes; leak detection is disabled.
The same new assertions against the previous committed launcher fail at the
first FIFO grant, demonstrating the regression.

[The ordinary-account guest fixture](../accounts/guest/package_isolated_launch.v)
makes 78 refused requests through the real authentication/session/package service:
13 direct/link targets, three launch modes, administrator and standard accounts.
Both application data directories remain absent and private transport sockets
are retired. Targets include a real block-device node as well as `/dev/null`.
Ten accepted CLI/window launches read and update regular files and aliases with
spaces in their names; a readable neighboring file remains hidden. Writes open
the existing file without `O_CREAT`, consistent with the unchanged `rw` grant.
The original group/identity, stdio, PTY, window, trust/tamper and audit checks also
remain required.

Run the host assertion runners directly with the pinned V compiler:

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused -gc none \
  -o /tmp/document-check tools/packages/pkgcore/document_test.v
/tmp/document-check
```

Run [the guest controller](isolated-launch-check.v) as documented in the
[ordinary launch qualification](isolated-launch-check.md), with a new state
directory and the appropriate production sandbox/kernel. It now requires:

`PACKAGE DOCUMENTS ordinary-admin-standard regular-and-alias read-write outside-denied special-target-refusal before-data clean-runtime PASS`

Both QEMU TCG guests passed: **AArch64 in 93.8 seconds**, **x86_64 in 117.8
seconds**, with clean guest shutdown and nine verified input/serial hashes each.
The guest init and package/account/authentication/session programs were built
from current sources. The final AArch64 init was rebuilt after an initial fixture
write incorrectly requested `O_CREAT`; its unchanged production programs were
reused from that first build. The [initial failure](results/2026-10-13/document-grants-initial-aarch64.txt)
is retained. Both guests use the previously qualified production kernel/sandbox.

- [AArch64 receipt](results/2026-10-13/document-grants-aarch64.json),
  [serial](results/2026-10-13/document-grants-aarch64.serial.txt) and
  [QMP](results/2026-10-13/document-grants-aarch64.qmp.txt).
- [x86_64 receipt](results/2026-10-13/document-grants-x86_64.json),
  [serial](results/2026-10-13/document-grants-x86_64.serial.txt) and
  [QMP](results/2026-10-13/document-grants-x86_64.qmp.txt).
- [Host checks](results/2026-10-13/document-grants-host.txt),
  [previous-launcher regression](results/2026-10-13/document-grants-baseline.txt) and
  [toolchain/source/artifact ledger](results/2026-10-13/document-grants-toolchain.json).

This verifies document admission and real sandbox access on the retained
kernel/compiler tuple. The full distribution/UI suite was not rerun for this
launch-only change. Grants use the
existing path-based sandbox policy; they do not pin an inode or document version.
Graphical login presentation, public publisher enrollment and full catalog/runtime
migration remain separate roadmap gates.
