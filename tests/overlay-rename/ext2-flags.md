# Ext2 inode flags after remount

The flag setter stored immutable and append-only bits on disk, but the mount
and recursive directory loader omitted them when constructing resources.
After remount, the file, directory or root therefore lost its protections in
memory. Both constructors now initialize the existing scalar `attr_bits` from
the inode's supported bits before publishing the resource, matching the
existing `resource_from_inode` helper. This adds no allocation or lifetime.

The separate maintained V `--case flags-persistence` probe sets both bits on
a regular file, directory and volume root, closes the descriptors, syncs and
remounts the volume writable. All three must still return `0x30`. Even root
must be refused a writable file open, directory chmod and new child creation,
while the original file bytes remain readable.

Results from 14 October 2026 are retained in `build/development17-20261013`:
`diskflags-drain-{arm,x86}-before-a` fail assertion 684 with flags zero;
`diskflags-drain-{arm,x86}-after-a` pass. Both final volumes pass read-only
`e2fsck -f -n`. The dedicated controller/fixtures are frozen in
`diskflags-drain-snapshot`; its direct probe does not call the pending overlay
flag-update or held-alias fixtures. The first combined overlay tests exposed
the same lost protection at their remount assertion 666. The initial fast direct
probe passed functional checks but its filesystem check found pending setup
retirement allocations. The final probe waits 25 seconds for those queues before
unmounting; those initial results remain separate from final evidence.

Both final kernels use isolated `kernel-inodeflags3-{arm,x86}-tree` worktrees
derived from the previously qualified [xattr preflight kernels](xattr-preflight.md),
with the pinned compiler and link seed 17. They also contain the separately
reviewed overlay routing/publication changes; the direct probe exercises
non-overlay flag setters. The existing pointer-return spelling normalization
for this legacy compiler remains in the isolated sources. The evidence checker
compares the committed source after that normalization.

`inodeflags3-lifetime-review.md` binds the independent source/generated-C
review to both final generated files. `diskflags-drain-evidence.log` records
the dedicated receipts, controls, preserved source hashes and filesystem checks.
Broader flag masks, journal failure/crash recovery, concurrent flag changes and
shared-mapping adversarial matrices remain open.
