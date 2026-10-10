# Native emulator desktop preparation

`desktopprep/policy.v` prepares the N64, PS1 and PS2 desktop test root filesystems,
compiler and archive commands, and QEMU environment. Each harness keeps its
parser, temporary-directory and log contexts, QMP and screenshot helpers,
gameplay assertions, deadlines, signals and final cleanup.

The controller borrows the actual caller's Path, options, environment and
subprocess objects through the Package Session ABI. Raw filesystem strings,
Python widths, operand order and native Python exceptions stay intact. One
ordered dictionary holds named preparation values on a saved error. Dynamic
paths and results never enter the finite per-harness literal pool.

All three harnesses share the import and syntax bridge. The first preparation
call builds a private SDK library and query with the invoking Python's host
architecture and headers. `VINIX_PACKAGE_STORE_LIBRARY` and
`VINIX_DESKTOP_PREPARATION_QUERY` may select previously built artifacts. Cold
build owners use private directories and retire at interpreter exit.

Python dictionary expansion, list/tuple construction and formatting bindings
receive zero migration credit, as do fixed recipe data and unchanged guest
fixtures. Host comparisons include real copies, permissions and symlinks,
raw paths, supplied objects, failures and complete controlled harness workflows.
Controlled processes and screenshots establish no new emulator, kernel or QEMU
execution result. Extra private bridge frames do not preserve exact traceback
frame layouts or recursion budgets.
