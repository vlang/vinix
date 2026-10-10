The guest controller uses `virglcore` for host checks, launch arguments,
serial capture, marker validation, exit status and process shutdown. Its V
query borrows actual Python objects through the shared Package Session ABI.
It keeps the public command line, regular expressions, markers and deadlines.

Python retains the `TemporaryDirectory` owner, the `pty.fork` child branch,
`chdir`/`execve`, capture initialization and the sequential `finally` cleanup.
The query has finished before the actual fork. Named values live in private
state dictionaries across calls; failed helper locals live with the saved
exception traceback. Temporary targets and operands retire at their original
expression boundaries. Fixed attribute names and literals have finite caches.

`VINIX_VIRGL_GUEST_QUERY` can select a prebuilt query; otherwise the shared host
controller builds and installs a private executable. The Package SDK supports
`VINIX_PACKAGE_STORE_LIBRARY` for an existing library. Both build paths use
`build-support/find-v.sh` and retain the compiler diagnostics.

Host control and PTY fixtures exercise the controller without rendering.
An actual GPU test still requires the Apple-silicon macOS host, KekVM QEMU,
matching Vinix kernel/initramfs and the original guest workloads. A host
fixture PASS makes no claim about QEMU rendering or native AGX firmware.
Private implementation helper replacement and exact private traceback frames
are outside the migration boundary. Callbacks near CPython's global recursion
limit can observe the native bridge overhead.
