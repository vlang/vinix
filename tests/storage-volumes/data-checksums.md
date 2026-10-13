# Data checksum manifest qualification

The native V controller runs `data_manifest_test` under ASan/UBSan alongside
all existing suites and a real-file, mocked physical-device/publisher model.
An independent SHA-256 implementation checks 8192 chunk/padding cases and a
million-byte vector. Fixed workspace hashing covers the 64-KiB read boundary,
interrupted and sector-aligned short reads. Malformed contexts and length
overflow preserve the caller. All 4992 single-bit changes to a 624-byte
manifest fail privately; checksummed invalid headers, reserved fields, embedded
bundles, counts and later record order/slots are also rejected. A complete
64-disk/mapping/region manifest reaches 11392 bytes. CLI tests cover maximum
counts, complete decimal tokens and remainder rejection before I/O.

Device models cover reverse participant order, complete-list rejection before
opens, partial pin failures, repeated physical IDs, nonphysical/offline devices,
identity/geometry changes before and after hashing, invalid identity reads,
zero/failed/oversized/unaligned data transfers and later checksum mismatches.
Every descriptor drains. Corrupt/symlink/nonregular/missing references fail
before devices open. Source/destination lexical aliases preserve source bytes.
Special-file/directory/symlink destinations reject before device opens; a guest
physical-device destination preserves the actual device node.
Changed/equal publications cover short/EINTR writes and each file-fsync/close/
rename/directory-fsync failure. Before rename old bytes remain; afterward only
the complete manifest appears. Retry completes both flushes. Armed publication
faults never enter verification. All three commands detect buffered output
failure. Generated target utility and guest C must contain no heap dependency.

First boot records a 696-byte reference for the actual two-disk/five-row bundle.
Creation respects writer exclusion; verification and offline inspection remain
available. A later-disk byte corruption causes failure without a success prefix,
and the saved reference remains exact. Restoring the original page makes the
same reference pass. Held descriptors, modes, generations and bundle bytes
remain intact. `PLAN DATA PASSED:` is required. Second boot verifies this
guest-produced reference after device reorder (`PLAN DATA BOOT VERIFIED`).

Both targets retain all old assertions, with **200 warmup + 200 measured
41-command cycles / 16400 utility processes**. Each cycle includes full
read-only verification of five desired extents. Every slab class and large-page
total must stay flat or decrease; the 1800-second per-boot limit is unchanged.
The fixture warms both reusable snapshot buffers and records their ready totals
before recapturing the baseline, keeping instrument faults out of measurement.
After all eight earlier boots, the guest records an 1104-byte manifest for nine
grown mappings and persists it itself (`PLAN DATA SAVED:`). A ninth production
boot verifies the complete reference, exact bundle/reference bytes, original
and extension data and unchanged generations (`PLAN DATA BOOT PRESERVED`).
Independent host artifact checks validate both actual manifest CRCs, embedded
bundles, canonical disk/slot records and SHA-256 against physical backing bytes,
while retaining every previous artifact assertion.

These tests establish corruption detection against a trusted reference for
quiescent data. They do not establish coherent snapshots of concurrent writes,
authentication, repair or power-loss recovery beyond the shared publisher.
