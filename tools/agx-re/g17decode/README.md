# Native G17 recovery foundations

`macho.v`, `instruction.v` and `register.v` own the original recovery tool's
Mach-O symbols/UUIDs, virtual-to-file translation, symbol code spans, AArch64
instruction predicates, bounded static W/X register resolution, instruction
sequence checks, authenticated kernel rebases, PC-relative data reads and
store-span coverage. These predicates intentionally retain the original
recovery subset's accepted encodings, including reserved instruction forms.

`query.v` is a synchronous compatibility dispatch for the remaining Python
recovery families. The existing extraction ABI borrows input only until a call
returns and allocates each JSON response with libc; the adapter copies and
releases it exactly once. Instruction values preserve unsigned 64-bit fields
and arbitrary-width signed local branch addresses. Mach-O names and C strings
use native UTF-8 replacement with the original decoder's prefix consumption.
Native V callers import the public functions directly. `_native_g17.py` and
the original module's wrappers contain only serialization, tuple/set shape,
slice conversion and error-class handling.

The foundational port replaces 63 functions (1,056 original Python lines,
39,334 original function bytes). The remaining recovery algorithms and their
independent Python fixtures are still maintained and honestly counted.

Validation compares the original Git-controlled Python implementations with
121,304 native controls on ARM64, x86-64 and ASan/UBSan, including exhaustive
UTF-8 byte pairs, logical-immediate masks, random instruction families,
malformed/truncated Mach-O images, signed offsets and wide branch targets.
All 227 existing G17/T6050/T8103 recovery checks pass; 12 retain their original
skip because their private binary fixtures are unavailable. Nineteen native
tests retain positive and rejection cases. The actual G17 driver UUID, all
6,545 symbols, ten power/initialization code spans and six vtable targets also
match. Repeated bridge calls from foreign threads return owned output counts
to zero, with bounded collector retention; mutable borrowed inputs may change
immediately after return without altering returned metadata or code bytes.

The shared image-extraction ABI also preserves arbitrary signed public
`align_up` integers with native `math.big`; bounded native Mach-O offsets keep
their fixed-width implementation. Kernel and imported libraries are unchanged.

Machine-local source controls and qualification receipts are stored under
`~/.cache/vinix-python-to-v/agx-recovery-20261008/`. They contain original
source snapshots and source/binary/log hashes; no Apple image is committed.
