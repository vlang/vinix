# Android evidence private-byte measurements

Source revision: `b5e8d23fd` (`tests/native-android-ws/apfs-private-size.v`).
The read-only helper checks returned attribute masks, packed field offsets against
`lstat` data length, unique hardlink status, and before/after metadata. Independent
review found no blocking issue. Normal and production compilations exited zero; the
production guard and noncanonical-path check each rejected execution with exit one.
The source smoke query and all bounded evidence queries exited zero.

The local SDK documents `ATTR_CMNEXT_PRIVATESIZE` as bytes immediately recoverable
on deleting a file, excluding clone and snapshot sharing. Values are conservative
per-file lower bounds at query time. A deletion set may additionally own extents
shared solely inside that set. Metadata checks use second-resolution `os.Stat`
timestamps and do not establish an atomic snapshot.

Under `/Users/alex/.local/state/vinix/android/`, the measured directories were:

| Directory | Private bytes |
| --- | ---: |
| `frame-metrics287-build-2026-10-25` | 6,492,160 |
| `frame-metrics288-build-2026-10-25` | 5,533,696 |
| `path-ops296-framework-build-2026-10-25` | 73,445,376 |
| `path-ops296b-framework-build-2026-10-25` | 0 |
| `drawable-optical306-framework-build-2026-10-25` | 0 |
| `maps362-prelaunch-review-bootstrap-generated-c-2026-10-26` | 1,503,232 |
| `maps364-prelaunch-review-bootstrap-generated-c-2026-10-26` | 1,540,096 |
| `maps364-replay-receipt-bootstrap-generated-c-2026-10-26` | 1,523,712 |

The five old framework bundles also passed fresh unchanged `build-bundle-check290`
audits against their original manifest pins. Their gross directory sizes do not
establish a net benefit from materializing compressed archives.

Exact-file metadata queries of Compound258/260/262 baseline and Compound276 fixed
working/canonical `boot.img` pairs returned zero private bytes for all eight files.
Maps300/304/308/311/358/360 canonical prelaunch and postrun `boot.img` pairs likewise
returned zero for all twelve files. Each image has 4 GiB logical length. Queries
did not read or hash image contents. No archive or removal was performed during
this review.

The external evidence directory is
`/Users/alex/.local/state/vinix/android/apfs-private-size-hardening-review-2026-10-26`.
It preserves the source, consumed compiler and helper binaries, SDK references,
exact-path scan logs, rejection logs, and command statuses. All twelve entries in
`SHA256SUMS` passed fresh readback; that manifest's SHA-256 is
`52e0217b4017118c41b28043128d48b95110b3d322b1a171ac20a8cf989cb0a6`.
