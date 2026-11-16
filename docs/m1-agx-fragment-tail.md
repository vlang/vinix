# Fragment parameter and scratch offsets

The 13.5 fragment converter now preserves the scratch word at `0x8c8` and
leaves the following reserved word at `0x8cc` zero. It previously copied scratch
into that reserved slot. Metadata remains at `0x8d0`. The third parameter-block
getter now returns `0x4b8`, correcting its previous `0x4a8`.

The packaged [Asahi fragment declaration](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/fragment.rs)
places `unk_v13_3` after `unk_pointee`, before `JobMeta`. The selected V layout
model parses eight fragment and three common job records with their version
gates. The preceding compute gate checks the packed pointer, integer, tag and
event representations used to normalize known aliases. This derives the
13.5 offsets above and the next tail at `0x900`. Its modeled size `0x96c` fits
Vinix's `0x974` allocation; this does not establish complete record equality
or replace an independently compiled Rust layout oracle.

The current native builder initializes scratch and reserved words to zero,
so this is a conversion-semantic correction, not an observed hardware crash
fix. Native render preparation currently does not call the third-block getter.
The conversion only splits one byte copy; it creates no allocation, owner or
pointer lifetime. The 12.3 carrier is unchanged.

Validation passed:

- 6,000 ASan/UBSan complete expected fragment images through the real converter,
  with five scratch patterns, every metadata field populated, following tail
  values and full-width counters. All padding is compared. Existing 12,000
  vertex images, 8,000 compute pairs and independent layout tests also pass;
  stack-use-after-return detection is enabled and sanitizer linkage retained.
- Both exact prior-function negatives compile. The old getter rejects `0x4b8`;
  the old converter loses a nonzero scratch value at byte `0x8c8`. Baseline,
  negative modules, function checksums, runners, binaries and failures remain.
- All 39 V test files, selected primary-source gates and strict native ARM C
  storage checks for 113 helpers plus their negative selftest pass.
- Root generated-C review confirms that conversion differs only by splitting
  the scratch/metadata copy. Render preparation, cleanup/reaper, batch publication,
  compute preparation and vertex/compute conversion bodies match preceding C.
  No new lifetime requires independent review.
- Existing async/scheduler, close/BIND/UNBIND/GEM/timestamp/GET_PARAMS, syncobj
  wait, wire, fence, VM and sanitized production PTE regressions pass.
- Isolated ARM and clean ordinary x86 builds pass from
  `474024e1c650835fb93311fe3be17ef937b85591` plus one retained native overlay,
  `kernel/gpu/agx/fw/fragment.v`. Ordinary x86 excludes native AGX and uses
  `LD_X86_64=ld.lld`; exact inputs, C and ELF are retained for both builds.

Allocation allowance audits **still fail identically** on baseline and changed
code: 381 ARM/289 x86 sites, 828/813 sources, equal per-file/kind counts and
identical logs. No allowance changed. Compiler counts do not measure heap rates.

The source model exposes an unresolved 12.3 difference: reference size `0x930`,
scratch `0x8b0`, metadata `0x8b4` and tail `0x8e4`, versus Vinix carrier size
`0x938`, scratch `0x8b8`, metadata `0x8bc` and tail `0x8ec`. This increment does
not certify that carrier. Other timestamp/tail fields also remain unqualified.

Fresh heads: Omarchy `8f2df93aafd448b5c301c07e5f93e8fda2274ec4`, packages
`7e1afe060914a948792c411b05e8bb39ba1b317e`. Pins remain Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Full audit: `not_equivalent`
(exit 1); selected gates pass.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-fragment-tail-20261116/`.
Canonical `bundle/` and full archive restoration are checked with the unchanged
complete typed inventory checker. `completion.txt` binds nine source paths and
two reports to the feature commit. Initial helper diagnostics remain preserved.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `6570fc5ab6eea3c2c08f581e517ef36a252f5d1b3f553e10cbb2c18a04983640` |
| `bundle.tar.gz` | `73d2b3e8c34655e2a46cd68effbab2708439921f01ae49dba0f31cb4c382137d` |
| `bundle/vinix-aarch64` | `62d8a24b991aa843fb7c5aa4f8a60f197a189b61ed72d6c7f29815cc4ca729dd` |
| `bundle/vinix-x86_64` | `e1e5b0d0f27569dc1073d46587cc47ff0b03ea346fb50fb0a6a1704e727dc06c` |
| `bundle/blob-aarch64.c` | `fe9c471458ee544e3d54c4bf1d7713a76cafba1a1d724f702a1adc3f180c8336` |

Hardware interpretation, allocating job preparation, ABI/Mesa migration,
reservation fences, retained queue ownership, cumulative timelines, remaining
wire fields, topology and power management remain open. No native hardware
test, GPU workload, Vinix/QEMU boot, reboot, SSH or deployment occurred.
