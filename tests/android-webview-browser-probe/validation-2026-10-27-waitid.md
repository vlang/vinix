# Browser child-status diagnostic — 2026-10-27

The separate browser probe can now record the actual child status returned by
its existing `waitid` calls. This diagnostic addresses the missing exit status
in [r12](validation-2026-10-26-r12.md); it does not establish the crash cause,
browser completion or Google account sign-in.

The pinned interposer is loaded with musl's explicit `--preload` argument only
for the UI probe. The helper trampoline builds its own loader arguments without
the interposer. Each call forwards the original arguments once and preserves
the native result and errno. At most 32 successful waits with a populated child
PID produce numeric records. No extra wait or child watcher consumes status.
The module is built with `-no-builtin`; independent generated-C review checked
its native enum/function-pointer ABI and that module initialization does not
initialize standard I/O, signal handlers or an allocator.

Host regressions pass for exact argument/pointer forwarding, successful and
failed return values, errno, an invalid output pointer on failure, empty polls,
null output, the output cap and a failed stderr write. A real libc first-symbol
resolution test also preserves errno through a nonblocking poll while a child
is held alive by a pipe. The preparation and session self-tests pass. The
session test ran as an ordinary user: synthetic root-protection checks run,
while its actual root-owned fixture branch is conditional on UID zero.
The AArch64 DSO exports `waitid`, needs only `libc.so`, and has no undefined
`sigaction`, `setvbuf` or `malloc` symbol. These checks do not substitute for a
guest replay.

The final prepared bundle freezes sources over base revision
`1c6a46a51dcb1b342c3d6aaea4f0f532a28e6adc`, including the uncommitted diagnostic
sources hashed in its receipt. Compiler SHA-256 is
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`.
Preparation checks 15 addon APKs, 5,568,334 archive bytes and 401 payload files.
Its external inventory self-test and complete write/check pass.

Preserve these artifacts beneath `/Users/alex/.local/state/vinix/android/`:

| Artifact | SHA-256 |
| --- | --- |
| `browser-probe-build-2026-10-26-r16-waitid/build.json` | `5a11abcd134f2eb4f83d2adb131fad01e8bddf56be601e1d4809c65737e2c4fb` |
| `browser-probe-build-2026-10-26-r16-waitid/bin/libbrowser-waitid.so` | `a8101b81339b0e8d7ebdc0a8f3700a8733f140849797ffca405c46f620a69b30` |
| `browser-probe-build-2026-10-26-r16-waitid.inventory.json` | `66afe6e6bc17a012acf7efadc326dfe2ff52eebbb6833e58a67d58dd8afe3763` |
| `browser-probe-vm-2026-10-26-r13-quiet-waitid/stage.json` before kernel replacement | `27bae349074b4218ab76c8f3626673899a17c3d0d5cac6344dd1c12eb80752f3` |

Build/test logs, the generated C reviewed for the no-builtin build and the
strict inventory recheck log are retained in
`browser-waitid-build-2026-10-26-r1/`. The fresh stage uses quiet PID1, authority
fixture r5 and recvmsg fixture r3. Its preparation passes without launching
QEMU. The owner subsequently applied the qualified P_PIDFD kernel replacement
and completed [the r13 replay](validation-2026-10-26-r13.md), which reports
SIGABRT termination of WebKitWebProcess. r14 and r15 prepared bundles retain
earlier builds from before the no-builtin correction and were not used for
that replay. The complete sealed r12 evidence remains unchanged.
