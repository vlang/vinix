The VNC and Venus test runners and Steam's archive, socket-owner and build
helpers use native V through these entry points:

```sh
build-support/qemu-system/tests/run --state-dir OUTSIDE_CHECKOUT
build-support/venus/tests/run --state-dir OUTSIDE_CHECKOUT
build-support/steam/tar -xf ARCHIVE -C DESTINATION
build-support/steam/lsof -P -F upnR -i TCP@127.0.0.1:PORT
build-support/steam/unpack-deb INSTALLER.deb OUTPUT
build-support/steam/relative-link TARGET LINK
build-support/steam/build-guest --arch aarch64 --static --output ELF
```

The Steam image installs the compiled static guest helper as both `tar` and
`lsof`. The repository entry points compile V directly for host use. Unsupported
tar operations still replace the process with the private GNU tar. Extraction
keeps Steam's original flags, path and link guards, regular-file modes, and
plain/gzip/bzip2/xz/LZMA inputs. GNU and PAX sparse files retain their holes,
logical size and following archive boundaries. Hard-link fallback retains
archive metadata, including fractional PAX modification times. DEB extraction
also restores directory attributes after extracting their children.

The native procfs reader retains Steam's field order, local or remote endpoint
matching, decimal port parsing, Unicode decimal process names, and tolerance
of processes and descriptors disappearing during the scan.

`qualify.v COMPILER NEW_EVIDENCE arm|x86|san` performs five cold builds, the
existing tar reader/writer tests, native archive/procfs fixtures and actual
frozen-C comparisons. The VNC model covers 34 exact protocol, pixel, Xlib and
ownership traces; the Venus model covers 13 device-probe outcomes. On macOS,
the qualifier owns its compiler wrapper and selects ARM or Rosetta x86.

Decoder tests cover large streamed output, nonzero exit, a hanging child,
descendants, failed spawns, closed standard descriptors, SIGINT/SIGTERM, and
exact PID/descriptor retirement. Observation keeps the leader unreaped until
its private process group is retired. `test-buildhelpers.v` covers real
compressed DEB sections and metadata, lexical relative links and custom guest
cache invalidation; the unchanged default guest-builder regression also passes.

Qualification builds real static ARM and x86 Steam helpers and VNC/Venus model
ELFs. It executes no Python or Vinix guest. Host behavior and static linking
are checked; an actual Steam client launch still needs its guest workload.
