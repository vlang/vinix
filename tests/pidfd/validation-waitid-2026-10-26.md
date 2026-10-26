# waitid(P_PIDFD) compatibility

The quiet WebKit probe in
`~/.local/state/vinix/android/browser-probe-collected-2026-10-26-r11-quiet/results/browser/probe.log`
reported `waitid(pid: 21435, pidfd=34) failed: Invalid argument`. Its kernel
implemented `pidfd_open`, but accepted only `P_ALL`, `P_PID` and `P_PGID` in
`waitid`. GLib uses the descriptor selector after opening a pidfd successfully.
This establishes a compatibility gap; it does not establish the cause of the
probe's DOM timeout or its separate `g_close(fd:22)` warnings.

The change adds `P_PIDFD`, including `O_NONBLOCK`/`WNOHANG` behavior, through the
existing child-event claim and copyout path. A retained descriptor keeps the
pidfd identity record alive. A process-table pin keeps the exact target alive
across blocking waits and concurrent reaping; selection compares that pointer
instead of a reusable numeric PID. Every return releases both references after
dropping locks and releasing any child-event claim. Other wait selectors retain
their existing behavior.

The implementation follows Linux's
[waitid selector and nonblocking behavior](https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux/+/refs/heads/linux-5.15.y/kernel/exit.c)
and [pidfd descriptor validation](https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux/+/refs/heads/linux-5.15.y/kernel/pid.c).
The [GLib child-watch implementation](https://gnome.pages.gitlab.gnome.org/glib/coverage/glib/gmain.c.gcov.html)
explains why opening a pidfd successfully reaches this wait selector.

## Frozen builds

Artifact parent:
`~/.local/state/vinix/android/pidfd-wait-kernel-build-2026-10-26-r1`.
Both successful builds used committed baseline
`ecbd3964aff243304e16df45271c7de8dee4d2da` plus retained `source-r2.patch`, SHA-256
`988fd56e9388dfb12e1cbb2c58f11b55668cf433715c45519690177c884ab086`.
The earlier `kernel-aarch64` attempt is preserved: the V compiler rejected an
inferred `int` errno passed to a `u64` parameter; the successful patch makes that
conversion explicit.

| Output | AArch64 (`kernel-aarch64-r2`) | x86-64 (`kernel-x86_64-r2`) |
| --- | --- | --- |
| Kernel SHA-256 | `a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151` | `54a482432a17e83a80fd24de03ff14aaffbb0eb4746caddde58fcc22b251e03e` |
| `build.json` SHA-256 | `1e9077779aaed08188e6f8111ca9ceb27b479517ece736a58157049f004fb36d` | `afb2bd75c1ead9c5e1bf6f6f8d5acfb14b54034197b386c26c340a1e02ceafda` |
| Complete `sha256.json` SHA-256 | `32a134cc1ee3d02bfb56d91ee429ac3f5fb9895ba525021eb7aa84a7ec64f6ee` | `b5cb7e918a7a907086852a8a7040509a1712edf883dc19f3682bbcae490561e8` |

The V builder source is `tests/unix-recvmsg-flags/kernel-build.v`, SHA-256
`0557001a5cb60d9dfccdc07e60cb90f7dafea33206b59ae2f7c5f4a7b5634186`;
its retained host executable has SHA-256
`2d535210f998b6b4835214d16494dc7303d302844123623810e68b7092335d43`.
The frozen V compiler has SHA-256
`109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e`.
Each architecture has a separate detached source worktree, compiler/library
closure and dependency copy. Before/after checks bind all tracked kernel
sources, the complete shared dependency path/type/content set, dependency
symlinks, source patch, relevant host-generator sources and tool executables.
These are frozen source/dependency/compiler bundles; the host SDK and every
transitive host-tool input are not a hermetic toolchain closure.

## Lifetime review and validation status

Independent source and generated-C review found no new heap allocation,
interface box or promoted local in the changed wait path on either architecture.
The pidfd resource cast is a direct pointer; the existing child waiter remains
stack allocated. The target pin precedes process-table unlock, and the existing
event claim is released before the new outer process pin and descriptor.

Both kernel builds pass and produce matching-architecture ELF64 kernels without
an interpreter. A final independent review checked descriptor/process lifetimes,
lock ordering and both generated-C paths again before committing.

## Native guest results

The retained static fixture passed **20 ordered cases and 117 checked wait
results on each architecture**, using the frozen kernels above:

| Architecture | Complete boot bundle below `~/.local/state/vinix/android/` | Verdict |
| --- | --- | --- |
| AArch64 | `pidfd-wait-guest-2026-10-26-r1` | `LINUX PIDFDWAIT: PASS` |
| x86-64 | `pidfd-wait-guest-2026-10-26-x86-r2` | `LINUX PIDFDWAIT: PASS` |

Both raw `serial.log` files pass the retained `pidfdwait-check --mode native`.
Its 30 negative controls also pass. The fixture includes eight rounds of closing
a shared descriptor while a waiter sleeps and eight rounds racing that waiter
against a sibling's `wait4`, plus nonblocking, identity, option and copyout
checks. These bounded correctness cases do not measure allocation retention.
No Linux-reference execution is claimed.

The fixture build is `pidfd-wait-fixture-build-2026-10-26-r2`, inventory SHA-256
`a62b9744831e92dc571bf48578ccde021b7cce4f54d0a36f42db7ef9c9c37d31`.
Its original fixture commit is
`63e15657060c9314086fa230be1a3723f0881837`, applied to this checkout as
`16881a175`. The independent 234-file compile/inventory recheck is retained in
`pidfd-wait-fixture-recheck-2026-10-26-r2`. The checker/reference tools are in
`pidfd-wait-host-tools-2026-10-26-r2`, inventory SHA-256
`bf956bd039b0932a97415d41c5a61ce708e31026eb3b37120de2e8ed46d6f400`.

The generic V runner used prebuilt init executables. The AArch64 wrapper command
was `tests/kernel-gaps/run-native --arch aarch64 --kernel-dir
<kernel-aarch64-r2>/source/kernel --state-dir <aarch64-boot>
--prebuilt-init <fixture-build>/aarch64/init --expect 'LINUX PIDFDWAIT: PASS'
--fail 'LINUX PIDFDWAIT FAIL' --no-network --timeout 180`. The x86-64 run used the
retained `pidfd-wait-native-runner-build-2026-10-26-r1/generic-run`, matching
architecture paths, and both `LINUX PIDFDWAIT DETAIL:` and `LINUX PIDFDWAIT FAIL:`
failure markers. Its host stdout is retained as
`pidfd-wait-guest-2026-10-26-x86-r2-run.log`; the earlier AArch64 host stdout
exists only in the session transcript. The runner does not produce an inputs
receipt. Complete generated ISOs, initramfs, roots and raw UART are preserved;
ISO-extracted kernel and init bytes independently match both frozen builds in
`pidfd-wait-runtime-check-2026-10-26-r1`.

The failed maintained AArch64 compile attempt is retained separately in
`pidfd-wait-native-2026-10-26-aarch64-r1` (missing cross-link startup/libgcc
inputs). The first x86-64 boot preparation, `pidfd-wait-guest-2026-10-26-x86-r1`,
stopped at a Limine HTTP 502 before QEMU. Neither is counted as a guest verdict.

## Complete evidence seal

`~/.local/state/vinix/android/pidfd-wait-complete-evidence-2026-10-26-r1/manifest.json`
has SHA-256
`d4adfbd22f7530cf68e4175665d1b2012b57c61152cc0908de579bfc55880440`.
The retained V sealer binds 18 complete, nonoverlapping external roots and
12,912 path entries: successful and failed kernel/fixture builds, both native
boots and failed preparation, checker/reference and runner sources/executables,
compile rechecks, ISO extraction, and sealer source/executable/self-tests.
It verifies directory membership, modes, regular-file bytes and literal symlink
targets. Referents outside these roots, host SDK/tool transitive dependencies
and hostile concurrent namespace mutation are outside this inventory's scope.
The 10 sealer controls pass. Recheck the complete retained bundle with:

```sh
<evidence>/seal check <evidence> \
  d4adfbd22f7530cf68e4175665d1b2012b57c61152cc0908de579bfc55880440
```

This report establishes native wait compatibility. It makes no Google account
authentication or browser-success claim; a separate WebKit replay must assess
its application behavior.
