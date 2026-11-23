# Memfd write seals

An explicit `F_SEAL_WRITE` request returns `EBUSY` while a shared mapping
can write to the file. A read-only mapping made using a writable descriptor
counts because `mprotect` can upgrade it. A shared mapping made using a
read-only descriptor can coexist with the write seal. Fork and splits retain
the original mapping, and remap preserves its permission ceiling.
[Linux 6.12.51 seal installation](https://github.com/gregkh/linux/blob/v6.12.51/mm/memfd.c#L234)

`F_SEAL_FUTURE_WRITE` preserves existing mappings and their original
permissions. With either write seal present, new shared mappings that
request write permission fail with `EPERM`. New read-only shared mappings
get a ceiling that makes a subsequent write upgrade fail with `EACCES`.
Private copy-on-write mappings retain their usual permissions.
[Linux 6.12.51 mmap admission](https://github.com/gregkh/linux/blob/v6.12.51/mm/mmap.c#L393)

Adding `F_SEAL_EXEC` on an executable inode also adds `F_SEAL_SHRINK`,
`F_SEAL_GROW`, `F_SEAL_WRITE`, and `F_SEAL_FUTURE_WRITE`. Linux checks
for busy mappings before applying those implied bits, so an execute-only
seal request preserves the write access of existing mappings. An explicit
write bit in the same request triggers the busy check.
[Linux 6.12.51 implied seals](https://github.com/gregkh/linux/blob/v6.12.51/mm/memfd.c#L234)

## Qualification

The same native probe ELF per architecture passed on Vinix and Linux
6.12.51. It covers partial unmap, fork, failed mapping admission, remap,
`mprotect`, private mappings, writes and file resizing, plus 64 concurrent
mapping-versus-seal attempts per architecture. Both preceding Vinix kernels
failed the check for a writable-capable mapping left after partial unmap.

Production kernels came from `514bc9a65` plus the archived patch. The
`memfdcreate`, `memfdpolicy`, `sharedmem`, `mmap`, and `mseal` regressions
passed on both architectures. The focused DRM PRIME probe passed range
bounds, aliasing and remap restrictions on both architectures. The
`drm-wire`, `agx-cpu-cache`, and `agx-file-close` host suites passed. The
allocation checker reported the same existing failures and the same 306
AArch64 and 254 x86-64 allocation sites.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `11a6f50bf9846b7e` | `21ccd695e7fef574` | `3fa0bbb3079a52b9` | `677f6f866850425a` |
| x86-64 | `f66945e1e58662ad` | `f453c7a82d5f3ff3` | `5eb39dcfbf051ea1` | `9506507476d21979` |

Hashes are SHA-256 prefixes. The restored and verified archive is
`~/.cache/vinix-r15/memfd-write-seals/qualification.tar.zst`, with SHA-256
`613aff76ccc47dab590d77d4f2592f69ef28309aea4e6c5682a71f4fd35f7f49`.

## Limits

Vinix checks writable-capable mappings and temporary mapping references.
Linux's wait for independently pinned file pages remains open.
[Linux 6.12.51 pin check](https://github.com/gregkh/linux/blob/v6.12.51/mm/memfd.c#L234)
