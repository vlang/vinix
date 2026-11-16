# Vertex and compute command extents and common fields

The 13.5 vertex and compute converters now preserve their complete common
declared fields, including padding and the flags after `client_sequence`.
Both previously stopped at that sequence byte and left some earlier common
padding uncopied. The command extents now match the selected packaged
[vertex](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/vertex.rs)
and [compute](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/compute.rs)
source-layout model:

| Record | 12.3, unchanged | Previous 13.5 | Corrected 13.5 |
| --- | --- | --- | --- |
| Vertex | `0x5e0` | `0x61c` | `0x608` |
| Compute | `0x2dc` | `0x320` | `0x31c` |

G13 vertex adds a counter after the tag and a suffix after the final old flag;
all common fields after the tag shift eight bytes. `TilingParameters` remains
`0xa0` in both versions. Compute's first parameter block remains `0x160`; its second remains
`0x60` while replacing its last word with a zero prefix. The converters exclude
the old aggregates' implicit tail padding, which would otherwise overlap the
new suffixes. Firmware-address getters and the shared compute flag at `0x305`
are unchanged.

Native preparation currently zeroes the newly preserved padding and flags.
This corrects conversion semantics and record extents; it does not establish
an observed hardware crash fix or change userspace timestamp support.

The new V model recursively matches common leaf fields from the versioned Rust
declarations. Recursion matters when a parent size stays equal despite internal
field movement, as in compute's second block. Expected spans come from those
declarations, independently of native copy ranges. Existing pointer/integer,
event and tag representation guards run first; record `repr(C)`, padding,
array and software-float representations also have explicit guards. Unknown
active types fail. This remains a selected source-layout model, not an
independently compiled Rust oracle or every native initialization value.

Validation passed:

- 8,000 ASan/UBSan complete vertex/compute command images through the real
  converters. Every source byte is nonzero; cases cover five full-width
  counters and four guarded alignments. Every common declared byte, including
  padding, is compared; new fields/suffixes start zero and sources/guards stay
  unchanged. Stack-use-after-return detection and sanitizer linkage are retained.
- Four old-code negatives compile. The exact prior converters lose nonzero
  padding at vertex `0x454` and compute `0x1c0`; complete prior modules fail
  the 13.5 extent checks. Raw baselines, exact selections, hashes, overlays,
  runner, binaries and failures remain. Overlays never alter the expected map.
- All 40 V test files, selected primary-source gates and native C storage
  checks for 115 helpers plus their allocation-mutation selftest pass. Unit
  checks cover equal-size nested movement, unknown types and representation drift.
- Existing 12,000 vertex-start images, 8,000 compute start/finalize pairs,
  12,000 fragment images, layout, async/scheduler, lifecycle/mapping, wait,
  wire, fence, VM and sanitized production PTE regressions pass.
- Root generated-C review matches exact converter byte-span edits, without
  allocations, frees or new lifetimes. Native render/compute preparation,
  both cleanup/reaper paths, batch publication and fragment conversion match
  preceding C textually. Emitted types carry the corrected result extents.
- Isolated ARM and clean ordinary x86 builds pass from
  `e5a47036b23816047a476415c734a8e4287d097c` with two retained native overlays:
  `fw/vertex.v` and `fw/compute.v`. Ordinary x86 excludes native AGX and uses
  `LD_X86_64=ld.lld`. Exact input snapshots, generated C and ELF remain for both.

Allocation allowance audits **still fail identically** on baseline and changed
code: 381 ARM/289 x86 sites, 828/813 sources, equal per-file/kind counts and
identical logs. No allowance changed. Existing temporary heap copies remain;
compiler counts do not measure native heap rates.

Fresh upstream heads: Omarchy `1b38e58317817cc48a45d27e73cae5da3fbb34fe`,
packages `46356364b2e9cf6b917091ac7c688bb4139675cb`. Pins remain Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Full audit is still
`not_equivalent` (exit 1); selected gates pass.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-work-tails-20261116/`.
The canonical `bundle/` and full archive restoration use the unchanged complete
typed inventory checker. `completion.txt` binds ten source paths and two
reports to the feature commit. The initial missing host diagnostic stub and
passing earlier unit/audit snapshots remain in `diagnostics/`.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `7f359c32bf44284062f034238b9572c51d8f66fd567dc20d91964c82507c8fc3` |
| `bundle.tar.gz` | `3a1768485277a5fae3e91db4e8af1f94475e9d57c7b145ba11926d46b099ac15` |
| `bundle/vinix-aarch64` | `7fd8e5eaee3a385059e601a18428c4912b6f3f4d5299bcea4f3599060f761a34` |
| `bundle/vinix-x86_64` | `ff48ab07c9654e8fe61d4b7cc94d9da17f73a4184233db588e2881a44594d69d` |
| `bundle/blob-aarch64.c` | `d0dedaaacf43e222ed2a9c7172e1b0b6e66884f4d125724a48b78c92aa621c92` |

Allocating job initialization, firmware interpretation, other wire/default
fields, ABI/Mesa migration, reservation fences, cumulative timelines, queue
ownership, memory attributes, topology and power/reset remain unqualified.
No native hardware test, GPU workload, Vinix/QEMU boot, reboot, SSH or
deployment occurred.
