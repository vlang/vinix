# Native N64 and PS2 core builders

Two native V commands retire **4,990 Python bytes / 142 lines** and the obsolete
borrowed-object query modules:

```sh
build-support/n64/build --output build/n64 --jobs 4
build-support/n64/build --host --output build/n64-host
build-support/ps2/build --output build/ps2 --jobs 4
```

The commands retain the original output, SDK, LLVM, Linux-header and environment
defaults. Invalid options, job counts and build inputs return 2; runtime failures
return 1 and interrupts return 130. Both complete app build scripts now invoke V
for the core, homebrew and frontend, without Python.

The pinned upstream revisions, hashes, user agents and download limits remain
unchanged: 16 MiB for N64/zlib and 8 MiB for Iris. Regular archive members retain
their bytes and executable modes; traversal, absolute/backslash paths, links,
rootless files and members above 16 MiB are rejected. Source replacement uses
an owned private directory. Cached downloads are verified and retained on error.

N64's memory, CPU/RSP-budget and interpreter patches retain their original bytes.
The native builder reads the upstream make manifest, removes lexical `./` from
source paths, and preserves C/C++/zlib object order. Iris selects the same C/C++
sources and excludes the same unused interpreters and renderers. Its path sort
compares components, as pathlib did: `disc/cue.c` precedes `disc.c`.

Compiler commands, header/source/compiler/libc fingerprints and sorted JSON
stamp bytes retain the original format, including array spaces and Unicode
escaping. The strict first-party bridge and native assembly use the direct V
module producer. Archive publication uses the original member order and an
atomic rename. N64 stages the native source, producer and test dependencies,
pinned archives, patch recipe, frontend and homebrew for source distribution.

Workers own separate pipe pairs and process groups, use the caller's directory
only in children and return logs in input order. Every worker is joined before
success or failure returns. The first error in input order becomes the build
log, with the original UTF-8 replacement policy; successful logs remain binary.
Interrupts preserve the prior log and retire children and wrapper descendants.
Only the main thread owns the signal-handler scope.

The process runner closes unrelated descriptors atomically in owned children:
Darwin uses the SDK's `POSIX_SPAWN_CLOEXEC_DEFAULT` and explicit standard-stream
inheritance; Linux uses glibc's child-side closefrom action (glibc 2.34 or newer).
This fixes a measured race between concurrent pipe retirement and spawn action
construction. Existing direct-child APIs retain their previous behavior.

## Qualification (2026-10-11)

- Both commands and the worker checker build from scratch on ARM, Rosetta x86
  and ASan/UBSan. Actual ARM64-musl core builds and cache reuse pass on each.
- The complete newly extracted and patched source trees match the original
  prepared trees. All 162 N64 and 58 Iris compiler commands and cache records
  match the original receipts after remapping the private output directory.
  Iris's receipts predate its V bridge: its current first-party source hashes
  and native-ABI header hash are included, as the original recipe requires.
- Independently replaying the original recipes produces identical objects,
  default-producer bridge objects, ABI assembly and complete ordered archives.
  The original JSON stamp bytes match too. No Python was run as an oracle.
- Both full build scripts successfully link and stage their ARM64 frontends.
  A fresh N64 native-host object/archive build passes the real-ROM boundary
  fixture, including replacement, frames, saves, reset and cleanup.
- Each checker profile runs 384 compiler children with ordered binary logs,
  cache hits and flat descriptor counts. Failure workers are joined; only
  successful objects get stamps. SIGINT retires compiler children and their
  descendants, checked by their actual PIDs.
- The same worker checker passes on ARM Linux/glibc 2.39. V emitted the C on
  macOS and GCC compiled it in the Linux VM; a V helper moved one generated
  constructor attribute before its declarator for GCC compatibility. The
  constructor body and all worker algorithms are unchanged.
- The existing process runner's five test suites pass, and the emulator-input
  checker passes on all three profiles, including all 27 standard-descriptor
  layouts. The shared runner change preserves those contracts.
- Both cold public entrypoints pass from outside the checkout. The staged
  corresponding-source package cold-builds its command and rebuilds the complete
  N64 core and frontend using the declared external compiler and ARM64 musl SDK.
  Its boundary command also passes real-ROM execution with an explicit native
  host build directory and archive.

Sanitizers cover host controllers; the upstream cores and guest executables
are uninstrumented. macOS leak detection is disabled. No kernel was rebuilt
and these checks establish no new guest gameplay or commercial-game result.
Frozen original bytes, independent V recipes, source/cache comparisons and
`core-*.log` are retained under
`~/.cache/vinix-python-zero-process-20261011/`.
