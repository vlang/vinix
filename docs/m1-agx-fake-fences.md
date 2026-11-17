# Independent fake AGX fence contexts

Fake submission fences now use a fresh nonzero context and sequence 1 for every
job. Previously all queues of a file used the file address as context and the
clock as sequence. Context deduplication could then drop still-pending jobs.
The fake backend's independent completion workers can retire out of order even
on one queue, so per-queue contexts alone would leave the same problem.
Generic fences deliberately carry no queue-dependency elision provenance.

This follows the context-ordering contract in packaged Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, `include/linux/dma-fence.h`, and
`drivers/dma-buf/dma-fence-unwrap.c`: merge keeps only the latest sequence of
each context. Independent fake jobs must therefore have distinct contexts.
Asahi's ordered scheduler remains different; this correction preserves every
fake dependency rather than claiming scheduler equivalence.

Context exhaustion returns before fence allocation. Existing submit admission
checks retain precedence; an acquired VM/file pin is unwound under the file
lock, which is released before returning `-12`. Outputs remain untouched.
Fence, completion-worker, queue and close metadata lifetimes remain unchanged.

Offline validation uses isolated Vinix
`0d7a4df5b598242f4f6bbb77a914426459054714` plus two owned kernel overlays;
concurrent event changes are excluded:

- ASan/UBSan and `-gc none -manualfree`: all 48 same/cross-queue retirement
  permutations retain four pending dependencies and propagate an error.
  Sixteen extracted submit-transaction cases verify compute/render, VM busy,
  counter saturation, exhaustion, exact pin unwind, unlock and output identity.
  The last context succeeds once; 1,000 later reservations fail. Full DRM
  regressions pass. VM/file plumbing is modeled; the transaction body adapts
  only the output array's address expression to a borrowed fixture parameter.
- Four compiled negatives fail the intended assertions for shared contexts,
  exhaustion fallback, dependency elision and missing VM-pin unwind.
- ARM MP and x86 builds and all 77 source-contract files pass. ARM generated C
  shows no hidden allocation before the unchanged fence constructor, and confirms
  failure cleanup (including the existing staged-resource defer) before output
  effects. Admission/work paths and six completion/close/queue bodies match
  baseline after generated temporary-number normalization. Ten shared DRM bodies
  match on ARM; nine match on x86, which prunes the fake backend and constructor.
- Allocation diagnostics remain 377 ARM / 289 x86 sites across 852 / 824 source
  files. Every file/kind count matches the preceding complete bundle; existing
  allowance failures remain and allowances are unchanged. These diagnostics do
  not enumerate all explicit allocations or establish native retention rates.
- Independent lifetime review found no production blocker. Fixture-only copies
  of the queue array and output parameter were removed after generated-C review.
  This is functional/lifetime evidence, not a claim of flat native memory usage.

Full parity remains **incomplete**. The generic timeline capability stays
disabled. Eager callback timing, retained published metadata, legacy/modern
interoperability, remaining UAPI/Mesa integration, firmware/cache lifecycle and
hardware qualification remain open. No hardware access, firmware execution,
Vinix/QEMU boots, deployment or reboots occurred.

Maintained [tests and reproduction instructions](../tests/agx-fake-fences/README.md).
The complete bundle and restored archive are retained at
`/Users/alex/.local/state/vinix/omarchy-m1-fake-fences-20261117/`.
The original preceding timeline-transfer bundle is checked without weakening
its complete-inventory requirements. A post-commit receipt binds feature bytes
to the sealed source. Earlier fixture compile/control failures remain separately
retained in the state directory.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `96fe38b238aac899dc2106d42f07658a6ebad6b38729f90bf62b877a4671df55` |
| `bundle.tar.gz.inventory.txt` | `ccae3e420231750009615779db949b0bc73bdd197bb7986d4aeefb850995c87d` |
| ARM ELF | `a38b8bae4e384b070eb30cd5b881e08f1299bad91eb40864abaccc583c544dde` |
| ARM C | `382a70164add9bbf3fcaf24a88f0405fb7d95941dd5e7e4934110c22c4072620` |
| x86 ELF | `38a36d919d581cef29648fb6266b796eec7537b5ef994a6ebdc69db328995c8f` |
| x86 C | `c169809640036572701ee7eeb3920a46119959e90161b15137a3556b14ed8a64` |
