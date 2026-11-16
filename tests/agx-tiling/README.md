# Base M1 render tiling

Build `run.v` with V and `-path 'tools/agx-re|@vlib|@vmodules'`, then pass
`--asahi-linux PATH` to the pinned Linux-Aurora checkout. Run with
`ASAN_OPTIONS=detect_stack_use_after_return=1`.

The host fixture compiles the complete actual native tiling helper, its two
arithmetic helpers and result declaration. A restricted expression translator
reads the selected Rust formulas and emits a separate widened scalar model.
Unknown names, calls, casts and syntax fail. Independent mathematical ceil and
alignment operations evaluate the model. It specializes to one GPU cluster;
the selected source's clustered overrides are explicitly checked and excluded.
No Rust compiler or firmware oracle is claimed.

The fixture compares every native result field and the complete packed tiling
record, including declared reserved bytes, over dimension/tile boundaries,
sample/uTile combinations, layer limits, sizes above 4 GiB and control words.
Invalid dimensions, layers, sample counts and reversed uTile shapes are refused.
It does not allocate a GPU buffer, run privileged code, boot or exercise a GPU.

`--gpu-source FILE` supplies a complete alternative native module for executable
counterexamples. `AGX_TILING_MODEL`, `AGX_TILING_C` and `AGX_TILING_BINARY` retain
the generated model, C and executable outside Git. Full initialization,
multicluster hardware and userspace ABI migration remain separate checks.
