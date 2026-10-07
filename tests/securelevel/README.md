# Securelevel userspace device and domain policy

Securelevel 2 prevents writing block-device descriptions, including descriptors
opened before the level was raised. Open, write, pwrite and writev enforce the
same rule. Read-only disk opens and O_PATH remain available; filesystem writes
and cache/metadata writeback call resources directly and remain available.

At securelevel 1, an established initial-UTS domain name cannot be changed or
cleared. Private UTS namespaces may configure their independent names. Raising
the level uses an atomic compare/exchange loop so concurrent raises cannot
accidentally lower a newer policy. Only init may lower a positive level.

Run `python3 tests/securelevel/run.py` for ARM64 or add `--arch=amd64` for x86.
The runner follows the existing dumpability VM setup and environment overrides.
The disk fixture is a block-mode inode used to exercise userspace dispatch;
the ARM runner also mounts a real persistent EXT2 /root and checks ordinary
file writes/fsync at level 2. Hardware-cache barriers have separate storage tests.

The maintained native guest is V in `securefixture/core.v`. Its header contains
native declarations, private-function scope and scalar/layout assertions only.
The original 104-line C guest is frozen at
`1696dbaf6be3d2379c420288abde4268d0455a77` (blob
`b8392ad942dffb5a7d26cf66b07a127eda745b5f`). Use `--source=/absolute/guest.c`
to run that original Git blob as an independent control.
`--state-dir=/absolute/new-state` retains the native inputs, guest ELF and VM
artifacts; the directory must be new. `--kernel-dir=/absolute/worktree/kernel`
copies an already-built matching kernel immutably and disables rebuilding it.
Without that option, the existing environment and build behavior apply.

The V port preserves the saved native errno across `close`, the initial UTS
domain checks, levels 0/1/2/0, all original verdicts and the 300-second guest
allowance. Each of the original 50 concurrent-raise children creates two native
pthreads using the same registered C wrapper address, joins both threads before
leaving its stack, and is reaped with the original EINTR-aware `waitpid` loop.
Callback arguments are immediate pointer-width values 1 and 2. Local buffers,
the transfer vector and wait status remain stack values borrowed synchronously
by libc. The native fixture object imports no V allocator.

Both original C and maintained V controls passed in native QEMU TCG guests on
ARM64 and x86. Each produced the same 17 ordered checks and errno values, all
three feature markers and the original final PASS within the unchanged
300-second allowance. Source and native-code review confirmed the complete
50-child, two-thread workload; no individual runtime thread counts were traced.
The ARM EXT2 images passed read-only `e2fsck -f -n` afterward and contained the
fsynced byte `x`; the x86 fixture uses initramfs/tmpfs.

The tested V guest ELFs have SHA256
`fe6d8e16a87510b8bc44234b96d6e3e0263e71a39b2d745ba83680177ee90028` (ARM64) and
`8bb7d7032ad6f2a9ff1d6ef18d1fb07c79b52c533f9c675fdd606654f20ac57f` (x86).
Previously qualified, unchanged kernels were reused:
`05ce36f10282f9ed7263d560fc60b5a4b057e3fdf0158fb07d3fa41a27f048ed` (ARM64) and
`b871254e8493566beb5b2e4436a06765a05db7d0f8fae561bb448d135f9c4199` (x86).
The actual boot images' kernel and init bytes matched those inputs. This stage
does not claim a fresh kernel build, sanitizer coverage, a kernel allocation
measurement or physical-hardware validation.

This extends SEC3 but does not close it. Mounted-disk protection at level 1 is
covered by the [mounted-disk policy tests](../mounted-disk-policy/README.md).
Physical-memory devices and controls for future packet filters remain to be
implemented. Clock backward-step protection at level 2 is tested separately.
