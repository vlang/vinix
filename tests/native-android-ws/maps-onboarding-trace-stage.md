# Maps onboarding trace controller overlay

`maps-onboarding-trace-stage.v` replaces only the diagnostic account controller
and its desktop launcher alias over the sealed `maps-broadcast-result-r2` image.
It appends `maps-onboarding-trace-diagnostic.tar` with exactly three regular
files: both identical controller executables and the deployment `build.json`.
The deployment changes only the two controller input hashes. Its framework,
JNI, runtime, APKs and security roles retain their exact existing identities.

The base manifest is
`98522d60a7627927b7ee6b861db502b6574e3d6ab14fdecb09e2da38b2f441de`.
Preparation verifies the complete base and all twenty-six inherited sealed
bundles before and after staging. The fourteen existing modules retain their
hashes and order. Every preceding overlay contributes to the inherited inode
mode audit. Preparation uses APFS clones without a full-copy fallback, bounded
streaming media checks, a 1 GiB reserve and a 512 MiB disk-growth limit. The
source closure, tool identities, command receipts and output checksums remain
in the external stage bundle.

Disk growth accumulates observed volume drops during writable phases without
refunds. Only the initial and final input/media audits and the final output
inventory refresh the available-space baseline: these phases read files and
write no stage files. Media hashes finish before the receipt-writing interval.
The 1 GiB reserve is enforced at both ends; preflight still requires 1.5 GiB.
Other sessions' writes during writable phases remain conservatively charged.
Command and module-hash receipts are writable phases. The final receipt and
seal writes receive separate disk checks printed to the external preparation
log, with the read-only output inventory measured between them.

Build and self-test one tool at a time with the pinned V compiler and Boehm GC:
Record peak RSS and swaps with `/usr/bin/time -l`. Image preparation and kernel
patching need an outer file-size limit of at least 16 GiB for the existing boot
image; the stager's reserve and growth guards remain enabled.

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v -new-compiler -prod \
  -gc boehm -nocache -cc cc \
  -path '/Users/alex/code/vinix/tests/native-android-ws|/Users/alex/code/vinix/build-support|/Users/alex/code/vinix/build-support/android|@vlib' \
  -o /absolute/external/maps-onboarding-trace-stage \
  tests/native-android-ws/maps-onboarding-trace-stage.v
/absolute/external/maps-onboarding-trace-stage --self-test
/absolute/external/maps-onboarding-trace-stage --prepare /absolute/external/fresh-stage
```

Keep the existing stage immutable. Use `clone-maps-account-stage.v` to make a
fresh mutable copy, then the kernel patcher's separate `--maps-onboarding-trace`
profile to install the already validated frozen pidfd kernel. That profile
requires the exact base, new controller producer and fourteen original module
identities; earlier profiles retain their original requirements. The existing
bounded lifecycle runner can boot the fresh copy with 12 GiB and one VM.

Start the guest account controller with
`/opt/vinix-maps-account/bin/maps-account-guest --broker --trace-onboarding`
before launching Maps from the desktop. This opt-in records view trees and
threads in the existing private Maps log. The regular account-result export
continues to exclude that log. This diagnostic overlay establishes no Google
authentication result; runtime evidence must be recorded separately.

## Preparation evidence, 2026-10-27

Source revision `527981b8cf3961a889dcbc2de83553e33d3f2b97` prepared the
immutable external stage
`/Users/alex/.local/state/vinix/android/maps-onboarding-trace-r2` successfully.
Its manifest SHA-256 is
`de315f3f5f0120efbd1368a47e11db945aa9212160fc7e1ff351e522e9435be5`;
the staged boot image hash recorded in its receipt is
`962a9983c22099485fdb8e7e07105e2bcc2c14a33c2dd6a0fef1cc16b33ad070`.
Preparation took 191.96 seconds (93.83 user, 67.09 system), peaked at
68,599,808 bytes RSS, and reported zero swaps. Final charged growth was
163,901,440 bytes, with 5,216,178,176 bytes available. All complete-input,
payload, module-preservation, media-readback and final disk checks passed.

Tools and logs remain under
`/Users/alex/.local/state/vinix/android/maps-onboarding-trace-build-2026-10-27-r1`.
The successful `maps-onboarding-trace-stage-receipt-accounting` executable has
SHA-256 `48f3af7b2d6306b03104099469a47df1acdf46eff62351f0349752b5a8abee44`.
The retained preparation logs are:

| Log | Result | SHA-256 |
| --- | --- | --- |
| `prepare.log` | Failed before output creation: concurrent volume writes during the initial read-only audit counted toward growth. 116.45 s, 35,373,056 bytes peak RSS, zero swaps. | `f9f2938707a0a7ed860909a9f8ee1c1da0c81b40b8fad1a1b3341acf5a912cd3` |
| `prepare-audit-accounting.log` | Failed final guard: eager receipt/image-inventory hashing still counted as writable time. 202.62 s, 67,846,144 bytes peak RSS, zero swaps. Its `maps-onboarding-trace-r1` output remains a failed attempt. | `983fc845b34982d8cd7cc8d03a46e2ce98a8c2cde2a6bc38c272de93283bd449` |
| `prepare-receipt-accounting.log` | Passed preparation of the r2 stage above. | `e4b28e0eff2ace313c48fbbe5cd13b3948e3a110902e9ac17c8522aaedf73b7f` |

These results establish image preparation only. Maps interaction and Google
account authentication require separate evidence from the fresh VM clone.
