# Bounded owned signed-index decoding

Signed repository indexes now use the bounded `StoredReader` primitives already
used for persisted manifests. The reader owns every returned envelope, package,
dependency, payload and string-array field. It retires partial declarations on
failure; `close_decoded_index` keeps its existing result cleanup contract.

The previous generic JSON decoder allocated an empty field-tracking boolean
array without releasing it. Generated C identifies that scratch allocation; an
isolated 64-call probe retained 64 one-byte records for both direct decoding and
signature verification, while replay-history construction retained zero. The
same probe retains zero after this change. No compiler or standard-library
source changes are required.

Signature verification still authenticates the original bytes before schema or
typed admission. The signed-schema scanner runs before the bounded typed reader
to preserve required-field and ambiguity diagnostics. It is bounded by the index
size limit; typed parsing then checks JSON structure and field bounds before
envelope/package validation. Publisher canonical bytes and signatures remain
unchanged. Escaped unique names, surrounding JSON whitespace and omitted legacy
`window_protocol` remain supported. Partial/unknown/duplicate declarations,
coercions, invalid UTF-8, malformed numbers, trailing data and invalid manifests
are refused. Malformed JSON reports the bounded reader/scanner's specific
diagnostic in place of the generic decoder message. Sequence supports the full
unsigned 64-bit range; expiry supports the full signed 64-bit range and retains
the existing comparison with `now`.

Metadata remains limited to 8 MiB and 4,096 packages. Nested fields use the
existing stored-manifest bounds, consistent with package validation. Exponents,
fractions and leading zeroes are refused. The exact size limit and limit-minus-one
are accepted; one byte over and 4,097 packages are refused. Full package
declarations run outside the allocation
tracker's 16,384-live-record table, natively, under sanitizers and in both guests.

The tracked fixture requires zero retained bytes for 1,000 empty, one-package and
64-package observations on both metadata targets, plus 1,000 cycles of each
partial/schema/numeric/UTF-8/manifest refusal. Other runners use 64 functional
cycles to bound guest runtime. Independently returned records survive source
retirement and another owner's cleanup, and reproduce exact declaration bytes in
the empty/growing cases. Full catalogs qualify every nested declaration with one
live owner at a time.
Signed original/legacy documents and signature-before-schema refusals run for
64 cycles. Repository-status checks remove their previous residual allowance
and warmup: migration, newer floors, equivocation, signature refusal and exact
retired-key recovery now all require zero retained bytes.

The maintained repository guest suite includes the new decoder fixture, existing
signed-schema service checks and repository-status checks. Failed signed refresh
and enrollment preserve configuration, cache, replay history and installed state;
restored publication remains usable. Host checks also cover signed CLI workflows,
catalog ownership, enrollment, signature compatibility, stored state and release.

An initial AArch64 run reported allocation failure in the combined large-inventory
fixture. The final fixture streams input from one encoded
package template, retires boundary buffers and runs each guest size/architecture
and refusal/boundary/signature group in a fresh worker. Full limits and assertions
are retained; resource limits are unchanged. The failed controller/serial output,
fixture source, generated C and executable are retained in the evidence ledger.

Publisher template decoding and unrelated service lifetimes remain outside this
change. Production publisher enrollment, catalog migration, graphical
login/display integration and wider foreign-runtime qualification remain open
for roadmap 14 acceptance.

The subsequent [publisher manifest reader](manifest-decode-check.md) extends the
shared bounded package primitives to source templates and packed inventories,
preserving strict signed/state declarations while allowing template defaults.
This report's results retain their original signed-index scope.

## Recorded results, 2026-10-16

All **40 focused compile/run checks** passed: twelve core and one protocol pairs, two tracked-allocation pairs, two ASan/UBSan pairs, four signed CLI/driver checks and two guest-tool builds.

Fresh QEMU TCG guests passed with clean shutdown and nine verified artifact hashes each: AArch64 **158.4 seconds**, x86_64 **164.9 seconds**. These deadlines qualify functionality, not performance.

- [before/after isolated probe](results/2026-10-16/index-decode-baseline.txt)
- [host results](results/2026-10-16/index-decode-host.json)
- [host summary](results/2026-10-16/index-decode-host.txt)
- [core assertions](results/2026-10-16/index-decode-core.txt)
- [tracked decoder and repository observations](results/2026-10-16/index-decode-memory.txt)
- [sanitizers](results/2026-10-16/index-decode-asan.txt)
- [signed CLI](results/2026-10-16/index-decode-cli.txt)
- [initial compilation and diagnostic assertion](results/2026-10-16/index-decode-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/index-decode-toolchain.json)
- [aarch64 receipt](results/2026-10-16/index-decode-aarch64.json)
- [aarch64 report](results/2026-10-16/index-decode-aarch64.txt)
- [aarch64 serial](results/2026-10-16/index-decode-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/index-decode-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/index-decode-x86_64.json)
- [x86_64 report](results/2026-10-16/index-decode-x86_64.txt)
- [x86_64 serial](results/2026-10-16/index-decode-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/index-decode-x86_64.qmp.txt)
