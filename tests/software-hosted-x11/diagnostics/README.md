# Fixed hosted diagnostic recovery

These helpers preserve the reviewed recovery support for two failed x86-64
Launch options fixture attempts. They establish no accepted native baseline.
The isolated fixture baseline was `2213d9505f811799b769213d31f0c8b50e0676d8`.
External artifacts remain under
`/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a`.

Each helper accepts only its fixed `--reclaim-reviewed-native03` or
`--reclaim-reviewed-native05` scope. Before removing that expanded original, it
requires the exact failure, complete original inventories before and after an
independent strict archive check, unchanged source/tool/controller pins, and
the original directory's device and inode. It preserves controller siblings,
literal symlink targets and external input referents. The historical manifest
authenticates regular-file bytes and literal link targets; directory existence,
modes, owners and timestamps are unauthenticated.

Both source snapshots are preserved byte-for-byte. The 03 header records its
pre-execution preparation status; the later execution is recorded below. Both
helpers built with `-prod` using compiler SHA256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`.
These are default-collector host builds, without ASan, allocation tracking or
manual-free qualification. The independent reader's separate normal/production
33-control qualification is described in
[evidence-archive-check.md](../../packages/evidence-archive-check.md).

## Attempt 03

[archive-native03.v](archive-native03.v), source SHA256
`f65e6d1a019152fcc191c56475e8fe07e32f8439b6c2bd082501cc2297554caf`,
retains the exact child-ready timeout. Its original image SHA256 was
`a511c6b4908c9b10d4549b1a925c7dd55758009e9b702526bfb0f350b0837871`.
The separate altered-magic filesystem diagnostic copy and all 16 regular
diagnostic files remain outside reclamation, with their hashes checked twice.
They observed the child operands and file effects but are not admission evidence.

The production build receipt is `archive-native03-build-01.json`, SHA256
`0128f4923f27be199d1c79526aa84e1754e6306b81f178ec08cc5d6684ef429b`.
The failed expanded original was removed after the qualified reader verified
1,198 sealed entries: 1,188 regular payloads and 10 literal symlinks, plus gzip
integrity through 501,457,408 decoded bytes. Canonical directory headers are
permitted but unsealed.

| Retained artifact under `failed-diagnostics/` | SHA256 |
| --- | --- |
| `native-x86_64-03.tar.gz` (199,328,527 bytes) | `3e95e212586f1ddcc34d7c857ab064cecfc33a3987c45b1cc57f8bcfcbe63970` |
| `native-x86_64-03.bundle.sha256` | `7bd4274fd3372b4c2d37f9508e330dc332736387422d2af500940aef657156dc` |
| `native-x86_64-03-stream-reclaim-01.json` | `e0dea5aecaf6b860c3a3187ff7c97220dd14b8aad47d36e585a7b693a9d093c5` |

The external supervisor's storage measurements were incorrect: V's macOS
`os.disk_usage` multiplied available blocks by `f_bsize` (1,048,576) instead of
`f_frsize` (4,096), inflating byte counts 256 times. Its active 250 MiB abort
threshold was ineffective; continuous byte-accurate enforcement did not pass.
Separate actual `df -k` snapshots stayed above 250 MiB (lowest observed
429,780 KiB), and the archive remained below the 210 MiB bound. The parent also
independently observed approximately 1.07 GiB before the archive, 846 MiB during
creation and 775 MiB at completion. These discrete observations do not establish
continuous enforcement. The flawed supervisor receipt (SHA256
`458507395f464bde04b8283e9eaffe911b33eb8feb39c5a56537ffe7600e06d1`)
and summary (SHA256
`c17f0096d9394808ca27b091be92c8ad06229450faddc73898df10897b52b4a5`)
remain unchanged. Their explicit correction, calibration and actual `df`
observations are retained in
`failed-diagnostics/native-x86_64-03-budget-correction-01.json`, SHA256
`fccd6ccd7167490becc947f6ed05396aa524ecb9f2a538c59a5a9670aed0dd44`.
The strict archive/content/original/pin/identity checks were unaffected. Future
storage budgets use actual `df -k` output.

## Attempt 05

[archive-native05.v](archive-native05.v), source SHA256
`41aa4312965c92ccb0dd246be8a15822935d48e22c5064ace5d4ec908061ded6`,
retains the exact adopted-child reap refusal. The immediate wait result was not
logged, so its precise cause remains unproven. The qualified reader verified
all 1,200 sealed entries, literal links and gzip integrity before removing only
the failed expanded original. Original inventories passed before and after;
controller siblings and external referents remain retained.

| Retained artifact under `failed-diagnostics/` | SHA256 |
| --- | --- |
| `native-x86_64-05.tar.gz` (199,371,398 bytes) | `0fa18c12ee564d6cd28416f814dcd95bc5cec0858324357dff768c5036f780bd` |
| `native-x86_64-05.bundle.sha256` | `e4e1925b2169b7439c783a621edb916dfee54d80c6a8cdff4203333d82753837` |
| `native-x86_64-05-stream-reclaim-01.json` | `208d4cc5718a49a5c8122361707a9e1be0d4915e16e9ff6568d9ea843f141b6a` |

The actual archive size exceeded the earlier 150 MiB estimate. That inaccuracy is
recorded in the separate retained reclamation summary.
