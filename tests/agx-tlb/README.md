# Apple GPU TLB invalidation

Run `v run tests/agx-tlb/run.v --sanitize` from the repository root.

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
- all host page-table allocations are released.

The source-reference gate independently checks the actual instructions,
barriers and root-publication order against Omarchy's Asahi-derived driver:

```sh
make -C tools/agx-re check-g13-reference ASAHI_LINUX=/path/to/linux-aurora
```

These tests do not execute privileged instructions or GPU commands. Cross-build
the AArch64 kernel to validate assembly; the hardware acceptance sequence in
`docs/m1-agx-bringup.md` remains required to establish working acceleration.
