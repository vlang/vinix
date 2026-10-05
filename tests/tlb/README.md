# Tagged ARM64 TLB regression tests

Vinix retains user translations across direct switches between tagged ARM64
address spaces. Each live `Pagemap` owns one of 255 globally unique eight-bit
ASIDs. ASID zero is reserved for the kernel and for pool exhaustion; switching
to zero preserves the conservative local whole-TLB flush. Sixteen-bit-capable
CPUs use the same eight-bit configuration, so CPU migration does not change
the ownership contract.

Every TTBR0 leaf is non-global, including `PROT_NONE` descriptors and copied
COW/shared leaves. TTBR1 kernel leaves remain global. Every CPU programs
`TCR.A1=0` and `TCR.AS=0`; thread contexts save the full tagged TTBR0, while
`Pagemap.top_level` remains a physical address. Present user descriptors use
broadcast break-before-make even when the map is inactive. Existing page/table
unmaps still broadcast their invalidations.

Destruction first drains process-inspection references and invalidates the
map's ASID before any existing page/table frees. It releases ownership only
after every range is removed. Both release and later allocation complete
`DSB ISHST; TLBI ASIDE1IS; DSB ISH; ISB` before a tag can change owner. An
unsuccessful teardown retains its tag rather than letting a live table alias
another owner's translations. The bitmap and lock are static; the switching,
reservation and release paths allocate no memory.

This closes the ARM64 portion of VM7. It does not implement x86 PCID,
16-bit-ASID generation rollover, huge pages (VM6), or pointer authentication
(SEC7). ASID-zero switches and existing full invalidations may still evict
other tags. No throughput or native-hardware speedup is asserted.

Build with the pinned repository V compiler and isolated dependency directories:

```sh
VEXE=/Users/alex/code/v/v make -C kernel -j4 CC=clang \
  V=/Users/alex/code/v/v ARCH=aarch64 LIMINE_MP=1 VFLAGS='-d tlb_selftest'
VINIX_QEMU_SMP=4 python3 tests/kernel-gaps/run.py \
  --source tests/tlb/guest.c --arch aarch64 --kernel-dir kernel \
  --expect 'TLB: ASID pool exhaustion and reuse PASS' \
  --expect 'TLB: SMP protection and address reuse PASS' \
  --expect 'TLB: fork COW and 300 map recycling cycles PASS' \
  --expect 'TLB: exec replacement and tag reuse PASS' \
  --expect 'TLB: repeated context switches retention PASS' \
  --expect 'TLB: ALL PASS' --timeout 300
```

The optional boot test executes the production ASID allocator, reserves all
255 owners, checks zero/exhaustion, releases one owner, verifies exclusive
reuse, releases the pool, and repeats allocation/release 2,000 times. It also
checks the programmed TCR selector/width and non-global `PROT_NONE` descriptor.
It uses no heap allocation. This is pool exhaustion coverage, rather than a
claim that 256 full user processes were booted simultaneously.

The actual guest pins a worker to CPU 1 and the main thread to CPU 0 for 100
permission and unmap/address-reuse rounds, alternating read-only and
`PROT_NONE`. A freed-frame filler makes stale reuse observable. It also checks
300 fork/COW address-space recycling cycles and 32 exec replacements. Finally,
two live processes on one CPU perform 20,000 alternating scheduling rounds,
with slab-class and large-allocation measurements taken while both remain alive.

The same guest also runs against x86 to check the shared teardown changes:

```sh
# Build in a separate checkout/object tree.
VEXE=/Users/alex/code/v/v make -C kernel -j4 CC=clang \
  V=/Users/alex/code/v/v ARCH=x86_64 LD_X86_64=/opt/homebrew/bin/ld.lld
python3 tests/kernel-gaps/run.py --source tests/tlb/guest.c \
  --arch x86_64 --kernel-dir kernel \
  --expect 'TLB: SMP protection and address reuse PASS' \
  --expect 'TLB: fork COW and 300 map recycling cycles PASS' \
  --expect 'TLB: exec replacement and tag reuse PASS' \
  --expect 'TLB: repeated context switches retention PASS' \
  --expect 'TLB: ALL PASS' --timeout 300
```

Validation on 2026-10-02: both architecture builds and actual QEMU guests passed
(ARM64 four CPUs using HVF; x86 two CPUs using TCG). The switching experiment
kept every slab class except size 48 flat, and retained zero large-allocation
pages. Size 48 increased by one object (48 bytes), matching the separately
identified baseline `/proc/slabinfo` `lib.Text.str()` receiver allocation per
read. The test prints that observed delta and allows at most this one known
reader allocation; it does not call it measurement noise or claim complete
kernel leak freedom. Generated C for the ASID pool, switch, teardown and release
contains no `memdup`, heap allocation, or array construction.
