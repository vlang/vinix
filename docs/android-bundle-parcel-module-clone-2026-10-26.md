# Bundle parcel module clone feasibility

Read-only query source: `b5e8d23fd`
(`tests/native-android-ws/apfs-private-size.v`). Queries cover exactly the
`run-old/module` and `run-new/module` directories in the retained
`bundle-parcel363-fixture-2026-10-26` and current
`bundle-parcel365-fixture-2026-10-26` bundles under
`/Users/alex/.local/state/vinix/android/`. These results precede any relocation of
the interrupted 365 new run.

Each module contains 55 files and has 304,607,232 private bytes. The file
`opt/android-test/maps-application.apk` accounts for 304,177,152 private bytes in
each module. All four APKs have 304,176,297 logical bytes and SHA-256
`6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2`.
Their mode is 0644, uid/gid 501/20, link count one, and recorded mtime 1792619534;
the files have distinct inodes on the same device.

The two old module trees have identical contents. Comparing the new module trees
finds only the expected framework `api-impl.jar` difference. The private-byte,
hash and metadata commands exited zero; old/new recursive content comparisons
exited zero/one respectively.

Replacing three APKs with verified APFS clones of the fourth could recover
912,531,456 private bytes, approximately 870.3 MiB, while retaining their content
and paths. This estimate is a per-file lower bound at query time. Independent
source review found no evidence-contract blocker, but future execution must
preserve target metadata, verify sibling clones before atomic rename, compare
complete bounded inventories, and pass the unchanged original complete auditor
for sealed 363 against its original unchanged manifest. This query did not run
that full audit or draft a consolidation helper.

Capacity recovered independently while the analysis ran, so consolidation was
paused. All target files remain unchanged. Seven small query and review records
are preserved at
`/Users/alex/.local/state/vinix/android/bundle-parcel365-module-clone-analysis-2026-10-26`.
All entries passed checksum readback; the `SHA256SUMS` SHA-256 is
`dc1d0b4a225c801aac4d9b74ac739c3157d67e981878070a631447b3a8b68fde`.
