# AIR bitstream reader

`airbitcode.parse(data)` decodes the raw LLVM bitstream inside an AIR module.
Use the `bitcode` range returned by `metallib.parse` to exclude an LLVM wrapper.
The input must begin with `BC C0 DE` and remain alive and immutable while using
borrowed blob ranges. The stream owns three flat arrays: blocks, records and
scalar operands. Call `stream.free()` once, then free the input.

Blocks include a synthetic root at index 0 with parent -1; other parents and
record block fields are array indexes. Start/end bits describe the payload,
excluding the subblock header. Each record references an operand range in
`stream.values`; blob operands reference bytes in the original input and are
not expanded into scalar operands. Unknown block/record IDs are retained.

The reader supports fixed fields, VBR integers up to 64 bits, literals, Char6,
arrays, aligned blobs, local abbreviations and BLOCKINFO inheritance. It checks
abbreviation grammar, scopes, block extents, END_BLOCK placement, field widths
and integer overflow. Padding bits are ignored as LLVM permits. A signature-only
stream is structurally valid, without establishing any LLVM module semantics.

`stream.metadata_strings(data, record_index)` handles the narrow LLVM
METADATA_STRINGS record (block 15, code 35). It decodes the VBR6 lengths and
returns borrowed byte ranges into the concatenated string data. Free that
range array separately. Pass the same immutable raw input used for parsing.
The separate [metadata/reflection layer](METADATA.md) indexes module metadata
and classic AIR shader entry points; raw stream parsing keeps other records.

Limits are 32 MiB of input, depth 64, 65,536 blocks and abbreviations, 262,144
records and abbreviation operands, and 4,194,304 expanded scalar operands.
Abbreviations have at most 256 operands; inherited/local abbreviation references
are charged against a total work limit of 262,144. A decoded metadata string
table has at most 262,144 strings. Transient decoder arenas are freed on success
and error. Limits bound expansion independently of compressed input size.

This is a shader-loading prerequisite. It does not validate LLVM IR types or
references, decode AIR instructions, translate shaders, execute Metal commands
or provide GPU capabilities. The runtime's default Metal device stays
unavailable. Native macOS framework samples establish format coverage only;
Fortnite's packed shaders are not yet covered.

The separate [`stream.ir_module(data)` layer](IR.md) indexes and checks a strict
subset of LLVM types and function signatures. Raw `parse` remains a bitstream
decoder; instruction semantics and execution require further backend work.

`stream_test.v` builds synthetic fixtures in V, checks malformed input and
mutations, and exercises expansion/work limits. `tests/ios/air-bitcode-inspect.v`
provides these modes:

- `inspect FILE.bc`: decode counts and module header text.
- `compare FILE.bc LLVM_DUMP`: compare every block's ID, scope, code width and
  word extent; every record code and scalar operand; ordinary blob bytes; and
  decoded METADATA_STRINGS strings. Length-table encoding and padding are not
  compared to LLVM's textual dump.
- `negative-controls FILE.bc LLVM_DUMP`: require a complete dump with ordinary
  blobs and metadata strings, compare it, then reject 12 corrupted dumps.
- `library FILE.metallib LLVM_BCANALYZER FRESH_EXTERNAL_DIR`: verify the MTLB,
  extract every unique module, run LLVM and compare in one process. Retains the
  input, raw streams, independent LLVM traces and exit statuses externally.

Generate reference dumps with LLVM's `llvm-bcanalyzer --dump --dump-blockinfo
--non-symbolic --show-binary-blobs FILE.bc`. Use matching flags, including
BLOCKINFO records and binary blobs. Keep native inputs, binaries and results
outside Git.

Compile tests and the inspector with V's `-enable-globals -gc none`, including
`compat/ios` in `-path`. The frozen toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` requires `V_RESOURCE_PATH`
pointing there and `V_MACOS_V3_NO_FALLBACK=1`; use `-nocache -cc clang` and
`-cflags -O2` for normal builds. Sanitized builds use
`-cflags '-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer'` and
`-ldflags '-fsanitize=address,undefined'`.

Format references: [LLVM bitstream format](https://llvm.org/docs/BitCodeFormat.html#bitstream-format)
and [LLVM's bitstream reader](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Bitstream/Reader/BitstreamReader.cpp).
