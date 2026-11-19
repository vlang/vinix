# M1 AGX InitData values

Earlier checks compared the G13 InitData layouts with the reference. This
pass compares the values Vinix writes into each field for base M1 (t8103)
at firmware 12.3 and 13.5 with Omarchy's pinned Asahi builder
([`initdata.rs`](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/initdata.rs)
at Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`). It also compares
the device-tree power derivation and the UAT protections of the objects
InitData points to. A wrong default here can stop the firmware on the first
hardware boot.

## Differences fixed

| Field | Before | Asahi and now Vinix |
| --- | --- | --- |
| HwDataB `unk_20`, `unk_28` | `0x11_0000_0000`, m1n1's macOS capture | 0 |
| HwDataB `num_cores` | active cores: 7 on a seven-core M1 | cores per cluster × clusters: 8 |
| Globals `unk_903c` at 13.5 | 0 | 1 (at 13.5 offset 0x9190) |
| HwDataA `T81xxData` at 13.5 | the eight pre-13.3 values | zero: Asahi fills it below 13.3 only |
| HwDataA `pwr_integral_min_clamp_2` | the integer clamp | never written |
| HwDataA 13.5 SE `*_clks` | SE constant × `apple,pwr-sample-period-aic-clks` | SE constant × 24 MHz clocks per sample period |
| UAT firmware-shared RW | PXN set: the GPU could read channel rings, FwStatus, RTKit and timestamp buffers | `PROT_FW_SHARED_RW`, no GPU access |
| UAT firmware-shared RO | PXN set: Asahi's `_PROT_FW_NA` | `PROT_FW_SHARED_RO` |
| t8103 OPP nodes | `status = "disabled"` nodes skipped | every child read, as `of_get_next_child()` does |

The last two SE rows and the OPP row give the same values on a stock m1n1
device tree; they diverged only when the device tree supplies the overriding
property or disables a node.

InitData RegionA stays firmware-writable. Asahi maps it firmware read-only,
m1n1 maps it read-write, and both run on hardware. Vinix moved it to
read-write in September after a firmware fault at RegionA+0x10. Its
read-only encoding was then actually firmware no-access, so that fault does
not establish a firmware write. Keeping read-write cannot fault.

## Compared and equal

Five independent comparisons walked every field the reference builder sets
for t8103, including fields left zero and version-conditional fields:

- HwDataA: about 128 fields at 12.3 and 152 at 13.5.
- HwDataB: 56 fields at 12.3 and 53 at 13.5, including all 20 or 25 I/O
  mapping slots and their virtual addresses.
- Globals: 68 field groups, including the shared tables and the
  device-tree power coefficients.
- RuntimePointers, FwStatus, UAT level info and InitData: 53 fields or
  groups, with object sizes, allocators and the firmware start order.
- Device-tree power derivation: about 70 values, including OPP parsing,
  SRAM clamping, relative power and boost tables, and power zones.

## Remaining differences

- Asahi's software float rounds exact ties up, and its multiply and divide
  truncate before rounding. Vinix rounds correctly to even. They differ by
  one ULP where a result falls exactly between two floats. At 13.5,
  `gpu_se_filter_1_a_neg` = 1 − 1/3 is such a tie: Asahi and m1n1 write
  `0x3f2aaaab`, Vinix `0x3f2aaaaa`. Other coefficients checked against the
  live t8103 inputs are equal.
- Unused `pwr_*` fields in `hw/t8103.v` hold values that are not t8103's;
  nothing reads them.
- The native Apple device-tree power loader is incomplete, but that boot
  path is still gated off.

## Validation

`tests/agx-g13-abi` checks each value above at both firmware ABIs for a
seven-core identity. Five negative controls each revert one fix and fail at
its own assertion. `tests/agx-tlb` checks all eleven protection words against
Asahi's `Prot::from_bits` encoding; the previous constants failed it.

Passed in an isolated worktree at `707df8e76` plus this change:

- `agx-g13-abi`, `agx-t8103-opp`, `agx-tlb` and `agx-g13-failure` under
  ASan/UBSan, plus `agx-g13-layouts`;
- the regenerated InitData layout check and 79 G13 contract test files;
- all 122 pinned-reference checks against Linux-Aurora and m1n1
  `b4654b32941d51afdb77579d63e7cb1aa6c03ecc`;
- AArch64 (`LIMINE_MP=1`) and x86_64 `PROD` kernel builds. The generated
  AArch64 C carries the new HwDataB, Globals and protection values;
- the allocation scan: the same 427 findings as the previous baseline,
  with only line numbers moved.

The changed paths run only on an M1 GPU, so no QEMU boot was attempted.
Native M1 validation remains open.

Evidence is under
`/Users/alex/.local/state/vinix/omarchy-m1-initdata-values-20261119/`.
The kernels were not retained because of low disk space; their SHA-256
checksums are in the bundle.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `a2f53f4f0a6232468dd3f87220bab10cf3f63df1769c960a4fdb12bdb300a049` |
| `bundle.inventory.txt` | `997e0e0d40dd035d8de677da28aa5431ebc761d318a42649fc965e846bf874c8` |
