# Register the modern native Asahi ioctl interface

Native G13 now accepts eleven modern Asahi operations through the real DRM
node, alongside the existing Mesa 25 interface. Flat packets, combined sync
records and timestamp objects reach the existing native scheduler. This closes
the disconnected-parser gap from [the preceding audit](m1-agx-signoff-20261117.md).
It does not establish complete modern-driver parity or a working upgraded Mesa.

The kernel baseline is `612f3032a27ab253800be6a1f8464d898b8beabd` with only
seven kernel overlays, built in a private worktree. Concurrent event-manager
edits are excluded. The reference remains packaged Asahi
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, selected by packages
`538b4824bafe9959c1b7894961ade1dc7d027ec4`; Omarchy is
`c3c8acf1ef376d19c400464eab9bc382a8667c6f` and the matched Mesa source pin is
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`.

## Registered behavior

- The first decoded driver request reaching a handler selects that file's
  ABI under its lock. Canonical GET_PARAMS requests distinguish the two formats
  by size/direction. Subsequent overlapping command numbers stay in that
  dialect. Generic DRM operations do not select it. Registry construction is
  serialized so simultaneous first requests cannot create competing file owners.
- Modern GET_PARAMS returns the canonical 64-mask response, G13 shader ISA 2,
  legacy HAL generation, nanosecond command timestamp frequency and only the
  supported feature bits. Modern GET_TIME converts the architectural counter
  with Asahi's reduced rational formula; legacy GET_TIME keeps raw ticks.
- Modern VM/GEM/object/queue adapters use the existing owned backend paths.
  Queue creation installs its USC base before publishing the name. Submission
  captures that scalar with the queue owner under the file lock, so namespace
  deletion cannot change the captured execution base.
- Modern SUBMIT parses the 16-byte combined sync array, snapshots the complete
  packet, decodes up to 64 commands with caller-owned parser/command scratch,
  and transfers the captured queue only on accepted pending registration.
  Scratch is freed on every success/error path; accepted jobs own their state.
- Modern VM_BIND snapshots the complete strided batch before any mapping
  changes. Short operations are zero extended and long tails are skipped, as
  the packaged G13 `read_up_to` path does. Operations execute sequentially:
  malformed later operations preserve the successful prefix; a batch-copy
  fault changes no mapping. Read/write/single-page flags translate explicitly.

The actual modern table's eleven numbers, sizes and directions match the
packaged header. Modern GEM_MADVISE remains absent; no placeholder reports
successful purge advice.

## Ownership and allocation checks

Independent lifetime review found no blocker in scratch cleanup, pending
transfer, queue/USC capture, VM-bind ownership or registry/file lock ordering.
It makes no hardware-correctness claim.

Generated C exposed two implicit heap records in the first sync builder.
Taking an explicit address still caused promotion with this compiler. Passing
the builder to a value-snapshot helper removes both allocations. Controlled
host measurements with warmed owners and `MallocNanoZone=0` show:

| 1,000 staging calls, each of three batches | First builder | Final builder |
| --- | --- | --- |
| No syncs | 2,000 retained blocks / 3,584,000 bytes | 0 blocks / 0 bytes |
| One binary input and output | 2,000 retained blocks / 3,584,000 bytes | 0 blocks / 0 bytes |

These are host malloc bytes, not native slab rates. Both intermediate native
builds, the failed address-only correction and their source/C diagnostics remain
retained. The final native C guard rejects hidden allocation in 18 bodies and
checks all temporary owners, copy ordering, USC capture and driver registration.

## Validation

Passed:

- 74 audit/contract/layout/UAPI test files from the isolated checkout, including
  the updated explicit legacy-comparison scope.
- ASan/UBSan production DRM framing/table/handler tests, including per-file
  collisions, extended framing, nanosecond time and queue/GEM round trips.
  The surrounding legacy close/mapping/namespace/ownership suite also passes.
- 1,200 modern VM-bind checks using real mapping handlers: copy/OOM refusal
  before mutation, successful-prefix errors, short/strided records and exact
  RO/WO/single-page translation.
- The modern packet-to-pending fixture: combined syncs, immutable copied input,
  USC capture, reverse completion and 700 copy/OOM/retry/drain checks. A complete
  64-command mixed ioctl resolves 192 timestamp captures, survives detach and
  retires in reverse. The existing full asynchronous suite passes in kernel GC
  mode with fake-stack detection.
- Four compiled negative variants fail designated cleanup, USC, batch-copy and
  ABI-isolation assertions. Six generated-C mutations are rejected.
- All 28 canonical wire records and every field offset match the packaged C
  header oracle. The sanitized flat-packet parser, generic DRM transport and
  logical-queue lifetime fixtures pass.
- Isolated AArch64 with MP enabled and ordinary x86_64 kernel builds. The
  original strict x86 checker confirms whole generated-C equality with the
  preceding baseline after its existing discard-path normalization.
- ARM allocation diagnostics stay at 377 sites across 839 sources, including
  four new source files; x86 stays at 289 across 813. Every file/kind count
  matches the preceding baseline. Existing allowance-check failures remain;
  the allowance list and historical checkers are unchanged.

The source audit's five selected protocol gate groups pass. Its 15 differing
ABI facts now explicitly describe the retained legacy compatibility declarations,
with `comparison_scope=legacy_compatibility_declarations`. Those facts do not
measure modern endpoint incompatibility. Modern declarations are retained too;
the header oracle and registered-node fixtures validate this increment's wire
integration. Full parity remains uncertified.

## Remaining acceptance work

Vinix still builds Mesa 25.0.5; the paired Mesa/image migration is outstanding.
GEM_MADVISE, complete timeline-chain semantics and reservation/scatter backing
remain open. Modern input/output arrays keep the native 64-record bound, and
zero-point timeline outputs return EOPNOTSUPP before publication. VM binding
retains the existing busy-VM policy. Firmware/default/error-path completeness,
native scheduling, whole-kernel leak rates and hardware execution are unqualified.
The subsequent [sync-storage increment](m1-agx-sync-storage.md) removes the
modern 64-record sync-list bound; complete timeline semantics remain open.
Modern validation precedence is also unfinished: unsupported render-SCS layouts
are rejected before queue construction, while the reference checks them later.
The subsequent [render-SCS correction](m1-agx-queue-scs.md) closes that specific
queue-validation-order gap without qualifying the other remaining behavior.

No GPU access, firmware execution, Vinix/QEMU boot, SSH, deployment or reboot
occurred. Follow the remaining offline port with hardware acceptance; passing
host fixtures does not certify native execution.

The complete external evidence is at
`/Users/alex/.local/state/vinix/omarchy-m1-modern-dispatch-20261117/bundle/`.
It retains source snapshots, build-input inventories, C/ELFs, test programs and
executables, reference sources, negative cases, diagnostics and lifetime review.
The original preceding sign-off archive is checked before sealing. Full archive
restoration and both named roots are checked without weakening any historical
auditor. A post-commit receipt binds the feature paths and reports to the bundle.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz.inventory.txt` | `6e68f30a10697e05bc41c6dc245aea783b0ead65509ce883ac442cd86f5a8e06` |
| `bundle.tar.gz` | `b04eecebd2a4aba070f6148dc7b85799240eac645cd24dc8a0deb0b79f19a0cf` |
| AArch64 ELF | `d3d4390f994f46c529e9cec887bb8fd21b416aaafd4a96296670efa9918aa21d` |
| x86_64 ELF | `d9b995085bb31ef59851dc7b4c583f10fc754cca411aad184b0009bcdf65a505` |
| AArch64 generated C | `d8656ffaec6454a7e77c0318b3926294131a6e10c73157d85abff1ddfa794f9f` |
