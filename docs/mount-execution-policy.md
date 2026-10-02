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

The current VFS shares child mounts between bind aliases of an inode. `..`
from a child reached through multiple nested aliases still uses the child's
single recorded parent. Correcting that case needs an owned mount context;
the regression suite does not claim that it is resolved.

`tests/mount-policy/run.sh` exercises the implemented rules on both
architectures, including repeated denied execs measured through slab counters.
