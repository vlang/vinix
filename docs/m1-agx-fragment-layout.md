# Fragment layouts and depth insertion

Vinix's 12.3 third fragment parameter block had eight extra trailing bytes.
Removing them moves the command's later fields and their native firmware pointers
back eight bytes. The 13.5 converter now consumes that corrected carrier and
places depth dimensions after its new `unk_390_0` word, at `0x768`. Previously
it placed depth dimensions at `0x760`, where the inserted word belongs.

The converter also copies the complete common tail through the final flag at
`0x948`, including the timestamp-pointer bytes, client-sequence padding and
following flags. Its extent decreases from `0x974` to the modeled `0x96c`.
Both command sizes now equal the selected packaged
[Asahi fragment declarations](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/fragment.rs).

| Field or extent | 12.3 | 13.5 |
| --- | --- | --- |
| Third parameter block size | `0x2a8` | `0x2b8` |
| Depth dimensions in the command | `0x750` | `0x768` |
| First flag | `0x758` | `0x770` |
| Busy word | `0x870` | `0x888` |
| Scratch word | `0x8b0` | `0x8c8` |
| Metadata | `0x8b4` | `0x8d0` |
| Common tail | `0x8e4` | `0x900` |
| Command time | `0x8fc` | `0x918` |
| Kernel timestamp pointer pair | `0x904` | `0x920` |
| User timestamp pointer bytes | `0x914` | `0x930` |
| Complete command size | `0x930` | `0x96c` |

The existing V source-layout model now checks size equality for both versions,
derives the 12.3 firmware-address constants and timestamp pair from the same
records, and verifies the insertion and complete common-tail spans. Its report
retains every `RunFragment` and `JobParameters3` field. Packed pointer, integer,
tag and event aliases remain guarded by the preceding compute reference gate.
This is not an independently compiled Rust layout oracle or a comparison of
every native initialization value.

The carrier's three legacy opaque user-timestamp fields still represent the
same 16 bytes and remain zero during native preparation. No user-timestamp
feature or ownership change is introduced. Existing job, scene and timestamp
owners continue to retain the backing referenced by firmware.

Validation passed:

- 12,000 complete fragment byte images across both ABIs, through the real
  carrier/converter. Nonzero depth and adjacent words, flags, busy/overflow,
  scratch, every metadata field, command time, both pointer pairs, client
  sequence, common padding and following flags expose shifted or dropped data.
  Existing 12,000 vertex images, 8,000 compute pairs and work-command layout
  tests also pass with ASan/UBSan and stack-use-after-return detection.
- The complete prior fragment module compiles and rejects its old `0x938`
  carrier size. The exact prior converter, compiled against the corrected
  carrier, rejects a misplaced depth byte at `0x763`. Baseline, negative
  sources, selected-function checksum, runners, binaries and failures remain.
- All 39 V test files, selected primary-source gates and strict native ARM C
  storage checks for 113 helpers plus their allocation-mutation selftest pass.
- Generated-C review matches the converter to its exact byte-span edits, with
  no allocation, free or new CPU lifetime. Render preparation, cleanup/reaper,
  batch publication, compute preparation and vertex/compute converters match
  preceding C textually; emitted types carry the corrected extents/positions.
- Existing async/scheduling, lifecycle/mapping, wait/syncobj, wire, fence, VM
  and sanitized production PTE regressions pass.
- Isolated ARM and clean ordinary x86 builds pass from
  `64aa70252e61b9752eda0f7311e57a6cc3aca6f3` plus one retained native overlay:
  `kernel/gpu/agx/fw/fragment.v`. Ordinary x86 excludes native AGX and uses
  `LD_X86_64=ld.lld`. Exact inputs, generated C and ELF are retained for both.

Allocation allowance audits **still fail identically** on baseline and changed
code: 381 ARM/289 x86 sites, 828/813 sources, identical per-file/kind counts and
logs. No allowance changed. Existing native heap copies remain; compiler counts
do not measure heap rates.

Fresh upstream heads: Omarchy `8f2df93aafd448b5c301c07e5f93e8fda2274ec4`,
packages `7e1afe060914a948792c411b05e8bb39ba1b317e`. Pins remain Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Full audit remains
`not_equivalent` (exit 1); selected gates pass.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-fragment-layout-20261116/`.
Canonical `bundle/` and full archive restoration use the unchanged complete
typed inventory checker. `completion.txt` binds seven source paths and two
reports to the feature commit.

The sealed provenance's phrase "every versioned firmware address" refers to
the eight 12.3 tail getters. Parameter-block getters and 13.5 destination
offsets remain unchanged; the retained source and layout report show the scope.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `8dd8d4f5f22f4c00f91b40325ac0cad34242043cc5904b50045ed35265df5976` |
| `bundle.tar.gz` | `b3bffe0251797455acd9c2c8abe044cb6d24f1bafa21c7fad28de2a71be4ae16` |
| `bundle/vinix-aarch64` | `024834a71f20b65a66a92ea30970cef20b3f4675b22a2059ed82c4fac1cf8d53` |
| `bundle/vinix-x86_64` | `a4fc64183285d4da00f9d1c17494a201a8d4372f072091ab53de1ee01b23a585` |
| `bundle/blob-aarch64.c` | `a60587bda643cc5cf305930d233e7b018e8d0eb5c569a502e0b4ecc12cf13896` |

Other firmware fields/defaults, ABI/Mesa migration, reservation fences,
cumulative timelines, retained queue ownership, memory attributes, topology
and power/reset remain open. No native hardware test, GPU workload, Vinix/QEMU
boot, reboot, SSH or deployment occurred.
