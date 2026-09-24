# Privileged operation policy

Vinix uses a small part of [SBP's selector-based design](https://github.com/okTurtles/sbp): privileged operations have stable, human-readable `domain/action` names. The kernel's [policy](../kernel/security/policy.v) lists the selectors it recognizes and denies unknown selectors. Syscall handlers check permission before reading userspace arguments or changing system state.

| Selector | Syscall operations | Current rule |
| --- | --- | --- |
| `filesystem/mount` | `mount` | Effective UID 0 and `CAP_SYS_ADMIN` |
| `filesystem/unmount` | `umount2` | Effective UID 0 and `CAP_SYS_ADMIN` |
| `system/hostname/set` | `sethostname` | Effective UID 0 and `CAP_SYS_ADMIN` |
| `system/domainname/set` | `setdomainname` | Effective UID 0 and `CAP_SYS_ADMIN` |
| `system/reboot` | `reboot` | Effective UID 0 and `CAP_SYS_BOOT` |

The rule applies to both architecture ABIs where those operations exist. A denied call returns `EPERM`. The AArch64 syscall smoke test checks full and effective-only privilege drops, invalid userspace pointers, authorized calls with a nonzero real UID, and unchanged host and domain names after denials.

`tests/security-policy/run.sh` exercises the production allowlist with a controlled credential source, including unknown selectors presented by an effective-root caller and a root caller whose capability was dropped, as a container runtime does.

For `mount` and `umount2`, authorization precedes all argument reads. Authorized calls copy the source, target, and filesystem type from userspace into bounded kernel-owned strings, checking each mapped page and requiring a NUL byte within 4096 bytes. Invalid pointers return `EFAULT`; unterminated strings return `ENAMETOOLONG`. A NULL source or target is an invalid pointer. The filesystem type may be NULL, as on Linux, for a remount, bind, move, or propagation change. This keeps a root caller's bad pointer from becoming an unchecked kernel dereference.

The AArch64 Linux ABI and the amd64 native ABI map mount and unmount directly to the shared VFS syscall handlers. The current amd64 Linux compatibility table leaves those syscall numbers vacant, returning `ENOSYS`. Kernel boot and storage code uses `mount_at_root()` with kernel-created arguments; it is not a userspace entry path.

For an authorized caller, `umount2` detaches the mount at its target, and returns `EINVAL` when nothing is mounted there.

This policy is a starting point for more specific permissions, not an isolation boundary between processes that still run as root. Vinix currently starts processes with UID 0 and every capability; the capability sets are what let a container runtime take some of them away. There are no per-process selector grants. Applications that drop their credentials cannot perform the listed operations. The policy does not install or use the JavaScript SBP runtime in the kernel.

## Desktop selector worlds

The desktop compositor has a separate selector boundary for pointer actions. It records whether each hit target came from compositor UI or a decoded application tree. The compositor interprets its own selectors only for compositor targets; application selectors are opaque and are routed to the app window under the pointer through that app's RPC pipe. An app can use any action name, including one that resembles a window or Start-menu command, without gaining that command. This is a per-application dynamic fallback similar to SBP's star selector, not a shared global selector registry. The optional `vinix-desktop --trace-selectors` switch logs routed pointer selectors with their world for runtime inspection.

The compositor has narrow, explicit bridges to the Files context menu and Capture service. Other application selectors do not trigger desktop commands. This boundary applies to desktop UI actions; it does not mediate arbitrary system calls or provide per-process capabilities.
