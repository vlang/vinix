# Native OpenGothic tools

The maintained OpenGothic builder, Vinix guest runner and KekVM guest-agent
command compile V directly. Desktop pointer and keyboard input uses
[`desktop/tools/input`](../../desktop/tools/input), backed by `androidrun`.

```sh
build-support/opengothic/build --help
tests/opengothic/run --help
tests/opengothic/kekvm-control --help
```

`gamehost` owns pinned checkouts, idempotent patches, six joined download
workers, APK indexes, the original compiler recipe, private runtime/ICD staging,
demo checksum admission and installed-game copying. Layer merges preserve
symlinks; game installation copies follow them, as the original did. Maintained
compiler commands invoke native V fronts.

The guest runner uses `sourcecommand.PtyChild`, which reserves the leader's PID
until its process group is retired and the sole reap completes. Native QMP
connections own their sockets from construction through explicit close. Input
keeps the original menu delay and key timing. Native image code produces the
capture; no host Pillow installation is required. FPS rows retain split-line,
warmup, median, marker and minimum-sample checks.

The guest-agent client opens a fresh connection for each request, retries refused
connections, synchronizes with a cryptographically random 32-bit nonce and
discards delayed replies. It preserves wide IDs, shell command arguments,
captured output/status and 256 KiB transfer chunks. The remote file handle closes
after success, host-file errors, short writes, remote errors and interruption;
cleanup uses the same bounded socket policy while allowing retirement to finish.
Its native base64 decoder preserves the original ASCII/padding policy described
by [CPython's decoder](https://github.com/python/cpython/blob/v3.10.19/Modules/binascii.c).

Qualification runs `test-build.v`, `test-guest.v` and `test-agent.v`, plus the
shared native input and PTY suites. The build suite checks complete controlled
recipes, staged contents, reruns, failures, real tar/curl/Git operations and all
six download workers joining before the first ordered failure is reported.
The guest suite exercises eight complete cases through real PTYs and Unix QMP
sockets: software/accelerated capture, four failure paths and SIGINT/SIGTERM.
The agent suite checks actual socket synchronization, command polling, 600,001
byte transfers, cleanup, malformed/EOF replies, retry, interruption and 100
failed constructor lifetimes. Archive failure cycles also keep descriptors flat.

These are host qualification and controlled VM cases. They do not establish a
new upstream engine build, actual Vinix game rendering or new Venus performance
measurement. Existing captured game results and provenance remain unchanged.
The older borrowed-object V policies remain as historical source and are not
invoked by the maintained commands.
