# Native Android application runner

`tests/android/run` compiles this V dispatcher with the maintained compiler
bootstrap. It uses the existing V preparation, VM planning and result policies
through a synchronous native callback. Files, archive streams, manifests,
compiler commands, PTYs, threads, QMP connections and screenshots have native
owners; the command does not start an interpreter.

The original command options and the ten named interactive fixtures remain
available. An interactive session waits for Ctrl-C after readiness, requires
exact optional preflight markers, keeps application functionality unchecked,
makes reused state directories private and never captures a screenshot. The
normal runner preserves input acknowledgement, retries and production timing.
Its reader drains serial while the input worker waits for QMP. Retirement stops
and joins both workers before closing the PTY; the SDK reserves the leader PID
until its private process group is retired and performs the sole reap.

The native QMP monitor keeps arbitrary-width JSON integers, skips events,
prioritizes errors and owns cancellation and the twenty-second socket idle
timeout. PNG screenshots retain framebuffer pixels without Pillow. Explicit
JPEG, BMP, TGA and PPM destinations are also available; other extensions return
an error. Archive preparation streams USTAR data, retains inode hardlinks and
deduplicates equal large payloads. Literal Unix backslashes remain filename
bytes. Failed writers close without successful archive end blocks.

`build-support/roblox/build` stages the two native APK launchers against the
verified shared ART/Bionic/ATL/musl generation. It verifies ELF payloads, exact
file inventory, execute permissions and digests before replacing a previous
stage, and restores that stage after a publication error. Its ten named native
fixtures are available through `tests/roblox/build-test`. The desktop builder
uses native Android and Roblox preflights. ART/musl receipt APIs are also exposed
through the extensionless `build-support/android` commands and `androidtools`.

`desktop/tools/input` exposes the native pointer, text and Cmd-Tab commands.
The legacy Python input entry remains until OpenGothic's importing consumer is
ported. Shared Android interpreter bridges also remain for other consumers;
their presence receives no retirement credit in this stage.

Host qualification uses cold ARM, x86 and ASan/UBSan builds, the ported
interactive and staging fixtures, complete preparation fixtures, actual Unix
socket exchanges, streamed archive and pixel checks, flat descriptor counts
after failed archive owners, and a native mock VM with a real PTY. The mock VM
checks calculator acknowledgements and shifted keys while more than 1.2 MB of
serial drains, generic observation, screenshots and I/O failure cleanup. This
qualification does not establish a fresh Vinix Android or Roblox application
boot.
