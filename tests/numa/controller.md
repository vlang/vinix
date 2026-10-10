# NUMA guest controller

`numacore` owns environment and QEMU argument policy, exit-status conversion,
timed capture, shutdown escalation, and result reporting. It borrows the live
Python namespace, the public caller's actual builtins table, and operands through
the shared Package Session ABI. Fixed source constants use the module's finite
literal cache; dynamic caller values are never put in that cache.

Python retains argument parsing, the eager public marker/topology constants,
the socket owner, PTY fork/chdir/exec, and the original ordered `finally` cleanup.
Marker comprehensions and the failure generator remain counted Python syntax.
After fork, environment, command, PID and PTY descriptor ownership transfers to
the private state in the original named-local order; duplicate bridge references
retire before capture, so the transcript retires after those owners.
The generator closes over the genuine `recent` cell, so a caller that retains
it observes later transcript assignments. Original named locals survive saved
callback errors in the entry frame's private pins; the Session consumes its
private error slots after transport and descriptor cleanup.

Controller qualification compares the independent original implementation with
actual Python operands, errors, stdio, and PTY children. It does not establish a
fresh kernel build, QEMU boot, or physical NUMA behavior. Private bridge traceback
frames differ. Arbitrary external callbacks precisely at a Python recursion
budget are outside the qualified scope; no maintained recursive algorithm is
moved to a different frame.
