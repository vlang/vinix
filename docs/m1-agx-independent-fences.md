# Independent G13 queue fences

The [pre-hardware audit](m1-agx-prehardware-20261117.md) reproduced premature
cross-queue dispatch. Native compute and render work on the same logical queue
can retire independently in the host fixture. The producer fences share a
context, so the old reduction discarded the earlier fence even while it was
pending. DMA fence merging for DRM timeline transfer used the same reduction.

Both paths now collapse a native queue dependency only when they see the
same fence again. Ordered 64-bit sequences keep the latest fence per context.
Native queue identity still supports own-queue elision, and the worker can
continue to retire independent submissions in either order. The correction
uses the existing borrowed input storage. Timeline transfer uses its existing
fence-array allocation when multiple leaves remain pending.

Tests use Vinix `7483aa6a5` plus this patch in an isolated worktree and the
packaged Linux-Aurora pin `bed544bdf93a496ebf70ba180923bab12b6e01cf`.

- The reverse-retirement probe passes through legacy submission and a
  65-record modern submission. A consumer on another queue waits for both
  producer fences, and repeated records reduce to two dependencies.
- The DRM `TRANSFER` fixture retains both same-queue fences and collapses an
  exact duplicate. It checks both notification orders and runs with equal or
  unequal sequence values. The destination point stays pending until both
  fences complete.
- Restoring the old reducer and the old merge implementation individually
  reproduces the expected assertion failures. The normal AGX, fake-fence
  and DRM suites pass with ASan/UBSan. The 82 V contract and layout test
  files and five protocol source gates pass.
- The pinned reference oracles match 4,096 ordered 64-bit dependency
  selections and 8,640 ordered timeline transfer outcomes. This comparison
  covers ordered contexts. The independent native fences use Vinix's
  completion model.
- AArch64 MP and x86_64 kernels both build. The generated C keeps the copied
  dependency header on the stack and adds no allocation in sequence
  classification or merge reduction. Nine warmed submission copy/release
  batches and nine failed-transfer batches retain zero host malloc blocks or
  bytes. V reports the same per-file allocation counts as before, with 377 ARM
  and 289 x86 sites. Existing allocation-allowance failures remain.

The correction leaves Asahi's 32-bit per-entity sequence model, generic DRM
timeline capability reporting and the matched Mesa image open. Validation
used injected completion events and excluded the concurrent event-manager
edit. Hardware execution, deployment and reboot were outside this run.

The follow-up [32-bit fence numbering change](m1-agx-fence-ordinals.md) covers
the exported counter and verifies independent retirement through wrap.

```sh
ASAN_OPTIONS=detect_stack_use_after_return=1 \
  v run tests/agx-async/run.v --audit-dependency-order
ASAN_OPTIONS=detect_stack_use_after_return=1 \
  v run tests/drm-syncobj-wait/run.v
```

The complete inputs, executables, logs and verified archive restoration are
under `/Users/alex/.local/state/vinix/omarchy-m1-independent-dependencies-20261117/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `ea573a751d0f104071fa4bb22b7842ac2996c7f3d634f87d238d0847066fc06c` |
| `bundle.tar.gz.inventory.txt` | `594d42334ca7ea805221d6e3adaf98b7d7ce18ea61978cc5690b95ad37af52eb` |
