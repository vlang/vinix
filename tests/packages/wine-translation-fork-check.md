# Translated fork regression

The [probe](wine-fork-probe/main.v) checks 32 sequential forks without an exec
after the fork. Each child and its parent perform different arithmetic loops
with independent, fixed expected results. A child reports success only after
its result matches; the parent checks its own result and the child's wait
status before continuing. The final marker requires all 32 children to have
been reaped. Explicit checks remain active in production builds.

The [retained report](results/2026-10-23/translation-fork.json) records a known
failure, with the complete [guest serial log](results/2026-10-23/translation-fork-serial.log).
Normal and production macOS AArch64 controls each produced 32 child markers and
one final marker. Changing the first expected child result in a private source
copy produced exit status 1 and no success markers. The generated production
probe retains both arithmetic loops and their conditional back edges.

The [controller](wine-translation-fork-check.v) builds a static x86_64 probe and
a native AArch64 [guest](wine-translation-fork-guest/main.v). The guest verifies
real, effective and saved UID/GID 1000, no supplementary groups, and an absent
`VINIX_ALLOW_WX` before executing the pinned translator with its split RW/RX
patch. It does not run Wine. PID 1 waits with a bound and attempts group cleanup
and descendant reaping on failure. The host stops and reaps QEMU; this fixture
does not prove guest shutdown or complete descendant cleanup.

The captured ARM run failed after 8.246 seconds. It reached the ordinary-user
and probe-start markers, then both translated processes emitted interleaved
QEMU internal SIGSEGV diagnostics immediately after the first fork. No child or
final success marker appeared. The controller exited 1 without interruption.
Shared split-WX JIT backing across fork is a candidate cause, not a verified
diagnosis or fix. Wine/translation execution remains unqualified.

The controller requires `-prod` and binds its own source and translator patch
to embedded bytes. Separate normal-build and post-build source-mutation checks
each returned the exact refusal with exit status 1 and no success marker. The
ARM run captured 9,603 selected inputs, including whole probe/guest directories,
V libraries, target sysroot/GCC files, boot inputs and resolved helper tools.
Complete input sets and generated outputs matched after build and boot; the
evidence helper rechecked their hashes again before retaining this report.
Generated probe/guest C, ELF files, literal argument vectors, logs, inventories
and the controller executable digest are bound by the report. The original
controller's generated C is not part of that receipt. Ambient transitive tools
and Clang resource headers are not frozen, so this is not a hermetic build.

From the repository root, with the existing local qualification inputs:

```sh
export V="$PWD/build/package-https-runtime-work/toolchain/v"
export VEXE="$V"
export V_MACOS_V3_CALLER_VEXE="$V"
export V_MACOS_V3_CALLER_VEXE_PRESENT=1
export V_MACOS_V3_CALLER_VCHILD_PRESENT=0
export V_MACOS_V3_NO_FALLBACK=1
export V_C_ERROR_BUG_REPORT_DISABLED=1
FORK_ROOT="$PWD/build/package-wine-calculator-worktree"
"$V" -backend c -cc /opt/homebrew/opt/llvm/bin/clang -prod \
  -gc none -manualfree -keepc \
  -path "@vlib|$FORK_ROOT|$FORK_ROOT/tests/hardware-platform|@vmodules" \
  -o build/wine-translation-fork-check \
  "$FORK_ROOT/tests/packages/wine-translation-fork-check.v"
build/wine-translation-fork-check "$FORK_ROOT" \
  "$PWD/build/package-wine-translation-fork-new" "$V" \
  "$PWD/build/pty-kernels/aarch64/vinix" \
  "$PWD/build-aarch64-x86-translation/staging/usr/bin/qemu-x86_64" \
  "$PWD/build-aarch64-x11/sysroot" \
  "$PWD/build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0" \
  "$PWD/build-amd64-x11/sysroot" \
  /opt/homebrew/Cellar/musl-cross/0.9.11/libexec/lib/gcc/x86_64-linux-musl/14.2.0
```

