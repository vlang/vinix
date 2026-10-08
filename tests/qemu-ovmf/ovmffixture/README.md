The V fixture owns all twelve original firmware test groups: real Git patch
checks with LF/CRLF inputs, shallow direct-submodule cloning, interrupted-clone
recovery, toolchain discovery, and edk2 setup/strict-shell failures. The existing
Python entry preserves unittest case IDs, filters and Git-unavailable skips:

```sh
python3 tests/qemu-ovmf/test_patch.py
```

The direct native entry is:

```sh
build-support/run-v-tool.sh tests/qemu-ovmf/test_patch.v
```

Each case exclusively owns its temporary checkout. Failed checks return errors
through the cleanup boundary; constructor and child failures also retire the
checkout. Git and builder calls retain their original ten-second deadlines;
initial Git setup keeps its original absence of a deadline. Both child output
streams are drained while the process runs. ARM and Rosetta callers retain
their execution architecture.

Qualification compares the frozen original assertions and complete ordered
builder statuses/output/driver bytes at identical isolated paths on ARM64,
x86-64 and with ASan/UBSan. Git commit dates are fixed only in the comparison
harness. Additional tests force constructor and assertion failures and check
directory and descriptor retirement. The upstream mode-table bytes and
production shell builder/patch remain unchanged. No edk2 build, firmware image
publication or guest execution is claimed.
