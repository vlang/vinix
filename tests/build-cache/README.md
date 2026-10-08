# Build-cache fixtures

Run `tests/build-cache/run.sh` for the native V content and desktop cache
fixtures. Compiler selection follows `build-support/find-v.sh`.

The four content and seven desktop invalidation cases preserve the original
Python fixtures' assertions. Additional cases cover full signed nanosecond
widths and literal backslashes in Unix filenames. Content keys retain the v1
framing. Desktop keys use v2 and include the native implementation and import
transport as source inputs, so an implementation change invalidates a cached
image.

The command and import frontends still accept the existing Python interfaces.
Their shlex, subprocess version probe, and Python/Pillow version bindings remain
in Python; input selection, path resolution and hashing execute in V.

`test_prune_build_artifacts.py` remains an independent Python test for the
unrelated build artifact pruning tool.
