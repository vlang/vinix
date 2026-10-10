# Native kernel log symbolizers

`tests/kernel-allocs/sites KERNEL < run.log` names live `PERF-SITE` allocation
chains, subtracts four bytes from return addresses, removes allocator frames,
and deduplicates by label, size and chain (ignoring the changing count).
It streams input and retains the original lowercase-hex and Unicode 13 decimal
field parsing, including the distinction between `0` and `00` in raw chains.
Set `LLVM_BIN` to select the symbolizer directory.

`tests/user-access/sites KERNEL < serial.log` names direct user-pointer access
paths. It symbolizes unique addresses in numeric order, adjusts callers by one
byte, handles the ARM leaf link register and x86 stack-chain rules, and reports
unique read/write paths. No hits succeeds with status 0; reported paths exit 1.
Malformed UTF-8 process names use replacement characters. This command selects
`llvm-symbolizer` from PATH before the Homebrew fallback.

Both commands compile and run V directly. Addresses use arbitrary-width native
V integers. Allocation reporting retains stdout after a symbolizer error;
user-access reporting fails on a nonzero symbolizer exit. The shared host process
controller drains both pipes and reaps children.

```sh
v -cc cc test tests/kernel-symbols/symbolcore
v -cc cc -o /tmp/kernel-sites tests/kernel-allocs/sites.v
v -cc cc -o /tmp/user-sites tests/user-access/sites.v
VINIX_ALLOC_SITES_TOOL=/tmp/kernel-sites VINIX_USER_SITES_TOOL=/tmp/user-sites \
  v -cc cc test tests/kernel-symbols/symbolcore
```

Tests cover parsing, Unicode, wide addresses, zero spellings, frame filtering,
inlining, ARM/x86 chain construction, deduplication, empty logs, stdin and child
exit status. Optional command checks run separately compiled host executables.
Set `VINIX_SYMBOLIZER_REAL=1` to build isolated ARM and x86 ELF debug fixtures
with Clang/LLD and check both reporting policies using the real LLVM symbolizer.
These are host reporting checks, not new kernel allocation or usercopy results.
