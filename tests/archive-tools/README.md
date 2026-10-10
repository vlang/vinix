# Native QEMU archive tools

`tools/split-qemu-initramfs`, `tools/split-desktop-initramfs` and
`tools/build-qemu-module-iso` compile and run V directly through the repository's
compiler selector. Their positional arguments, cache format 1, file locks,
module limit and publication order are preserved. I/O and build failures exit 1;
invalid arguments exit 2. No Python command or import bridge is used.

Run `tests/archive-tools/run.sh` for all three native suites. The individual
entrypoints are `tests/qemu-initramfs-split/run.sh`,
`tests/qemu-module-iso/run.sh` and
`tests/storage/test_split_desktop_initramfs.v`. The storage runner also retains
its separate QEMU guest test. `VINIX_ARCHIVE_TOOLS_DIR` can point the suites at
three prebuilt production binaries; otherwise child processes dispatch through
the same V CLI module.

Input tar streams are parsed in V; libarchive supplies only decompressed bytes.
Boot-module sources deliberately reject compression. Outputs use USTAR and
10 KiB records. The root seed streams through zlib, level 1, with no filename and a
zero timestamp. Compressed bytes can differ from the original gzip stream; decoded records, metadata
and payloads are checked. Payload copying is bounded to a 1 MiB buffer, and no
uncompressed copy of the root seed is staged on disk. The gzip header defaults
are documented in the [zlib manual](https://zlib.net/manual.html).

The suites inspect outputs with system tar and, when installed, extract the
exact source from an ISO using xorriso. They cover shrinking modules, obsolete
symlinks, unchanged unrelated files, bad/empty/oversized archives, traversal,
hard links, symlinks, missing mountpoints, multi-megabyte payloads, exact integer
receipts, one-nanosecond invalidation, lock contention, concurrent callers and
descriptor cleanup. A V fake xorriso checks failure, undersized output and source
mutation without publishing over the old cache. The shared tar writer and reader
tests also cover synchronous write visibility and closed-descriptor errors.

Qualification on 2026-10-11 passed native ARM, actual Rosetta x86 binaries and
ARM ASan/UBSan for the suites, production frontends and three shared tar test
files. V 0.5.2 `c6bb06f` was rebuilt in an isolated matching source checkout:
the shared development binary was reading newer embedded header bytes with its
older recorded length. The shared compiler checkout was left untouched. Local
logs are `/tmp/vinix-archive-{parts,desktop,iso}-{arm,x86,san}.log`,
`/tmp/vinix-archive-front-*.log` and `/tmp/vinix-archive-shared-*.log`.

No Python was executed for qualification, and no new guest boot is claimed.
Four captured allocation-benchmark Python runners still name the historical
ISO script. They remain counted and await translation with their own frozen
workflows; their original tool revision is available in Git. Their recorded
source and results were not rewritten as part of this command port.
