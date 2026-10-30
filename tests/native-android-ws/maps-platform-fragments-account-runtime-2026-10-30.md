# Platform Fragment Maps account retry, 2026-10-30

The fresh retry opened a Google account window, then failed while inflating its
layout: GMS called the missing `ImageView.getMaxHeight()I` method. Maps later
displayed the compositor's stopped/exited message. The previous `pdo` platform
Fragment callback failure was not observed in the inspected results. No login
form, Google authentication or map imagery was validated, and no credentials
were supplied.

This run follows source checkpoint `37a18e8de` and reuses the exact Android
pair from the [ARM Fragment checkpoint](maps-platform-fragments-runtime-2026-10-30.md):
platform Fragment behavior from `05fbcfa9d`, native exception restoration from
`59879ee0b`, and qualified media tools through `f1d2cb425`. The signed fixture
was not repeated; its previous ARM pass applies to this identical JAR/native
pair and remains separate evidence from the real GMS run.

Paths below are relative to `/Users/alex/.local/state/vinix/android` (`S`):

- Immutable preparation: `maps-platform-fragments-r2`, manifest
  `1a079687d54ed8eae5ab881be3f0459d37ce8e69533bc12df48874cf7335199a`.
- Fresh guest, now stopped: `maps-platform-fragments-vm-r2` (`VM`).
- Runtime controls and strict import:
  `maps-platform-fragments-runtime-audit-2026-10-30-r2` (`A`).

The clone and frozen-kernel installation passed their unchanged guards in
12.127/56.417 seconds, with 25,542,656/41,975,808 bytes sampled aggregate RSS
and complete cleanup. The four-CPU, 12 GiB guest started at 10:18:21 UTC with
default QEMU user networking, runner
`06cdf596adae105d363a99792b732808deb611db72fe4d87af1a5bc8500fb0fd`
and frozen kernel
`a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151`.
Its framework JAR is
`6970582da55b15dd30391491d2be2213abe665fe0256167f45cccdd3de25bcd4`;
its native DSO is
`613c6b2c7b1e816a5d7b0694d626a52a5b4df19604a6a224df99ad13055aa74c`.

Both root terminals were opened before the account broker. Saved GUI evidence
shows Maps onboarding, the Add account chooser at 10:21:18 UTC, and a blank white
Google account window at 10:21:41. The private layout-stack capture
`VM/fragments-retry-private-layout-stack.png`, SHA-256
`b1bb608a22b66960c9eed45770909e58965b7e65228a9e56467db586a3fffcab`,
shows `WrapperControlledChimeraActivity.onCreate` reaching `LayoutInflater`,
`gjgi` and `GlifAuthAccountLayout` constructors. Its nested cause is
`NoSuchMethodError: getMaxHeight()I` on `android.widget.ImageView`. An earlier
background device-ID NPE found by the first broad search is a separate finding;
it is not identified as the account-layout cause. The later Maps capture shows
the stopped/exited message. These private-log observations are genuine terminal
screenshots; the public export intentionally excludes private app/broker logs.

The unchanged strict collector accepted all 24 entries and 2,818 chunks of the
complete controller export. Its bounded command exited zero with complete
cleanup, 27,901,952 bytes sampled RSS and zero swaps. The exact after-Maps
interval is 2,238,489 bytes, SHA-256
`d9c181930bc6842dfdc7f23303ef13437e47baea751370d5f66124756527ed91`;
its immutable receipt links to the before-Maps snapshot.

| Retained artifact | SHA-256 |
| --- | --- |
| `A/before-maps/receipt.json` | `e131be3680e1c2ad0ddb4a52c32d62fc7257f6f0f2e96071504da5d5359c92f4` |
| `A/after-maps/receipt.json` | `f064dcdf10e9a8117f43d1ef9364f49b540b5b3a48fdd1949c9ac6dd69140d11` |
| `A/strict/archive.json` | `a43dca50f29a36948e6be6d0eee54c920405e2df1750ac1c61cbd59f5781310f` |
| `A/strict/import.json` | `713d84819541a68b0a692eabbcc4b7ef118c132247f3331f532cc3729b8c2a3c` |
| `A/strict/results/receipt.json` | `fd7b883b5eb647f19546293bee61828b05e2992f51d6120a85919400e0b555ef` |

The controller receipt records `service_ready=true`, `status=failed`,
`broker_exit=1`, an auth-pump failure at stage 1/status -1, and two cleanup
survivors. Those remain failure findings; readiness establishes transport only.
The entire guest was subsequently stopped. The runner recorded SIGTERM for owned
PID 47821 at 10:24:22 UTC. Immediate reconciliation refused a transient live
identity mismatch; a subsequent unchanged `reconcile-stop` recorded absence at
10:24:34 without another signal or bypassing ownership checks. Both receipts
and the post-execution provenance note `A/operator-notes.md` are retained.

The VM, runtime audit and four original clone sidecars were closed to writes.
The unchanged streaming sealer
`b12a4d0b2b133714da6876a0ed5cda623984dc72284c482d8e3ae57975304e77`
sealed all six roots and 406 entries, then passed a separate fresh-process full
readback. The complete manifest is
`S/maps-platform-fragments-runtime-sealed-2026-10-30-r2/sealed-retry1/manifest.json`,
SHA-256 `242110614bf75f4a9c737bbe146fd8c33124f0798fb6b8524e55cb2f54c5fd80`.
Seal/readback took 9.342/5.687 seconds, sampled 14,008,320/13,352,960 bytes RSS,
and both exited zero with complete cleanup and zero swaps. Caps remained
600 MiB RSS, 900 seconds, 64 MiB observed shared-volume growth and 1 GiB reserve.
The first seal attempt exceeded the same growth cap at 76,120,064 bytes after
12.281 seconds; its failed controls and incomplete output remain preserved.
The successful retry changed neither evidence roots nor caps. Retain all
original bundles and historical auditors; this report does not replace them.
