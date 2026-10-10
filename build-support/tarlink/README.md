# Native initramfs archive deduplication

`build-support/link-duplicate-files IN.tar OUT.tar` stores eligible repeated
files once and converts later copies to USTAR hard links. Only regular files
of at least 4096 bytes below `usr/lib/` or `usr/share/` (with an optional `./`)
qualify. SHA-256, size, mode, UID and GID must match. The first copy remains the
target, including when its name is too long for a later hard link.

V parses tar headers, GNU long names and PAX overrides, hashes/copies payloads
in 1 MiB chunks, writes USTAR headers, verifies content and original links,
and publishes with POSIX rename. Duplicate member names fail before writing;
rewrite, verification and publication failures remove `OUT.tar.tmp` and retain
the destination. Source and destination can be the same path.

The system libarchive library only supplies a decompressed raw byte stream
for plain/gzip/bzip2/xz inputs. It does not parse member names, so macOS Unicode
normalization cannot change their spelling. Its declaration-only boundary
follows the [libarchive public header](https://github.com/libarchive/libarchive/blob/v3.7.7/libarchive/archive.h).
The separate Docker archive writer does not depend on this library.

Sparse and unknown tar member types are rejected before publication; the
previous USTAR rewrite did not reliably preserve those extensions. Standard
files, directories, links, devices and FIFOs retain their headers. Malformed
archive and decompression errors use native diagnostics. Error-free CLI output
retains the previous saved-byte calculation and decimal rounding.

```sh
v -cc cc test build-support/tarstream
v -cc cc test build-support/tarlink
v -cc cc -o /tmp/link-duplicate-files build-support/link-duplicate-files.v
VINIX_TARLINK_TOOL=/tmp/link-duplicate-files v -cc cc test build-support/tarlink
```

Native checks cover all eligible prefixes, excluded paths/small files, owner
and mode differences, changed timestamps/names, exact decomposed Unicode,
long first targets, multiple compression formats, PAX/GNU metadata, streaming
and padding boundaries, duplicate names, corrupt content, forward links and
transaction cleanup. System `tar` independently supplies three archive formats
and extracts output to confirm shared inodes and unchanged bytes. These are
host archive checks; they do not establish a guest boot.
