Native V prepares the clock, EXT2 mapping and private-page host test sources
and the minimal ELF64/ARM64 M1 deployment fixture:

```sh
build-support/source-tools/run clock kernel/time/time.v OUTPUT.v
build-support/source-tools/run ext2-mmap kernel/fs/ext2/ext2.v OUTPUT.v
build-support/source-tools/run private-fixture tests/private-pages/source_test.v DIRECTORY
build-support/source-tools/run private-install kernel/memory/mmap/mmap.v OUTPUT.v
build-support/source-tools/run m1-kernel OUTPUT
build-support/source-tools/run test-directory COMPILER DIRECTORY [compiler flags...]
```

Source reads retain strict UTF-8 and universal newline conversion. Selection
keeps the original markers, public function prefixes, body bytes, import order
and `VINIX_FILE_PAGES_HOST`/`VINIX_PAGING_HOST` variants. Missing markers fail
before writing the selected output. The M1 fixture keeps its exact 64-byte
header and 32-byte Limine MP request. No kernel implementation is changed.

The desktop test scripts reuse `native-utility-source.v materialize DIRECTORY`
to replace each regular-file symlink with its bytes. Dangling links and links
to directories stay links. `merge-activity` and `merge-parity` retain the
original file order, exclusions, unique sorted imports and Python-compatible
line splitting. The existing `merge` profile is unchanged.

The flat-directory test driver invokes every staged `_test.v` file directly,
with the caller's compiler flags and module environment. It retains failures,
continues with the remaining files and rejects an empty selection. It also
rejects assertion/panic/sanitizer diagnostics if a compiler returns zero.
Its existing command owner retires children on failures and interruption.
This avoids the shared SDK `vtest` executable's architecture/cache issues.
Both source modules include the native stat header so Darwin selects the
correct inode ABI under Rosetta.

The security-policy host fixture records the current audit hook and checks
one typed event per allowed/denied decision. The mapped-writeback fixture
now models the current non-journaled transaction calls; it rejects attempts
to simulate an unsupported journal. Its existing mapping tests remain.

`qualify.v COMPILER NEW_EVIDENCE arm|x86|san` cold-builds the source command,
desktop source command, behavior checks, existing utility tests and frozen V
reference. It verifies source/Unicode/ordering/link/ELF cases, compares the
existing merge output byte-for-byte with that reference, checks failure
continuation and empty selections, and runs the actual clock/security-policy,
EXT2 mapping, four private/file/paging combinations and disposable M1
deployment workflows. All eight translated shell callers receive syntax
checks. Full desktop UI suites and Vinix guests are outside this qualification;
no Python, GUI application, live ESP or Vinix kernel executes.
