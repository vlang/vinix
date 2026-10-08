# Native ext2 construction

`ext2_query.v` runs the tree traversal, overlay merge, directory layout,
geometry, block allocation, indirect address trees, inode/bitmap/superblock
construction and manifest workflow in V. `ext2_export.py` keeps its public
signatures, constants, `Node` dataclass, descriptor creation, exporter cache,
NBD server and command parser. `_ext2_native.py` retains the actual caller's
objects and invokes Python standard-library operations; it contains no ext2
layout or allocation algorithm. These remaining Python bytes are counted.

The controller uses the repository's `run-v-tool.sh` on its first call, or
`VINIX_EXT2_BUILD_QUERY` can select an already compiled query. Recursive calls
and builder methods stay in the same native query when they still resolve to
the original public function. Caller replacements, including a method bound
to a different receiver, invoke the retained Python callable.

Integer tokens preserve Python's arbitrary-width scalar behavior. The native
address-tree iterator borrows Python ranges in bounded chunks. Python owns
the original objects, iterators, bytes, paths and context managers until the
request completes. The registered manager differs from its entered value;
exits receive the original error and supplied traceback, retain suppression,
and preserve deliberate traceback clearing or replacement. The final builder
close resolves its current descriptor, matching the original `finally`.
Transport retirement closes input, waits at most five seconds, kills and
reaps when needed, and then retires remaining owners. Query children ignore
SIGINT and use their own process group so the caller's cleanup completes.
The original descriptor-open/ftruncate failure ownership is retained.

Qualification froze source `821b88a8d1751e887386b69995abcd92bc2a63ed`.
Each ARM64, actual Rosetta x86_64 and ARM ASan/UBSan profile passed 480
original/native controls, 17 ownership/error controls, 100 requests returning
to the exact descriptor baseline, full image and manifest byte/mode pairs,
and independent e2fsck/debugfs plus 11 actual qemu-io NBD pattern reads.
Both ABIs passed seven CLI pairs without a compiler, unchanged public
signatures/constants/parser AST, and actual cold CLI compilation/build/fsck.

The unchanged six-case `tests/dota2/export-test.py` ran against the frozen and
native exporters on every profile: five cases passed; the sparse allocation
limit in `test_valid_layout_and_qemu_reads` failed on this APFS host in both.
Depending on allocation reuse, the first failing original bound was either
metadata `< 2 MiB` or package `< 128 KiB`. Neither bound, fixture, timeout nor
test ID was changed. Independent supplementary checks exercised the NBD
reads that follow that host allocation assertion. An attempted HFS+ scratch
volume materialized sparse files and exhausted its space; its failures are
retained and are not passing evidence.

Local evidence is in
`~/.cache/vinix-python-to-v/dota-ext2-export-20261008/`, including frozen
source hashes, original AST scope, all failed attempts, profile binaries,
raw logs, qualification and post-commit receipts. Scope is 11,962 original
AST body bytes/256 lines; unchanged Python APIs and library bindings receive
no algorithm credit. This host port changes no kernel ownership or device
implementation and claims no fresh kernel build, desktop guest or GPU run.
