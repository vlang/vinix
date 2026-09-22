# Privileged operation policy

Vinix uses a small part of [SBP's selector-based design](https://github.com/okTurtles/sbp): privileged operations have stable, human-readable `domain/action` names. The kernel's [policy](../kernel/security/policy.v) lists the selectors it recognizes and denies unknown selectors. Syscall handlers check permission before reading userspace arguments or changing system state.

| Selector | Syscall operations | Current rule |
| --- | --- | --- |
| `filesystem/mount` | `mount` | Effective UID 0 |
| `filesystem/unmount` | `umount2` | Effective UID 0 |
| `system/hostname/set` | `sethostname` | Effective UID 0 |
| `system/domainname/set` | `setdomainname` | Effective UID 0 |
| `system/reboot` | `reboot` | Effective UID 0 |

The rule applies to both architecture ABIs where those operations exist. A denied call returns `EPERM`. The AArch64 syscall smoke test drops credentials in a child and checks each denial; it also checks that the host and domain names did not change.

`umount2` still returns `ENOSYS` for an authorized caller because unmounting is not implemented yet.

This policy is a starting point for more specific permissions, not an isolation boundary between processes that still run as root. Vinix currently starts processes with UID 0 and has no separate capabilities or per-process selector grants. Applications that drop their credentials cannot perform the listed operations. The policy does not install or use the JavaScript SBP runtime in the kernel.
