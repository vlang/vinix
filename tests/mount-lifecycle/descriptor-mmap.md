# Inherited descriptor executable mappings

File `mmap` now reads the actual saved mount of its descriptor when enforcing
`noexec`. An inherited description from an executable mount stays usable when
the namespace copy gains `noexec`; a description from a `noexec` mount gains no
execute authority when the copy loses that flag. Direct read/execute mappings return
`EPERM` on `noexec`. Read mappings retain their execute limit, so later
`mprotect` execute upgrades return `EACCES`.

VFS initialization now installs the existing raw mount-flags reader as the
file mapping callback. The mapping operation already holds the descriptor and
passes its actual context synchronously. The complete mapping, MAC,
resource/handle ownership, maximum protection, fork and release paths remain.
The raw reader retains its mount lock/read/unlock body. No allocation, heap
owner, reference transition or free is added.

[Linux v6.12 `mm/mmap.c`](https://github.com/torvalds/linux/blob/v6.12/mm/mmap.c)
consults the saved file path for `noexec`, rejecting direct execute mappings
and removing the maximum execute permission from other file mappings.

Use `--case descmaps` or `mm-0` through `mm-5`. Native `all` and Linux
`move-reference` include the group:

| Case | Saved description and copied mount |
| --- | --- |
| 0 | Executable mount, regular file; copy gains `noexec` |
| 1 | `noexec` mount, regular file; copy becomes executable |
| 2 | Executable mount, unlinked file; copy gains `noexec` |
| 3 | `noexec` mount, unlinked file; copy becomes executable |
| 4 | UID/GID 1000 owner on executable mount; copy gains `noexec` |
| 5 | UID/GID 1000 owner on `noexec` mount; copy becomes executable |

Each case duplicates a data-read-only descriptor, closes its original, copies
the namespace and gives the copy opposite flags. Fresh descriptions follow the
copy for linked targets. Statfs checks independently establish both policies.
Sixty-four cycles exercise private and shared direct read/execute mappings,
read mappings upgraded to execute, transitions through inaccessible pages,
read restoration and unmapping. Shared mappings cannot gain write permission
from a read-only description. Every readable mapping retains the eight marker
bytes; identity, mode, ownership, size, data and unlinked link counts remain.

Separate private mappings are inherited by a child, which closes its
descriptors and runs as UID/GID 1000 before execute-upgrade checks. Parent
checks repeat after its final descriptors close. Both processes retain the
original per-mapping execute limits and data. Owner cases drop privileges
before the entire mapping matrix. No mapped machine code is executed.

Evidence from 2026-10-15 is retained under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-descmaps-{arm,x86}-mm-0-before-a` | Previous kernels wrongly return `EPERM` for an inherited executable description when the namespace copy gains `noexec`. |
| `mount-descmaps-arm-mm-1-before-a`, `mount-descmaps-x86-mm-1-before-b` | Previous kernels wrongly permit an executable mapping through an inherited `noexec` description when the copy becomes executable. |
| `mount-descmaps-arm-descmaps-after-a`, `mount-descmaps-x86-descmaps-after-b` | All six corrected native cases pass. |
| `mount-descmaps-{arm,x86}-all-after-a` | The complete native mount suites pass. |
| `mount-descmaps-{arm,x86}-linux-a` | The same probe executables pass the portable Linux 6.12.51 suite, including all six mapping cases. |

| Architecture | Kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `d1d06e91b16d7c968cfd4d7c7b26d1fd17c941628c9378b7bb87ae6c84537e47` | `ec06445b0ffe9cf96abe4a11fb33730dee94c3164b41eb37a38dcd9b04c874b5` |
| x86_64 | `07311fc2922c850f71b8ca3f325be3420d91f690666e898078262c9172df45f9` | `8ca6a49959956058be5caf048fcc154b08f0594931ee3453e935557e28c56e2a` |

`mount-descmaps-{arm,x86}-input` preserves complete source manifests,
source snapshots, generated C, kernels and hashes. Builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. The control kernels are the qualified
[descriptor-inode-flag builds](descriptor-flags.md). Native ARM uses HVF/four
CPUs; x86 uses TCG/two, with 1024 MiB. Linux uses HVF/TCG, two CPUs and 512 MiB.
Controls and Linux runs allow 600 seconds; focused and cumulative native runs
allow 900 seconds. Networking is disabled. Controls and corrected runs share
all twenty-seven fixture sources and the same probe/C artifacts. Both
architectures' probe C has SHA-256
`3e4e31621eb5d1d98c47c8a09d12bff0a714afb58a3fc71e59e9864f58ce7408`.

Initial x86 states `mount-descmaps-x86-mm-1-before-a` and
`mount-descmaps-x86-descmaps-after-a` ended during Limine downloads, before
boot. Their logs and receipts remain preserved; these are not behavioral
controls. Retained Limine files were checked against every builder SHA-256 pin
before restoring the local boot cache. The stale x86 cache symlink to a removed
volume was preserved at `mount-descmaps-limine-cache-before/x86-link`.
`mount-descmaps-limine-cache-b.log` records the pin checks and cache repair.
Fresh retry states use the same probe and kernel.

The isolated builds extend the qualified descriptor-inode-flag inputs,
changing only the callback registration in `kernel/fs/vfs.v`. The baseline
still excludes the pre-existing open-created descriptor hunks, staged
pointer-return spelling edits and earlier fcntl/descriptor/lock changes
described in [the writer qualification](writer-policy.md). Later checkout
changes are excluded. The complete current checkout kernel was not built or
booted.

The assertion-enabled source/C audit compares all parsed namespace-qualified
functions after temporary/discard/loop-index normalization. Only VFS
initialization changes, matching completely after substituting the callback.
The mapping operation, both flag readers, MAC, protection limits, fork and
cleanup functions remain unchanged. Receipt checks pin all twenty-seven
fixture sources, controllers, artifacts, controls, shared native/Linux probe/C
identity and positive markers. A private index isolates the VFS commit from
the other session's staged edits; the post-commit audit checks both snapshots
after the same three excluded open-created hunks.
Per-architecture `descriptor-mmap-c-audit.txt`,
`mount-descmaps-source-evidence-a.log`, `mount-descmaps-evidence-a.log`
and `mount-descmaps-post-commit-a.log` retain the results.

Concurrent remount/setns timing, mremap and split mappings, `O_PATH` and combined
error precedence, broader MAC/W^X combinations, device/persistent/overlay
mapping integration, mapping reclamation measurements and desktop performance
scenarios remain open. Full OCI/rootless acceptance and roadmap section 17
remain in progress.
