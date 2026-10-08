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

The staging and VOffice policies also run in V. Their v2 keys fingerprint the
native helpers, follow symlink targets, detect directory cycles and omit
directory generation when recursively hashing metadata. V compiler inputs
exclude tests/generated files and the compiler sources already fingerprinted
by the compiler executable. Office app keys include each app's transitive
production modules. The additional native suite covers these invalidation
rules and compares Unicode13 word/space membership for every valid scalar.

Staging record publication and the VOffice compiler controller retain their
existing Python command frontends. The former incremental Python hashing
helpers had only these two in-repository consumers; both now request complete
native keys through the counted import transport.
