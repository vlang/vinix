# Lazy directory population in stacked overlays

When collecting a directory's layers, overlay population previously read each
layer's cached children directly. A lower layer that was itself an unpopulated
overlay directory had an empty cache. Its existing children therefore vanished
from the outer overlay, which then marked its own incomplete view populated.

Population now recursively prepares every overlay layer before collecting its
children. It uses the already-held `overlay_lock`, borrowed layer nodes and the
existing populated guard and merge/retirement paths. Backend layers retain their
existing no-op path. Preparing an inner directory's view does not copy it up.

Mount admission also caps backing overlay depth at eight. Each mount caches the
maximum depth of its lower, upper and work aliases; new mounts compute their
depth from those scalars without a recursive admission walk. Excess depth returns
`ELOOP` before staging creation, filesystem/root allocation or publication.
Subdirectory and bind aliases retain their original filesystem's depth.

The [copy-up protection fixture](protected-copyup.md) exposed this independently
of the protection-bit loss. Root prepares a private directory with an existing child,
then mounts two overlay layers without looking up that child in the inner layer.
UID/GID 1000 creates another child through the outer append-only directory.
Deletion of either existing or new child must fail with `EPERM`, while the inner
upper stays absent. The saved protection-only kernels instead report `ENOENT`
for the existing child, showing that its lower name was never collected.

A root probe mounts eight read-only layers without priming their inner views,
then has UID/GID 1000 read a nested file through the deepest mount. A ninth layer
must be refused with the target device/inode unchanged. Two batches each repeat
200 excessive-depth mounts for lower, upper and work inputs and 200 authorized
service reports, exercising both [security event producers](security-events.md).
All phase 70/71 live
class/large counts must match; raw staging storage must stay absent. The mounts
are then removed before the final retirement wait and volume checks.

Saved whole-root controls are `protected3-{arm,x86}-stacked-before-a` under
`build/development17-20261013`. Both fail assertion 697 with the diagnostic
`group=2`, the `protected-2-7/old` path and errno 2. The separate `depth-before-a`
controls use unbounded kernels, pass the protection cases and accept a ninth
mount; assertion 705 fails. Scoped `protected4-arm-stacked-before-c` and
`protected4-x86-stacked-before-d`
controls fail earlier at assertion 696 with `ENOENT`; their separate
`depth-before-c` controls still accept the ninth mount and fail assertion 705.
Final `protected4-arm-after-f`, `protected4-x86-after-g` and
`protected4-{arm,x86}-all-b` suites pass with the companion protection and event
corrections. The existing
stacked lifetime, held-descriptor, whiteout, opacity, failure, authorization
and remount cases remain covered. Final compared class/large counts stay flat,
four ext2 volumes pass read-only filesystem checks, and the global allocation
audit has 181 remaining baseline file/kind failures after removal of the two
event promotion sites. `protected4-lifetime-review.md` and
`protected4-evidence.v` bind the review and measurements to the final tree;
the three product fixes are committed separately. Earlier bounded kernels
retained one slab128 allocation per event; they are negative controls for the
event correction, not passing final allocation receipts.

The final compiler's static stack-usage records report population frames of
800 bytes on ARM and 808 on x86. The eight-overlay admission bound keeps the
layer descent bounded; the existing backend no-op can add one terminal frame.
The independent review identified the unbounded recursion in the preliminary
patch, then approved the cached-depth admission and final generated C.

This qualifies the reproduced two-layer lazy-directory case and the eight-layer
read-only boundary. Broader writable stacks, changing mount graphs, concurrent
raw-layer mutation and complete OCI/rootless-runtime behavior remain open.
Mount roots also retain permanent ownership after unmount; destroying their
cached trees and releasing all backing pins remains open. The fixture uses a
stable private lower subtree so it does not retain other suites' removed names.
