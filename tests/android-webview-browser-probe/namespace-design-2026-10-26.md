# User and network namespace implementation design — 2026-10-26

This is a static follow-up to [the production sandbox audit](sandbox-audit-2026-10-26.md),
not a qualification result. The reviewed repository revision is
`6a3b2c99641295bf7547143745783f1c8dc627c7`; its kernel paths were unchanged at
`082abeec82156361467cdfda952ec3e57fe92066`. No kernel changes, builds or guest
runs were performed for this design. Google account login remains unverified.
Keep `CLONE_NEWUSER` and `CLONE_NEWNET` rejected until their implementation
passes the gates below; accepting flags or returning successful netlink ACKs
without isolation does not implement the sandbox.

## Production requirements

The pinned WebKitGTK 2.48.1 launcher and bubblewrap 0.13.0 sources, their hashes,
and the original frozen-kernel bundle are recorded in the linked audit. They
are distinct from the repository revision reviewed here. The production
launcher uses local X11, `--unshare-net`, and `--dev /dev`
(`BubblewrapLauncher.cpp:749,831`). The latter sets `opt_needs_devpts`
(`bubblewrap.c:2122`). Unprivileged setup therefore needs two nested user
namespaces: caller UID/GID initially map to namespace ID 0 for devpts, then
another namespace maps back to the requested application IDs
(`bubblewrap.c:3258–3269,3380–3416`). Loopback setup occurs before the first
self-written UID/GID maps (`:3248,3268`). Namespace capabilities must therefore
work with empty maps and must not depend on a raw effective UID of zero.

