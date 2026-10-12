# Dynamic Linux package qualification

The V controller builds a target musl dynamic executable and a shared V library,
the static SDK Linux runner, and the production native sandbox. It checks that
the executable has both PT_INTERP and PT_DYNAMIC before staging. The guest
imports the prepared app/runtime roots with the actual `pack-root` CLI, creates
a throwaway signing key, enrolls a local repository and installs the Linux app.
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
- A shared-library call returning 23, UID/EUID 1000 and zero supplementary groups.
- Literal arguments containing spaces, semicolons and a dollar sign.
- Private-data writes as the user; host libraries, the package tool and unrelated
  same-user data hidden by the production sandbox.
- Runtime library tampering being refused before execution; restoring the signed
  bytes permits launch again.
- Upgrading to a signed runtime without the required shared library producing
  the loader's library-name diagnostic and status 127; rollback restoring launch.
- Uninstall removing both the app and unused runtime while preserving user data.

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

This qualifies this musl loader/package tuple and its stated assertions. It does
not qualify arbitrary Linux libraries, upstream apps, glibc, graphics/audio
brokers, network traffic, Wine or Apple API coverage. Use the separate
[native enforcement](runtime-check.md) and [persistent recovery](persistence-check.md)
checks for generation leases and ext2 transaction crash checkpoints.
