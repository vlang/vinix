# pidfd_getfd(2)

pidfd_getfd was vacant and returned ENOSYS on both architectures. systemd,
container runtimes and debuggers use it to take a copy of another process's
descriptor. `syscall_pidfd_getfd` in `kernel/userland/pidfd.v` implements it
on AArch64 and x86-64 (438), with `file.fdnum_receive` installing the copy.

## Semantics

- `flags` must be 0 (EINVAL, checked first). The pidfd must be an open pidfd
  (EBADF otherwise). Arguments are C ints: the low 32 bits of each register;
  a negative target descriptor is a huge unsigned one, which no table has.
- A reaped process is ESRCH.
- The caller needs ptrace's `PTRACE_MODE_ATTACH_REALCREDS` access. Vinix has
  no Yama, so this is the credential, capability and dumpability check that
  `READ_REALCREDS` makes (`proc.may_inspect_realcreds_locked`); permission is
  checked before the target descriptor and before an exited, unreaped
  process is reported as ESRCH, as Linux reports a task whose descriptors are
  gone; an unprivileged caller gets EPERM for another user's zombie.
- A missing target descriptor is EBADF. O_PATH descriptors are copied too.
- The copy is a new descriptor in the caller, the lowest free number, with
  `FD_CLOEXEC` set and the open-file description (offset and status flags)
  shared. A full table is EMFILE.

The target's descriptor table is read as kcmp reads it: under the process
table lock, with its descriptor lock only tried, taking references on the
descriptor and its description before either lock is released. An
independent review found the final reference's release could replace the
errno of a failed install and that the exiting check preceded permission;
both were fixed before commit.

## Qualification

`tests/linux-compat/run --cases pidfdgetfd` boots `pidfdgetfdfixture` as
init. It checks self copies (shared description, close-on-exec, shared status
flags, upper argument words, O_PATH), every error and its order, EMFILE,
data read through a pipe end taken from a child, an unreaped and a reaped
child, and, as UID 1000, EPERM against root before the descriptor check and
success against its own child. `syscall-reference.v --case pidfdgetfd` boots
the same ELF on Linux 6.12.51.

Source revision: the commit that adds this file. Kernels: `PROD=true`,
`LIMINE_MP=1`.

| Run | Result | Probe ELF | Kernel | Serial log |
| --- | --- | --- | --- | --- |
| Vinix AArch64 | 20 + 3 checks, 0 failures | `316d1c89958ad4b9` | `55f2f2e361d3dbfb` | `55a52a5f2d59db67` |
| Linux AArch64 6.12.51 | 20 + 3 checks, 0 failures | `316d1c89958ad4b9` | `c8d8cdec004d4259` | `5b5df9a6cc66f414` |
| Vinix x86-64 | 20 + 3 checks, 0 failures | `1917c8c47ba8b310` | `f641c61da8a563a6` | `75c5502563524010` |
| Linux x86-64 6.12.51 | 20 + 3 checks, 0 failures | `1917c8c47ba8b310` | `ec9073e710b26f59` | `2a1e8a85690b7b1d` |

Hashes are SHA-256 prefixes. Bundles are kept outside Git in
`~/.cache/vinix-r15/runs/getfd-{arm,x86}-1` and `getfd-{arm,x86}-linux-1`.

## Limits

- Yama's ptrace scopes are not modelled: a same-uid, dumpable process that is
  not an ancestor is allowed, as with Yama scope 0.
- The socket cgroup and netprio updates Linux's `receive_fd` makes do not
  apply.
