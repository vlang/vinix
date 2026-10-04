# Vinix mandatory filesystem domains

`vinix-mac` installs a bounded filesystem access matrix, gives inodes type labels,
seals that configuration for the boot and launches a process in a domain. A
confined process remains subject to the matrix as UID 0 with full capabilities.
The feature is separate from pledge/unveil and ordinary Unix mode bits; all
applicable checks must allow an operation.

Build `mac.c` as a normal static userspace utility. The private Vinix ABI is
`prctl(0x56584d41, command, domain, type, permissions)`; it is not Linux's LSM ABI.
Domains are 1–15; domain 0 is trusted administration. Types 0–28 are canonical
decimal `security.vinix` xattrs on tmpfs/ext2. Type 0 means an absent label. Type
29 describes anonymous pipes/sockets, 30 devices, and 31 other kernel resources.
Unsupported inode backends receive type 31 rather than an unrestricted label.
Raw block devices and mutation of kernel control resources are always denied to
confined domains. Granting character-device access authorizes that device class;
profiles must grant it only when the program needs and trusts those interfaces.

For example, before starting the application:

```sh
vinix-mac label 1 /srv/example
vinix-mac rule 1 0 inspect,read,execute,search
vinix-mac rule 1 1 inspect,read,write,execute,search,create,remove,metadata,ioctl
vinix-mac rule 1 29 inspect,read,write,ioctl
vinix-mac rule 1 30 inspect,read,write,ioctl
vinix-mac rule 1 31 inspect,read,search
vinix-mac seal
vinix-mac run 1 /usr/bin/example
```

Label existing children individually before sealing: labeling a directory does
not recursively relabel files already in it. New regular files, directories and
symlinks inherit the parent type before the kernel publishes their names.
Hardlinks keep the inode type; overlay copy-up preserves xattrs. `search` grants
directory traversal, independently of `execute` for programs/file mappings.
`inspect` covers inode metadata, `metadata` its modification, `create` directory
entry creation and `remove` deletion. Every omitted matrix entry denies access.

Rule installation and manual label changes require domain 0, effective UID 0,
CAP_MAC_ADMIN (34) and the initial user namespace. After `seal`, neither rules nor
manual labels can change, including for trusted root. Administrative recovery
requires reboot. A domain can activate only after sealing and on a successful
exec; fork and later exec retain it, and it cannot transition back to domain 0.
A failed exec retains the previous active domain. The loader checks its program,
shebang interpreter, ELF interpreter and ARM translation helper using the staged
domain. A launcher must be single-threaded when staging.

Reads, writes, positioned I/O, transfer calls, truncation, metadata/xattrs,
ioctls, path access, shared mapping writes and executable mappings are mediated.
Checks use underlying objects on each operation, including inherited, duplicated
or SCM_RIGHTS descriptors and path aliases. Mapping protection ceilings survive
mprotect/fork/remap. Exec discards old mappings before the new domain runs.
Confined processes cannot inspect or signal a different domain through root
capabilities, administer mounts/host controls, or manufacture devices. Inotify
instances from a different domain cannot disclose earlier privileged watches.

This is an initial filesystem/domain policy, not SELinux or AppArmor parity.
It does not supply network policy, general IPC mediation, information-flow
control, policy-language tooling or a general persistent MAC audit stream. The
kernel starts in trusted domain 0 and installs no production profile itself;
trusted boot policy/launchers must load the intended labels and rules and fail if
any operation fails. Protect that policy and its boot/root artifacts with the
verified-boot/root deployment. A malicious trusted administrator can deliberately
send file contents through an allowed IPC channel; this is not information-flow
isolation. Offline modification of an unverified filesystem can alter labels.

Guest regression: `tests/security-mac/test.c` exercises root confinement,
namespace authority, frozen labels/rules, descriptors and aliases, mapping
ceilings, transfers, process access, inheritance/exec and retained allocations.
