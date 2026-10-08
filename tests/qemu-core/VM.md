The core guest controller now owns launch arguments and environments, exact
feature and failure markers, PTY reads, shutdown deadlines, child retirement
and the persistence reboot sequence in V. It reuses the reviewed AGX host SDK.
The Python frontend retains argparse, its import signatures and public byte
constants. Its child binding calls only the original chdir/execve or execvp
primitives. The inherited amd64 environment uses execvp throughout; ARM keeps
its explicit environment overrides. Buffered, unbuffered and terminal stdout
retain the original ordering of text and guest bytes.

All argument and environment strings remain owned through fork and exec. A
master descriptor closes only after its child has been stopped and reaped.
A first SIGINT aborts the loop; further interrupts are ignored during retirement
and the previous handlers are restored. As with the AGX controller, an invalid
or overflowing timeout also retires a child that the original deadline addition
could abandon before entering try/finally. Cleanup error precedence is retained.

Qualification compares 8,644 frozen-original result policies per ARM, Rosetta
x86 and ARM ASan profile, seventeen actual PTY flows, thirteen CLI/path cases,
and twenty-two environment, stdout, timeout and interruption cases. Native
units exercise one hundred fork/argv/environment/master lifetimes against an
exact descriptor baseline. The original five-second unit deadline remains;
one ASan attempt missed startup under parallel compilation and passed when
rerun unchanged in isolation. Cold installation and missing-compiler failure
retire their private directories on both caller architectures. The shared
controller also passes all 9,105 existing AGX policy comparisons per profile.

Actual ARM QEMU runs with the frozen and native controllers pass all feature
markers and persistence verification across reboot using identical retained
init and initramfs inputs. Both controllers also pass the amd64 guest with the
same ISO, existing kernel and firmware. Two earlier native amd64 attempts hit
the untouched first-touch free-memory assertion; those attempts are retained
in the evidence. These boots use explicitly hashed existing kernels and newly
compiled independent fixtures, and are not fresh kernel-build evidence. No
fixture assertion or production timeout was changed.
