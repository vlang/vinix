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

The original functions and fixtures remain available in Git. Qualification
compares each instruction mutation, truncation, missing symbol and malformed
parameter against the frozen original implementation, and checks the full
real-image manifest on ARM64 and x86_64. Repeated foreign-thread calls measure
both post-collection V retention and outstanding explicit output allocations;
an independent ASan/UBSan C caller verifies borrowed-input and output-release
lifetimes at the native ABI.
