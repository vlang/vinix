# NFSv3 client (Mission 17-B)

`kernel/fs/nfs.v` implements the VFS facade in module `fs`. The independent
`kernel/fs/nfs/` wire/options module has no `fs` import. No generic callback,
lookup dispatcher or Handle ABI change is required. Registration is
`filesystems['nfs'] = &NFSFS{}` in `fs.initialise()`.

## Mounts

Sources: `10.0.2.2:/export/share` or `fecv3:/export/share`. Hostnames resolve
only through `/etc/hosts`, read via VFS and Resource.read with a borrowed stack
Handle. No DNS exists in v1. Guest hosts must include `10.0.2.2 fecv3`.
Numeric IPv4 needs no hosts file. Unknown names return ENOENT; malformed sources
return EINVAL. Aliases match exactly and case-sensitively; comments/whitespace
are supported, IPv6 lines ignored and conflicting IPv4 mappings rejected.
Bounds: 16 KiB hosts file, 1024-byte lines, 253-byte tokens/hostnames, 63-byte
labels, 1024-byte export path. Oversized input fails closed. A hosts file on
this NFS backend is rejected to prevent recursive resolution.

Options: `ro`/`rw`, `soft`/`hard`, `rsize=512..65536`, `wsize=512..65536`,
`vers=3` (or `nfsvers=3`), `proto=tcp`, `sec=sys`. Defaults: rw, hard, 65536-byte
I/O. Duplicates, contradictions, unsupported values and overflow fail. Local ro,
including initial MS_RDONLY, is a strict backend invariant across aliases.
RW remount cannot relax it: a fresh mount instance is required in v1.

Linux ACCESS can omit MODIFY/EXTEND on an RO export. The facade does not reject
write-open on that advisory basis. VFS modes and actual server READ/WRITE govern
access. With mount flags 0, a writable-mode file on an RO export reaches WRITE
and maps NFS3ERR_ROFS to EROFS. A production-facade regression covers this and
strict local ro.

## Namespace and lifetime

Existing permission snapshots run during every traversal, including for root.
They GETATTR files and GETATTR plus READDIRPLUS directories; directory open also
refreshes. Reads refresh attributes and fetch data without a content/page cache.
Host edits, growth, truncation and fresh pathname opens therefore see the server.
Search requires enumeration permission: search-only directories fail closed,
as in the bounded SMB design. Unsupported special files/symlinks are omitted.

Optional directory handles/attributes use LOOKUP/GETATTR fallback; ENOENT/ESTALE
from a vanished fallback entry is skipped. Reuse requires matching handle and
fileid. Replacement/deletion checks the actual map pointer under children_lock
before removal, marks old node/resource removed and retains them. Open handles
are never retargeted. Identity checks compare pointer addresses, not recursive
V struct/interface equality. A server-reported regular/directory type change
on an existing handle poisons the session before changing its node's type.
Only a completed scan sweeps unseen children; partial
scans fail, but earlier pages may already have published updates. Concurrent
mutation is not a transactional snapshot.

Readdir uses the existing VFS per-description snapshot. Rewind on an already
open description does not promise a fresh remote listing; reopen for freshness.
Bind aliases, cwd, detached roots and mount-root `..` retain existing VFS
semantics. Removed-directory traversal fails closed. This is not a claim of
full POSIX coherence or cross-client atomicity.

At most **4 successful independent mounts per boot** and **512 resources per
mount**, including the root, detached/poisoned sessions and retired nodes, are
retained. A directory also owns at most two dot redirects. Failed unpublished
mounts release reservation and all private allocations. Published nodes use
the existing permanent `mount_covered` pin (same as SMB); generic orphan teardown
cannot free registry pointers. Resource unref never reclaims/recycles storage.
Host identity churn eventually returns ENOSPC; a fifth independent mount returns
ENOSPC until reboot. Unchanged refreshes allocate no new resources. Each mount
owns three reusable ~68 KiB buffers and a 4096-cookie buffer plus bounded node
storage. This is bounded boot retention, not session-churn reclamation.

Unmount sends UMNT best effort on a temporary stream while preserving the live
NFS backend for aliases/open descriptions. Poisoned sessions detach locally.
UMNT is not a final-owner event; successful backend storage is never freed.
VFS-owned mount/create names are adopted, and VFS creates their dots. Borrowed
enumeration names are cloned once; only enumerated directories get facade dots.

## Protocol and limitations

AUTH_SYS uses current caller euid/egid and at most 16 supplementary groups on
every operation. Credentials are copied under the process-table lock, which is
released before network I/O; concurrent setgroups cannot free the array during
that copy. Inherited/shared FDs and credential changes use the current
caller, not opener credentials; v1 has no per-open credential snapshot. Trust
the server/network: no server authentication, TLS, encryption, integrity,
signing or Kerberos. Ephemeral ports require exports to admit them (Linux
`insecure`). Client code never changes server configuration.

Portmapper v2 GETPORT discovers NFSv3/mountd v3 TCP ports; no UDP fallback.
Both soft/hard are bounded: at most two five-second connection attempts and one
absolute five-second deadline per RPC. No request replay after uncertain
delivery. Timeout, framing/XDR or identity failure poisons the session; later
calls fail promptly. A timed-out mutation may have happened; inspect before retry.

Implemented: NULL, GETATTR, SETATTR, LOOKUP, ACCESS, READ, WRITE, CREATE(GUARDED),
MKDIR, REMOVE, RMDIR, RENAME, READDIRPLUS, FSSTAT, PATHCONF; GETPORT; MNT, UMNT,
EXPORT. MNT denial logs bounded EXPORT diagnostics when permitted. Symlinks,
READLINK, hard links, special-file creation and mmap are unsupported. Chunked
WRITE requests/requires FILE_SYNC, so fsync has no buffered data. Append refreshes
EOF and serializes this client; cross-client atomic append is unavailable.

Wire views allocate nothing. Records: 69632 bytes/128 fragments; handles: 1..64
bytes; names: 255 bytes; valid nanoseconds and signed-offset sizes required.
XDR checks padding, discriminants, union arms, exhaustion, xid/RPC/auth identity.
READDIRPLUS accepts opaque high/decreasing cookies but rejects zero/repeated/
cyclic cookies, changed verifiers, empty non-EOF pages and excessive scans.
Scans have a 4096-cookie bound; materialized identities have the stricter lifetime
512-resource cap.

## Verification

```sh
export V=/absolute/path/to/v
export VEXE="$V"
export NFS_SCRATCH=/absolute/path/to/writable/scratch
"$V" run tests/nfs/protocol .
```

The V runner uses NFS_SCRATCH, or the platform temporary directory. It runs production hostile
wire/parser fixtures, generates Linux C, and compiles/runs the production root
facade with narrow kernel-service fixtures, actual FileSystem/Resource interface
declarations and actual Stat. It scans C for hidden allocations in 15 hot
functions. This verifies contracts and controlled behavior, not kernel TCP/VFS
runtime. Optional `--kernel` is diagnostic: local V 0.5.2 rejects existing global
function-pointer initializer syntax before full kernel checking.

Full architecture builds and the disposable real-server QEMU qualification are
separate from these host fixtures; see tests/nfs/README.md. Record their actual
results separately. Do not infer kernel TCP/VFS behavior, allocation-churn
measurements or alias/detached-root qualification from host fixture success.