The output directory must be new. The retained failing output is
`build/package-wine-translation-fork-qualified-1`; host controls are under the
calculator worktree's `build/wine-fork-host-*`, and controller refusal controls
are under `build/wine-fork-controller-guards` in the main checkout.

## Cause, 2026-11-11

The failure comes from forcing split RW/RX in user mode, not from the account
or the kernel. QEMU's memfd split buffer maps one `tcg-jit` memfd twice, both
`MAP_SHARED` (`alloc_code_gen_buffer_splitwx_memfd` in `tcg/region.c`). After a
non-exec `fork()`, parent and child share those pages but each keeps its own
copy of the region allocator. Each process writes new translations and jump
patches over the other's code. Upstream enables split-wx only for system
emulation (`tcg_accel_instance_init`), so the binary patch in
`tools/packages/wineadapter/patch.v` turns on a mode QEMU never supports here.

The [A/B check](wine-fork-splitwx/check.v) boots one AArch64 guest and runs the
same retained probe three times:

| Variant | Result (run 1 / run 2) |
| --- | --- |
| Stock translator, root, `VINIX_ALLOW_WX=1` | 32 children reaped, status 0 / same |
| Split RW/RX translator, root | internal SIGSEGV after the first fork / same |
| Split RW/RX translator, uid 1000 | internal SIGSEGV / hang, killed at 60 s |

The fault addresses (`0xf900427472a0045c`, `0x529a68d4f9001274`) are AArch64
instruction words loaded as pointers, which fits overwritten generated code.
The runs used kernel `build/pty-kernels/aarch64/vinix` (SHA256 `246ce2e5…4771`),
the retained probe (`ea340091…1ae7`), the stock translator (`9025933d…1671`) and
the retained split translator (`93f1e83f…5475`). Their serial logs are under
`~/.cache/vinix-forkwx/` (`run-1/serial.log` `f5452883…985f`,
`run-2/boot/serial.log` `c82886c6…e96de2`).

## Fix, 2026-11-11

The approved fix is a translator built from source. The Dota translator builder
(`build-support/dota2/qemu-stage`) now applies
[`splitwx-fork.patch`](../../build-support/dota2/qemu/README.md) on top of QEMU
9.1.2. When the host refuses an RWX page, the translator chooses split RW/RX
itself. `fork_start` copies the used JIT bytes into a fresh memfd while every
vCPU is stopped, and the child maps that copy over both views. Hosts that allow
W+X keep the single RWX buffer. QEMU's configure needs Python with `tomli`. The
user approved Python for this third-party build on 2026-11-11. The interpreter
was a private venv made from `/usr/bin/python3` with the `tomli==2.0.1` that the
builder already pins, passed as `VINIX_DOTA2_QEMU_PYTHON`. Alpine 3.21 had
replaced three pinned development packages (`pcre2-dev` 10.43-r1, `zlib-dev`
and `zlib-static` 1.4-r0), so their pins were updated.

With that translator (`21bbd59f…ca83`) supplied as the check's third argument,
the same boot adds three variants:

| Variant | Result |
| --- | --- |
| Rebuilt translator, uid 1000, no W+X exception | 32 children reaped, status 0 |
| Rebuilt translator, root, no W+X exception | 32 children reaped, status 0 |
| Rebuilt translator, root, `VINIX_ALLOW_WX=1` | 32 children reaped, status 0 |

None of these variants logged an internal SIGSEGV, while the Alpine split
translator still failed in the same boot. The serial log is
`~/.cache/vinix-forkwx/run-3/boot/serial.log` (`12f69ae4…a96`). A repeat boot
(`run-4`) gave the same six results. The packaged Wine
runtime still stages the binary-patched Alpine translator. Moving it to the
rebuilt one, and requalifying Wine itself, is the next step.
