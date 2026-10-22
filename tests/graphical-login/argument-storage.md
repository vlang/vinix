# Graphical manager argument storage

The graphical manager keeps command arrays whose strings belong to its caller
or to permanent literals. It now frees their storage through the V array
runtime, without freeing the borrowed strings. Calling libc `free` on `data`
is invalid when the compiler gives arrays a managed allocation header.

The assertion-enabled `graphical_ownership_test.v` exercises 4,000 registration
success/refusal scopes with empty and populated fallback arguments. The pinned
compiler's `-new-compiler` mode is the mode used by the native manager build.
Tracked heap checks retain zero bytes; ASan/UBSan reports no error. Replacing
only the generated cleanup helper with the previous raw-data free makes the
same sanitizer test exit 134 with a bad free 16 bytes inside its allocation.

Run from the repository with the pinned V compiler and the account module path:

```sh
v -new-compiler -cc clang -nocache -enable-globals -gc none -manualfree \
  -d track_heap -keepc -cflags '-Idesktop/tools/tests' \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/graphical-arguments tools/accounts/sessioncore/graphical_ownership_test.v
/tmp/graphical-arguments
```

For sanitizers, replace `-d track_heap` with
`-cflags '-fsanitize=address,undefined' -ldflags '-fsanitize=address,undefined'`.
Use `ASAN_OPTIONS=detect_leaks=0:halt_on_error=1` and
`UBSAN_OPTIONS=halt_on_error=1`. V runtime global allocations are outside this
test's ownership claim. No production optimization flag is used, so assertions
remain enabled.

[The host report](results/2026-10-23/argument-storage.json) records source,
compiler, generated C and binary hashes. [The negative control output](results/2026-10-23/argument-storage-old-free.txt)
retains the allocator diagnostic. Parent-agent review verified that the seven
production array owners retire only after synchronous setup or manager cleanup
has reaped the readers; generated C calls the managed-aware array runtime and
does not free the strings. This host result does not claim native workflow
acceptance.
