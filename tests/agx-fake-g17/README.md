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

The host controller lives in `agxhost/`. `run.py` keeps the original argument
parser and architecture diagnostic, and `_native.py` transports CLI/import
requests and typed exceptions. The native controller stages sources, builds the
production core and both independent fixtures, enforces the original allocator
import guards and exact scale allocation pair, and runs optional frozen C
fixtures. `tools/agx-re/compile-v-trace.py` uses the same controller for its
maintained `Path` import API and CLI. Generated core bytes, compiler arguments,
stdout, inherited stderr and failure order remain covered by original controls.

Host qualification uses actual ARM and x86 V compilers, ASan/UBSan and an
always enabled ASan fake stack. It includes 61,344 original Unicode 13 regex
boundary controls per profile, the independent C fixtures, compiler/allocator
failures, invalid UTF-8 output, source-copy failures, CLI errors and concurrent
cold frontend installs with temporary-directory retirement. Original source
snapshots and source-bound receipts are under the machine-local
`~/.cache/vinix-python-to-v/agx-host-20261008/` directory. The shared source-copy
binding is qualified for fresh default trees, including file metadata, followed
symlinks and collected FIFO errors; arbitrary invalid-UTF-8 source names are
outside that copy qualification.

Darwin child launches retain the Python caller's CPU preference through the SDK
spawn attribute, including Rosetta callers and the fallback for single-slice
executables. Mixed ARM/x86 controller and caller combinations preserve original
fixture output and command arguments. These are host controller and native ABI
checks; the separate VM runner retains its own guest deadlines and markers.