The exact loopback sequence is `if_nametoindex("lo")`, a bound route-netlink
socket, `RTM_NEWADDR` for `127.0.0.1/8`, then `RTM_NEWLINK` with `IFF_UP`, each
with a matching success or error ACK. Primary source:
[bubblewrap `v0.13.0/network.c`](https://github.com/containers/bubblewrap/blob/v0.13.0/network.c#L150).
The separately retained file is
`/Users/alex/.local/state/vinix/android/webkit-bwrap-network-v0.13.0-2026-10-26.c`,
SHA-256 `1cfe04fcc38d33d5197feb96fc503d3fd51d234fb9392699a00bf4780ed6e9f0`.
It is not an addition to, or replacement for, the original complete audit bundle.

## Ordered implementation boundaries

1. **Canonical IDs and user-namespace ownership.** Keep process, inode, IPC and
   socket ownership as canonical kernel IDs. Add checked visible-to-canonical
   and reverse conversions: reject unmapped input; expose unmapped output as
   overflow ID 65534; preserve `-1` only where the syscall defines a sentinel.
   Add pinned immutable parent/owner information, depth and quota charges,
   bounded write-once UID/GID maps, and inherited setgroups restrictions.
   Today `proc/container.v:38,454` has no ownership tree and reports an identity
   map; `userland/cred.v:36` onward exposes and stores raw IDs.

2. **Capability containment before namespace creation.** Add an explicit
   credential/target-user-namespace capability check, including ancestry and
   creator ownership. Child authority must not authorize ancestors or siblings.
   Make host operations explicitly require initial-user-namespace authority;
   local operations require authority over the resource's pinned owner.
   `has_capability()` (`proc/container.v:345`) and filesystem checks
   (`fs/permissions.v:27,83,134`) currently inspect bare capability bits.
   Granting child capabilities before correcting them would expose host DAC
   and chown bypasses. Conversely, `security/policy.v:63` requires raw
   `euid == 0`, rejecting correctly mapped application users. Audit direct UID-0
   checks as well as capability helpers and exec/setuid transitions
   (`container.v:374,404`). The reference capability traversal is Linux v6.12
   [`cap_capable()`](https://github.com/torvalds/linux/blob/v6.12/security/commoncap.c#L63).

3. **Transactional maps and translated ABI boundaries.** At map-file open, pin
   the actual target user namespace and immutable opener credentials per file
   description; enforce the required current-caller authority too. PID-only
   `ProcFSResource` (`fs/procfs.v:111`) cannot safely identify the target after
   PID reuse, target unshare or descriptor passing. Validate bounded extents,
   checked arithmetic, non-overlap and complete parent mappings; publish once
   under a lock without partial changes. Support authorized unprivileged
   single-ID mapping, irreversible setgroups denial before unprivileged GID
   mapping, and parent-root `CAP_SETFCAP` protection. Reference:
   [Linux v6.12 user-namespace creation and map rules](https://github.com/torvalds/linux/blob/v6.12/kernel/user_namespace.c).
   Translate credential syscalls, stat/chown, groups, proc status, UNIX peer
   credentials, wait information and ACL IDs at their ABI boundaries.

4. **Atomic lifecycle and restricted admission.** Allocate before publishing;
   unwind every failure. `fs/namespaces.v:242` currently replaces namespace
   pointers incrementally without returning errors. Combined flags must create
   the user namespace first and authorize subsequent namespaces against it,
   rather than rechecking only parent credentials in the clone backends.
   Implement unshare/setns thread, shared-filesystem, ancestry and chroot
   restrictions; reset capability state correctly while preserving
   `no_new_privs`. Inheriting an existing namespace must not transfer its owner.
   User-namespace support can be qualified while network creation remains
   rejected and namespace-local operations remain individually gated.

5. **Safe private mounts.** Represent owner user namespaces for mount namespaces
   and filesystem instances separately. Lock inherited restrictions when a
   mount namespace becomes less privileged. `fs/mount.v:1070` currently replaces
   mount flags, which must not allow child root to clear inherited
   read-only/nosuid/nodev/noexec restrictions. Preserve MAC and process policy;
   explicitly authorize owned private setup instead of making the application
   globally trusted. Qualify tmpfs/proc/devpts, bind mounts and pivot operations
   with canonical ownership and safe device boundaries. Propagation operations
   currently report success without full propagation modelling; audit the
   `MS_SLAVE` private-copy contract before claiming compatibility.

6. **Socket ownership before network activation.** Pin each socket's creation
   network namespace. Accepted sockets inherit the listener's namespace;
   inherited, duplicated and SCM_RIGHTS-passed descriptors retain theirs.
   Key abstract UNIX bindings by namespace and name. Pathname UNIX sockets
   continue through VFS/DAC, allowing permitted shared X11 connections. Route
   interface ioctls, netlink requests and proc network views through the relevant
   pinned namespace, not the caller's current namespace or global defaults.

7. **Actual private transport and loopback changes.** Independent TCP/UDP bind
   and delivery state, routes, IPv4/IPv6, timers, reassembly and multicast are
   required. `netcore/core.v:48,633–642` exposes global PCB/interface/IP state;
   underlying lwIP also has file-static timers and reassembly. Filtering
   interface lists does not isolate that state. Choose a complete reentrant
   stack context or a bounded V private-loopback transport implementing real
   isolated socket semantics; unsupported features must fail honestly. New
   namespaces start with loopback down/unconfigured, no physical interface and
   no default route. Implement the exact bwrap address/link mutations with
   owner-user-namespace `CAP_NET_ADMIN`; `socket/netlink/netlink.v:436` currently
   returns `EOPNOTSUPP` for mutations.

## Acceptance and lifetime gates

- Parent and sibling authority never flows from child capabilities. Child root
  cannot read host-root mode-0600 files, map/chown unmapped host root, inspect
  parent secrets, mutate inherited host namespaces, or clear mount locks.
- Maps are one-shot and fail malformed, overlapping, overflowing, offset,
  parent-unmapped and unauthorized writes without partial state. Passed map FDs
  retain opener authority; target exit, PID reuse and unshare cannot redirect
  them. Exercise both nested mappings used by production bwrap.
- Siblings can bind the same local TCP/UDP ports and abstract UNIX names without
  cross-connecting. Private loopback works after bwrap's actual netlink sequence;
  host loopback, physical interfaces and external routes remain inaccessible.
  Existing host traffic and permitted inherited/shared-pathname connections
  continue working.
- Match every process/nsfs/map-FD/socket reference, parent/owner pin and quota
  charge with a release. TCP close can leave TIME_WAIT PCB/timer state after
  `Vinix_socket` release (`netcore/core.v:1605`); transport lifetime must cover
  that state. Per-namespace transport memory also needs quotas.
- Before freeing namespace objects, fix cached nsfs nodes/raw magic targets and
  the borrowed snapshot in `refresh_ns_directory()` (`fs/namespaces.v:156`).
  `put_namespace()`/`release_namespace()` (`container.v:191`,
  `namespaces.v:229`) do not currently establish a generic object destructor.
  Retain safe lookup pins and defer reclamation while readers may still hold
  pointers; do not turn an existing leak into a use-after-free.
- Qualify allocation failures and rollback, retained descriptors, fork/exit
  churn and flat slab/allocated-memory measurements; review every new lifetime.
  Build both architectures and run desktop regressions. Only then qualify the
  unchanged production browser sandbox and real account flow. None of these
  runtime gates is established by this report.
