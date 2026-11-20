# Filesystem ids: setfsuid(2) and setfsgid(2)

setfsuid and setfsgid were vacant (ENOSYS) on both architectures, and Vinix
had no filesystem ids: file permission checks and new files' owners used the
effective ids. File servers (Samba, NFS servers) and some setuid programs use
the filesystem ids to act for another user on files only.

## Semantics

Established with an exploratory probe on Linux 6.12.51 and checked by the
final probe.

- `Process.fsuid` and `fsgid` (`kernel/proc/fsuid.v`) follow the effective
  ids: every successful setuid, setreuid and setresuid call (and the gid
  calls) sets them to the new effective ids, even when those did not change,
  except a setresuid/setresgid that changes nothing, the filesystem id
  included, which Linux treats as a no-op. Fork copies them.
- setfsuid (AArch64 151, x86-64 122) and setfsgid (152, 123) take the low 32
  bits and always return the previous id. -1 only queries. The new id must be
  the real, effective, saved or current filesystem id, or the caller needs
  CAP_SETUID/CAP_SETGID; otherwise nothing changes.
- Leaving filesystem uid 0 drops CAP_CHOWN, DAC_OVERRIDE, DAC_READ_SEARCH,
  FOWNER, FSETID, LINUX_IMMUTABLE, MKNOD and MAC_OVERRIDE from the effective
  set; returning to 0 restores them from the permitted set, unless
  SECBIT_NO_SETUID_FIXUP is set. Any change makes the process undumpable.
- File permission checks (`fs/permissions.v`: access, removal, ownership,
  chmod/chown rights, links) and the owners of new files and memfds use the
  filesystem ids; `/proc/<pid>/status` shows them as the fourth Uid/Gid
  column. access(2) still uses the real ids.

## Qualification

`tests/linux-compat/run --cases fsuid` boots `fsuidfixture` as init. As
root it checks queries, results, argument words, the status columns, the
capability drop and restore, access and new-file owners by filesystem ids,
and dumpability; as a process with real/effective/saved ids 1000/1001/1002
it checks every permitted and refused id, file access by the filesystem uid
rather than the effective one, the ids following setresuid and setreuid, and
both sides of the setresuid/setresgid no-op rule. `syscall-reference.v --case
fsuid` boots the same ELF on Linux 6.12.51; its first run showed the no-op
rule, which the kernel then adopted.

Source revision: the commit that adds this file. Kernels: `PROD=true`,
`LIMINE_MP=1`.

| Run | Result | Probe ELF | Kernel | Serial log |
| --- | --- | --- | --- | --- |
| Vinix AArch64 | 20 + 22 checks, 0 failures | `aa0b75d159b59a8e` | `99749ce74431c78c` | `0df017ed5c75351d` |
| Linux AArch64 6.12.51 | 20 + 22 checks, 0 failures | `aa0b75d159b59a8e` | `c8d8cdec004d4259` | `2182cc355cc41ec8` |
| Vinix x86-64 | 20 + 22 checks, 0 failures | `7e3c2de88edba82f` | `a4bd91e2e74d891c` | `27e2d7eeb181f484` |
| Linux x86-64 6.12.51 | 20 + 22 checks, 0 failures | `7e3c2de88edba82f` | `ec9073e710b26f59` | `6e35cdab52bf22ef` |

After rebasing onto the signal-sender change, the unchanged probe passed again
on the combined kernels (AArch64 `17f5c19ae1bc0cce`, x86-64 `1bb45c40227ef313`), together with the
access, accessflags, open, capset, keepcaps, securebits, ambient and capbset
cases on AArch64 and access, capset and keepcaps on x86-64 (`fsuidreg-{arm,x86}-1`).

Hashes are SHA-256 prefixes. Bundles are kept outside Git in
`~/.cache/vinix-r15/runs/fsuid-{arm,x86}-1` and `fsuid-{arm,x86}-linux-1`;
the exploratory log is `~/.cache/vinix-r15/explore/fsuidx-arm-1`
(`70f7ff5caa16e568`).

## Limits

- Linux keeps credentials, the filesystem ids included, per thread; Vinix
  keeps them per process, so one thread's setfsuid applies to its siblings.
- NFS, SMB and 9P mounts still take their session credentials from the
  effective ids at mount time.
