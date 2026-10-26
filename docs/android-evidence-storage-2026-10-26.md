# Android evidence storage assessment, 2026-10-26

No further media cleanup qualified from this assessment. Compound247 cold cleanup
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
