The OpenBSD security guest controller uses `securitycore` for pcap frame
extraction, packet-randomness checks, launch arguments, port selection,
process polling and shutdown, serial capture and marker reporting. Its V
query borrows actual Python objects through the shared Package Session ABI.
The original marker thresholds, command-line options and deadlines remain.

Python retains the parser, initial capture state, `pty.fork` child branch,
`chdir`/`execvpe`, and sequential `finally` calls to `stop` and `os.close`.
Small generator and list-comprehension syntax helpers remain counted Python;
V owns their nontrivial predicates and arithmetic. Original recursive
algorithms are unchanged. Each public wrapper supplies its running frame's
builtins table for original global lookup. Fixed names have finite caches.
Named helper values remain with saved exceptions; temporary operands retire
at their original evaluation boundaries.

Other guest controllers import this runner and replace its markers,
`command_for` and `check_capture`. Those public lookups remain live. The
packet parser retains its original permissive truncation behavior.

`VINIX_SECURITY_GUEST_QUERY` selects an existing query; otherwise the shared
host controller builds and installs a private executable. The Package SDK
supports `VINIX_PACKAGE_STORE_LIBRARY` for an existing library. Both default
build paths use `build-support/find-v.sh` and retain compiler diagnostics.

Host, packet and actual PTY-child fixtures validate the controller without
booting a kernel. Actual OpenBSD-security guest validation requires a matching
Vinix kernel/image and the original guest workload. Host fixture passes do
not establish kernel security or QEMU behavior. Private implementation helper
replacement and exact private traceback frames are outside the migration
boundary. Callbacks near CPython's global recursion limit can observe native
bridge stack overhead.
