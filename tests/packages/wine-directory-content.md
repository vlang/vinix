# Native directory entry-name inventory

`wine-directory-content.v` records and checks immediate native macOS entry names
on an explicit JSON array of canonical absolute directory paths:

```text
CONTENT capture TARGETS.json FRESH_RECEIPT.json
CONTENT check TARGETS.json RECEIPT.json
```

Compile with the selected V compiler, `-backend c -prod -gc boehm` and the
repository module path. The main file and `winedircontent` reader are embedded
and rechecked before publication; receipts bind their hashes, the executable
hash and exact manifest bytes. Non-production tools refuse. Manifests and
receipts require bounded ordinary files, nonblocking no-follow descriptor reads
and matching path/descriptor identity and sizes. Publication uses exclusive
creation; it never overwrites an existing file or follows an output symlink.
Receipt files must be outside the observed directories to avoid adding their
own entry names. Check requires exact canonical serialized bytes, rejecting
unknown/duplicate fields and trailing text as well as altered names/declarations.

The reader opens each directory with `O_DIRECTORY`, `O_NOFOLLOW`, `O_NONBLOCK`
and `O_CLOEXEC`, checks type/device/inode against the held descriptor, and uses
`fdopendir`/`readdir` on that descriptor. It distinguishes end-of-stream from
enumeration errors. Dot entries are excluded; all other names, including hidden
and special-file entries, are hex encoded and sorted. Child objects are never
opened or followed. Names are bounded to 255 native bytes each. At most 2,048
unique targets, 4,096 names per directory, 16,384 names across one complete pass
and 1 MiB of aggregate raw name bytes are accepted. Manifests have a 1 MiB bound
and receipts an 8 MiB bound. Duplicate/noncanonical/linked/non-directory targets
refuse. Two complete observations must match, with canonical paths and node
identity rechecked; these quiescent observations are not an atomic snapshot and
cannot exclude concurrent change-and-restore races.

The production control runner supports private fixtures and optional original
format-11 host graphs:

```text
CHECK CONTENT FRESH_CONTROLS [ORIGINAL_BUILDER FIXTURE CONTROLLER PRODUCER RETAINER]
CHECK guards COMPILER FRESH_GUARDS --source-guards
```

It requires empty and populated baselines with hidden, quoted, newline, Unicode,
directory, dangling/cyclic-link and FIFO entries. Six live name/target controls
require exact refusals and restored baselines without changing ordinary fixture
bytes or receipt bytes. Child bytes, kinds, link bodies and descendants are
deliberately independent of this name-only inventory. Nine forged receipt cases,
ten invalid target declarations, nine declaration/publication cases and three
native bound increments bring the refusal matrix to 37. Native fixtures pass
at the exact per-directory/global count and raw-byte limits, refuse the first
increment, and restore admission. FIFO inputs have two-second command bounds;
retired FIFO metadata is retained before removal. Refusals require exit 1,
excluding signals/timeouts. Three further guards reject non-production use and
altered main/reader sources, with restored source baselines. Checks use explicit
errors and remain active under `-prod`.

With original graphs supplied, the exact original builder must admit every role
before and after read-only capture/check. Targets come from each admitted inner
replay's directory declaration, canonicalized and deduplicated. The original
host bundle, compiler/LLVM/SDK/image namespaces and all historical prerequisites
remain required. No historical directory entry is changed. Keep complete audit
bundles outside Git with typed inventories and checksums.

This additive tool keeps required host receipts at format 11 and does not change
sandbox permissions. Mandatory directory-name integration remains separate.
Directory names do not establish child content, complete search/absence closure,
exception-tree coverage, loader/toolchain closure, owned ARM/GUI acceptance,
redistribution or default activation.
