# Page-table reclamation regression

`pagetable.c` checks actual guest mappings, using the guest's page size. On
amd64 it crosses 2 MiB, 1 GiB and 512 GiB table boundaries, plus 256 TiB when
five-level paging is available. A four-level kernel must print a skip for the
256 TiB probe. On AArch64 it crosses the 32 MiB and 64 GiB boundaries of the
16 KiB translation tables.

The test keeps sibling pages mapped while it removes earlier tables, creates
holes with surviving entries on either side, handles faults on unmapped
addresses, and reuses the detached tables. A child verifies its forked pages
after the parent replaces its mapping, then writes a COW page without changing
the parent's value. Each replacement must contain zeroes.

Compile it with GNU GCC in a Vinix guest and run it as a normal program:

```sh
gcc -std=gnu11 -O2 -Wall -Wextra -Werror -fno-builtin \
    -DVINIX_PAGETABLE_STANDALONE tests/memory/pagetable.c -o /tmp/pagetable
/tmp/pagetable
```

The expected final marker is `PAGETABLE CHECK: PASS`. This fixture can also be
included in the core regression and called as
`CHECK(vinix_pagetable_boundaries() == 0)` from its first-boot worker. The
allocator comparison's frozen full-core validation uses that form on both
architectures, with two CPUs; amd64 runs with five-level paging enabled and
disabled, and AArch64 also runs its existing persistence verification boot.

The free-memory check permits 1 MiB of process and filesystem bookkeeping; it
does not replace the separate repeated-operation slab and memory measurements.
