# Supervised failed diagnostic recovery

The fixed native02 and ARM03 helpers preserve two failed Launch options fixture
attempts. They establish no native acceptance. Source preparation is based on
`17c1a196180acf2a5a1ae7580d219124aaf980f1`; all results remain under
`/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a`.
The native02 recovery completed under its separately authorized storage lane.
ARM03 recovery remains pending; its helper has only host build qualification.

Each helper requires its exact image and serial failure, copies all five
controller siblings into the archive, and admits only regular files, literal
symlinks and directories. The unchanged historical sealer checks the complete
original before and after the independently qualified strict gzip/all-member
reader. Archive, manifest, source, tool and sibling hashes and the original
directory's device/inode must agree before removal of the single hardcoded
expanded root. ARM03 additionally binds and rechecks native02's successful
completion receipt, archive, manifest and sidecar. The separate diagnostic copy
and external inputs remain outside both removal scopes. The internal native02
`iso/limine` symlink targets an archived empty directory. Directory metadata is
unsealed; regular-file bytes and literal link targets are authenticated.

The supervisor uses actual `/bin/df -k` on the fixed APFS volume: at least
550 MiB available initially, a 256 MiB refusal floor and a 210 MiB archive cap.
It samples while the helper runs, with a 30-minute wall deadline and five-second
`df` and cleanup deadlines. These are discrete observations. It drains output
while monitoring; child failures retain their complete separate logs and return
errors capped at 2,048 bytes. Final binding refusals are recorded in the receipt.

Cleanup uses raw negative-PGID signalling independently of `os.Process.status`,
requires the leader's actual `ECHILD` condition and group `ESRCH`, and never
signals a positive PID after the leader is reaped. Already-empty groups require
no kill. This is a trusted host, stopped-writer recovery procedure: after leader
reaping, a numeric PGID probe establishes existence rather than group identity.
It does not guarantee protection against adversarial PGID reuse. No general
process supervisor or concurrent-writer qualification is claimed.

All host tools built with compiler SHA256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`,
`-prod` and the default collector, without ASan, allocation tracking or manualfree.
The first supervisor compile refused an untyped map in an `if` expression; its
argv, compiler log and exit receipt remain unchanged. The typed-map retry is
recorded separately by [build-supervisor-retry.v](build-supervisor-retry.v).

| Source | SHA256 |
| --- | --- |
| `archive-native02.v` | `8f633f855c8470d415c39958d5ab27d913f323008eb17329257360f24b4092ba` |
| `archive-arm03.v` | `18dacd1796e44cb4c9cf541cb9d1c20e41f55966a34f65755a2712e5087b5be9` |
| `recoveryguard/recoveryguard.v` | `85859c002c42ba44e944ca7b80d1894c27150669e89fa98bd0f4438ae5fa8517` |
| `supervise-recovery.v` | `0c476c1b7547b2b22bc25fdc46d19b0e8804b675e285ad760ed8a601c6e5d372` |
| `recovery-guard-check.v` | `79fb0bd5bdd135787eac239a0cc91067184ad8ad0d381798aad29b5aa18dcdfc` |

The nine explicit checks passed in `recovery-guard-controls-01/results.json`,
SHA256 `2bad64852df92bf3fb037358fcc734c41d5a5b0da782dd4ce4bd9033f07f8437`.
They cover four error-message lengths, deadlines before/after expiry, exact
one-MiB failure output with exit37 and literal argv, a reaped leader leaving a
live descendant holding stdout, and repeated cleanup of the empty group. The
group case observed `waitpid=-1/ECHILD`, the intended live descendant/group and
held pipe, then group/descendant `ESRCH` after about 30 ms. Controls use explicit
checks under `-prod` and bind source/module/executable hashes before and after.

| Retained host build receipt | SHA256 |
| --- | --- |
| `archive-native02-build-01.json` | `63b0a776420146dc69da5c0014716ad61414d15429bb6313948fce5eea6ceeb9` |
| `archive-arm03-build-01.json` | `84388776863d8606c318442a02bd04b300081d6d579ece6f4cb6615c470cc5cf` |
| `recovery-guard-check-build-01.json` | `bb4cdead27303817049c3fc4bdbeafb51c8e9434eb3a74f2d4d346c52e4a085a` |
| `supervise-recovery-02.build.json` | `edd638abae28de39fa96743ce37ae0cf806439bc2fb8d1a2940f880819354742` |

These receipts bind exact compiler argv, source/module and executable hashes.
The supervisor executable SHA256 is
`d307810645466b8a2aad195e4aa9066d6dba983644d5d54157a9f9dfc4cfb9d9`.

The fixed native02 execution retained the original signed-child grant-open
failure. Complete original inventories passed before and after the strict
archive reader, which authenticated 1,198 entries: 1,188 regular payloads and
10 literal symlinks, with 501,434,368 decoded bytes. Final source/tool/sibling
pins and the original device/inode agreed before the expanded tree was removed.
The 199,299,827-byte archive and standalone manifest remain in
`failed-diagnostics/`; the five controller siblings and external inputs remain
outside the removed tree. This preservation does not qualify the failed fixture.

| Native02 retained artifact | SHA256 |
| --- | --- |
| `native-x86_64-02.tar.gz` | `3ad31681fbd48834d0a9ddc7207a88809646a94490f028ff6893a04dcee1f539` |
| `native-x86_64-02.bundle.sha256` | `dccac59ea84db131ced2ae2c1e4df18adf188e931817395749ad0a9120e2845a` |
| `native-x86_64-02-stream-reclaim-01.json` | `2d187a24d13ff2ee2551badb641c7d44492ed1ce50670ccfddfeff6c4a11e1a3` |
| `native-x86_64-02-supervision-01.json` | `a93030c1a7629ff5c535445e65fdf4984472b847de450b0c023065d4b423d882` |

The supervisor finished with exit0, no guard refusal, an observed private
process group, and actual leader reaping plus group absence. Its 479 actual
`df` samples began at 2,067,588 KiB available, reached a minimum of
993,872 KiB and ended at 1,531,588 KiB after about 106 seconds. The maximum
observed archive size was 199,299,827 bytes, below the 210 MiB cap. A subsequent
independent `df` read showed 1,392,332 KiB free. These observations do not
attribute concurrent filesystem changes or promise continuous storage bounds.
