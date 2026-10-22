# Process permission and local IPC

The explicit SDK `process` permission supplies both `proc` and `unix`. Programs
such as Neovim use child processes, socket pairs and local RPC together. The
grant adds no unveiled paths, Internet promises, display authority or devices.
Pathname sockets remain subject to unveil; abstract Unix sockets have no
filesystem path. Applications without this permission receive no Unix promise
unless their separately declared hosted display requires it.

The launch fixture checks 40 plans across both architectures, all four package
kinds, regular/terminal modes and native window protocols 1/2. It checks both
presence and absence of the grant, a single Unix promise, exact payload/runtime
and private-data paths, and absent Internet promises and X11 environment. The
existing 36-case ownership matrix checks the resulting plans for 1,000 warmed
plan/close cycles per case with zero retained tracked bytes. Dependency growth,
partial refusal and session handoff ownership checks also pass.

Recorded on 2026-10-23 using V `0.5.2 fd996fc`, `-cc clang -nocache
-no-skip-unused -gc none -manualfree -enable-globals` and the repository/accounts
module search paths:

- [ordinary host assertions](results/2026-10-23/process-ipc-host.txt)
- [tracked allocation checks](results/2026-10-23/process-ipc-heap.txt), adding
  `-d track_heap`
- [ASan/UBSan checks](results/2026-10-23/process-ipc-asan.txt), adding
  `-cflags '-fsanitize=address,undefined -fno-omit-frame-pointer'` and
  `-ldflags '-fsanitize=address,undefined'`, with leak detection disabled and
  sanitizer errors fatal
- [authenticated X11 path/environment checks](results/2026-10-23/process-ipc-x11.txt)

Compile `tools/packages/pkgcore/launch_ownership_test.v` for the first three
checks and `tools/packages/pkgcore/x11_launch_test.v` for the fourth. Run the
ownership binaries sequentially: their existing fixture filenames are shared.
These host checks qualify launch plans and V storage ownership. Actual socket
execution and application compatibility require separate native guest results.
