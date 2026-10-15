This fixture runs the unchanged V const-string backend, typed original Linux
facades, native image-range classifier and existing page allocator/string-copy
chain. The host replaces only linker endpoint addresses and physical-page
allocation/free transports. It never substitutes a per-pointer classification
decision or a C algorithm.

The designated image interval and its neighboring pages are real protected
mappings. Boundary queries and borrowed-pointer operations run with inaccessible
candidate bytes. A separate readonly mapping outside that interval must be
copied. Stack and owned inputs, empty strings, NUL at a protected page boundary,
source mutation, GFP rejection, allocation failure, reclaim policy and repeated
allocation/free cycles are observed through original public functions. Only
genuine production-owned copies are passed to free; the page transport rejects
any unknown base or page count.

Run from the repository root with the selected V compiler:

```sh
build-support/run-v-tool.sh tests/linuxkpi/const_string.v --keep-dir NEW_DIRECTORY
```

The retained evidence includes unchanged generated-body comparisons, original
header/type contracts, strict GNU99/GNU11 O0/O1/O2 sanitizer runs, freestanding
production imports and stack usage, commands and hashes. Native linker endpoint
placement and retained kernel allocations require separate guest evidence.
