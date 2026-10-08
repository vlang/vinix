# Native T6050 instruction-contract recovery

This host V module owns the ApplePTD, RTBuddy segment-flag, IODARTFamily,
AppleT8110DART and T8110 kernel page-table instruction proofs. The maintained
`recover_t6050_power.py` caller keeps its original public API through a narrow
JSON adapter. Its remaining recovery families are still Python and remain
counted as Python until their own ports pass qualification.

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

The original functions and fixtures remain available in Git. Qualification
compares each instruction mutation, truncation, missing symbol and malformed
parameter against the frozen original implementation, and checks the full
real-image manifest on ARM64 and x86_64. Repeated foreign-thread calls measure
both post-collection V retention and outstanding explicit output allocations;
an independent ASan/UBSan C caller verifies borrowed-input and output-release
lifetimes at the native ABI.
