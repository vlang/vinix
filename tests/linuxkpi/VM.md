The disposable LinuxKPI guest workflow is implemented in
`tests/agx-fake-g17/agxhost/linux_guest.v`. V owns fixture compiler arguments,
rootfs and ISO preparation, QEMU arguments, marker selection, panic grace time,
deadlines, polling, final serial validation and guest retirement. The fixed
public marker manifest lives in `linux_guest_data.v`. The Python entrypoint
retains argparse and the original mutable `MARKERS` list; importing its public
constants does not require a V compiler or a running native controller.

`_guest_native.py` provides synchronous stdlib filesystem, archive and process
primitives. It retains the actual Python exceptions, QEMU process and log file
until the native workflow finishes. Controller pipes retire before fallback
guest recovery, and the log closes after the guest has been reaped. Further
SIGINT signals are ignored during retirement and the previous handler is
restored afterward. This prevents repeated interruption from abandoning a
guest during its original five-second terminate-to-kill allowance. Existing
state directories are never overwritten or reused.

Qualification compares twenty-four frozen-original workflows per ARM64,
actual x86-64 caller/controller and ARM ASan/UBSan profile. The checks require
the intended success or error branch, exact stdout/stderr and exceptions,
complete child arguments and environments, identical USTAR bytes and files,
and no surviving guest PID. Controls include normal/default/opt-in guests,
late panics, panic grace time, timeout, terminate-to-kill, marker mutation,
invalid marker types, build failures and missing inputs. Both public constant
imports and CLI parsing retain their cold behavior on both caller ABIs.
Parent-only and process-group SIGINT controls reap their guests; repeated
signals during retirement also finish safely. One hundred repeated complete
workflows return to the exact parent descriptor baseline. Independent lifetime
review passed. Shared AGX and core guest policy checks retain their 9,105 and
8,644 frozen-original comparisons per profile.

Both frozen and native controllers pass an actual default four-CPU x86 QEMU
guest using the same retained kernel, pinned bootloader and newly compiled
independent fixture. The final native source passes again in a new state
directory. This is controller evidence for an explicitly hashed existing
kernel, not a fresh kernel build or full LinuxKPI guest API validation. No
fixture assertion or production timeout was changed. Machine-local evidence
is under `~/.cache/vinix-python-to-v/linuxkpi-guest-20261008/`.
