# M1 native driver VM geometry, 2026-11-15

Status: **incomplete driver parity**. Native context creation now matches
Asahi's selected driver-window geometry: validate the original 16 KiB-aligned
reservation, align its ends inward to 32 KiB, and round its shared/private
midpoint down to 32 KiB. The context records those normalized bounds, including
for user binding exclusion. Previously both window edges and the split used
the 16 KiB UAT granule.

Per-VM driver allocations now use `max(requested_alignment, 32 KiB)` and reject
size-rounding overflow before allocation. The VA heap, mapped extent and
physical page count use the same rounded size. This also covers default
allocations and tail-pointer backing that requests 16 KiB alignment. Stronger
alignment is preserved. UAT, user mappings and the dummy page retain their
16 KiB granule.

Offline validation passed:

- The ASan/UBSan fixture executes production context creation/destruction,
  identity allocation and driver allocation/release with injected locks,
  VA heaps, PTE and PMM services. Two hundred context cycles and 1,200
  shared/private allocations cover geometry, default/stronger alignment,
  permissions, overflow/invalid/inactive refusal, constructor/physical/VA/map
  failures and final backing release. Successful context metadata is freed
  only by fixture cleanup after destruction; native metadata retention is
  unchanged and whole-kernel heap behavior is not qualified.
- The pure VM test checks 1,000 varied windows against an independent
  division-based oracle, normalized edge permissions and invalid reservations,
  plus existing identity/exhaustion and bind validation. Prior file-close,
  mapping, private-BO, PRIME and queue-priority sanitizer regressions pass.
- Three V suites (eight test files), packaged-source/reference gates, all
  40 live ARM generated-C helper checks and strict negative storage selftests
  pass. The new scalar window helper allocates no temporary storage.
- Isolated ARM and clean ordinary x86 kernel builds pass; ordinary x86
  excludes AGX. No owning pointer, allocation site, free or callback lifetime
  transition was added by this change.

Build baseline: `a58e3038502b8990f08ffc105aaa9b6eb0ed61e5`, plus retained
`gpu/agx/vm/vm.v` and `gpu/agx/mmu/mmu.v` overlays. All AGX/syncobj/GEM/ioctl
V sources and generic `drm.v` match the isolated checkout; both architecture
overlays match the audited snapshot. The sibling `completion.txt` binds all
14 non-report feature sources to the commit and retains the reports separately.

Remote heads were rechecked unchanged: Omarchy
`d76f364b41ccf01909b1d84ffcc6bd4fbb8cd91d`, packages
`631b8696edc9b351e69cf0b16f2aba0804e1eaf5`. Their clean clones still select
Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`; m1n1 remains
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

Complete evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-vm-geometry-20261115/`:
canonical `bundle/`, `inventory.json`, and `bundle.tar.gz`. Complete extraction
and restored/canonical inventories pass the unchanged historical checker.

| Artifact | SHA-256 |
| --- | --- |
| Inventory receipt | `eaf3407db435c95484608b07a4e2f27c9e413ce9508cedc6a9d87bb422531f27` |
| Complete archive | `17df15ed1f7f6ff32b4653fe3641279112b64c03f3935f74941250cbc71649f7` |
| ARM ELF | `e0f06861702f39282b305ce7e61210474850147e50fe346a747017e440dba0c4` |
| x86 ELF | `b0a67bf605cb530b9c991f75ecfbed34eacce92fb7d2c2bfc58455ecd613a140` |

The audit still returns **not_equivalent** (expected exit 1). This matches
selected native window/alignment behavior; allocator placement, modern
ABI/Mesa integration, VM replacement/splitting, Linux reservation-fence/cache/
accounting semantics and unchecked behavior remain open. No native GPU or
firmware execution, Vinix boot, hardware test, reboot or deployment occurred.
