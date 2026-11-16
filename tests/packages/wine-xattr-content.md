# Native extended-attribute content inventory

`wine-xattr-content.v` records and checks complete native macOS attribute names
and values on an explicit JSON array of canonical absolute regular-file and
directory paths:

```text
CONTENT capture TARGETS.json FRESH_RECEIPT.json
CONTENT check TARGETS.json RECEIPT.json
```

Compile with the selected V compiler, `-prod -gc boehm` and the repository module
path. The source and `winexattr` module are embedded and rechecked; receipts also
bind the executable hash and exact target-manifest bytes. Only production tools
publish or admit receipts. Capture uses exclusive creation and never replaces
an existing file or follows an output symlink. Check accepts the canonical
serialization emitted by the same executable, rejecting unknown/duplicate
fields and trailing text as well as changed content. Manifests and receipts use
bounded nonblocking descriptor reads with identity and size checks too.

Each target is opened with `O_NOFOLLOW`, `O_NONBLOCK` and `O_CLOEXEC`; identity is
checked against `lstat` using the held descriptor. Attribute enumeration and
value reads use that descriptor and `XATTR_SHOWCOMPRESSION` to expose native
compression metadata hidden by the default API. Repeated name enumeration, final path identity
checks and two complete content observations must agree. Errors refuse rather
than silently omit unreadable attributes. This is a bounded observation, not an
atomic filesystem snapshot; concurrent change-and-restore races remain outside
its claim. Use quiescent targets. No target attribute is written by the tool.

Names and values are hex encoded without UTF-8 conversion. Empty sets and empty
values remain distinct. Limits are 2,048 targets, 256 attributes per target,
64 KiB for each native name list, 255 bytes per name, 1 MiB per value, 16 MiB of
aggregate raw name/value bytes per observation, and 64 MiB per receipt. Target
manifests must be ordinary nonempty files no larger than 1 MiB. Symlinks,
noncanonical/duplicate paths, FIFOs, devices and unsupported nodes refuse.
Copies that lose native attributes fail this check even if ordinary file bytes
match; this differs deliberately from the serialized probe evidence in the
[required format-9 host receipt](wine-host-required-check.md).

`wine-xattr-content-check.v CONTENT FRESH_OUTPUT` exercises binary/empty native
baselines, restoration after each mutation and 35 refusal cases: same-size and
directory value changes, added/removed/renamed names, empty attributes and
previously empty targets, node type, forged/canonical declarations, target
admission, native name/value/total limits, oversized/FIFO declarations and
exclusive publication. Its FIFO
case and an actual `ditto --noclone --hfsCompression` fixture verify bounded special-node
handling and hidden compression contents respectively. The FIFO
case has a two-second deadline; invalid native inputs must publish no receipt.
All checks use explicit conditions under `-prod`.

Append `HOST_BUILDER FIXTURE CONTROLLER PRODUCER RETAINER` to also capture and
check each original graph's canonical metadata targets. The original builder
must admit each complete host graph before and after the read-only audit.
Alias spellings collapse to their canonical targets. OS-root/device subpath
exceptions, directory entry names and other paths outside that explicit set
are not covered. The new checker does not modify historical fixtures.

This tool supplements ordinary byte inventories. It does not pin every
attribute readable by the host sandbox, grant publisher authentication or
integrate live xattr content into required host receipts. Existing verifiers,
complete original bundles and compiler/SDK/image namespaces remain required.
Broader query/search/metadata and loader closure, owned ARM/GUI, redistribution
and default activation remain open.
