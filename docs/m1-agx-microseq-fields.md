# Complete start/finalize field comparison

The offline comparison now derives all six G13 start/finalize layouts directly
from the packaged Asahi
[microsequence declarations](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/microseq.rs).
Every old native typed member offset and both record sizes are checked before
comparing converted byte images. Common fields are matched by semantic name,
including nested attachment list/count fields, independently of native copy
ranges. No additional native converter change was needed.

| Instruction | 12.3 size | 13.5 size |
| --- | --- | --- |
| StartVertex | `0x17c` | `0x18c` |
| FinalizeVertex | `0x74` | `0x84` |
| StartFragment | `0x194` | `0x1ac` |
| FinalizeFragment | `0x9c` | `0xb4` |
| StartCompute | `0x154` | `0x16c` |
| FinalizeCompute | `0x64` | `0x7c` |

The model derives added counter, notifier and flag locations, the removed
compute word, fragment insertions and reserved tails. It checks inserted zero
defaults within each selected render/compute builder. Attachment member offsets
and sizes also come from source. Unsupported versioned attachment fields,
capacity/type/field changes, opcode wrapper changes and unknown active types
are refused. Packed pointer/integer/event, array and record representation
guards run before the new source gate. Opcode wrappers are modeled as their
sole `OpHeader` field; this is not an independently compiled Rust oracle.

Validation passed:

- 48,000 ASan/UBSan complete converted images: six operations, 100 nonzero
  source patterns, four independent source and destination alignments and
  five distinct full-width counter/notifier/flag argument sets. Source and
  destination guards remain unchanged. Stack-use-after-return detection and
  sanitizer linkage receipts are retained.
- Six complete native firmware-module mutations each shorten exactly one
  common-field copy by one byte. All compile and fail at the intended missing
  byte: `0x177`, `0x73`, `0x19b`, `0xa3`, `0x153`, `0x5f`, in table order.
  Their generated expected models/reports match the passing case exactly.
  Sources, binaries and failures remain outside Git.
- All 42 V test files and selected primary-source gates pass. Fresh runs also
  pass 14,400 timestamp and 12,000 work-command images. The 117 native storage
  checks and their allocation-mutation selftest pass on the pinned ARM C.

This commit changes only host tooling, tests and reports. Native AGX/shared DRM
sources match the preceding sealed inputs byte for byte. The existing ARM and
ordinary x86 C/ELF, both original overlay snapshots and build receipts are
retained with explicit reuse provenance from
`dca42e6c328615dc94faed9dd91f3fbdec0c6add`; no new native build is claimed.
Native ownership and cleanup are unchanged. Allocating preparation, initializer
bindings, firmware behavior and heap rates remain separate checks.

The preceding allocation allowance audits still fail at 381 ARM / 289 x86
sites; their original logs and comparison remain. No allowance changed and no
new native allocation audit was needed for these host-only changes.

Fresh upstream heads remain Omarchy `fc3fd084a4d66ae77c5333838b7f439753b5e67a`
and packages `e92166c54ce35de8839246663278526ec930eec9`. Pins remain Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The fresh full audit still reports
`not_equivalent` (exit 1); selected gates pass.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-microseq-fields-20261116/`.
Canonical `bundle/` and a complete archive restoration pass the unchanged typed
inventory checker. The original preceding bundle is also checked in full.
`completion.txt` binds six source paths and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `f0c1d15336b35781fdfb47a4c01020066622e9b5820ce7daf19508b93312b644` |
| `bundle.tar.gz` | `0c4aac37a8ae075a01b24c540c4785f968737b9bea1a6194c1eca5fa963af160` |
| `bundle/vinix-aarch64` (reused) | `cf256e1315906fa0210feb0c8caec293c835ef8f02b079e15a04b7cfacca54e7` |
| `bundle/vinix-x86_64` (reused) | `e22261f0dc002fa227f8f20bf04086c01b28c60255dc813f7fa7cab3a7523a4c` |
| `bundle/blob-aarch64.c` (reused) | `97c2beeb5d1cbb5071b9a2a4748f86989825f280abc780e6dd32d855d66ba79d` |

Full ABI/Mesa migration, other initialization defaults, reservation fences,
cumulative timelines, queue ownership, memory attributes, topology and
power/reset remain unqualified. No hardware test, GPU workload, Vinix/QEMU
boot, reboot, SSH or deployment occurred.
