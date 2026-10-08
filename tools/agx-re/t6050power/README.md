# Native T6050 instruction-contract recovery

This host V module owns the ApplePTD, RTBuddy segment-flag, IODARTFamily,
AppleT8110DART and T8110 kernel page-table instruction proofs, initial PMP
publication/readiness ordering, RTBuddy patchbay writes and ASCWrap-v6 mailbox,
IORVBAR lock and CPU-run sequences. The maintained
`recover_t6050_power.py` caller keeps its original public API through a narrow
JSON adapter. Its remaining recovery families are still Python and remain
counted as Python until their own ports pass qualification.

The PMP dashboard module proves selector/die conversion, request publication,
status probing, the pre-ready acknowledgement bypass and the ready-gated polling
paths. The T6050 PMGR module recovers all 60 RegMap calls in order and the resume
and hibernation republication sites. These proofs keep byte-search offsets and
arbitrary integer address arithmetic separate until the decoder applies the
original 64-bit address mask.

The ApplePMP firmware module proves endpoint attachment and mailbox/ping
completion, all nine unconditional patchbay writes and their exact call sites,
RTBuddy fixup/load ordering, and the CPU-start/Hello/roll-call status machine.
Firmware-loaded and transport-ready metadata retain their original limited
meaning; the dashboard readiness proof remains a separate requirement.

Image proofs read PMGR interrupt names, RTKit identity-block candidates,
firmware-source properties and AppleA7IOP resource properties through native
Mach-O readers. `EvidenceReader` separates those primitive reads from the
instruction proofs so the original reader fixtures remain independent.
`MachOEvidence.image` is borrowed only during the synchronous call; returned
strings, tables and proof metadata own their storage.

The topology module owns T6050 PMGR/PMP DeviceTree validation, both die
wrappers and DART/mapper bindings, interrupt overlays, gate routes and packed
SoC-device dashboard layout. Preorder predicates retain the original validation
order. The public Python node objects are marshalled once; native property
buffers and returned metadata own their storage. Published bypass keys are
visited in numeric order, preserving the original SID-range result even for
wide counts. `topology_test.v` keeps the complete independently authored
synthetic topology and both original SGX/AGX rejection fixtures.

The patchbay module owns the protected Mach-O segment table, RTKit identity
selection and aligned patch-region record walk. It preserves version4/5 field
locations, mapped span and file slice behavior, writable reporting, mandatory
tags, ASCII replacement and exact rejection/struct diagnostics. Native virtual
span arithmetic retains integer width until validated physical slicing. The
independent synthetic preload-image fixtures retain complete results for all
alignments and both segment protections; no real firmware image is committed.

The controller layer owns identity validation, ordered symbol/function collection,
required property strings, vtable slots and component-proof composition for the
nine PMGR/PMP/firmware/A7IOP/DART/kernel/ASCWrap recovery entry points.
`ControllerReader` is synchronous. Paired RTBuddy bytes are decoded only on
their first reader call, preserving each controller's validation order. Native
fixtures retain selected read-only symbol/code/property/table evidence, source
image identities and complete independent Python results and call traces.
They contain no complete firmware image.

`Function.code` is borrowed only for a synchronous proof. Returned metadata
contains ordinary owned values; direction lookup and mask/shift arrays are
copied. The shared extraction ABI registers foreign calling threads before V
allocation, copies results into explicit libc-owned output and releases that
output before the Python adapter returns. Host tools use Boehm GC; this module
is not linked into the freestanding kernel.

`core_test.v` replays independently authored instruction fixtures from the
original Python tests, with their complete expected results and rejection
messages in `testdata/contracts.json`. It also tests wide numeric comparison,
array ownership and malformed address/target errors. The first-party algorithms
are native V; the fixture JSON contains test inputs and expected values only.
`transport_test.v` similarly retains the independent readiness, patchbay-write
and ASCWrap fixtures in `testdata/transport.json`, including every original
full-output and rejection check.
`dashboard_test.v` retains the independent dashboard and PMGR fixtures in
`testdata/dashboard.json`, together with byte-search, wide MOVZ operand and
vtable diagnostic controls.

`firmware_test.v` retains the independent attachment, mandatory patch/fixup,
and RTKit boot fixtures in `testdata/firmware.json`, including full results and
original rejection checks. Additional controls preserve call cardinality,
negative word offsets and exact readiness dictionary numeric equality.

`image_proofs_test.v` keeps the original property-reader inputs and all their
full-result and rejection cases in `testdata/image-proofs.json`. Its patchbay
candidate fixture comes from the frozen real RTBuddy image and retains only
the functions and symbols that the original proof reads.

The original functions and fixtures remain available in Git. Qualification
compares each instruction mutation, truncation, missing symbol and malformed
parameter against the frozen original implementation, and checks the full
real-image manifest on ARM64 and x86_64. Repeated foreign-thread calls measure
both post-collection V retention and outstanding explicit output allocations;
an independent ASan/UBSan C caller verifies borrowed-input and output-release
lifetimes at the native ABI.

`public_constants.v` supplies the original public symbol, UUID, layout and
patchbay-input constants, sharing existing native contract values. Python
provides lazy import, directory and star-import compatibility, including Path
defaults and the original nested tuple type. Its remaining frontend preserves
argparse/file I/O, dataclass object identity and lazy traversal callbacks.
`frontend_test.v` retains the final three independent Python fixtures for IMG4
DeviceTree payload selection, ADT exact consumption and PMGR interrupt records.
