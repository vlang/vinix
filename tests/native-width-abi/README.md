# Native integer and memory ABI

Run the same probe with the pinned release compiler and current V:

```sh
v run tests/native-width-abi/run.v /path/to/pinned/v /external/fresh-pinned-state
v run tests/native-width-abi/run.v /path/to/current/v /external/fresh-current-state
```

The selected kernel and utility code uses explicit `u64` storage because both
supported kernel architectures are 64-bit, while the pinned V compiler does
not provide the current native-width `uint`. Native C interfaces retain
`size_t` through a C scalar alias, including exported functions: matching the
width alone would change `unsigned long` to `unsigned long long` on Linux.
The two page-cache allocation casts use `int` for their fixed 128 KiB request,
which fits both compiler versions.

The probe checks native struct layout, a `size_t` round trip above 2^32, signed
64-bit storage, pointer identity, and the exact page-cache allocation size.
It compiles the production memory and secret-erasure bodies against native
`size_t` declarations and exercises alignment boundaries, zero lengths,
overlapping moves, comparison signs, and guard bytes. Only module names and
exported symbol names are changed in the copied production bodies, so they do
not interpose on the host process's libc. The unrelated `atoi` function from
the memory source is excluded. The V compiler treats the C fixture header as
an opaque native input.

The runner uses strict V3, production mode, and no compiler fallback or cache.
It runs beside the selected compiler so older versions use their own standard
library when the runner itself was built by another version. It keeps
compiler version, production-source hashes, build output, and runtime output
in the required fresh external state directory. Generated files are not
checked into the repository.

## Validation record

The candidate based on Vinix `f31187b778eca927284f39eb89569266cc670f15`
passed this runtime on Linux x86-64 with the pinned V
`9bfa1dc3f3455d5733d5c226662b6aaba8544f2c` and a V
`92cf0f51a5b5f1c6004084aad5bc6b17151f18e6`-based compiler with unrelated
int128 fixes. The affected `fetch` and `mount` utilities also built in
production mode with the default GC and ran their `--help` paths successfully
on both compilers. Full kernel builds are a separate integration check.

The complete local evidence is outside Git under
`/workspace/scratch/05ce597f4d63/ci-evidence/`. Each bundle's `sha256.txt`
lists every generated file; the manifest hashes are:

| Bundle | SHA-256 of `sha256.txt` |
| --- | --- |
| `vinix-native-width-current-production-04` | `0be1307ebeea09436c707782f2a10022adb0fbbe06e653efeff15eb065b852cc` |
| `vinix-native-width-pinned-production-04` | `ef9022533ff5ca79b06454b274f22c560c16c6312822cf4295bc56563cbd80a4` |
| `vinix-native-width-utilities-results-03` | `05ff31ba6b71da44e20f2e8c6faad7a0fb912672a042e9b291112bc652320de4` |
