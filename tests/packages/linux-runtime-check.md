# Dynamic Linux package qualification

The V controller builds a target musl dynamic executable and a shared V library,
the static SDK Linux runner, and the production native sandbox. It checks that
the executable has both PT_INTERP and PT_DYNAMIC before staging. The guest
imports the prepared app/runtime roots with the actual `pack-root` CLI, creates
a throwaway signing key, authenticates/enrolls a local repository through the CLI
and installs the Linux app.
The runtime includes upstream copyright and Vinix licensing documents.

```sh
V=/path/to/v v -path '@vlib|@vmodules|tests/hardware-platform' run tests/packages/linux-runtime-check.v \
  --arch aarch64 --kernel /build/arm/kernel/bin/vinix \
  --state-dir /tmp/package-linux-arm
V=/path/to/v v -path '@vlib|@vmodules|tests/hardware-platform' run tests/packages/linux-runtime-check.v \
  --arch x86_64 --kernel /build/x86/kernel/bin/vinix \
  --state-dir /tmp/package-linux-x86
```

Use a current kernel with the account-session and sandbox interfaces. The usual
[hardware controller options/toolchains](../hardware-platform/README.md) apply.
The payload builder additionally needs the matching `ARCH-linux-musl-gcc` with
dynamic `libc.so`; `VINIX_MUSL_CC_AARCH64` and `VINIX_MUSL_CC_X86_64` can select
compiler executable paths. Provide the corresponding musl copyright file with
`VINIX_MUSL_COPYRIGHT` when it is not at `build-support/musl/COPYRIGHT`.
No network repository, desktop, release credential or shell is needed. The
controller captures the kernel before building, and validates all fixture ELF
targets before embedding them. State directories must be new or empty.

The real `vinix-session` handoff and `vinix-sandbox` execute the signed runtime's
runner, which execs the signed musl loader. Its `--library-path` resolves the
external fixture library in the runtime's `usr/lib`; the executable's ordinary
host PT_INTERP path is bypassed. Guest assertions cover:

- Absolute guest and relative library symlinks becoming regular signed files.
- The runtime being installed as a dependency, with no extra requested root.
- Read-only full-closure review exposing the runtime and publisher, followed by
  fingerprint-bound install. Reusing the pre-install review fails as stale.
- A shared-library call returning 23, UID/EUID 1000 and zero supplementary groups.
- Literal arguments containing spaces, semicolons and a dollar sign.
- Private-data writes as the user; host libraries, the package tool and unrelated
  same-user data hidden by the production sandbox.
- Runtime library tampering being refused before execution; restoring the signed
  bytes permits launch again.
- Reviewed upgrade to a signed runtime without the required shared library producing
  the loader's library-name diagnostic and status 127; reviewed rollback restoring launch.
- That runtime-only update appearing in `view` and `--json updates` with the
  resolved version, publisher and action while the application's version stays
  unchanged. After the reviewed upgrade, Updates returns an empty success.
- Reviewed uninstall removing both the app and unused runtime while preserving user data.
- Repository revocation denying launches/rollback while reviewed uninstall remains
  usable, and an empty refresh retaining the sequence floor. Re-enrollment with
  an older signed index fails; re-enrollment with the latest exact index succeeds
  without changing installed state or personal data.

A passing retained run writes `qualification.json` with architecture, SDK,
scenario and hashes/lengths for kernel, sandbox, dynamic payload, shared library,
musl loader, static runner, service, session runner and serial log. Keep the log
alongside the receipt; failure cannot produce a passing receipt. Retained images
contain fixture keys only.

The scenario passed on both targets on 2026-10-12 using an isolated build of
committed kernel revision `7ac619bd`. Retained receipts and complete serial logs:
[AArch64 receipt](results/2026-10-12/linux-aarch64.json),
[AArch64 serial](results/2026-10-12/linux-aarch64.serial.txt),
[x86_64 receipt](results/2026-10-12/linux-x86_64.json),
[x86_64 serial](results/2026-10-12/linux-x86_64.serial.txt).
Guest images were retained in the corresponding host state directories during
qualification. The x86_64 build used the V sampler generator directly, bypassing
the stale Python sampler recipe in that kernel revision.

The fingerprint-bound review flow also passed on both targets on 2026-10-12
with those same kernel artifacts:
[AArch64 review receipt](results/2026-10-12/review-aarch64.json),
[AArch64 serial](results/2026-10-12/review-aarch64.serial.txt),
[x86_64 review receipt](results/2026-10-12/review-x86_64.json),
[x86_64 serial](results/2026-10-12/review-x86_64.serial.txt).
Their `PACKAGE REVIEW` marker covers full runtime/publisher disclosure and stale
confirmation refusal; maintenance uses reviewed upgrade, rollback and uninstall.

The repository administration flow passed on both targets on 2026-10-12 with
those same kernel artifacts:
[AArch64 repository receipt](results/2026-10-12/repositories-aarch64.json),
[AArch64 serial](results/2026-10-12/repositories-aarch64.serial.txt),
[x86_64 repository receipt](results/2026-10-12/repositories-x86_64.json),
[x86_64 serial](results/2026-10-12/repositories-x86_64.serial.txt).
Their `PACKAGE REPOSITORY` marker covers authenticated enrollment, revocation,
retained replay floors after an empty refresh and successful re-enrollment.
These guests use initramfs; metadata publication interruption is simulated by
host fixtures, rather than tested as a physical power cut in these runs.

The resolved runtime-update view passed on both targets on 2026-10-12:
[AArch64 updates receipt](results/2026-10-12/updates-aarch64.json),
[AArch64 serial](results/2026-10-12/updates-aarch64.serial.txt),
[x86_64 updates receipt](results/2026-10-12/updates-x86_64.json),
[x86_64 serial](results/2026-10-12/updates-x86_64.serial.txt).
The `PACKAGE UPDATES` marker checks the service view/CLI Updates before and after
the reviewed runtime-only upgrade. Kernels were rebuilt from revision `7ac619bd`
in isolated worktrees with LLVM and `KERNEL_LINK_RANDOMIZE=0`; the x86_64 sampler
used the V generator directly. These are newly built artifacts, with hashes in
the receipts. Exact kernels are cached locally under
`build/package-update-qualification/kernels/ARCH-7ac619bd` for reruns.
Headless UI fixtures separately check per-row complete upgrade review, new/removed
dependency presentation, dependency-root guards, blocked-plan diagnostics and
zero retained redraw allocations. View reload and blocked-status measurements
match the JSON decoder's independent EOF allocation baseline.

This qualifies this musl loader/package tuple and its stated assertions. It does
not qualify arbitrary Linux libraries, upstream apps, glibc, graphics/audio
brokers, network traffic, Wine or Apple API coverage. Use the separate
[native enforcement](runtime-check.md) and [persistent recovery](persistence-check.md)
checks for generation leases and ext2 transaction crash checkpoints.
