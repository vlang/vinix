# PowerPC PR #273 review fixes

The [review](https://github.com/vlang/vinix/pull/273#issuecomment-6730031282)
identified trailing-slash mutations, archive `getdents64`, and creation through
dangling symlinks. The follow-up retains final-component directory requirements,
returns the resolved parent/name for a missing symlink target, and supports both
directory ABIs for archive descriptors. Directory moves remain unsupported.

Validation on 2026-11-09 uses base revision
`a2bb95cb60d9df9fa71efedc67e3873e0f68a080` plus the exact changed sources retained
in the bundles below. Toolchain: V `b7b4dd46eeb3d39cf8d3e8ef757093d872cbc230`,
Zig 0.15.2, LLVM objcopy 23.1.0, QEMU 11.1.1, and e2fsprogs 1.47.4.

- Host ext2 regression passes, including missing-target resolution, trailing
  separators, symlink chains, allocation reclamation and independent `e2fsck`.
- The native PPC musl storage fixture passes two QEMU mac99/7450 boots with
  512 MiB. It verifies both files' contents survive rejected unlink/rename
  operations, rejects regular-file creation with trailing slashes, and preserves
  mkdir/open/rmdir of directories with trailing slashes.
- Dangling relative/absolute fast symlinks create the resolved target while
  retaining both symlink inodes. `O_EXCL`, `O_NOFOLLOW`, missing intermediate
  components and trailing-slash link targets are checked separately.
- Libc enumerates archive `/bin` and `/etc`; raw `getdents64` checks record
  layout, small buffers, invalid pointers, descriptor position and repeated EOF.
  The existing ext2 listing, indirect I/O, unlink-open, random and stdio checks
  pass, the counter persists, and both offline filesystem checks pass.
- The three archive/firmware host unit test files pass. Generated kernel C has
  no calls to heap-allocation functions.

Complete retained bundles are under `/Users/alex/.cache/vinix-pr273-review`:

| Bundle | SHA-256 of `SHA256SUMS` |
| --- | --- |
| `ext2` | `6feaa40b3ddfbfefdd3fac399d8bb67e375948c57cba9afb5a18068b0c71947f` |
| `abi-verified` | `2575a16bbaea600c0c582e259be2e5c31371d7169c024080322ec7b06ab107e0` |

The extended graphical `test-shell` runs pass legacy archive listings, keyboard,
pointer and framebuffer checks, then fail USB audio playback (second tone in
`shell-graphics`, first tone in `shell-retry`). Network and stable-free-page
checks are not reached. These are failed diagnostic runs, not shell-suite passes.
Their complete file inventories are retained alongside the bundles as
`shell-graphics.inventory.json` (SHA-256
`d1bc4ae960eb75b3a2ad496e78f104d1f2bd7d76a30a4e2e2521d2f6e97c918c`)
and `shell-retry.inventory.json` (SHA-256
`c68f6a24380336c9e08d4fcb236a8dba97e91a8eebbb1a32716e12f971bc5ff0`).
The stopped serial sockets were removed before inventorying. A serial-only run
also stopped in OpenBIOS before kernel entry; graphics uses `output-device=scca`.

The storage fixture uses its own linker script without an unused empty
`PT_TLS` segment. Kernel ELF validation is unchanged. This host also requires
`VINIX_PPC_OBJCOPY=/opt/homebrew/opt/llvm/bin/llvm-objcopy` because Zig's host
objcopy cannot link on this macOS version. See [PowerPC build instructions](powerpc.md).
