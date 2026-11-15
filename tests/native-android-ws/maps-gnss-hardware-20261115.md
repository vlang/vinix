# GNSS hardware metadata, 2026-11-15

The UID adapter in 6672e3774 passed the full signed ARM suite in r96-api.
A fresh full account retry, r97, used that exact SDK/native/fixture combination.
The host had recovered to roughly 18 GiB free; its 15-second quiet-window
probe passed with only 4341760 bytes observed growth. Staging passed under
the original resource caps. Google services reached authenticator readiness,
then its persistent location worker failed on the missing virtual method
LocationManager.getGnssHardwareModelName()Ljava/lang/String; and called
System.exit(10) at 07:31:22. Maps and Google account UI were not launched.

Vinix's existing LocationManager has no location providers. The new V adapter
adds the model-name and model-year queries, returning null and zero respectively.
This follows [Android's metadata API](https://developer.android.com/reference/android/location/LocationManager#getGnssHardwareModelName())
and the [AOSP service's absent-provider branches](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android10-c2f2-s2-release/services/core/java/com/android/server/LocationManagerService.java).
It adds no provider, location fix, hardware identity or permission grant.
Existing provider and location behavior is retained.

The signed regression checks both queries repeatedly on the real location
service, including a worker thread without a Looper. It also checks empty
provider lists, disabled location/GPS, no last-known GPS fix and unchanged
state after the queries. The SDK builder checks six missing/duplicate baseline
declarations and rejects either already-present hardware method before full
assembly and LocationManager DEX readback.

External evidence root: `/Users/alex/.local/state/vinix/android`.
Compiler: current /Users/alex/code/v/v, V 0.5.2 cbfc1be. Successful build guards
retain RSS 629145600, wall 300000 ms, reserve 1073741824, growth 536870912 and
output 4194304 bytes, exit/child 0/0 and complete cleanup.

| Check | Evidence stem | Time ms | Peak sampled RSS | Observed growth |
| --- | --- | ---: | ---: | ---: |
| Full SDK assembly, readback, eight input refusals | framework-gnss-hardware-20261115-r1 | 2243 | 491028480 | 28012544 |
| Full native producer, generated C and AArch64 GCC -Werror link | gnss-hardware-native-20261115-r1 | 13998 | 588677120 | 51032064 |
| Signed shared-display API fixture assembly/signature verification | current-api-gnss-hardware-20261115-r1 | 895 | 176455680 | 888832 |

| Candidate artifact | SHA256 |
| --- | --- |
| framework-gnss-hardware-20261115-r1/classes.dex | 57453c189505ed80ac5aefbf73fb9954a8fc93b9aba922bf1e75a32ade57b5af |
| gnss-hardware-native-20261115-r1/native/libvinix-android-native.so | 4403f4cd994d142e71b12a72513601a76029960dc1056ee24c183727bcf9fe0b |
| current-api-gnss-hardware-20261115-r1/probe.apk | f0e20aba07add746bec16f205b8eca06ba0c8b971cb5828f0a50588fcef33ff1 |

## r97 retained failure

Both terminals verified the persistent data volume, UUID
f58f3184919b4ae983e32dc7b65d5fca. Private results were copied to
/var/lib/vinix/apps/r97-private/results and synced; the copy terminal's mount
check, copied receipt and shell prompt were observed before stopping owned
QEMU58433. PID absence and no open image handles were verified before read-only
debugfs extraction. Read-only e2fsck passed. The storage watch is partial.

The full private bundle is under
maps-current-20261115-r97-account/private-readback/r97-private/results.
The broker.log hash matches its manifest. The exported and private receipts
compare identical. The complete Maps export reconstructed without removals:
1426554 bytes / 2787 chunks. All raw evidence is retained outside Git.

| Evidence | SHA256 |
| --- | --- |
| maps-r97-uart-20261115-r1/full.log | 49ddbd4ec95a6e9c62d1849f7bdedea0939571fbbff153c738a9252516bfadb7 |
| maps-r97-readback-20261115-r1/archive.json | 125bba43439da4b58780e17d2589104afe68cb5de0dfa1fc8da5b45ae6559e6a |
| Same readback/exported-receipt.json | ee419158c02e55138463726b3ec7800f059a2bf7f4cd82260ea8fe7acd1f39a7 |
| Private results/broker.log | 2db01e4ce4ae30db38742a3aff78fce5570a32e5b5b0e16c048d161258e419d1 |

## r98 signed ARM qualification

The full signed API suite passed in fresh r98 with child exit 0. Its retained
child log contains GNSS-HARDWARE-PASS, USER-UID-PASS and CURRENT-API-PASS;
the absent hardware/provider/fix assertions also passed from a worker thread.
The complete API export reconstructed without removals: 22759 bytes / 45 chunks.

| ARM API evidence | SHA256 |
| --- | --- |
| maps-gnss-api-uart-20261115-r1/full.log | 0e1fa1fe9559470e3eb13762178e973409204a022f30e0d024d48fdbba76ccfb |
| maps-gnss-api-readback-20261115-r1/archive.json | ac0ceeeb34ed387ef3c33311be07bd8e3fa3d30529910e67cbf9c277e18f5de1 |
| maps-gnss-api-child-20261115-r1/child.log | adb55ff6cf7b97610a3cc216d9d4c24b03dc3694ed14c521d3c0e369b7ff0db2 |

The actual Google services retry is in progress in r98. No full Maps or Google
authentication claim is made.
