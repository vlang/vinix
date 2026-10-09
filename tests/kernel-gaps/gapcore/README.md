# Disposable guest controller

`main.v` owns guest compiler commands, private rootfs/image construction,
architecture boot policy and hypervisor forwarding. `pty.v` owns the PTY
read loop, marker decisions, bounded QMP/signal stop and transcript retirement.
The Python entry points retain their argparse interfaces and imported signatures.
`_native.py` binds actual standard-library objects and preserves public helper
lookups, marker/list identity, iterator behavior and exception objects.

This is a host V tool using the normal host GC. The synchronous transport keeps
borrowed objects, callback exceptions, context managers, output and PID/master
owners alive until callbacks complete and the native controller is reaped.
Explicit context exit removes its active owner before calling `__exit__`;
failed entry has no exit, and broken transport unwinds remaining owners afterward.
Only outer boot owns the guest PID and master. Emergency retirement probes
`waitpid` before signaling, preventing a stale PID from being killed after a
caller stop override reaped it. SIGINT is retained as the original exception,
ignored during retirement, and the previous handler is restored afterward.
Saved exceptions remain active during cleanup library calls, preserving
`sys.exc_info()`, exception identity, context chains and cleanup precedence.

The original one-second QMP timeout, three three-second stop phases, 0.05-second
poll, 0.2-second select, absolute boot deadline and two-second marker settling
remain intact. The independent guest fixtures, compiler helper and verdict
assertions are unchanged. Three earlier leaks are deliberately retired: invalid
post-fork timeout/type/overflow errors now stop/reap/close; a final drain error
now best-effort closes its owned master while retaining that error and omitting
the serial write; and an overridden/failed stop cannot leave an owned child
unreaped. Failed child exec prints its traceback and exits the child instead of
running a second controller protocol in the forked interpreter.

The frozen original scope is 11,449 bytes / 234 lines of policy, excluding the
retained argument parsers. The two original frontends total 13,747 bytes; the
maintained frontends plus library/ownership adapter total 14,984 bytes, a signed
Python reduction of **-1,237 bytes**. Shared transport/bindings receive no new
algorithm credit. No language exclusions or vendoring attributes are changed.

Machine-local evidence is in
`/Users/alex/.cache/vinix-python-to-v/kernel-gap-guest-20261008/`:

- ARM64, x86-64 and ASan/UBSan V builds using frozen V 0.5.2
  `6d549c2f095d5e3e97963e55a2ebf1dc2810db46`.
- Each profile passed 58 complete compiler/image/helper controls, 12 stop/QMP
  controls, 29 hypervisor forwarding controls, 123 imported policy controls,
  four signature checks, six real bool/float deadline calls, six saved-error
  frame/precedence controls, and the original 12 independent runner tests.
- Each profile passed three invalid timeout retirement controls, a real public
  stop override with borrowed drain, SIGINT before and during retirement,
  and 100 whole PTY runs with every FD count equal to the starting count.
  An actual missing executable also retained the failed-child verdict and reap.
- Eight synthetic controller failures exercise context entry, suppression,
  cleanup overrides and emergency PID/master recovery on both Python ABIs;
  these are transport faults, not an ASan native-code coverage claim.
- Both cold public installs and six cold CLI controls per ABI passed. The x86
  frozen compiler needs `VFLAGS='-d use_bundled_libgc'`; its default GC linker
  failure is retained as an unaccepted toolchain attempt.
- Frozen and native callers freshly compiled the unchanged hypervisor init and
  passed ARM64 and x86-64 QEMU. Final prebuilt-init runs in fresh state directories
  passed both architectures with the final controller. These use recorded
  prepared kernels, not newly rebuilt kernels. TCG reports hypervisor unavailable;
  no actual nested VMX execution or rendering is claimed.

The immediate/nonfinite timeout fixture retains raw serial output and normalizes
only the echoed `^Ax` monitor input when comparing output: PTY echo can race the
child's `PASS` line. Exit status, markers, child bytes and verdict text remain
asserted. The earlier ordering-only rejection is retained in the evidence.
`qualification.json` records source/input/compiler hashes and each result;
`post-commit.json` records the scoped source commit and committed blob hashes.

The ordinary object bridge is now a maintained V shared library:
`build-support/cpythonhost/gap_d_cpython_gap.c.v`, selected only by
`cpython_gap`. `core_library.v` exposes the shared CPython object ABI; the
lazy loader uses the calling interpreter's public development headers.
`VINIX_KERNEL_GAP_CORE_LIBRARY` selects an explicitly prepared library.
The interface retains actual objects, aliases and exceptions. Function
lookup/calls, argument and keyword iteration, owner IDs, checkpoint/sweep,
wait-status consumption, policy/boot/drain/stop forwarding and recursive
owner-result restoration run in V. Argument-tag syntax, manager registration,
handled-exception replay, POSIX fork, signal masking and emergency retirement
remain in the independently covered Python boundary.

On exceptional returns, the Python boundary owns the original bridge's named
expression references through the saved traceback. The native session consumes
these references into counted syntax frames rather than leaving inactive native
owners. Detached callback and comprehension fixtures verify their destruction
order, including retirement when the actual traceback is cleared. This is a
host object-lifetime contract, not a kernel manual-free claim.

The ordinary bridge removes 4,299 original Python bytes / 84 lines, offset by
its library/syntax boundary for a signed net Python reduction of 745 bytes.
Machine-local evidence for this stage is
`/Users/alex/.cache/vinix-python-to-v/gap-library-core-20261010/`.
The evidence includes original/native call, fork and guardian fixtures, actual
PTY ownership, weak-object/factory/error controls, nested/threaded sessions,
reference counts and cold builds on both interpreter architectures. No new
kernel rebuild, QEMU guest or hardware execution is claimed by this stage.
