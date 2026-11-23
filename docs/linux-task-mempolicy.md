# Native thread-local NUMA policy

`set_mempolicy` changes the calling thread's policy. `get_mempolicy` with
zero flags reads that policy. A new thread or process inherits the
creating thread's policy by value. An executable replacement keeps the
policy of the thread that called `execve`, including a nonleader that
becomes the new leader. [Linux 6.12.51 memory policy implementation](https://github.com/gregkh/linux/blob/v6.12.51/mm/mempolicy.c)

An explicit `mbind` policy takes precedence for its range. For private
anonymous mappings, `MPOL_INTERLEAVE` follows the page index even when
threads fault pages out of order. A bind policy can allocate from any
allowed node in its mask. `MPOL_PREFERRED` selects the first eligible node,
and an empty preferred mask selects `MPOL_LOCAL`.

The native mask import uses `maxnode - 1` bits and distinguishes a bad
pointer from an invalid mask. Failed requests leave the caller's policy
intact. This qualification covers the five classic modes. Preferred-many
policy has [separate placement and fallback coverage](linux-preferred-many.md).
Exact shared anonymous interleave phase, extended mode flags, and Linux's
interleave query through `MPOL_F_NODE` without `MPOL_F_ADDR` remain open.

## Qualification

The same native musl probe ELF per architecture passed on Vinix and Linux
6.12.51 in single- and two-node guests. It checked independent sibling
policies in a shared address space, fork from a worker, and exec by a
nonleader. Two-node guests confirmed different physical placement for
the two threads and page-index placement for out-of-order interleave
faults. The previous Vinix kernels failed the sibling-isolation check.

Production builds used `3ffdc7e3b` plus the archived source patch. The
allocation checker reported the same existing failures and the same
306 AArch64 and 254 x86-64 allocation sites. Independent review verified
that the policy value is copied before new or replacement threads can run.
The existing AArch64 NUMA regression passed with its test program in the
boot archive.

The `mbind`, `mempolicy`, `threadnice`, and `execown` regressions passed on
both architectures. The exec runs kept large-page counts flat across 200
cycles each as root and UID 1000.

Run the [fixture](../tests/linux-compat/taskpolicyfixture/core.v) with
`tests/linux-compat/run --arch ARCH --kernel-dir DIR --state-dir FRESH-DIR
--cases taskpolicy`.

| Architecture | Probe ELF | Vinix kernel | Vinix two-node log | Linux two-node log |
| --- | --- | --- | --- | --- |
| AArch64 | `1fc0cdda9a1eeb1e` | `1aca2ac7f64d559d` | `849e5e00d564434d` | `8c3159969b003679` |
| x86-64 | `09e8b3bc8e1a61f8` | `a94431a7c6548cb3` | `6f6284a1ee2823fb` | `92473c1fb4e49f16` |

Hashes are SHA-256 prefixes. The restored and verified archive is
`~/.cache/vinix-r15/taskpolicy/qualification.tar.zst`, with SHA-256
`9d6c2d87ef92293bc7f964b9b797f64f2c87ca9ad5968ce68a96d5b190da9d3e`.
