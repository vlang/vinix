# execveat signed descriptor ABI

Both architecture dispatchers now normalize `dirfd` through `i32` before
direct-image lookup, directory lookup and synthesized script-name construction.
Previously the empty-path branch passed all 64 register bits to descriptor
lookup, causing a valid low descriptor number to fail with `EBADF` when the
upper word was nonzero. Interpreters now receive a descriptor name based on
the same normalized number used for lookup.

Only one scalar import and its three uses change. Existing validation order,
mount/noexec/W^X checks, MAC, credentials, script/interpreter handling, image
loading and argument/descriptor releases retain their bodies. No allocation,
reference transition, free or lifetime is added.

[Linux v6.12 execveat](https://github.com/torvalds/linux/blob/v6.12/fs/exec.c)
declares its descriptor argument as `int`. Its executable-name construction
uses the resulting number in `/dev/fd/N`; Vinix uses `/proc/self/fd/N`.
The fixture accepts either spelling while requiring the normalized number.

Use `--case execfd` or `ed-0` through `ed-7`. Native `all` and Linux
`move-reference` include the group:

| Case | Description / caller |
| --- | --- |
| 0 | Linked native ELF, duplicated read-only description, root |
| 1 | Linked native ELF, duplicated `O_PATH` description, UID/GID 1000 |
| 2 | Unlinked native ELF, duplicated read-only description, root |
| 3 | Unlinked native ELF, duplicated `O_PATH` description, UID/GID 1000 |
| 4 | Script with a native interpreter, duplicated read-only description, root |
| 5 | Script with a native interpreter, duplicated `O_PATH` description, UID/GID 1000 |
| 6 | Relative directory, signed `AT_FDCWD` and absolute-path requests |
| 7 | Invalid signed descriptors, flag/empty-path precedence and retained `noexec` refusal as UID/GID 1000 |

Each request retains its low 32 bits while testing upper words zero,
`0x11223344`, all ones and only bit 63 set. Image/script cases use both legal
empty-path flag combinations. Original descriptions are closed after duplication.
Successful images check real/effective UID/GID and exit with status 39. Script
interpreters additionally compare their script-name argument with the normalized
number and reopen `/proc/self/fd/N` to check its `#!` signature. The negative
cases require exact errors; identity, size, mode, ownership, link count and
mtime/ctime remain intact. Executable reads may update atime.

Evidence from 2026-10-15 is retained under
`/Users/alex/.cache/vinix-linux-compat/execfd-20261015`:

| States | Result |
| --- | --- |
| `{arm,x86}-ed-{0,3,4,5}-before-a` | Previous kernels return `EBADF` for a valid duplicated descriptor with upper word `0x11223344`, for linked/unlinked ELF and read-only/`O_PATH` scripts. The zero-upper-word request succeeds first. |
| `{arm,x86}-execfd-after-a` | All eight corrected native cases pass. |
| `{arm,x86}-all-after-a` | Complete native mount suites pass, including all eight cases. |
| `{arm,x86}-linux-a` | Identical probe ELFs pass the portable Linux 6.12.51 suites, including all eight cases. |

| Architecture | Fixed kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `f996a467aeccd8f19400ab1021ab212a9b91f1d0529eabdd78ff10242765102b` | `b6119f6134baa3196dc158e3538867d8dae9e6b9dfd83cf315d8e15857a65e11` |
| x86_64 | `fde6febdd1bde4d3816353b65fbe6625aed31709f1d1a145c9294d1b4c796fc5` | `7049307c48d527df6d3a31dd7bfbc3ffd39caa55f0b78058bc2a243c121a3e6c` |

Both probe C files have SHA-256
`48abfe1609261c481ed16bdde2c457dfb2a88b66dd0b5c190c93d80b8124499d`.
Controls and corrected runs share all thirty-two fixture sources and probe/C
artifacts; Linux reuses the identical probe ELFs. Native receipts pin these
sources, controllers, kernels and images. Linux receipts additionally pin the
wrapper, initramfs, QEMU and serial log. Every requested case marker and the
final verdict must be present.

`before-{arm,x86}` and `after-{arm,x86}` preserve kernels, generated C, both
loader sources and tracked kernel, build-support and native-generator source
manifests. Isolated worktrees start at committed baseline
`34935456e70252a8c5f99bf641b319e170741dba`; corrected
builds apply only the retained `owned.patch` for the two architecture loaders.
No source hunks are removed from that baseline. Uncommitted checkout edits,
including the staged VFS spelling change, and later commits from concurrent
sessions are excluded. The entire current checkout kernel was not tested.

Builds use V source `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, recovered
compiler SHA-256
`9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b`,
Clang with `-fstack-usage`, and link seed 17. `compiler-recovery.json` records
the compiler rebuild provenance; `compiler-inputs.json` pins 15,146 verified
compiler inputs. The untracked kernel dependencies are shared through
symlinks; `dependency-inputs.json` records 1,495 file hashes or symlink targets
after the builds and the final audit rechecks them. These dependencies are
not private copies frozen before compilation. The x86 heap sampler is
generated from the same baseline generator with the host V compiler before
the kernel build. `tool-inputs.json` pins host V, kernel V and Clang.

ARM probe compilation uses a private copy of the Homebrew musl-cross 0.9.11
headers/libraries and GCC 14.2.0 `crtbeginT.o`, `crtend.o`, `libgcc.a` and
`libgcc_eh.a`. `sdk-inputs.json` pins the copied bytes and symlink targets;
the retained V `clang.v` wrapper selects these support files. Probe/controller
tools use the host V compiler. These are host build inputs, not native Vinix
toolchain qualification.

Native ARM uses HVF/four CPUs; x86 uses TCG/two, each with 1024 MiB. Linux
uses HVF/TCG, two CPUs and 512 MiB. Networking is disabled. Controls and Linux
allow 600 seconds; focused and cumulative native runs allow 900 seconds.

The assertion-enabled source/C audit compares all parsed namespace-qualified
functions after normalizing compiler temporary/discard/loop-index numbers.
Every function except `syscall_execveat` matches the baseline. Its complete
body matches after one signed-i32 scalar import and substitution at exactly
the three descriptor lookup, script-name decimal and parent lookup uses.
The existing validation, mount/MAC/W^X, credentials, interpreter/loader,
process publication and allocation/free/release bodies remain identical.
No new allocation, reference transition, owner or free is introduced.

`source-evidence-a.log`, `after-{arm,x86}/c-audit.txt`, `pins-a.log` and
`evidence-a.log` retain the source, input and runtime checks. The retained
V audit tools run with assertions enabled. `post-commit-a.log` verifies all
ten committed paths, the exact two-file kernel patch, direct identity with
the tested loader sources and preservation of unrelated staged VFS edits.

Inherited-directory mount routing, concurrent descriptor close/reuse, namespace
or remount timing, `AT_FDCWD` with empty paths, dynamic ELF interpreters,
translated images, broader MAC/W^X and error combinations, persistent/overlay
integration, allocation-flatness and desktop performance remain outside this
qualification. Full OCI/rootless acceptance and roadmap section 17 remain
in progress.
