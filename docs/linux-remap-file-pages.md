# Native remap_file_pages

`remap_file_pages` replaces a shared regular-file range at the same virtual
address, starting at a different file page. The address and length round
down to page boundaries, and the full protection argument must be zero.
The replacement inherits current protections and mapping ceilings and uses
the original open file description even after its descriptor closes.
Adjacent ranges can be replaced together when they share that description
and their mapping attributes match. [Linux 6.12.51 remap implementation](https://github.com/gregkh/linux/blob/v6.12.51/mm/mmap.c#L1663)

The replacement undergoes fresh mmap admission. Memfd write seals and VMA
seals apply, and the source span is revalidated under the address-space
lock before replacement. A concurrent `munmap` can cause `EINVAL` if it
removes the source first. Ordinary remaps try to fault in accessible file
pages after installation. `MAP_NONBLOCK` suppresses prefault on unlocked
views. The other input flags are ignored.

Vinix preserves the old view when write-seal admission rejects a writable
replacement. The Linux 6.12.51 probe observed `EPERM` and removal of the
old view on both architectures. It verified residency before touching the
address and reinstalled a read-only source for the next check.

## Qualification

The same ELF per architecture passed on Vinix and Linux 6.12.51. The probe
checks rounding, overflow, offsets and aliases, closed and reused descriptors,
adjacent mapping compatibility, seals, `MAP_NONBLOCK`, and 128 remap/unmap
races. Both prior Vinix kernels returned `ENOSYS`. The x86-64 Linux reference
passed on retry after an interrupt exception during its initial boot.

Production builds used `bc57dc1dd` plus the archived patch. The `mmap`,
`memfdseals`, `cachestat`, `sharedmem`, and `mseal` regressions passed on
both architectures. The allocation checker reported the same existing
failures and the same 306 AArch64 and 254 x86-64 allocation sites as the
baseline.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `bab5a6f4eec74b34` | `47d58660f6fdeb25` | `dfc265f5d01d11da` | `4796f178d6526b84` |
| x86-64 | `276f008004414377` | `891042d386a6b2d8` | `4c643975eeecfea7` | `147db21fe998b21a` |

Hashes are SHA-256 prefixes. The restored and verified archive is
`~/.cache/vinix-r15/remap-file-pages/qualification.tar.zst`, with SHA-256
`f710138d8afd0917b0c6a9ae0d24250ace279d1d311d72a1d1bd7c58b7b437ce`.

## Limits

Supported sources use writable open descriptions of regular files. Private,
anonymous, device, and callback-backed System V shared-memory mappings are
outside the supported set.
