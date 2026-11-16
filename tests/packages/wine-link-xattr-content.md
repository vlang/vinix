# Native attribute content on symlink nodes

`wine-link-xattr-content.v` captures and checks native macOS attributes on the
symlink node itself, plus the literal link body:

```text
LINK_CONTENT capture TARGETS.json FRESH_RECEIPT.json
LINK_CONTENT check TARGETS.json RECEIPT.json
```

Compile with `-prod -gc boehm` and the repository module path. The main source,
`winelinkxattr` module and unchanged `winexattr` limits source are embedded and
rechecked. Receipts bind those hashes, the executable hash and exact manifest
bytes. Only the canonical receipt serialization is accepted; unknown/duplicate
fields and trailing bytes refuse. Declaration files use bounded, nonblocking,
no-follow descriptor reads. Publication uses exclusive creation.

Targets must be unique absolute paths whose parent spelling is canonical.
The final component must be a symlink and is deliberately not resolved.
Dangling links, cycles and links to FIFOs can be observed without opening the
referenced objects. Relative link bodies are recorded literally as hex; they
are not normalized. Names and values are hex too, preserving binary and empty
attributes. Changing the referenced object's bytes or attributes does not alter
this link-only inventory. That object needs separate ordinary/native admission.

The reader opens `O_SYMLINK | O_NONBLOCK | O_CLOEXEC`, checks the descriptor's
symlink type/device/inode against `lstat`, then uses `flistxattr`/`fgetxattr`
with `XATTR_SHOWCOMPRESSION`. The native API survey establishes that adding
`O_NOFOLLOW` to this open returns `ELOOP` on this profile. Readlink bodies use a
fixed 4,097-byte buffer and refuse values beyond 4,096 bytes. Repeated names,
body, path identity and two complete observations must agree. No attribute is
written by the inventory tool. This is a quiescent observation, not an atomic
snapshot; concurrent change-and-restore races remain outside its claim.

Limits inherited from `winexattr` are 2,048 nodes, 256 attributes per node,
64 KiB per native name list, 255 bytes per name, 1 MiB per value and 16 MiB of
aggregate raw name/value bytes per observation. Manifests are limited to 1 MiB
and receipts to 64 MiB. Noncanonical parents, duplicate paths, ordinary files,
directories, direct FIFO targets and missing nodes refuse. The CLI does not
silently replace an aliased parent with its canonical spelling.

`wine-link-xattr-content-check.v CONTENT FRESH_OUTPUT` runs binary/empty,
dangling/cyclic/FIFO-link and restored baselines, target-independence checks,
exact name/value limits, and 38 refusals. Native mutations change link values,
names, bodies and node types while preserving target/receipt bytes. Forged
receipts, invalid targets, native bounds and declaration/publication errors
must refuse; FIFO cases have a two-second bound. Retired FIFO metadata is
retained before removing the private IPC nodes. Refusals require exit code 1;
crashes cannot satisfy a negative control. All checks remain active with `-prod`.

Append `ORIGINAL_BUILDER FIXTURE CONTROLLER PRODUCER RETAINER` for read-only
coverage of each complete original format-10 graph's declared metadata alias
links. The original builder must admit each graph before and after inventory.
Canonical-parent paths collapse duplicate spellings of the same link node;
their literal bodies must match the admitted alias declaration. Historical
nodes and attributes are never changed by these controls.

This additive tool does not change required format-10 host receipts or sandbox
permissions. It supplements their canonical regular-file/directory attribute
inventory. Mandatory symlink-node integration, other readable symlinks,
OS-root/device exceptions, directory names/search absence, loader/toolchain
closure, owned ARM/GUI and default activation remain open. Original verifiers
and all complete prerequisite bundles remain required.
