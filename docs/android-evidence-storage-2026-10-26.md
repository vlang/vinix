# Android evidence storage assessment, 2026-10-26

Read-only VM assessment qualified no further image cleanup. Compound247 cold cleanup
is recorded in `tests/native-android-ws/compound-button.md`; Maps360 redundant
working-copy cleanup is recorded in `maps360-permission-metadata-replay.md`.

External receipts are under `/Users/alex/.local/state/vinix/android/`:

| Read-only assessment | Receipt | Result |
| --- | --- | --- |
| Compound262 complete gzip stream | `compound262-cold-estimate-2026-10-26.json` | 8,870,727,680 bytes; discarded stream, no archive written |
| Older working VM extent samples | `older-working-extent-samples-final-2026-10-26.json` | Compound258/260/262 baseline and Compound276 fixed working/canonical pairs share all four sampled physical ranges |
| Compound262 working baseline aligned zeros | `compound262-zero-range-scan-final-2026-10-26.json` | 33,882,112 bytes in 147 ranges; no hole punching performed |

Compound262's retained complete manifest remains
`266c69ebfe021eae6224cfefe920d39ec348a2d1b9c89bc310bc0c60cd837526`.
The estimate receipt is
`9605c6b82d1b8af711904382e95bc9b79085428afd97b673a91132612c883f4b`;
its source is committed in `ea43ec193`. The complete archive cannot fit in the
available space, so no cold-storage attempt followed.

The extent samples use file offsets 0, 1, 2 and 3 GiB for each 4 GiB image.
The latter three samples also share physical offsets across these old attempts.
Sampling does not establish total unique allocation or expected physical recovery.
The zero scan records full image SHA-256
`15d7cf0ed5873a3cd404acd80b760c89bb3ef296b97b39336e79d50a01b5cede`,
size 4,294,967,296 and mode 0644. Zero bytes alone do not prove allocated or unique
extents, and this amount is insufficient for the requested storage recovery.

`build/android-maps/service-stop361-{old,new}` are symlinks directly into the
retained Service361 fixture's `run-old` and `run-new`; they are not disposable
working copies. Both links and canonical targets were left untouched.

The V readers record their source/binary hashes in each receipt. These assessments
leave original auditors and complete evidence unchanged.

The final extent-sample receipt SHA-256 is
`01a6aae4e624d81df56d1692827c008272f7081f1c3d37b289137dbf8f6d694b`;
the final zero-range receipt is
`b1a09d13c0fbccd217fe459e662874e8d6b4d23b0f6e1df40bf610808e4a0495`.

## Inflater290 failed-build cold preservation

`tests/native-android-ws/failed-builds290293-cold-cleanup.v` created a new archive,
restored it, and ran unchanged `build-bundle-check290` against both complete trees
(750 files each). Full typed comparisons also covered directory entries, symlink
targets and modes, including the root mode. Both trees were rechecked immediately
before removing only the fixed original expanded tree and temporary restore.
All child commands exited zero, 00:58:45–00:58:52 UTC. The archive and its adjacent
checksum remain under `/Users/alex/.local/state/vinix/android/`:

| Artifact | Value |
| --- | --- |
| Archive | `inflater-trace290-failed-build-2026-10-25.tar.gz` |
| Archive bytes / SHA-256 | 108,933,356 / `03e1870821cc12b3722bd79161aee1c9d9ad6fe2955ffd6809ae44fcdef15646` |
| Original manifest | `58cd4c6b5b52ad20b0df7d5b6b4ea891018b0873f6197c3d519349253b0739ff` |
| Sidecar directory | `inflater-trace290-failed-build-2026-10-25-cold-cleanup-2026-10-26` |
| Sidecar complete typed manifest | `e74bdc31ccb2bcf435a53e4ae7ac5f3bb53b5c015f38db65310257693e6d4e89` |
| Receipt | `0d8fb3d252d9998ba569d004afd2555518061b071b1481e7c587880d6db56c2a` |
| Cleanup source | `b55fae22ef0c80f6f275dffa2b4d962719287f1ec376f1b1cf1ec21b29c68827` |
| Cleanup binary | `3ccab541a00741b2f36f923be9f7a355c1fb2230e536fce1c9f24ebbc2be349d` |

The normal compiler command was
`v -o build/android-maps/failed-builds290293-cold-cleanup tests/native-android-ws/failed-builds290293-cold-cleanup.v`
(exit zero); source and executable hashes were read back before execution. The
sidecar preserves both consumed files, the unchanged reader source/binary, typed
inventory, exact command arguments/exits, logs and fresh checker receipts. The
production build exited one with `assertions required` before creating a sidecar;
its external log is `failed-builds290293-cold-cleanup-prod-guard-2026-10-26.log`,
SHA-256 `ee43c310ddd4c5119bd29df53f6428707281d3d023d8d4034d54c7f013d98912`.

This preserved evidence but did not recover physical space: recorded availability
fell from 703,544 to 598,592 KiB. APFS clone sharing makes gross directory size an
unreliable estimate; the new compressed archive holds two copies of the roughly
50 MB R8 JAR. No further candidate archive was started after this result.

To audit later, verify the adjacent archive checksum, restore it into a fresh
directory with `/usr/bin/tar -xSzpf`, then invoke the preserved unchanged checker
with restored root, original manifest SHA-256 and a fresh external receipt path.
The original checker remains complete; it was not changed for cold storage.

## Read-only rehydration feasibility

`tests/native-android-ws/inflater290-rehydrate-analysis.v` accounts for all 751
regular members, including the manifest, using the retained typed inventory and
archive listing. Actual file hashes in successful Framework290/288 bundles match
736 members totaling 153,700,506 bytes. The remaining 15 members total 426,614
bytes: failure receipts/logs, two generator copies, source inventories and the
original manifest. Both R8 copies and the historical V compiler have matching
donors. No file was cloned or restored, and the archive/checksum remain intact.

The read-only receipt is
`/Users/alex/.local/state/vinix/android/inflater290-rehydrate-analysis-final-2026-10-26.json`,
SHA-256 `daccb79ac50ee22e0142ec69d3e051c91ac85b85821d878ca5ad16c51b6d7ed0`.
It records each expected hash, size, mode and validated donor, plus consumed
source/binary and manifest pins. A future clone rehydration would require fresh
donor checks, full typed comparison and unchanged original-auditor passes before
changing archive retention. That work was paused when unrelated storage release
restored the build gates; the complete archive remains the retained original.
