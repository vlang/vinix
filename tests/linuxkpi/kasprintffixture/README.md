# Formatted-allocation host contract

Run `v -path 'tests/linuxkpi|@vlib|@vmodules' run tests/linuxkpi/kasprintf.v
--keep-dir NEW` from the repository root, with the intended compiler in `V`.

The fixture executes production V bodies through genuine native ellipsis calls,
compiler `va_start` and `va_end`, exact Linux typed `va_list` facades, and the
kernel's instruction-only named-two-argument `kasprintf` entry. No fabricated
cursor or replacement formatter implements a successful operation.

Page allocation, immutable image endpoint addresses, and console output are host
transports. The production checked allocator, string ownership classifier,
format parser, argument readers, warning frontend, and taint update execute
unchanged. The page transport records genuine bases and page counts; it can
reject allocation or mutate a borrowed source between the two formatter passes.
The console sink renders the real warning's nested `%pV` through the production
formatter and checks its exact message and warning taint.

The controller generates constant format/argument call sites in V to reach the
actual `INT_MAX-1` count boundary without allocating its output. It covers the
exact boundary, rejection above it, the remaining count inherited by nested
`%pV`, and bounded second-pass overflow with a real warning and preserved small
allocation. A sentinel proves that the raw canonical cursor stops at the first
overflow. Three warmup/retained-allocation measurements belong to the native
guest fixture, separate from the host's repeated exact page recovery.

Ordinary modest count mismatches keep the first-sized terminated prefix. A
second-pass count above `INT_MAX-1` is outside the supported length domain:
the warning reports `UINT_MAX`, and a nested overflow conservatively retains
the preceding outer prefix. The genuine nested-cursor test changes inner `%u`
to 257 large-width conversions between passes under outer `pre:%pV`; its
first-sized six-byte owner returns `pre:` and is freed exactly once.

Six strict GNU99/GNU11 and O0/O1/O2 object/sanitizer profiles execute on each
available native host ABI. Apple Silicon executes both SysV64 through Rosetta
and Darwin ARM64. Freestanding SysV64/AAPCS64 objects also compile the actual
genuine-origin and nested-descriptor helper bodies. Their imports and stack
usage are checked, and production classifier objects retain actual linker
endpoint imports. Host protected mappings use the host's real page size.

Algorithms and export wrappers are selected byte-for-byte from full production
module generation. A narrow unchanged V source stage supplies matching type,
constant and storage metadata; only its isolated initialization body is used.
This avoids the native compiler's module-global anonymous-loop counter changing
an otherwise identical body when the module is narrowed. Actual compiler
`va_start` and `va_end` imports use the native `va_list` typedef; generic
`void *` imports can make the native V compiler heap-promote the cursor. The
receipt preserves generated sources, exact imports, static stack evidence,
compiler commands, input hashes and artifact hashes.

Native linker placement, ARM guest behavior, retained kernel heap objects, and
full GPU completion require separate evidence.
