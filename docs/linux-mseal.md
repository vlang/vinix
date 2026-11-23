# Linux memory sealing

`mseal` (462) seals native AArch64 and x86-64 mappings. It rounds the length
up to a page, requires a page-aligned start, and checks the whole span before
sealing any page. Gaps and uncommitted parts of the break arena return
`ENOMEM`. A zero-length request at an aligned address succeeds. Repeated seals
preserve the existing seal.

The seal prevents `munmap`, `MAP_FIXED` replacement, `mremap`, and `mprotect`
from modifying the sealed mapping. `MAP_FIXED_NOREPLACE` reports `EEXIST`.
An overlapping unmap leaves the entire request intact. `mprotect` can change
the unsealed prefix before it reaches a seal and returns `EPERM`.

On private nonwritable anonymous pages, the seal also refuses discard advice,
including `MADV_DONTFORK` and `MADV_WIPEONFORK`. Writable sealed mappings
keep their write access and support discard and wipe-on-fork. File aliases
can still change shared bytes, and `msync`, locking and unlocking still work.
Fork inherits the seal. Exec and process exit release their old mappings.
These rules follow the [Linux 6.12 implementation](https://github.com/torvalds/linux/blob/v6.12/mm/mseal.c)
and [Linux's userspace ABI documentation](https://www.kernel.org/doc/html/v6.12/userspace-api/mseal.html).

The page map serializes sealing with VMA creation, remap, heap changes and
fork. That keeps a concurrent seal from attaching to a relocation's partially
copied destination. SIGKILL can interrupt a wait for the gate.
Boundary splits reuse existing backing ownership. Both splits finish before
any seal is set. An internal allocation error can leave a metadata boundary
that was already split.

Run the maintained guest probe with `tests/linux-compat/run --cases mseal`
on each architecture. It checks exact validation, retained bytes, fork and
exec, an unprivileged seal, break growth and shrink, and concurrent sealing
and relocation. Vinix-specific checks cover OpenBSD `mimmutable` and measure
storage over 200 seal-and-exit cycles. The same ELF runs on Linux using
`tests/linux-compat/syscall-reference.v --case mseal`.

## Qualification

The optimized Vinix kernels use `ab420ef6f` plus the kernel changes in this
commit, with `PROD=true` and `LIMINE_MP=1`. The reference guests run Linux
6.12.51.

| Guest | Passing checks | Probe ELF | Kernel | Serial log |
| --- | --- | --- | --- | --- |
| Vinix AArch64 | 168 | `0a95cf8b2162e0ff` | `1e0ebbcc952beb40` | `dd1f48fa0df5aa75` |
| Linux AArch64 | 154 | `0a95cf8b2162e0ff` | `c8d8cdec004d4259` | `857be74c2bdc3e7b` |
| Vinix x86-64 | 167 | `fdc151ec8f703358` | `801bbdefca1650c9` | `5eafcb328bf75ab0` |
| Linux x86-64 | 153 | `fdc151ec8f703358` | `ec9073e710b26f59` | `a6c62f238c4defcf` |

No live slab class grew over 200 seal-and-exit cycles. Large pages stayed at
81 on AArch64 and 219 on x86-64. The independent review identified a race in
an earlier version, during relocation. The final update gate closes that
window, and the probe checks the complete destination bytes according to which
syscall won. The allocation checker reports zero new sites in the
changed paths and still flags existing repository-wide allowance failures.

The existing `mmap`, `sharedmem`, `shmremap`, `mapstorage` and `sparsefork`
guest regressions passed on both final kernels. The eight Linux compatibility
host test suites and the generated inventory check also passed.

Hashes are SHA-256 prefixes. The evidence and full checksums are in
`~/.cache/vinix-r15/mseal/{arm,x86}/{vinix,linux-dev2}`. The allocation checker
output is in `~/.cache/vinix-r15/mseal/allocs.log`.

## Limits

Protection keys and translated or 32-bit callers remain outside the tested
ABI. `MADV_REMOVE` enforces the seal in the protected case. The underlying
hole-punch operation through that advice is still unimplemented.
