# G13 vertex-start encoding

Compile `run.v` to an external path and execute it with `v` available. The
runner extracts the actual native single-cluster render initializer and its
writer, using the production firmware records and version converter. Host
records supply addresses and scalar state; no firmware or GPU work runs.

ASan/UBSan checks 12,000 complete byte records against explicit packed offsets,
including all padding, 12.3's zero word, 13.5's non-clustered marker at `0x188`,
counter insertion and notifier addresses. Cases vary zero/one/sixteen
attachments, full-width counters, event generations, VM/slot IDs and four
destination alignments. Guard bytes cover the entire buffer outside each write.
`AGX_RENDER_WIRE_TEST_BINARY` retains the instrumented test executable.
`AGX_RENDER_WIRE_TEST_C` retains its generated C. The native storage checker
also guards the writer and version converter against temporary allocations;
native C must keep the initializer and conversion result on the stack.

The existing G13 layout tests independently check the work-command offsets
used by the initializer's pointers. These host tests do not exercise allocation,
locking, job preparation, firmware interpretation or multi-cluster rendering.
