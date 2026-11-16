# Captured host replay with bounded existence and xattr queries

This additive macOS qualifier requires complete original format-8 host admission
by its exact pinned checker before and after replay:

```text
wine-query-closed-replay ORIGINAL_HOST_BUILDER FORMAT8_HOST_BUILD FRESH_OUTPUT
wine-query-closed-controls REPLAY ORIGINAL_HOST_BUILDER FORMAT8_HOST_BUILD FRESH_CONTROLS
```

Compile both V tools with the selected compiler, `-backend c -prod -gc none
-manualfree -cflags -fno-lto` and the frozen repository module path. The replay
links `libsandbox`. Its main file and six policy/image/probe modules have
embedded source guards, repeated before publication; non-production builds
refuse. Original host bundles and verifiers remain required and unchanged.

The existing data/metadata policy permits `access(F_OK)` and a named `getxattr`
read on an unlisted file. This tool demonstrates those successes under the
metadata-only counterfactual, then applies `winequeryclosure`: existence and
xattr reads require exact admitted metadata paths or the existing OS-root/device
exceptions. Bounded image aliases still resolve only to pinned ordinary images;
they receive query permissions without widening file-data permissions.

The helper and linker must create their output records. Three exact paths
receive existence permission only: the two restricted execution records and
the linker output. This pinned LLD also queries `program.tmp` followed by seven
lowercase hexadecimal digits. A separately recorded, anchored regex permits
existence checks only for that bounded output filename family. The sandbox
requires seven explicit character classes here; its counted-repeat spelling
does not match in the measured host profile. No input-directory prefix is
granted. Three malformed/non-hex/overlong temporary lookalikes must be refused.
A matching temporary file permits existence while its xattr read remains denied.
These execution exceptions grant no data, metadata or xattr read permission.

Captured and unrestricted external-object linking must reproduce the original
executable, with original archive-load coverage and pinned image hashes/UUIDs.
Existing allowed file/directory/stat and denied data/directory/stat/hidden-link
controls remain required. New positive controls query a captured object and
directory for existence, the known attribute value and its listed name. Six
unlisted direct/symlink/Data-volume paths must refuse all three operations with
EPERM/EACCES. Every result records its operation, path, return, error and data;
the parent checks exact operation order, targets, exit markers and outcomes.

Separate policies isolate the two new rules. The metadata-only policy must
allow unlisted existence and the seeded attribute value. The xattr-only policy
must allow existence while refusing the value; the existence-only policy must
refuse existence. Along with the output-only control, each role requires six
allowed control children, thirty-six denial children, four counterfactual/
isolation/output controls and two identical link baselines.

`attribute-fixture.json` serializes the controlled key, value and target paths.
The parent seeds only new replay fixtures and rechecks their native values before
publication. Regular result logs and fixture declarations retain the observed
attribute bytes for the typed inventory. The inventory covers that serialized
evidence; it does not audit all native extended attributes or host xattr content.
The policy allows arbitrary attribute names on admitted paths. Complete xattr
content admission, other query/metadata operations, ancestor entry names, writes,
network, helper startup and OS loader/cache bytes remain unqualified.

Before `receipt.json` is published, the parent repeats full original admission
and rechecks selected bytes, successful outputs, alias targets, fixture values,
all policy files, original proof/archive/checker/self hashes and source guards.
The production control runner requires 88 policy refusals (26 invalid input
sets across three query projections plus ten execution-path cases), deterministic
framing and three wrong-checker/incomplete/old-format admission refusals.
No assertion is relied on under `-prod`.

Preserve the complete original prerequisites and new audit bundle outside Git
with typed inventories. Receipts are local observations, not authenticated
trust anchors. Required host receipts keep format 8; mandatory query integration,
full SDK/ABI/library/search and hermetic admission, owned ARM/GUI and defaults
remain separate gates.
