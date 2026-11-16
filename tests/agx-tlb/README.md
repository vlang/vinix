# Apple GPU TLB invalidation

Compile `run.v` with V to an external executable, then run it with `--sanitize`.
Set `AGX_TLB_TEST_BINARY` to retain the sanitizer executable outside Git.

The runner executes the production UAT page-table operations and context-root
publishers against host allocations. Only physical allocation, locks, handoff
arbitration and privileged instructions are replaced. The TLBI fixture records
the PTE and context-table words visible at each invalidation. It checks:

- mapping and cache-attribute changes are visible before invalidation;
- unmapping and allocation rollback invalidate before returning;
- a partial reprotect failure still invalidates changed entries;
- each range causes one invalidation, and unpublished tables cause none;
- root publication, removal and reuse invalidate the correct ASID;
- global firmware mappings use full invalidation;
- RO, WO and RW mappings use Asahi's distinct exact leaf encodings, and all
  nine reprotection transitions replace the permission selector before TLBI;
- 16 KiB page/range TLBI operands cover scale boundaries and advance the
  address between full chunks, including canonical high addresses;
- all host page-table allocations are released.

One hundred SINGLE_PAGE cycles map 1, 2, 3 and 17 virtual pages to the same
physical page, with every RO/WO/RW PTE checked across an L3 boundary. Ordinary
maps still advance physical addresses. All aliases disappear on unmap; an
injected table-allocation failure rolls back the written leaf before TLBI.
Unaligned addresses and wrapping ranges refuse without invalidation, and
destroy releases every table allocation after each cycle.

Another hundred cycles remove head, tail, middle and complete ranges from
contiguous and repeated mappings with RO/WO/RW permissions across L3 boundaries.
Every surviving production PTE retains its physical address and permission word;
only the requested hole is cleared before TLBI. Final destruction returns all
host page-table allocations.

BIND preparation adds a hundred sanitizer cycles. Actual root/table OOM returns
failure; a later L3 failure preserves old leaves and retains earlier empty
tables under their root. After complete preparation, forcing every allocation
to fail still permits both contiguous and repeated replacement across the full
prepared span. Preparation emits no TLBI or leaf writes. Final destruction
releases all tables. Run this suite with `--sanitize` as described above.

The source-reference gate independently checks the actual instructions,
barriers, root-publication order, bind permission selection and GPU UAT
permission encodings against Omarchy's Asahi-derived driver:

```sh
make -C tools/agx-re check-g13-reference ASAHI_LINUX=/path/to/linux-aurora
```

These tests do not execute privileged instructions or GPU commands. Cross-build
the AArch64 kernel to validate assembly; the hardware acceptance sequence in
`docs/m1-agx-bringup.md` remains required to establish working acceleration.
