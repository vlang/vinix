# Modern Asahi packet command inputs

Vinix now translates its copied modern flat-packet records into the existing
generation-neutral G13 render and compute inputs. This is a migration component:
the public driver still registers the Mesa 25 ioctl ABI. Production dead-code
elimination omits the new, unregistered decoder. It does not enable Mesa 26 or
establish full driver equivalence.

The reference remains Omarchy's packaged
[Linux-Aurora driver](https://github.com/omacom/linux-aurora/tree/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi).
Fresh upstream heads are Omarchy `e19607fc5ab3cbe6d2d4ebb13bd9e990db3854d1`
and packages `b4c914c215561b38031f83133e62a203aef12a3d`. The selected Linux,
Mesa and omarchy-mac package definitions match the previous checkpoint byte
for byte. Pins remain Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`,
Mesa `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

The adapter preserves engine-specific attachment state, applies Asahi's fixed
attachment exponent of one, supplies queue USC bases, derives sampler limits,
and translates barrier sentinels and compute opcodes between the ABIs. Render
translation duplicates the modern depth/stencil resources into the native
load/store/partial inputs, remaps render flags and supplies the source's
preemption, clear-pipeline, ID and ISP-control defaults. The native G13 tiling
calculation continues to determine TIB sizing. Legacy attachment validation
and command staging retain their existing behavior.

All three engines' timestamp handle/offset pairs remain separate copied
metadata. A null handle ignores its offset, as in Asahi's common lookup helper.
The future modern submit handler must resolve and retain timestamp objects,
validate their ranges and apply their firmware mappings before dispatch.
This decoder performs none of those operations and publishes no jobs.

The caller owns immutable packet bytes, output storage and reusable parser
workspace. Invalid packets return zero usable commands, including after a
partially staged prefix; callers must discard that prefix. Output capacity is
bounded to 64. The parser workspace avoids V's conservative promotion of local
mutable values to heap storage. No new free or asynchronous lifetime is added.

Validation passed:

- The V oracle selects initializers from the pinned Rust compute/render
  constructors and translates only supported scalar expressions. It accounts
  for every native canonical field, rejecting missing/new fields and unknown
  expressions. Sanitized fixtures compare 89 scalar fields across 16,384 mixed
  hardware commands, all supported render flag combinations, full-width
  resource values, sampler wrap, attachment replacement/persistence, independent
  barriers and all timestamp slots. Additional cases cover zero-extended short
  records, invalid flags/opcodes/tails, truncated packets, output capacity,
  empty/software-only packets, timestamp null handles and independent copies.
- Twelve complete adapter mutations compile and fail their designated field,
  attachment, barrier, timestamp or capacity assertion. The V runner, test
  fixture and oracle remain in Git; variants, executables and failures remain
  outside Git. Both address and undefined-behavior sanitizers run, with
  stack-use-after-return detection enabled.
- All 49 focused V test files, selected reference gates and the original 141
  native C storage guards pass. Twelve additional guards inspect the exact
  host C for the unregistered decoder and parser; their allocation-mutation
  selftest passes. The existing native guard selftest also passes unchanged.
- Fresh ARM/x86 builds pass in isolated worktrees. Generated-C review confirms
  unchanged legacy staging/validation, native preparation/retirement,
  publication, ownership reapers, final close and worker service. x86 C matches
  the previous checkpoint after normalizing compiler discard-variable path
  hashes. Wait, wire, fence, close, async, CPU-cache, VM, sanitized TLB, layout,
  render and packet-reader regressions pass. Fresh source-derived fixtures pass
  30,375 tiling results, 12,000 work images, 14,400 timestamp images and 48,000
  start/finalize images.

Baseline and final allocation audits retain the existing allowance failure at
381 ARM / 289 x86 sites. Per-file/per-kind counts are unchanged. ARM source
count increases from 830 to 831; x86 remains 813. The allocation allowance and
historical inventory checker are unchanged. Native heap rates remain unmeasured.

The fresh full audit still reports **not_equivalent** (exit 1). Remaining work
includes modern ioctl/Mesa integration, per-command timestamp objects,
reservation fences, cumulative timelines, VM capacity/close scheduling,
remaining wire/default coverage, topology and power/reset behavior.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-packet-input-20261116/`.
Source baseline is `c95ea12ee22d7a37bf8644c9131506463f8a0eb1` plus eight retained
source paths, including one native overlay. Nine unchanged runner binaries are
reused only after source/binary checksum checks; dependent fixtures are rebuilt.
The complete previous bundle, current canonical bundle and full archive
restoration pass the unchanged typed inventory checker. `completion.txt` binds
the eight sources and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `d01a950346655cbbedc51805970a62d3de8554099b47fc0ed542e30204564477` |
| `bundle.tar.gz` | `f3bbddefc7ddb493f06d7c57c95d379e7e70950f0f818378c299242be0853430` |
| `bundle/vinix-aarch64` | `1c5ff0774d37efaf9e993cd36957e02191305b457384a9ec7e943376c0fd807d` |
| `bundle/vinix-x86_64` | `8ea67f1164f759a7d1b7035da5034d39c202c55f5037a0fb6469616102fe0def` |
| `bundle/blob-aarch64.c` | `5e0da00bad1d53556d7dcc5f9fd239942934a2ebbac99d2ec2985918b5d4baa8` |

No hardware workload, Vinix/QEMU boot, reboot, SSH or deployment occurred.
