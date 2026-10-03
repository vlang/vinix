This is the native translator used by Dota-enabled Vinix images. It installs
at `/usr/bin/qemu-x86_64` because Vinix's translated helper execution and
partial-page `madvise` support identify that executable path. Its build and
staging directories are separate from the existing Wine/Steam translation layer.

`inputs.json` pins the QEMU 9.1.2 source archive, Alpine 3.21 development packages,
and the musl compatibility patches from Alpine's QEMU 9.1.2-r1 package. Their
source is the [Alpine package recipe](https://gitlab.alpinelinux.org/alpine/aports/-/blob/3.21-stable/community/qemu/APKBUILD).
The native X11 sysroot and userland GCC support libraries must already exist.
The helper hashes their headers, static archives and CRT objects, along with
compiler versions, its configuration and the checked-in patches, before reusing
a private build. A changed or missing cached memory mapper triggers rebuilding.

`noreplace.patch` adds a guest-range occupancy check while QEMU's existing
`mmap_lock` is held. In [upstream 9.1.2's memory mapper](https://gitlab.com/qemu-project/qemu/-/blob/v9.1.2/linux-user/mmap.c),
that check applies only to reserved guest address spaces. Vinix has 16 KiB native
pages and translated x86 programs have 4 KiB pages, so the fragment path can
otherwise reuse a native page and zero an occupied guest fragment despite
`MAP_FIXED_NOREPLACE`. Checking before the fragment work preserves existing
guest pages and still allows a free sibling fragment. `PROT_NONE` reservations
count as occupied too.

Build with `python3 build-support/dota2/qemu-stage.py --work build/dota2-qemu
--staging build/dota2-runtime/staging`. The output is a static AArch64 ELF with
no interpreter or native library dependencies; `usr/libexec/vinix-dota2/qemu-build.json`
records its hash and build inputs. The helper preserves the staged private glibc
runtime. The translated `tests/dota2/mmap32-probe.c` contract checks collisions,
sentinel preservation, large reservations, a free sibling page and an interior
hole on actual Vinix.

`wake-op.patch` validates and unprotects a writable guest secondary word before
the native `FUTEX_WAKE_OP` atomic write. Translated code can make its containing
16 KiB native page read-only even when that 4 KiB guest data page remains
writable. A kernel write cannot enter QEMU's userspace fault handler, so the
previous translator returned `EFAULT` for such valid writes. The patch retains
`mmap_lock` through this nonblocking operation to serialize concurrent code
protection. It checks guest write permission alone, preserving write-only
mappings and errors for read-only, inaccessible and unaligned operands.
Blocking futex operations retain their existing path.

The paired [WAKE_OP regression](../../../tests/dota2/wake-op-README.md) runs
an explicitly selected old and new translator on the same Vinix kernel and
fixture. It verifies the reproduced write fault, preserved permissions and
128 successful writes with acknowledged worker code execution between steps.
It does not trace native page protection at every step or certify the separate
full futex contract.
