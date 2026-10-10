# Kernel allocation checker

`run.sh` checks both architectures' allocation reports against `allowed.txt`.
Its source copier is native V: it copies the architecture-filtered seed list,
recursively adds missing local import modules and preserves existing modules'
filtering. Copied files retain their contents, modes and timestamps.

```sh
tests/kernel-allocs/run.sh
v -cc cc test tests/kernel-allocs/copycore
```

The native tests cover cyclic imports, filtered modules, source metadata,
Unicode whitespace, relative destinations, literal Unix backslashes and the
report runner. A compiler failure on either architecture remains fatal even
when warnings were printed, and `--update` cannot accept an incomplete report.
Tests use shell compiler stubs and a separately compiled native source copier;
they do not need Python.

Set `VINIX_KERNEL_ALLOCS_COPY_TOOL` to an already compiled `copy_sources.v`
executable when testing with a compiler stub or reusing a prepared host tool.
The default `copy-sources` command follows ordinary `V`/`VINIX_V_COMPILER`
discovery and builds outside the checkout.

The port was compared with the original Python copier on both real kernel
architecture source lists, using ARM and Rosetta x86 host executables. Copied
inventories, complete file bytes, permissions and nanosecond modification times
matched. This validates source preparation and report enforcement; it does
not claim a new kernel allocation pass or guest boot.
