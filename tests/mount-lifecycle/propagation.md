# Propagation request validation

Propagation requests now resolve a mount identity under the VFS writer lock
and require a mounted root. Ordinary directories/files and detached roots
return `EINVAL`. Exactly one of `MS_PRIVATE`, `MS_SHARED`, `MS_SLAVE` and
`MS_UNBINDABLE` may be supplied, optionally with `MS_REC` and `MS_SILENT`;
conflicting modes or other flags return `EINVAL`. Source, filesystem and data
options do not supply propagation flags. Remount and bind dispatch precede
propagation, so `MS_BIND` with propagation bits actually creates a bind rather
than returning success without attaching anything.

The validation follows [Linux 6.12.51's namespace implementation](https://github.com/gregkh/linux/blob/v6.12.51/fs/namespace.c).
That stable version checks that a propagation target remains mounted and
requires administrative authority in its namespace's user namespace. It permits
an active foreign root when that authority exists. The reference probe uses
the initial privileged account; per-user-namespace propagation authorization
remains unqualified in Vinix. The existing mount capability and policy gates
run before the new validation, including for malformed requests.

Vinix still accepts valid propagation requests without implementing their
propagation effects. Its namespace override/fall-through arrangement remains
unchanged. This change qualifies request validation and dispatch, not shared
peer groups, recursive mode changes, private isolation or OCI runtime support.

The V fixture selects five cases with `--case propagation` or `pr-0` through
`pr-4`:

| Case | Checks |
| --- | --- |
| `pr-0` | All eleven conflicting mode combinations and eight extra flags, repeated 200 times on a live root; each valid mode with every `MS_REC`/`MS_SILENT` combination succeeds. |
| `pr-1` | Ordinary directories and files inside a live mount refuse propagation, including a cwd-relative request; their mounted root accepts it. |
| `pr-2` | A detached read-only root held through `O_PATH`, and its children, refuse propagation while a replacement lives at its old pathname. |
| `pr-3` | A child's active foreign root accepts valid modes for the privileged parent; its children refuse. After the child detaches and exits, the held root also refuses. |
| `pr-4` | Directory and file binds with propagation bits must attach the source inode. Propagation accepts the bind alias's root while refusing the same inode through its unmounted source route. |

Every refusal first verifies that ordinary `O_PATH` lookup succeeds. UID/GID
1000 with no supplementary groups must receive `EPERM` before validation.
Repeated requests preserve device/inode identity and marker contents. Held
read-only roots remain readable and refuse creation/writable/truncating opens.
Directory and file aliases restore their original destination after unmount.
Valid mode checks include ignored source/type names and the `wxallowed` data
option; successful validation cannot silently alter read-only policy.

Qualification from 2026-10-14 is retained under
`build/development17-20261013`:

| States (both `arm` and `x86`) | Result |
| --- | --- |
| `mount-propagation-*-pr-{0..4}-before-a` | Previous admission kernels incorrectly accept conflicting flags and ordinary live/detached/foreign child paths; bind dispatch returns success without attaching. |
| `mount-propagation-*-pr-{0,2}-before-b` | Final fixture reproduces conflicting-mode and detached-root acceptance on the previous kernels, using the exact final probe ELF. |
| `mount-propagation-*-all-after-b` | Patched native kernels pass all five cases and every prior mount mode, move/depth, identity and attachment-admission check. |
| `mount-propagation-*-linux-b` | Linux 6.12.51 passes all portable cases with the identical final native ELF. |

The first fixture revision expected detached roots to accept valid modes.
`mount-propagation-*-linux-a` preserves the Linux rejection that corrected this
expectation. The `before-a` controls stop at earlier child-path/dispatch failures
and never reach that expectation. The final fixture adds detached-root refusal
checks; the `before-b` controls, final native runs and passing Linux references
share that source revision and ELF. These distinct states preserve failures
instead of replacing them with passing results.

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `c019caf6811286734f9f9ebda4391c295ea44724a3cdc8e8462d54120eca608f` | `cba492dd7d8fc8c079e47849184a5d293abc867e4e90b548d2a5048e9c251e02` |
| x86_64 | `e13616516dece126bf498731da38c3a9afb64aa3397c5840801e3a69f3dbfbd2` | `222ba5e728ec037d4d990ad74c332ad444680a814f5b15c6801178784a759ce3` |

Isolated worktrees reuse the frozen `mount-admission` kernel sources, changing
only `kernel/fs/mount.v`. They retain the VFS baseline limitation described in
[identities.md](identities.md), excluding other sessions' changes. The builds
use V source `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link shuffle seed 17. `mount-propagation-{arm,x86}-input` freezes the ELF,
generated C, changed source and complete kernel source manifest. The controller
pins all four fixture files when caching a probe. `mount-propagation-evidence.log`
independently verifies receipts/artifacts, fixture revisions, controls, complete
positive markers, shared ELF identity and unchanged baseline sources. It also
checks the generated validation function's stack cursor, writer lock, root and
detachment guards, flag checks and dispatch order; the function introduces no
allocation calls or new kernel ownership. No allocation-flatness claim is made
for complete mount operations or namespace creation.
