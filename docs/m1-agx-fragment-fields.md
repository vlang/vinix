# Complete fragment fields and auxiliary defaults

The 13.5 fragment converter now copies the complete `0xf0`-byte second parameter
block. It previously copied `0xe0`, dropping 16 declared padding bytes at
`0x4a8..0x4b8`. Command sizes, firmware pointers, ownership and other copy ranges
are unchanged. Current native preparation zeroes these bytes, so this corrects
conversion fidelity without claiming an observed hardware failure.

The recursive field-by-field model now includes the packaged
[fragment declarations](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/fragment.rs),
alongside vertex and compute. It matches common leaf fields by identity through
nested layouts, including declared padding. It also derives the two new
`AuxFBInfo.unk3` locations, `0xc0` and `0x6e8`, and reads their `0x100000` scalar
from the [render builder](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/render.rs).
The expected image uses those defaults and zero for other added fields and
aggregate padding. Native copy ranges and module overlays cannot alter that map.

Record `repr(C)`, packed pointer/integer/event/tag, padding, array and software
float representations are guarded. The default parser accepts one scalar U64
literal within the auxiliary initializer, rejects expressions and internal
duplicates, and ignores unrelated later source. This remains a selected V
source-layout model, not an independently compiled Rust oracle or every native
initialization value.

Validation passed:

- 12,000 ASan/UBSan complete modeled command images across all three converters,
  with nonzero source patterns, five full-width counters, four guarded source
  alignments and unchanged sources/guards. New auxiliary words match their
  source-derived defaults. Stack-use-after-return detection and linkage receipts
  are retained.
- The initial unmodified converter fails at `0x4a8`, leaving zero instead of
  nonzero declared padding. Its binary, model, report and failure remain. An
  explicit complete old-module overlay compiles and fails at the same byte;
  its source matches the baseline and preceding sealed source exactly.
- All 40 V test files, selected primary-source gates and native ARM C storage
  checks for 115 helpers plus their allocation-mutation selftest pass. The new
  literal-boundary test's initial mistaken expectation and source remain in
  diagnostics; it now tests both internal-duplicate refusal and external-text
  isolation.
- Generated-C review proves the native difference is only `0xe0` to `0xf0` in
  one copy length. No allocation, free, owner or pointer lifetime changes.
  Render/compute preparation, both cleanup/reaper paths, batch publication and
  vertex/compute converters match preceding C textually.
- Existing 12,000 vertex-start images, 8,000 compute start/finalize pairs,
  12,000 separately constructed fragment images, layout, async/scheduler,
  lifecycle/mapping, wait/syncobj, wire, fence, VM and sanitized production PTE
  regressions pass.
- Isolated ARM and clean ordinary x86 builds pass from
  `fae5214d898bce2b85451e48b1e527ea78a2d0ed` plus one retained native overlay:
  `kernel/gpu/agx/fw/fragment.v`. Ordinary x86 excludes native AGX and uses
  `LD_X86_64=ld.lld`. Exact inputs, C and ELF remain for both; private generated
  build objects were cleaned after retention to keep disk use bounded.

Allocation allowance audits **still fail identically** on baseline and changed
code: 381 ARM/289 x86 sites, 828/813 sources, equal per-file/kind counts and
identical logs. No allowance changed. Existing temporary heap copies remain;
compiler counts do not measure native heap rates.

Fresh upstream heads: Omarchy `24c508e9e5afb82284bdd736465f76ec6492125e`,
packages `46356364b2e9cf6b917091ac7c688bb4139675cb`. Pins remain Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Full audit remains
`not_equivalent` (exit 1); selected gates pass.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-fragment-fields-20261116/`.
Canonical `bundle/` and full archive restoration use the unchanged complete
typed inventory checker. `completion.txt` binds eight source paths and two
reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `a0c561f686df668f4e12ba3d2b4d26f5d21340120573393df60466939302a986` |
| `bundle.tar.gz` | `ca62373f963169dcff5a1c4cc7136bf715d7a691cc18b08cc8c81f636ba2fc36` |
| `bundle/vinix-aarch64` | `8f4c7247aed73e9e01e84385faf64195e4f5243a19fd0d293f17ff13ee2b7115` |
| `bundle/vinix-x86_64` | `f025aca8759a8ca96e2ffd6e26b3f477f3044fcb3170bfaf5e7fd3bc66638526` |
| `bundle/blob-aarch64.c` | `ea6cc4aa859c6569a79e3afddcbceaf4d6f12f7d462db156c974a0414e2278f5` |

Other firmware/default fields, allocating initialization, ABI/Mesa migration,
reservation fences, cumulative timelines, queue ownership, memory attributes,
topology and power/reset remain unqualified. No native hardware test, GPU
workload, Vinix/QEMU boot, reboot, SSH or deployment occurred.
