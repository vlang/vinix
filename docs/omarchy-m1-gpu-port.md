# Omarchy M1 GPU comparison and UAT invalidation port

Compared on 2026-11-14. Omarchy configures and packages the Apple graphics
stack; the M1 kernel implementation is Asahi's Rust AGX driver, carried by
Linux-Aurora. The package's immutable kernel pin is the reference for this
port, rather than an unrelated branch tip.

| Source | Revision |
| --- | --- |
| [Omarchy](https://github.com/omacom/omarchy) latest default branch | `723072a553d77d9086444a166413fe9d6b19f045` |
| [Omarchy Mac](https://github.com/omacom/omarchy-mac) legacy integration | `667500c5eefab78424af66350f5ea7bf40fdede6` |
| [Mac packages and manual](https://github.com/omacom/omarchy-mac-pkgs) | `28abebee14de05c35a2caa8dd257d056d15a641e` |
| [Omarchy package definitions](https://github.com/omacom/omarchy-pkgs) | `503056583af49f294e76424b63523f00aa619766` |
| [Linux-Aurora pinned by linux-aurora/PKGBUILD](https://github.com/omacom/linux-aurora/tree/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi) | `bed544bdf93a496ebf70ba180923bab12b6e01cf` |

The clones remain under
`/Users/alex/.local/state/vinix/omarchy-m1-20261114/`. The `aurora-linux`
checkout is detached at the package pin and has an `omacom` remote identifying
the packaged source. No upstream installer or Python tooling was executed.

## Missing logic ported

Asahi's `mem.rs` broadcasts GPU TLB invalidation with `tlbi vmalle1os` and
`tlbi aside1os`. These outer-shareable CPU instructions reach the Apple UAT;
the inner-shareable instructions used by Vinix's CPU virtual-memory manager
are insufficient. Firmware-control requests perform ASC cache maintenance
and do not replace GPU translation invalidation.

Previously Vinix changed UAT PTEs and context roots without issuing any GPU
TLBI. A cached translation could survive unmapping or ASID reuse, or retain
old cache attributes while the driver tried to flush firmware caches.

The V port adds:

- full-system barriers before and after each outer-shareable invalidation;
- invalidation after publishing or removing context roots;
- invalidation after map, reprotect and unmap, including allocation rollback
  and partial reprotect failure;
- full invalidation for global firmware mappings, and ASID invalidation for
  user mappings;
- activation only after a page table's root has been published, so building
  an unpublished table does not broadcast unnecessary invalidations.

Range edits hold the page-table lock across the operation and invalidate
once before returning. The port deliberately invalidates an entire ASID
instead of using the reference's range encoding, which depends on the CPU
page granule. This is conservative and may evict more translations; performance
has not been measured. No new kernel allocations or object lifetimes were added.

The OPP host fixture also declares its libc diagnostic alias, matching the
existing G13 layout fixtures, so current V can run that regression test.

## Validation

The retained kernel source is Vinix `63fc675f13718e5724bfeac54431344815be5085`
plus this port's three kernel source files. Builds use isolated worktrees;
concurrent changes in the main checkout are excluded.

Passed:

- `v run tests/agx-tlb/run.v --sanitize`;
- `v run tests/agx-g13-failure/run.v --sanitize`;
- `tests/agx-g13-abi/run.sh`, `tests/agx-g13-layouts/run.sh` and
  `tests/agx-t8103-opp/run.sh`;
- `v -cc cc test tools/agx-re/g13contract`;
- `make -C tools/agx-re check-g13-reference` with the pinned Linux-Aurora
  checkout and m1n1 `b4654b32941d51afdb77579d63e7cb1aa6c03ecc`;
- AArch64 kernel build with `LIMINE_MP=1` and x86_64 kernel cross-build;
- inspection of the linked AArch64 kernel: the map, reprotect, unmap, bind
  and unbind paths contain outer-shareable TLBI with `dsb sy` on both sides;
- `git diff --check` and formatting verification of the new V sources.

Logs, linked kernels, disassembly, source snapshots and the checksum receipt
are retained in `/Users/alex/.local/state/vinix/omarchy-m1-20261114/`.
`evidence.json` binds the tested source files, upstream pins and artifacts;
its SHA-256 is
`90ec316389365996535dfbb98a101bff6b56315887d32ecd6602d34a89eae47a`.
The source digests were compared with both isolated kernel worktrees.

| Built kernel | SHA-256 |
| --- | --- |
| AArch64 | `cfebef4ef9d87345e9e9a984d1ea526dd2f5ee5fc181dd282b23c7e831de3e0e` |
| x86_64 | `f6a88703d42e5199d1dbd7b2237f7556cbbf56ebca163d751461de7e63d80b75` |

## Acceptance limits

This ports the identified UAT maintenance gap for Vinix's existing base M1
(t8103) path. It does not establish that all driver differences have been
eliminated. Firmware ABIs remain 12.3 and 13.5; userspace remains the pinned
Mesa-era UAPI. Native Apple DeviceTree bring-up and other M1-family variants
retain their existing limitations.

No Vinix boot, compute execution, rendering, lifecycle stress or performance
measurement was performed on an M1 for this change. Follow the hardware
acceptance sequence in [M1 AGX bring-up](m1-agx-bringup.md) before claiming
working GPU acceleration.

Follow-up work and the remaining parity gaps are tracked in
[M1 AGX parity](m1-agx-parity.md). That report also records a retention incident:
the original linked AArch64 kernel was replaced during a later build. Its
checksum receipt is unchanged, but that historical bundle is now incomplete.
