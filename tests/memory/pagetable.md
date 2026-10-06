# Page-table reclamation regression

`pagetablefixture/core.v` checks actual guest mappings, using the guest's page size. On
amd64 it crosses 2 MiB, 1 GiB and 512 GiB table boundaries, plus 256 TiB when
five-level paging is available. The original probe addresses are 64 MiB,
32 GiB, 4 TiB and 256 TiB. A CPU without LA57 prints a skip for the final
probe; a supporting CPU must exercise it. On AArch64 it crosses the 32 MiB
and 64 GiB boundaries of the 16 KiB translation tables at 128 MiB and 512 GiB.

The test keeps sibling pages mapped while it removes earlier tables, creates
holes with surviving entries on either side, handles faults on unmapped
addresses, and reuses the detached tables. A child verifies its forked pages
after the parent replaces its mapping, then writes a COW page without changing
the parent's value. Each replacement must contain zeroes.

Build the native fixture and run it against an isolated kernel:

```sh
python3 tests/memory/run-pagetable.py --arch x86_64 \
  --kernel-dir /path/to/isolated/kernel \
  --state-dir /path/to/new/pagetable-build \
  --guest-state-dir /path/to/new/pagetable-guest
```

Use `--arch aarch64` for ARM, or `--build-only` to emit a static executable
without booting. `CC_AMD64` selects GNU musl GCC; `CC_AARCH64` and
`VINIX_AARCH64_SYSROOT` select the ARM Clang/SDK. The test gets a 3,600-second
outer boot allowance with every original check unchanged. PID 1 remains alive
after the complete success marker.

The expected final marker is `PAGETABLE CHECK: PASS`. The generated fixture
object also exports `vinix_pagetable_boundaries`, so a core regression can link
it and call
`CHECK(vinix_pagetable_boundaries() == 0)` from its first-boot worker. The
allocator comparison's frozen full-core validation uses that form on both
architectures, with two CPUs; amd64 runs with five-level paging enabled and
disabled, and AArch64 also runs its existing persistence verification boot.

`--original-reference /path/to/immutable/pagetable.c` builds the independent
original against the same native SDK and entry. Both C/V guest pairs passed
all original 45 check sites: ARM covered both 16 KiB boundaries, and x86 covered
all four 4 KiB boundaries including LA57. Native IR preserves volatile byte and
signal accesses and the SDK's `returns_twice` jump-buffer declaration; both V
objects have no allocator imports. Signal callbacks use their actual C wrappers,
and pipe/COW lifetimes end in the original close/reap/unmap order. This native VM
regression adds no host sanitizer or new kernel-build claim.

The free-memory check permits 1 MiB of process and filesystem bookkeeping; it
does not replace the separate repeated-operation slab and memory measurements.
