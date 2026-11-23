# PID namespace memfd policy

`/proc/sys/vm/memfd_noexec` reports the effective value in the caller's
active PID namespace. Its mode is `0644`. Writing requires global effective
UID 0 and `CAP_SYS_ADMIN` over the user namespace that owns the active PID
namespace. An inherited descriptor uses the caller's credentials and
PID namespace at the time of each operation. [Linux 6.12.51 PID sysctl](https://github.com/gregkh/linux/blob/v6.12.51/kernel/pid_sysctl.h#L6) [Linux sysctl permissions](https://github.com/gregkh/linux/blob/v6.12.51/fs/proc/proc_sysctl.c#L419)

| Value | `memfd_create` with neither flag | Explicit `MFD_EXEC` |
| --- | --- | --- |
| `0` (initial default) | Executable | Allowed |
| `1` | `MFD_NOEXEC_SEAL` | Allowed |
| `2` | `MFD_NOEXEC_SEAL` | `EACCES` |

Flag validation precedes policy enforcement, which precedes name import.
Explicit `MFD_NOEXEC_SEAL` works at every scope. [Linux 6.12.51 memfd creation](https://github.com/gregkh/linux/blob/v6.12.51/mm/memfd.c#L288)

A child PID namespace starts with its parent's effective value. Its live
effective value is the highest setting along its ancestry. A write below
the ancestor floor returns `EINVAL`. `unshare(CLONE_NEWPID)` selects a
namespace for future children. PID `setns` accepts the caller's active
namespace and its descendants. [Linux 6.12.51 PID namespaces](https://github.com/gregkh/linux/blob/v6.12.51/kernel/pid_namespace.c#L101) [Linux policy inheritance](https://github.com/gregkh/linux/blob/v6.12.51/include/linux/pid_namespace.h#L53)

## Qualification

The same native ELF per architecture passed on Vinix and Linux 6.12.51.
The probe covers flag and name error ordering, initial memfd modes and
seals, integer parsing and offsets, credentials on inherited descriptors,
active versus future PID namespaces, and policy changes while a child
namespace is live. It also creates a nested namespace for future children,
returns to the active namespace with `setns`, and checks that joining an
ancestor fails.

The Vinix kernels were built from `be24c737d` plus the archived patch.
The baseline kernels fail at opening the sysctl. The `memfdcreate`,
`namespace`, `sharedmem`, `userns`, `procns`, and `clonepidguard` regressions
passed on both architectures. The storage cases reached their verdicts
after rerunning with longer timeouts. The allocation checker reported the
same existing failures and the same 306 AArch64 and 254 x86-64 allocation
sites as the baseline.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `6b4ffcf71e85d7ec` | `e96651a48cc051a9` | `55c6c4198eba5811` | `bbdee0feb6cb92d0` |
| x86-64 | `9b28eefe6b1448ca` | `71c871724d274a9d` | `06a2dd471c672d2b` | `8741b05d6490e8e3` |

Hashes are SHA-256 prefixes. The restored and verified archive is
`~/.cache/vinix-r15/memfd-noexec-policy/qualification.tar.zst`, with SHA-256
`2dcf8efedbfe1e827c78d159282273aa6b1d230b2955eda7ec944e89fbb02f3c`.

## Limits

Vinix PID number translation covers one nested level. The policy walks
the full PID namespace ancestry. Credential checks use Vinix's existing
user namespace capability model.
