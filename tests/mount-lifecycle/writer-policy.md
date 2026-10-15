# Regular-file writers and read-only remount

Writable regular-file descriptions now retain a writer on the actual mount
object selected at open. A writable-to-read-only remount returns `EBUSY` while
that object has writers. The shared Handle drops its pin at final release,
after its existing resource close work. Duplication, fork, mappings and in-flight
references keep that Handle alive; closing just one descriptor cannot release
its mount writer.

A temporary pin covers regular-file copy-up, truncation and descriptor
construction. Writable descriptions acquire their own overlapping pin before
publication. Failed acquisition or descriptor publication unwinds through the
existing cleanup; read-only `O_TRUNC` releases its temporary pin on return.
Read-only and `O_PATH` descriptions retain no permanent writer. Both acquisition
and the read-only transition use the mount lock, so a writer either blocks that
transition or observes `EROFS` before the protected work begins.

The pin follows the raw mount pointer. Namespace copies initialize their writer
count to zero, while inherited descriptions continue to pin their original
mount. Making the copy read-only must still permit `ftruncate` on an inherited
writable description. The existing descriptor access-mode checks remain in
place. A root-opened writable descriptor also retains that authority after a
child drops to UID/GID 1000; pathname truncation of the root-owned `0600` file
returns `EACCES` and remount returns `EPERM`.

[Linux v6.12 open handling](https://github.com/torvalds/linux/blob/v6.12/fs/open.c)
likewise retains write access with the open description, and its
[mount implementation](https://github.com/torvalds/linux/blob/v6.12/fs/namespace.c)
refuses a read-only transition with active writers.

Use `--case writers` or `wr-0` through `wr-9`. Both native `all` and Linux
`move-reference` include these cases:

| Case | Coverage |
| --- | --- |
| 0 | `O_WRONLY`/`O_RDWR` source writers block only their mount; the directory bind can become read-only. |
| 1 | Reverse source/bind direction with the same ownership checks. |
| 2 | A namespace copy becomes read-only; inherited descriptor truncation succeeds and fresh writable opens fail. |
| 3 | Sixteen dup/close cycles retain the writer until the last duplicate closes. |
| 4 | A synchronized fork retains the writer after parent close; privilege drop preserves descriptor authority and denies pathname/remount access. |
| 5 | Private and shared mappings retain the writer after descriptor close, until unmap. |
| 6 | Sixteen `EMFILE` failures release both temporary and private-Handle pins. |
| 7 | A regular-file bind writer blocks only that exact attachment. |
| 8 | Read-only `O_TRUNC`, `O_PATH`, invalid lengths and descriptor access errors do not leave writer pins. |
| 9 | A descriptor from a retired worker namespace retains a usable original mount and closes safely. |

Writable-descriptor checks repeat shrink, growth and unchanged size sixteen
times. They verify zero-filled growth, contents through a retained reader,
unchanged cursor, device/inode/mode/owner/link metadata, and negative-length
errors. The writer cases use private tmpfs mounts with networking disabled.

Evidence from 2026-10-15 is retained under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-writers-{arm,x86}-wr-{0,3,4,5,7}-before-c` | Previous kernels incorrectly accept the read-only remount while the source, duplicate, child, mapping or file-bind writer remains. |
| `mount-writers-{arm,x86}-writers-after-a` | All ten corrected native cases pass. |
| `mount-writers-arm-all-after-a` | The cumulative native mount suite passes, including inode flags and all ten writer cases. |
| `mount-writers-{arm,x86}-linux-a` | The same final probe ELFs pass the portable Linux 6.12.51 suite. |

| Architecture | Kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `e17c833760fba44e0ba1e44e0133cb101ed81eb7754aa6a1cdb02e45f793e333` | `6714bcbe347b7ee2235217490202a18ff158767ad6f5d0e700aad11635fb5a64` |
| x86_64 | `74d8a7e72971eeeb52cf3ac3d5482f2f27d52d0814540eb91f7f57a6b8192d5b` | `2ddcbd1715a381303af4432648985112c94a5811a29ad5202690ce7ec1205f0d` |

Both isolated builds start from the qualified rename inputs, applying only this
change to `file.v`, `mount.v`, `mount_policy.v` and `vfs.v`. Complete source
manifests, changed sources, generated C, kernels and hashes are preserved in
`mount-writers-{arm,x86}-input`. Builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. Native ARM uses HVF/four CPUs; x86 uses TCG/two, with
1024 MiB. Linux uses HVF/TCG, two CPUs and 512 MiB. Focused native timeouts are
300/900 seconds; the cumulative ARM suite and Linux use 600 seconds.

The frozen baseline excludes the checkout's pre-existing open-created VFS
descriptor hunks and staged pointer-return spelling edits. Its `file.v` also
predates existing fcntl query/owner/O_PATH/pipe-size changes, atomic descriptor
pair publication, duplicate flag ordering and description-lock cleanup. The
independent review inspects both final-close variants: the writer callback
follows `release_flock` in the frozen build and `release_description_locks` in
the checkout. The complete current checkout kernel was not built or booted.
The commit audit accounts for these exclusions rather than treating the frozen
build as qualification of unrelated changes.

`mount-writers-lifetime-review.md` pins the reviewed frozen and checkout sources
and both complete generated C files. Its SHA-256 is
`24d18233a9a8c639a8b4b13a942e77f7f4d95dee0cb8084c07a2f8fec83c26d0`.
The assertion-enabled `mount-writers-evidence-a.log` audit verifies that review,
source manifests, all nineteen fixture hashes, artifacts, receipts, boot images,
shared probe/C identity, old-kernel failures and positive native/Linux markers.
All parsed namespace-qualified generated functions match the previous build,
after temporary/discard number normalization, except five reviewed functions.
Removing only the callback, registration, busy guard, permanent pin block and
temporary pin/defer blocks makes those complete functions match too. Exactly
three allocation-free writer helpers are added. Per-architecture
`writers-c-audit.txt` retains the result. A post-commit audit checks the committed
patch and source exclusions against both isolated inputs.

Initial `wr-0-before-a` probes failed compilation because `go` is reserved by
V; the fixture variable is now `proceed`. The next `before-b` probes encountered
Vinix's existing `EFAULT` for a null mount source. The final `before-c` probes
use `"none"`, matching the existing bind-remount fixture, without removing any
assertions. Their ELFs/C are reused for every qualified control and corrected
run. Older completed mount/overlay boot images may be losslessly archived as
`test.iso.gz`; their decompression hashes are checked before removing originals.
Sources, probes, kernels, logs and receipts remain available.

This qualifies regular-file description ownership and the same-object remount
interlock on tmpfs. The temporary pin starts after lookup and optional creation;
it does not serialize creation, unlink, rename, metadata or every mutation with
remount. Existing inherited-route policy lookup still maps by namespace mount
ID and needs separate work for divergent copied flags. Filesystem-wide remount,
persistent/overlay integration, concurrent namespace switching and queued
`SCM_RIGHTS` runtime tests remain open; SCM lifetime paths were reviewed only.
There is no new mount allocation/free, reclamation or allocation-flatness claim.
A new cumulative native x86 run and desktop performance scenarios are outside
this qualification. Full OCI/rootless acceptance and roadmap section 17 remain
in progress.
