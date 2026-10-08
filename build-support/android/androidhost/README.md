The native host package owns DEX class and bootstrap-map parsing, bounded
ARM64 ELF validation for 16 KiB pages, canonical overlay paths and streaming
SHA256. It also owns ordered runtime manifest policy, coherent output sets,
SONAME alias checks, ATL builder/compiler and DEX receipt policy, source
provenance, slash-only path containment and temporary-file installation.
Every destination is checked before the first payload is published. Copying
uses a bounded buffer; verification and mode checks precede atomic rename,
and the temporary descriptor/file retires on success and error.

It preserves the original table bounds, strict integer types and unbounded
size rejection order, duplicate checks, ASCII errors, validation order and
optional-versus-required ELF behavior. Path resolution follows symlinks
component by component and preserves literal backslashes, missing ancestors
and loop errors. Upstream libc and V libraries remain unchanged.

`host-query.v` accepts one JSON request per line. The Python import adapter
marshals paths, bytes, observed metadata, return types and exceptions; each
request runs in a separate host process. Files are closed on success and
error, and returned DEX names and decoding-error bytes own their storage.
The import frontend retains standard-library JSON/ZIP/XML reads, bootclasspath
and public ART/ATL pairing contracts, Python set order, manifest identity and
equality, and opaque extension fields.

The lifecycle, cookie, autofill and location probe builders also run in V.
Their compatibility entries retain the original argparse interface and error
marshalling. V checks pinned inputs, collects classes, invokes javac/D8/aapt2
with inherited standard streams, checks provider and APK payloads, and writes
hash receipts. Spawn preserves exec errno, negative signal status and the
original absence of a deadline; child descriptors close before exec and
interpreter-ignored signals restore their default behavior.

Archive headers, class ordering, 1980 timestamps, mode bits, UTF-8 flags,
duplicate lookup and append publication are V policies. Compression uses the
system's unmodified zlib. Checked offsets remain wide before slicing; ZIP64
count records and local/central extra fields are supported. Owned host arrays
bound any single archive or decoded payload to less than 2 GiB. The original
compiler producers use stored or deflated payloads. Failed class reads retain
a finalized partial JAR; failed D8 validation preserves append-mode close
behavior on missing or invalid APK output.

Qualification compares complete outputs and exceptions against the frozen
original Python implementations, including independent Android host fixtures,
byte/word/truncation controls and read-only real ART boot DEX payloads. These
also cover complete runtime errors and installation state, hardlink aliases,
mode bits, publication preflight, temporary cleanup and descriptor baselines.
These host checks do not execute Android applications or the guest runtime.
Probe qualifications compare complete command arguments, statuses, output,
error attributes, file state, archives and receipts against the four frozen
original controllers. External compilers are controlled child
processes, with the two expected pins set to immutable fixture input hashes;
production pins stay unchanged. Full deterministic archive bytes are checked
against original zipfile outputs, with ARM64/x86_64 and sanitizer validation.
