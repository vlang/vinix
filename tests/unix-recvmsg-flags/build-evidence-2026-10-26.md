# Unix receive compatibility build — 2026-10-26

Kernel commit `ee0d3b6ff3d2586a0e5f35a27042643afaa298f3` accepts inert
`MSG_NOSIGNAL` on Unix receives. An independent review found no new allocation
or lifetime changes. The extracted production mask passed 124 host cases; the
previous mask failed the required negative control. Actual guest syscalls and
the WebKit IPC retest remain pending.

Artifacts are retained under `/Users/alex/.local/state/vinix/android/`:

| Bundle | Receipt SHA-256 | Complete inventory SHA-256 |
| --- | --- | --- |
| `unix-recvmsg-flags-build-2026-10-26-r3` | `e15f100836821c82b947e56ff0821668ce56e86880cfe45f748be91c7c286e83` (`build.json`) | `c107951f4e36f0a7106f4bfaa6e50086944088c9fbdc1f046e79d067e0aef4af` (`sha256.json`) |
| `unix-recvmsg-kernel-aarch64-2026-10-26-r3` | `29360df6915a356b021db5d868ec02e2ba51dfe32ab2b63e16368e1adf2bd4d0` (`build.json`) | `576a4c277b00e39734e0038b6952bdc3c5c279581b2d73721f830e6cafacd2ea` (`sha256.json`) |
| `unix-recvmsg-kernel-x86_64-2026-10-26-r2` | `dd5bfd871ff9960cb44ba16ca14680a11d0f40bb111643f37493845db3d7c10a` (`build.json`) | `f3dd7b1b8356bb481be1457bcdd9a88aed42570c6d2a6ccf72d21c956a67cf53` (`sha256.json`) |

The static AArch64 fixture's SHA-256 is
`48b9b323b6a2cead60c4a157802327985df6773b143c4d4ef2707b6b10ae1dc9`.
The frozen AArch64 kernel's SHA-256 is
`ac90558eac4f2ea6b74c72c3f519370e98e9f88b0a5384aa82cc386bdd1876ce`.
The x86_64 kernel's SHA-256 is
`9b1a5469b9e13531e8772f4ff29d7aa2b7c5e7c02ff8cffc1200326721a78ed1`.
All three receipts explicitly record `guest_executed: false`. The fixture tests
stream, sequence-packet and datagram receives, rejected flags preserving queued
data, nonblocking semantics and descriptor passing with close-on-exec checks.
Its final success marker is `UNIX-RECVMSG-FLAGS-PASS all=3`.

The kernel build used an isolated committed worktree, compiler SHA-256
`109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e`,
and source/tool/dependency pins checked before and after compilation. The
dependency inventory regression passed unchanged input and rejected five
mutations: added, removed, modified, type-changed and symbolic paths. The
initial maintained builder and checks are committed in `b008d764c`. The x86_64
build uses builder-source SHA-256
`7e60150e344cbe9a7545fc0bfc697fd2e7a2f7e7c77883026849edcc2a77192b`,
which also retains the host-generator source closure, tracked module symlink
targets and the compiler's Boehm archive. Its tracked-input regression passed
unchanged sources and rejected a changed symlink target and file substitution.

Earlier build attempts remain preserved. AArch64 r1 failed because the newer
compiler rejects legacy kernel types. AArch64 r2 compiled, but review found
its builder did not detect added dependency files; r3 adds that check and
rebuilds. The first x86_64 attempt stopped because its sparse source closure
omitted the native generator; r2 includes it and builds successfully. No guest
boot pass is claimed for either architecture here.
