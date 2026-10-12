`run_vm` invokes the native V controller in `../native-render-tools/renderhost`.
V owns the original host checks, launch arguments, byte transcript, marker
validation, exit status and shutdown. It also owns the scratch directory,
PTY and child setup. The maintained command requires no Python import bridge.

The original 900-second default, 250 ms reads, 128 KiB marker window,
10-second result deadline and 5/2/2-second shutdown phases remain. The child
stays unreaped until its private process group and descriptor are retired.
Signals and capture errors complete cleanup before returning the original
error. A second signal cannot abandon that owner. Unicode stage diagnostics
and arbitrary-width timeout integers use the shared native Unicode 13 parser.

Host control and PTY fixtures exercise the controller without rendering.
An actual GPU test still requires the Apple-silicon macOS host, KekVM QEMU,
matching Vinix kernel/initramfs and the original guest workloads. A host
fixture PASS makes no claim about QEMU rendering or native AGX firmware.
The historical `virglcore` object-query implementation remains separately
available for protocol compatibility; it is outside the maintained native CLI.
