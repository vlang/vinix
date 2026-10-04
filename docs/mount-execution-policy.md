# Execution and device mount policy

`noexec` rejects executable images, scripts and ELF interpreters with `EACCES`.
Executable file mappings return `EPERM`; a mapping first made without execute
permission through that mount cannot gain it through `mprotect`, even after
splitting, fork or `mremap`. `nodev` rejects character and block device opens
with `EACCES`, while `O_PATH` can still name them. Open descriptions and working
directories retain the mount used to reach them, so a restricted bind alias
does not change another alias's policy.

W^X is the default. `VINIX_ALLOW_WX=1` remains an explicit compatibility request,
but the kernel accepts it only from an effective-root launcher holding
`CAP_SYS_ADMIN` in the initial user namespace, or for an executable reached
through a mount that an administrator marked `wxallowed`. An unauthorized request fails exec with
`EPERM`. Neither an environment variable alone nor setuid executable ownership
grants an exception. Existing root compatibility launchers keep their request.

For an unprivileged compatibility program, an administrator can set
`wxallowed` when mounting its executable filesystem, or when remounting it:

```sh
mount -t tmpfs -o wxallowed tmpfs /compat
mount -o remount,wxallowed /compat
VINIX_ALLOW_WX=1 /compat/program
```

Bind mounts inherit the source policy and can be remounted independently. A
remount without `wxallowed` revokes the exception for future launches through
that mount; running processes retain their exec decision. The current option
is visible in `/proc/<pid>/mounts` and `/proc/<pid>/mountinfo`. Scripts and
architecture translators validate each requested executable before handing
execution to the next image, so an authorized interpreter cannot authorize
an unauthorized original program. An unprivileged script or translated
program requesting the exception therefore needs `wxallowed` on every mount
carrying an executable in that chain, including its interpreter or translator.

Nested shared child mounts retain the actual alias route used to enter them,
so `..` restores that alias's policy. Open descriptions and filesystem state
store a bounded context inline; namespace copies resolve its mount identities
by stable ID, and moves rebase held descriptors and cwd to the new attachment.
Each context holds at most 64 mount entries (1032 bytes on both architectures).
A path exceeding that bound fails with `ELOOP`. Path walks use one stack cursor
shared across recursive link resolution, with no allocated view cache.
Filesystem state and mount attachment snapshots serialize node/context pairs
so concurrent cwd, chroot and move operations cannot mix their policy.

A relative `#!` interpreter name resolves from the caller's current working
directory, including when `execveat` reaches the script through another
directory descriptor. This follows the Linux ABI; older Vinix versions used
the descriptor's directory in that case. The interpreter's actual cwd mount
route receives the same execution and W^X checks as other executable images.

`tests/mount-policy/run.sh` exercises the implemented rules on both
architectures, including repeated denied execs measured through slab counters.
