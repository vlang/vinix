The graphics builders use native V for streamed BLAKE2b-512, SHA-512 and
SHA-256 checksums, pinned Venus package preparation and private library staging.

```sh
build-support/graphics-tools/run checksum blake2b ARCHIVE EXPECTED 'Mesa archive'
build-support/graphics-tools/run venus-prepare ARCHIVE BUILD MANIFEST
build-support/graphics-tools/run libraries SYSROOT/usr/lib PRIVATE/lib
```

Venus retains Mesa 25.0.5's full BLAKE2b hash and the 34 Alpine 3.21 ARM package
hashes. Downloads use at most eight workers. Every worker retires before a
failure returns; a private partial file is verified before entering the cache.
Cached corrupt files fail without being overwritten. Extraction uses the host
tar through the existing V command owner and starts only after all package
checks pass. Existing source trees are retained. Invalid or duplicate manifest
names are rejected before downloading. The pinned archives supply Linux UAPI
headers as system headers to the actual probe build.

Library staging retains `*.so*` name selection, regular-file contents,
permissions and times, relative or absolute symlink text and replacement of
dangling destination links. A missing source directory has no matches.
V-to-C calls in the Venus and QEMU builders use `compile-v-module` directly.
Chromium, LibreOffice, QEMU and x86 translation package staging no longer
requires an unused Python executable.

Run `qualify.v COMPILER NEW_EVIDENCE arm|x86|san` to cold-build the command,
behavior checks and module generator. It compares 27 streamed digests with
OpenSSL, downloads 17 actual fixture packages with curl, checks cached reuse
and failure cleanup, and verifies library metadata and link cases. It then
verifies/extracts the actual cached Mesa and 34 Alpine archives, checks every
staged shared library, and links real ARM/x86 static-musl Venus probes and an
ARM dynamic-musl VNC viewer. Shell syntax is checked for all seven callers.
The qualifier retires its extracted data without following cache symlinks.

Qualification executes no Python, Mesa generator, graphics application,
guest probe ELF or Vinix guest. Sanitizers apply to host tools. Mesa's foreign
generator SDK remains a separate prerequisite, described in the
[Venus build documentation](../venus/README.md).
