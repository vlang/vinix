# Execution and device mount policy

An empty-path `execveat` of a valid script returns `ENOENT` when its descriptor
has `FD_CLOEXEC`, before starting the interpreter. Native ELF execution still
accepts the descriptor and closes it in the new image. Clearing the flag
allows script execution. See [the close-on-exec checks](../tests/mount-lifecycle/exec-cloexec.md).

`execveat` reads `dirfd` as a signed 32-bit C `int`, including for empty-path
execution. Unused upper register bits cannot change the selected descriptor
or the `/proc/self/fd/N` name passed to a script interpreter. Absolute paths
still ignore `dirfd`. See [the descriptor ABI checks](../tests/mount-lifecycle/exec-fd.md).

`execveat` accepts only `AT_EMPTY_PATH` and `AT_SYMLINK_NOFOLLOW` in the low
32 bits of its flags argument. Unsupported bits return `EINVAL`; unused upper
register bits are ignored. A final symlink left unfollowed returns `ELOOP`,
including a symlink held with `O_PATH`. Intermediate symlinks can still be
followed. See [the execveat checks](../tests/mount-lifecycle/exec-flags.md).

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

An installed runtime can instead receive its own read-only executable mount.
For example, an administrator can approve the packaged Firefox ELF directory:

```sh
mount --bind /usr/lib/firefox-esr /usr/lib/firefox-esr
mount -o remount,bind,ro,nosuid,nodev,wxallowed /usr/lib/firefox-esr
```

An ordinary user then launches the approved ELF directly:

```sh
VINIX_ALLOW_WX=1 /usr/lib/firefox-esr/firefox-esr
```

The `/usr/bin` shell wrapper is outside this approval. Helpers must execute
through approved mounts too. Keep the runtime directory administrator-owned;
`nosuid` preserves ordinary effective credentials. For a complete OpenJDK 21,
the corresponding directory is `/usr/lib/jvm/java-21-openjdk`, and the direct
entry points are its `bin/java`, `bin/javac` and `bin/jar`.

Revocation removes `wxallowed` while preserving the restrictions:

```sh
mount -o remount,bind,ro,nosuid,nodev /usr/lib/firefox-esr
```

Unmount the self-bind before an administrator updates or removes the package,
then approve the resulting installed runtime explicitly. The qualification
controller's `--jit-runtimes` option performs the scoped setup in a disposable
guest; it does not persist a production administrator's approval across boots.

Bind mounts inherit the source policy and can be remounted independently. A
remount without `wxallowed` revokes the exception for future launches through
that mount; running processes retain their exec decision. The current option
is visible in `/proc/<pid>/mounts` and `/proc/<pid>/mountinfo`. Scripts and
architecture translators validate each requested executable before handing
execution to the next image, so an authorized interpreter cannot authorize
an unauthorized original program. An unprivileged script or translated
program requesting the exception therefore needs `wxallowed` on every mount
carrying an executable in that chain, including its interpreter or translator.

Empty-path `execveat` with `AT_EMPTY_PATH` checks both `noexec` and
`wxallowed` on the descriptor's actual saved mount. Remounting a namespace
copy cannot grant or revoke that inherited descriptor's authority. Fresh
descriptions and ordinary pathname requests use the current namespace's
attachment. To revoke future launches through a saved description, revoke
approval on its actual attachment. Script interpreters still undergo their
own pathname checks. The [descriptor W^X tests](../tests/mount-lifecycle/descriptor-wx.md)
cover approval, denial and the resulting mapping permissions.

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
