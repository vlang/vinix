# Independent G17 command fixtures

`run.sh` checks the production V verifier/encoder and the native descriptor
bridge. The independent V encoder fixture retains all sixteen recovered-ABI
golden hashes, dense and appended-address goldens, capacity failures and command
mutations. Its 32 checks retain the original diagnostic lines and expressions.
Host ASan/UBSan builds reject hidden allocation imports.

The independent V verifier retains all 41 original trace, size, resource and
provenance checks. Its 314-record scale case retains the single explicit
`calloc`/`free` pair, checked in generated output; every other buffer stays on
the caller's stack. Use `run_encode_native.py --fixture verifier` to run it
on either native architecture.

`python3 run_encode_native.py --arch aarch64 --kernel-dir /path/to/kernel
--state-dir /path/to/new/state` runs that same fixture and production policy in
QEMU. Use `--arch x86_64` and `CC_AMD64` for the other architecture. Native
fixtures model command bytes; they do not establish physical GPU operation.

The original 289-line encoder oracle is recoverable from
`15048510:tests/agx-fake-g17/test_encode.c`. A materialized immutable copy can be
supplied with `run.py --c-encoder-reference` or
`run_encode_native.py --c-reference`. `VINIX_G17_TEST_ARCH=x86_64` selects the
x86 host ABI when the host compiler targets x86 on an ARM machine.
The original 420-line verifier is recoverable at
`083cb12b:tests/agx-fake-g17/test.c`; use `run.py --c-verifier-reference` or
the native runner's `--c-reference` with `--fixture verifier` for comparison.
