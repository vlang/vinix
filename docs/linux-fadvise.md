# Native file advice

`fadvise64` resolves the descriptor first, returning `EBADF` for a closed
descriptor or one opened with `O_PATH`. Anonymous pipes and named FIFOs
return `ESPIPE` before range and advice validation. Directories, sockets,
devices, and write-only files accept valid advice. The descriptor and
advice arguments use their low 32 bits. The signed 64-bit offset may be
negative, while a negative length or unknown advice returns `EINVAL`.
[Linux 6.12.51 file advice implementation](https://github.com/gregkh/linux/blob/v6.12.51/mm/fadvise.c#L29)

`NORMAL`, `RANDOM`, and `SEQUENTIAL` update read-ahead policy on the open
file description. `WILLNEED` and `DONTNEED` send bounded, best-effort hints
to the backing filesystem. A zero length covers the remaining file. A
positive range whose endpoint exceeds the signed offset limit is treated
the same way. For `DONTNEED`, an offset between `-PAGE_SIZE` and zero rounds
up to the first page.

The existing EXT2 backend evicts only clean and fully covered backing-cache
pages. It keeps dirty pages for writeback and does not remove mapped pages.
`NOREUSE` succeeds without changing cache aging policy. See the
[backing-cache implementation and tests](../tests/pagecache/README.md).

## Qualification

The same probe ELF per architecture passed 1,970 checks on Vinix and Linux
6.12.51. Root and UID 1000 used the same open descriptions and checked
descriptor and advice truncation, signed offsets and lengths, error
precedence, and musl `posix_fadvise` returning the error code without setting
`errno`. The probe also checked shared offsets and file contents after advice.
The previous Vinix kernels failed on the first valid negative-offset hint.

Production builds used `f65fd1721` plus the archived source patch. All three
host page-cache test files passed. The `readahead`, `opathseek`, `pipeabi`,
and `processmadv` guest regressions passed on both architectures. The
allocation checker found the same existing failures and the same 306 AArch64
and 254 x86-64 allocation sites. Independent review verified that the
descriptor and handle references are balanced and cache changes require MAC
approval.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `efe35fdaf40b0455` | `7175acaf394a311d` | `092ddd6218d4de5d` | `b0fe073648f153cb` |
| x86-64 | `18ba4b89200785f8` | `e5858cfd70e35119` | `ae5f058a42a5ac5a` | `e7d7afa9a6a4c420` |

Hashes are SHA-256 prefixes. The restored and verified archive is
`~/.cache/vinix-r15/fadvise/qualification.tar.zst`, with SHA-256
`2a6344ed3a39f0488e640f253da239ebb5658e95ac8df3fb133784ab844a7d2f`.
