# Socket metadata authorization

Opening a bound UNIX socket with `O_PATH` used to give its metadata description
access to the live transport. Socket lookup checked the resource type but ignored
the description's flags. Even with the pathname's mode set to 0000, `listen()`
succeeded through that metadata handle. This violates the limited operations
supported by [Linux O_PATH descriptions](https://man7.org/linux/man-pages/man2/open.2.html).

The shared socket-operation lookup now rejects `O_PATH` with `EBADF`, releasing
its temporary FD/Handle pin once before returning. Ordinary socket operations
retain their existing ownership and cleanup. Collecting `SCM_RIGHTS` payloads
keeps the unrestricted descriptor lookup: metadata handles may be passed through
a real socket. Independent review checked the V source and generated C for both
architectures, including refusal cleanup and queued Handle ownership. The guard
adds no allocations.

The native V fixture runs as UID/GID 1000 with supplementary groups cleared. It
opens metadata while the socket pathname has mode 0000, then checks refusals for
`listen`, `bind`, `connect`, `shutdown`, `getsockname`, `getpeername`, `getsockopt`,
`setsockopt`, `sendto`, `recvfrom`, `sendmsg`, `recvmsg`, `sendmmsg`, `recvmmsg`,
`accept` and `accept4`. Valid buffers exercise the lookups and must retain their
sentinels. A refused option change leaves the listener's keepalive value intact.
Both accept refusals run with a real connection pending; the listener must still
accept it. A metadata descriptor sent as `SCM_RIGHTS` is closed before delivery;
the receiver verifies its socket metadata, `O_PATH` and `FD_CLOEXEC`, and rejects
`listen` through it. The native ancillary payload uses explicit 32-bit integers.

On 14 October 2026 the following results were retained under
`build/development17-20261013`:

| State | Result |
| --- | --- |
| `socketaccess-arm-before-e`, `socketaccess-x86-before-e` | Prior metadata-release kernels accept `listen` through `O_PATH`: site 440 returns 0 and the fixture fails. |
| `socketaccess-arm-after-d`, `socketaccess-x86-after-d` | Persistent ext2 and overlay socket checks pass, including all refusals, descriptor transfer, live connections, hardlinks, moves, remount and permission checks. |
| `socketaccess-arm-all-d`, `socketaccess-x86-all-d` | Existing atomic rename, failure rollback, mixed lifetime, persistence, whiteout and opacity checks pass. |
| `socketaccess-arm-basic-c`, `socketaccess-x86-basic-c` | Disk-free socket authorization probe passes in native Vinix. |
| `socketaccess-arm-linux-b`, `socketaccess-x86-linux-b` | The identical probe ELF from each native run passes on Linux 6.12.51-0-virt. |

Each persistent socket batch performs 32 cycles on direct ext2 and 32 on the
overlay upper; both batches settle for 25 seconds. All 18 ARM slab classes plus
the large count, and all 14 x86 slab classes plus the large count, match between
batches. The mixed lifetime regression also remains flat, with zero writes after
free. All four final volumes pass read-only `e2fsck -f -n`. The global allocation
audit still fails with the same 182 baseline file/kind findings; its allowlist
was not changed.

| Input | SHA-256 |
| --- | --- |
| Fixed ARM kernel | `ab52d4fb0510da9e055a42049e242145ac837370dc06579c6a8d7b59de6e0990` |
| Fixed x86 kernel | `a194f2c90d79f261d2582a821daa482d1a76da37d229e5154f830d3ef5f1a6a7` |
| Operation fixture | `824700d238cc7f5789312e6c720ee7ea2a78a049f17c8fc8b6fbc29636929475` |
| Socket fixture | `d35ddd8796b131e3fe2456490ab9b06265d2ffcab950b7ba63192709ee376136` |
| Core fixture | `6b21e5771d4f42c05ab8de21e803f2e340522d8a6640544c842baf1395bb6cef` |
| Shared ARM native/Linux probe | `f1a6fc821630065a32b0489b720e97d04e588d4a4d7699548d2033e83781c68d` |
| Shared x86 native/Linux probe | `7b3c6902c876eb5e8164af63fae2bf37f746651e06a4115c980e1e9e43e10d71` |
| Linux ARM reference kernel | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| Linux x86 reference kernel | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |

Both Vinix kernels were built in the existing isolated `9b01dbca2` worktrees with
the preceding filesystem/socket fixes and this guard, using preserved V compiler
`f6358ec` and link seed 17. The assertion-enabled V evidence checker verifies
the source and receipt hashes, controls, complete memory samples, native/Linux
probe identity and filesystem checks. It normalizes only the three known
concurrent per-open creation bookkeeping differences in VFS. The checker and
result are `socketaccess-evidence.v` and `socketaccess-evidence-final.log`;
independent review is retained as `socketaccess-lifetime-review.md`.

The Linux reference uses a real device number (1:3) for denied unprivileged
device creation because [Linux exempts 0/0 whiteouts from CAP_MKNOD](https://github.com/torvalds/linux/blob/v6.12/fs/namei.c#L3865).
Vinix disk cases still test their separate 0/0 refusal. Early native ABI
compilation failures, reference attempts using 0/0 and host disk exhaustion
attempts remain separate from completed verdicts. Cleanup reclaimed only
completed owned firmware/image staging; identical immutable kernel copies were
consolidated without changing their paths or bytes.

See [the controller instructions](README.md) to repeat the checks. The Linux
reference qualifies these socket semantics only; it does not measure Vinix
retention. Broader syscall error precedence, power-loss recovery, tracing,
rootless OCI runtime acceptance and complete server qualification remain open.

The subsequent [ordinary pathname-open correction](socket-open.md) extends the
same probe. The fixture hashes above identify this metadata-authorization
qualification; the linked page records the expanded fixture and newer kernels.
