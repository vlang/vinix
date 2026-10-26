# Tarstream skip workspace lifetime

On 2026-10-27, `Reader.skip()` retained its 1 MiB read buffer and padding
allocation after every unread member under `-gc none`. Both buffers now have
deferred frees covering normal completion and read failures. `read()` borrows
the buffer synchronously; neither reader state nor the native input retains it.
The lifetime was independently reviewed before commit.

The retained V probe, `tarstream-skip-check.v`, reuses one descriptor and a
deterministic archive containing a 1 MiB + 513 byte payload. Iterations alternate
unread and partially read payloads. Success checks the next member and its bytes;
two truncated inputs require the body/padding EOF error. Actual reads touch the
allocation, avoiding misleading RSS from untouched zero-filled pages.

The reported runs below were sequential, measured with `/usr/bin/time -l` on
macOS. Figures are maximum resident bytes; all assertions passed.

| Case | Before: 1 skip | Before: 128 skips | Fixed: 1 skip | Fixed: 128 skips |
| --- | ---: | ---: | ---: | ---: |
| Success | 2,785,280 | 139,575,296 | 3,850,240 | 5,750,784 |
| Body EOF | 2,785,280 | 138,035,200 | 2,785,280 | 4,259,840 |
| Padding EOF | 2,785,280 | 139,198,464 | 3,850,240 | 5,324,800 |

This removes the per-member skip workspace growth. Other header/member
allocations remain outside this fix; total process memory is not claimed to be
constant. Before/after inputs have identical SHA-256 hashes for each case.
The full `reader_test.v` suite also passed under `-gc none`, including the new
descriptor test around 512-byte padding and 1 MiB chunk boundaries.

Baseline revision: `4ec35b4b169d6829e4ccf53c1012f2c550970952`.
Fixed reader SHA-256: `73b5beca34cd512f4690fe66b9f06fe152f3193f51b297f5df1d6faf1bffdf6c`.
The compiler was `/Users/alex/code/v-tccbin-bootstrap-20261026/v`, SHA-256
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`.
Probe flags were `-new-compiler -gc none -nocache -cc cc -d tarstream_fd_only`,
with `-path '@vlib|SNAPSHOT/build-support'`; each process received
`1|128 success|body-eof|padding-eof FRESH_DIRECTORY`.
Reader tests used the same flags without `-d tarstream_fd_only` and
`test build-support/tarstream/reader_test.v`. Builds ran one at a time; probe
compilation peaked below 192 MiB and reader test compilation below 159 MiB.

The complete sources, binaries, inputs and raw logs remain outside Git at
`/Users/alex/.local/state/vinix/android/tarstream-skip-check-2026-10-27-r1`.
`serial-*` logs are the reported sequential sweep. The initial sweep's shell
sessions overlapped after yielding; its logs are retained but not used above.
The bundle's `sha256.txt` digest is
`b9be8cc6d5bd96d2a0dce6bfe3978e178eadba2a29b49b5f8fcd8e6702eb565c`.
Its checksum verification passed. No guest boot or Google account login was
performed for this memory fix.
