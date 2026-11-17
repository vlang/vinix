# GEM advice for resident private objects

The modern native driver now registers all twelve packaged request numbers,
including `GEM_MADVISE`. It validates pad/advice before file-local handle lookup,
rejects shared/external objects, records WILLNEED/DONTNEED under the object lock,
and returns `retained=1`. Existing contiguous backing stays resident; advice never
frees pages or changes GPU/CPU mappings. Shmem purge/repopulation remains open.

The file lock protects reference acquisition. The owned reference survives file
unlock and concurrent handle removal, then is released after object unlock on
every success/refusal exit. Outputs change only on success; a later transport
copyout fault preserves committed advice. No idle or still-visible VM name is
required. Legacy ABI selection remains isolated.

Reference: Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Asahi
`file.rs`/`gem.rs`, `drm_gem_shmem_helper.c` and `asahi_drm.h`. Native builds use
Vinix `5648deb6a83989698af3f42f659511727004a812` plus four owned kernel overlays;
concurrent event changes are excluded. Offline checks pass:

- ASan/UBSan and `-gc none -manualfree`: 96 header/ownership/state cases,
  scripted handle removal, resident contents, framing and copyin/copyout faults,
  plus the file/VM/queue/PRIME/modern-transport regressions. GEM backing/refcount
  plumbing is modeled; advice and ioctl bodies are production code.
- Four compiled negatives fail the intended header/private eligibility,
  reference-cleanup and state assertions.
- All 2,048 resident advice sequences / 20,480 transitions and the 16-byte
  record's offsets match compiled unchanged pinned shmem code. The reference is
  sanitized; reservation locking is stubbed and purged states are excluded.
  Rust ioctl/eligibility bodies receive source comparison only.
- Three warmed batches of 10,000 calls retain zero host malloc blocks/bytes
  with balanced temporary references. This does not establish native slab or
  whole-kernel retention rates.
- ARM MP and x86 builds and 78 source-contract files pass. ARM C confirms no
  hidden allocation/backing operations and exact reference/unlock/output order.
  Helper C matches sanitized, measurement and trace builds; caller C matches
  the first two after fixture-name normalization. Fourteen shared GEM/BO/
  lifetime/submission/transfer bodies match baseline on ARM and five on x86,
  which prunes the new endpoint. Independent lifetime review covers ownership,
  lock order and fixture teardown.
- Allocation diagnostics remain 377 ARM / 289 x86 sites across 853 / 825 source
  files. Every file/kind count matches the preceding complete bundle; existing
  allowance failures remain. Allowances and historical checkers are unchanged.

Full parity remains **incomplete**. Purge/repopulation, scatter/shmem backing,
interruptible reservation locks, accounting, sync interoperability, callback
timing/reclamation, matched Mesa integration and hardware acceptance remain
open or unqualified. Generic timeline capability stays disabled. No GPU access,
firmware execution, Vinix/QEMU boot, deployment or reboot occurred.

Maintained [tests and reproduction instructions](../tests/agx-gem-advice/README.md).
The complete bundle, archive/restoration and post-commit receipt are retained at
`/Users/alex/.local/state/vinix/omarchy-m1-gem-advice-20261117/`.
Sealing rechecks the original complete preceding bundle; binding checks committed
feature bytes against sealed source. Earlier fixture/checker setup failures are
retained separately in the state directory.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `7f6fb0147ca315173a4ccd684f500c17ff9c348c666c3ac9a0fc58eb5f4cfcde` |
| `bundle.tar.gz.inventory.txt` | `d3510d1abaa99b79f1200c5c9383deb4439c7b34528634afb9359bd0a38506f6` |
| ARM ELF | `6cecc93c6f040f4049f24c021125c60d1b419a893a23dddc3306953a97e60c17` |
| ARM C | `5cc4d62891d77643397c070c3dc61145a5f4f8266e457e51be9845ed2a1836b9` |
| x86 ELF | `dce7e0760efc9f47c9b7f69503eb2ddc65db0842d6dbda0e0f372e058a0737b8` |
| x86 C | `232550a13e56a4760bb091eca9d2a602d28a7eb71f349d4cec3f9cb50ff8b23f` |
