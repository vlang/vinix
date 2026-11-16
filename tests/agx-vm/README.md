Compile `run.v` with V to an external executable, then execute it. Set
`AGX_VM_TEST_BINARY` to retain its ASan/UBSan executable outside Git.

The runner imports the current pure VM/identity and ioctl modules directly
from `kernel/`; it does not require a generated `kernel/modules` directory.
It executes no page tables, firmware or GPU. Geometry, identity exhaustion,
operation/global bind shapes and deferred per-VM reservation checks run against
production V functions. The file-close fixture separately tests real binding
ioctl lookup errors, reference counts and mapping effects with injected services.
