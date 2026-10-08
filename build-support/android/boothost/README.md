The native controller owns ART boot library reconstruction, provenance checks,
verified download publication, cache reuse, D8 command planning, staged JAR
replacement, and native guest Java probe packaging. The original Python entry
keeps argparse and synchronous library bindings. ZIP and tar parsing/compression,
Path operations, subprocess launches and existing ART public API calls use the
unmodified Python standard library. No Python fixture algorithm is hidden in
those bindings.

Archive handles are opaque IDs owned by the calling Python request. Native code
closes them in original nesting order, including error paths; close/unlink errors
retain the original cleanup precedence. A transport failure closes every remaining
archive and removes partial staging files. Controller shutdown closes pipes and
waits, then kills/reaps an unexpectedly blocked controller. External compiler and
download commands retain their original inherited environment and unbounded wait.
All native strings and JSON values are owned; hexadecimal WTF-8 transport preserves
lone surrogates, and tagged non-finite floats preserve strict receipt type checks.
The equality corpus includes wide integer/float, boolean and container comparisons.

Cache identity now includes the complete maintained policy/binding source closure,
including Android, fixturehost and hosttest V sources and ABI headers. Its ordered
path/length delimiters and each committed blob are independently verified. Native
source changes invalidate prepared caches even when the thin Python entry is
unchanged. Compiler qualification is recorded separately; binary UUIDs and build
paths are excluded from cache identity.

Qualification preserves all nine original bootclasspath cases and compares full
frozen production APIs, compiler argv/error ordering, exact deterministic archives,
receipts, real staging/hardlink behavior, malformed values and cleanup on ARM64,
x86_64 and ASan/UBSan. Shell compiler fixtures perform real filesystem/process
operations for prepare/cache/probe workflows. An independent opaque ART API shim
isolates staging sequencing, while the existing ART runtime fixture tests exercise
the real production API. These checks do not claim network downloads, real Java/D8
compilation, an Android application, fresh kernel builds or guest execution.
