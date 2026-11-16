# Timestamp instruction pair binding

All six native timestamp initializers now bind `user_ts_pointers` at instruction
offset `0x24` to the optional timestamp pair inside their command allocation.
Previously this instruction member was zero. The packaged Asahi builders bind
the pair address whenever they emit a timestamp, including when the pair's
individual entries are empty. Vinix still emits these operations only for its
legacy `input.has_result` path; modern user timestamp support is not added.

The selected source model derives instruction layouts and command offsets from
the packaged [microsequence](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/microseq.rs),
vertex, fragment, compute and job declarations. The
[render builder](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/render.rs)
and [compute builder](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/compute.rs)
provide the field binding. Record, packed pointer/integer/event and opcode
representations are guarded. The opcode tuple is modeled as its sole `OpHeader`
field; this remains a selected V source-layout model, not a Rust-compiled oracle.

| Engine | 12.3 pair offset | 13.5 pair offset | 13.5 scratch offset |
| --- | --- | --- | --- |
| Vertex | `0x5c4` | `0x5cc` | `0x5e5` |
| Fragment | `0x914` | `0x930` | `0x949` |
| Compute | `0x2c0` | `0x2c8` | `0x2e1` |

The new checked scalar getter rejects other firmware ABIs and unknown or
combined pipe values. Each 16-byte pair fits within its already-retained
command, alongside the existing command-time/kernel-pair references. Both
entries still initialize to zero. The 13.5 scratch binding and instruction
sizes (`0x34`/`0x3c`) remain unchanged.

Validation passed:

- 14,400 ASan/UBSan complete images from all six actual native initializers
  and the actual timestamp writer: two ABIs, four guarded destination
  alignments, three command addresses and 100 cycles. Expected bytes are
  source-derived. Empty pairs in old/default and converted commands, refused
  ABI/pipe values, scratch, kernel pointers, opcode and UUID are checked.
  Stack-use-after-return detection and linkage receipts are retained.
- The exact preceding native source compiles against the same fixture and
  fails at byte `0x24`, zero versus the expected pair pointer. No historical
  signature adapter or expected-model change is needed.
- All 41 V test files, primary-source gates and 117 native ARM C storage
  checks plus their allocation-mutation selftest pass. Existing wait/syncobj,
  fence, wire, async/scheduler, close/mapping, VM, sanitized production PTE,
  layout, 12,000 work-command and render microsequence regressions pass.
- Root source/C review removes three scalar-getter lines and six bindings to
  reproduce the exact preceding native preparation source. Both cleanup/reaper
  paths, batch publication, timestamp writer/converter and all three work
  converters match preceding ARM C textually. No new allocation, mapping,
  user BO, free, owner or reference lifetime is introduced.
- Isolated ARM and ordinary x86 builds pass from
  `14c693c19fb42b2c93054fc2197159fa3fe8690e` plus the two retained native
  overlays, `fw/microseq.v` and `gpu/g13.v`. Ordinary x86 excludes native AGX
  and uses `LD_X86_64=ld.lld`. Both input snapshots, C and ELF are retained;
  private generated objects were cleaned after retention. Sparse-checkout
  generator omissions and their failed build logs remain in diagnostics.

Allocation allowance audits still fail on baseline and changed code: 381 ARM /
289 x86 sites, 828/813 source files, equal per-file/kind counts. New source lines
change log locations, not counts. No allowance changed. Existing temporary heap
copies remain; compiler counts do not measure native heap rates. Initial test
compilation and baseline-checkout setup failures are retained in diagnostics.

Fresh upstream heads: Omarchy `fc3fd084a4d66ae77c5333838b7f439753b5e67a`,
packages `e92166c54ce35de8839246663278526ec930eec9`. Pins remain Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Full audit remains
`not_equivalent` (exit 1); selected gates pass.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-timestamp-pair-20261116/`.
Canonical `bundle/` and full archive restoration use the unchanged complete
typed inventory checker. `completion.txt` binds ten source paths and two
reports to the feature commit. Completed compiler scratch directories were
removed to bound disk usage; original canonical bundles and archives remain.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `45a21503cc6254cf3c181523fbdb68b923080b399eb2a513eb4264da07500b60` |
| `bundle.tar.gz` | `6070b2805c490fafdfcc8703cd80acb3a769f177c4e7c0e7faa61ae43f90cd4d` |
| `bundle/vinix-aarch64` | `cf256e1315906fa0210feb0c8caec293c835ef8f02b079e15a04b7cfacca54e7` |
| `bundle/vinix-x86_64` | `e22261f0dc002fa227f8f20bf04086c01b28c60255dc813f7fa7cab3a7523a4c` |
| `bundle/blob-aarch64.c` | `97c2beeb5d1cbb5071b9a2a4748f86989825f280abc780e6dd32d855d66ba79d` |

Modern timestamp/UAPI/Mesa migration, other initialization defaults,
reservation fences, cumulative timelines, queue ownership, memory attributes,
topology and power/reset remain unqualified. No native hardware test, GPU
workload, Vinix/QEMU boot, reboot, SSH or deployment occurred.
