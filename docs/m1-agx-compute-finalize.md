# Compute finalizer command flag

Firmware 13.5 compute finalization now receives the same command-flag address
as compute start. The packaged
[Asahi compute builder](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/compute.rs)
sets both references to `RunCompute.unk_flag`; Vinix previously left the
finalizer's pointer zero. Both native calls now use one named command offset.

The selected reference layout model derives the command flag at `0x305` and
the unaligned finalizer pointer at `0x6d`. It parses the versioned Rust compute,
job and finalizer records, retaining their gates and checking packed pointer,
integer, opcode and event representations before normalizing known aliases
through the existing V layout engine. It checks the reference finalizer sizes
and that the flag fits command backing. This is a source-layout model, not an
independently compiled Rust layout oracle or a full wire comparison.

The 13.5 converter writes the pointer bytewise inside its existing `0x7c`
record. The 12.3 writer ignores the additional scalar and preserves its `0x64`
record. The pointer refers to the existing job-owned command, already referenced
by the finalizer's job-parameters pointer and by compute start. No new backing
allocation, CPU ownership or freeing path is introduced.

Validation passed:

- 8,000 ASan/UBSan byte-exact start/finalize pairs execute the actual native
  writers and production converters. They cover both ABIs, full-width flag
  values, every copied field and padding byte, the removed legacy word,
  backward branches, attachment markers and four guarded destination alignments.
  Stack-use-after-return detection is on. The 12,000 vertex cases and independent
  work-command layout/translation tests also pass.
- The exact prior converter body builds with a signature-only adapter adding
  the new unused scalar. It fails at byte `0x6d`: zero where the flag is required.
  Raw baseline, adapter, body checksum, runner, binary and rejection are retained.
- 38 V test files, selected primary-source gates, and the strict native ARM C
  checker for 112 helpers plus its negative selftest pass. The checker now guards
  the finalizer converter against temporary allocations.
- Root native-C review confirms unchanged CPU allocation/free and BO reference
  counts. The writer is identical after its scalar parameter/forwarding change.
  Compute command packing/start conversion, render preparation, batch publication
  and compute cleanup/reaper bodies match preceding C. Independent lifetime review
  approved the exact three native inputs, C and ELF: command/microsequence backing
  remains retained through completion and invalidation, or stopped shutdown.
- Existing async/scheduling, lifecycle/BIND/UNBIND/timestamp/GEM/GET_PARAMS,
  wait/syncobj, wire, fence, VM and production PTE regressions pass. PTE tests use
  `--sanitize`; new wire/layout sanitizer linkage receipts are retained.
- Isolated ARM and clean ordinary x86 builds pass from
  `2f2f7efe22d0e639ed2efe28c7c80dcacc83b9d0` with three retained native overlays:
  `gpu/g13.v`, `fw/microseq.v` and `fw/compute.v`. Ordinary x86 excludes native
  AGX and uses `LD_X86_64=ld.lld`; both exact input snapshots are retained.

Unchanged allocation allowance audits **still fail** on baseline and feature:
381 ARM/289 x86 sites, 828/813 sources, identical per-file/kind counts and logs.
No allowance was changed. The existing finalizer writer's implicit CPU temporary
heap copy remains; native heap rates are not measured by these compiler counts.

Fresh heads: Omarchy `b0b9f443eaca8f86124e8ff7437baa2e23e3ef13`, packages
`7e1afe060914a948792c411b05e8bb39ba1b317e`. Pins remain Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Full audit: `not_equivalent`
(exit 1); selected gates pass.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-compute-finalize-20261116/`.
Canonical `bundle/` and full archive restoration pass the unchanged complete
typed inventory checker. Initial preparation, source-selector and C-matcher
diagnostics are preserved. `completion.txt` binds eleven source paths and two
reports to the feature commit.

Two failed seals remain separately inventoried: the first selected an earlier
rejected gate log; the second found an absent diagnostic directory. Their
original sources and failures remain in `failed-seal-bundle/` and
`failed-seal-copy-bundle/`; the successful seal requires the passing gate log
and checks its named directories before collecting evidence.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `21b56136dd3d881fa5103cab4d583f5ead0f152ab505f72430f3b7b09b09f5e5` |
| `bundle.tar.gz` | `fd8346a8ba0056453835a89ab757436daf728d68197362c57e7cc5f1227e6e58` |
| `failed-seal-inventory.json` | `6cfaa1608c2b7bdbd9079a6694dc8645f36f6ee5a0f01538acda6efcf8c28889` |
| `failed-seal-copy-inventory.json` | `4c08295159d19eb0cc33770a95e81c4c3022e1e5695645c53b899ab1ec39a7d8` |
| `bundle/vinix-aarch64` | `bb2fd0b44d00e3c006749bfb27f2109154af101989651da8e1f8a9bdb9bd7386` |
| `bundle/vinix-x86_64` | `1379c99fd6abdd34cb288262dc997ee2cf8689bbe73532123418de6303569b9e` |
| `bundle/blob-aarch64.c` | `cc8918ec1f26650d388111528cbef26ad140fdefa946849f90695ebfd8766acd` |

Host records inject addresses and fields; complete allocating job preparation,
firmware flag interpretation and GPU execution remain unqualified. ABI/Mesa,
reservation fences, retained queues, cumulative timelines, other wire fields
and the remaining parity gaps stay open. No native hardware test, Vinix/QEMU
boot, reboot, SSH or deployment occurred.
