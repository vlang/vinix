# Native timestamp wire regression

Build `run.v` with V and `-path 'tools/agx-re|@vlib|@vmodules'`, then run it
with `--asahi-linux PATH` pointing at the packaged Linux-Aurora checkout.

The runner extracts all six actual timestamp initializers and the actual native
writer from `kernel/gpu/agx/gpu/g13.v`. Expected complete byte images come from
the selected Asahi `Timestamp`, `RunVertex`, `RunFragment`, `RunCompute` and
`TimestampPointers` source declarations. The opcode tuple is modeled as its sole
guarded `OpHeader` field; this is not a Rust-compiled layout oracle.

ASan/UBSan checks 14,400 images: both phases of all three engines, two firmware
ABIs, four destination alignments, three command addresses and 100 cycles.
Enable `ASAN_OPTIONS=detect_stack_use_after_return=1`. Optional
`AGX_TIMESTAMP_WIRE_BINARY`, `_C`, `_MODEL` and `_REPORT` outputs retain evidence
outside Git. `--native-source PATH` tests exact historical native initializers
against the same current expected source model.

The fixture checks encoding, empty optional pairs and offset refusal. It does
not execute allocating native preparation, firmware, the modern timestamp UAPI,
GPU workloads or native heap measurements. Command lifetime is reviewed in the
native source and generated kernel C separately.
