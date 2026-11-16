# Start/finalize instruction field comparison

Build `run.v` with V and `-path 'tools/agx-re|@vlib|@vmodules'`, then run with
`--asahi-linux PATH` pointing at the packaged Linux-Aurora source.

The model derives all six G13 start/finalize record layouts for 12.3 and 13.5.
It checks every old native typed member offset and both record sizes, then
matches common semantic fields recursively, independently of native copy
ranges. Added counter/notifier/flag words use distinct full-width arguments;
reserved inserted fields and aggregate padding are zero. Source builder
defaults and representations are guarded. This is a selected source model,
not an independently compiled Rust oracle.

ASan/UBSan compares 48,000 complete converted byte images with nonzero source
patterns, four independent source/destination alignments, five arguments and
100 cycles. Run with `ASAN_OPTIONS=detect_stack_use_after_return=1`.
`--kind KIND --fw-overlay FILE` lets the same expected model reject a complete
firmware module with a deliberately shortened common-field copy. Optional
`AGX_MICROSEQ_FIELDS_BINARY`, `_C`, `_MODEL` and `_REPORT` outputs retain evidence
outside Git.

This test exercises converters and typed layouts. Native initializer bindings,
allocating preparation, firmware execution and heap rates require separate
checks. It does not certify complete driver equivalence.
