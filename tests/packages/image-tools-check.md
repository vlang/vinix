# Captured image tool builds

The production package stager now compiles the package service, account-session
tool and Linux runner in one randomly named, exclusive mode-0700 workspace.
It checks workspace/image identity around every compiler call. Compiler failures
and invalid later outputs preserve all three previously installed tools.

Publication captures bounded, ordinary, owned single-link outputs and validates
their static ELF64 architecture and load/entry structure. Each binary is limited
to 64 MiB. File identity, size and mode are rechecked; hashing binds validation
and capture to the bytes published. All three owned byte buffers are captured
before preparing any destination. Later compiler-output edits cannot change them.

The complete temporary-output budget plus a 64 MiB reserve is checked before
destination creation. Parents are opened relative to the admitted image root,
without directory aliases, and must remain controlled on its filesystem. All
three private destination temporaries are written, mode-0755, flushed and checked
before the first rename. Publication uses held parent descriptors and replaces
leaf aliases themselves; predictable `.new` names remain untouched. Each file
is renamed atomically and its parent flushed. A failure after a rename reports
the saved tool and incomplete image build. This does not make the complete image
or the three renames one atomic transaction; distribute only completed builds.

Checked retirement closes workspace descriptors/metadata even when a replaced
tree must remain for inspection. Compiler errors retain cleanup-refusal details.
No consumer package state is initialized by tool compilation/publication.

The [core fixture](../../tools/packages/pkgcore/image_tools_test.v) checks **58
cases** across both architecture declarations: complete publication, missing or
wrong-target outputs at all positions, truncated/dynamic/malformed ELF, aliases,
hard links, nonexecutable/shared-writable/oversize outputs, disk/query/write/flush
refusal, workspace/image/parent substitution, unsafe destination parents,
directory destinations, preserved leaf aliases, captured-output edits and saved
output after final flush failure. Descriptor counts stay fixed; previous tools,
unrelated temporary names and outside/replacement data are checked byte-for-byte.

The [CLI fixture](image-tools-cli.v) runs **28 production staging invocations**
with a [V compiler substitute](image-tool-compiler.v). Every V and C compiler
position can fail; later output corruption and wrong architecture are refused
before replacement. Literal arguments and workspace/image/parent substitutions
are checked. Structural ELF fixtures are never executed. The original stager at
`82e0ce3eb` fails this same test after a third C compiler failure: earlier tools
were already replaced. The retained baseline demonstrates that regression.

The [host driver](image-tools-check.v) runs **20 checks**, including compilation,
both fixtures, ASan/UBSan, ELF/atomic/image application/configuration/retirement
regressions and the original failure demonstration. It records inputs, commands,
timings and log/binary hashes. Use a fresh work directory directly under `build`:

```sh
v -nocache -o /tmp/image-tools-check tests/packages/image-tools-check.v
V=/path/to/reviewed/v /tmp/image-tools-check "$PWD/build/new-image-tools-host"
```

The [native controller](image-tools-runtime-check.v) compiles and publishes all
three real static tools through this production stager, boots them on both
architectures, repeats the 58 core cases and executes package help/status,
session usage and Linux-runner argument admission. Required markers and clean
poweroff qualify tool staging/execution; they do not qualify application/runtime
compatibility or graphical sessions. Matching GCC cross compilers, QEMU TCG,
firmware and a kernel are required; see the [hardware harness](../hardware-platform/README.md).

```sh
v -nocache -path '@vlib|@vmodules|tests/hardware-platform' \
  -o /tmp/image-tools-runtime tests/packages/image-tools-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  VINIX_IMAGE_TOOLS_STAGE="$PWD/build/new-image-tools-host/stage" \
  /tmp/image-tools-runtime --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-image-tools-arm
```

Repeat with x86_64, its matching kernel and a new directory. These checks do not
claim complete service allocation freedom, kernel allocation freedom, production
publisher/catalog migration or full installed graphical/runtime acceptance.
Section 14 remains open.

## Recorded results, 2026-10-18

| Target | Result | Native guest time | Evidence |
| --- | --- | --- | --- |
| aarch64 | PASS | 21.452 s | [receipt](results/2026-10-18/image-tools-aarch64.json), [serial](results/2026-10-18/image-tools-aarch64.serial.txt), [production staging](results/2026-10-18/image-tools-aarch64.stage.txt) |
| x86_64 | PASS | 25.221 s | [receipt](results/2026-10-18/image-tools-x86_64.json), [serial](results/2026-10-18/image-tools-x86_64.serial.txt), [production staging](results/2026-10-18/image-tools-x86_64.stage.txt) |

All **20 host checks passed**, including 58 core cases, 28 real CLI staging
invocations, ASan/UBSan and the prior-version failure demonstration. The
[host receipt](results/2026-10-18/image-tools-host.json) retains exact input and
artifact hashes, commands and timings; the
[summary](results/2026-10-18/image-tools-host.txt) lists every check. The
[baseline log](results/2026-10-18/image-tools-baseline-reproduces.txt) and
[original source](results/2026-10-18/image-tools-baseline-stage.v) show the mixed
tool versions after a late compiler failure.

Each native guest passed all 58 cases, executed the three real production-staged
tools and powered off cleanly. All 14 resource-denial samples per guest were zero;
these bounded samples do not establish kernel allocation freedom. Existing
kernels are pinned. The x86_64 guest uses a V plain-USTAR media adapter for its
pre-gzip kernel; production boot-media tooling and kernel code are unchanged.

The [retention helper](results/2026-10-18/image-tools-retain.v) verifies receipt
hashes, the source anchor, failure/preservation markers and native results. Its
[ledger](results/2026-10-18/image-tools-toolchain.json) pins inputs, compilers,
binaries, logs, the media adapter and documentation. Builds use `-nocache`,
compiler fallback disabled, and V 0.5.2 `826e96f` with SHA-256
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.
