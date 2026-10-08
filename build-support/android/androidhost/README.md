The native host package owns DEX class and bootstrap-map parsing, bounded
ARM64 ELF validation for 16 KiB pages, canonical overlay paths and streaming
SHA256. It preserves the original table bounds, duplicate checks, ASCII
errors, validation order and optional-versus-required ELF behavior.

`host-query.v` accepts one JSON request per line. The Python import adapter
only marshals paths, bytes, return types and exceptions; each request runs in
a separate host process. Files are closed on success and error, and returned
DEX names and decoding-error bytes own their storage. Upstream libc and V
libraries remain unchanged. Runtime installation and build/test orchestration
are still at the Python frontend while their next stages are migrated.

Qualification compares complete outputs and exceptions against the frozen
original Python implementations, including independent Android host fixtures,
byte/word/truncation controls and read-only real ART boot DEX payloads. These
host checks do not execute Android applications or the guest runtime.
