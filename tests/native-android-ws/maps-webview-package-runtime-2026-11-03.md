# WebView package query ARM pass and Cronet class-loader failure

The signed WebView provider-package regression **passed on ARM**. GMS then
reached authenticator readiness but exited during the idle check: its extracted
Cronet module cannot resolve `android.content.Context`. No manual Maps launch,
Skip, search, tiles, route, Sign in or credentials occurred. Current imagery,
Maps rendering and authentication remain unverified.

Source revision `48313931125d9f3bea9c31343e9f4850f80d9c3d` contains core
`e6035988e`, producer `63e1e4374`, fixture `510c631a3`, delivery `40c9b3847`,
[SDK/native pair](webview-package-pair-2026-11-03.md) `52fd96047` and
[media qualification](maps-webview-package-stage.md) `0a150c3ba`. The SDK
keeps 2,117 classes; only WebView gains the public static nullable query. Its
42 existing methods, two fields and six native declarations remain unchanged.
The newly coupled native library retains complete producer provenance.

Paths below use `S=/Users/alex/.local/state/vinix/android`. Complete evidence is
at `S/maps-webview-package-runtime-audit-2026-11-03-r1` (`A`), both
`maps-webview-package-live-controls-2026-11-03-r1/r2`, preparation controls,
prepared `maps-webview-package-r1`, unbooted failed VM r1, stopped VM r2 with
both four-part clone sidecars, and `webview-package-api-transfer-live-2026-11-03-r1`.
`A/runtime-result.md` closes the saved plan without rewriting it. All historical
complete bundles, failed attempts and original auditors remain required.

The isolated UID/GID 10153 child 338 exited zero with six exact input hashes and
eleven unchanged checks. Receipt SHA-256 is
`3b9afaf6a38d2fbbb278a0ed37afd622b4cb9968b8cd322ec3355b1362aa1668`.
The complete 9,823-byte, 112-line child hashes to
`8d422a403b1941bc3990d0c9e6667dee38c287f1f15e17394588b44ed555d5c3`:
sole exact PASS at line 97, readiness at 106 and normal teardown through 112.
Independent `A/fixture-validation.md` hashes to
`5f57dbdfef2a9527fa255753e516608d24c4b9820ab1930e73d382f719b71c4f`.
It confirms source-bound 224 calls in seven batches: cold Activity thread,
plain bounded worker, after that worker, construction/settings, changed
JavaScript, local static data and after destruction. Every query returns null;
metadata, settings identity, normal restoration, worker completion and
destruction checks pass. Exceptional cleanup is source-reviewed, not an ARM
fault-injection result. This fixture establishes no visual rendering or Google
module completion. Unchanged zero-removal diagnostic import preserved all 32
chunks of its 15,914-byte archive, SHA-256
`ab70b8c27fca7a3bc3acb4ccc988379a677cbfe5d7ceacb34342eccc5b9ab8fc`.
This does not extend strict fixture-protocol qualification.

Prepared manifest is
`d6ca42875b50ff239966e42933bd9eab711905e314371b9d68af3c3eb0226b87`.
All 58 module readbacks and complete input rechecks passed in 345,874 ms,
sampled RSS 94,306,304 bytes, observed growth 319,131,648 bytes, both exits zero
and complete cleanup. The first clone passed, but kernel installation hit the
unchanged 2 GiB shared-volume growth limit after 24,709 ms: guard 125/child -1,
cleanup false, sampled RSS 39,469,056 and growth 2,324,037,632 bytes. Its receipt
also reports supervised-group cleanup timeout. Later exact-field process-table
and independent leader queries found no member of groups 59283, 59428 or 60334;
no further signal was sent. The saved absence observation preserves the
original timeout result. Complete r1 scratch/mutation state remains unbooted.

A fresh r2 clone and the same kernel/patcher passed under unchanged limits.
Clone took 5,347 ms; kernel installation/readback took 34,065 ms at 39,600,128
bytes sampled RSS and 496,455,680 bytes growth. Both guards/children exited zero
with complete cleanup. Kernel receipt SHA-256 is
`916be3c5e65cbb64cb6811b02907339c74425c5abee1834d8ed292ce0f099ab7`.
The early desktop's automatic pre-broker Maps window showed APK exited and was
closed before fixture execution; it supplies no manual replay result.

After fixture validation and mount release, the controller ran from 00:36:42
to 00:37:39 UTC on November 3. Receipt
`e35e5f523f50c0ce5f23601333d830338040d42da7a094665fc3c595a55453d1`
records broker 4807, readiness true, failed/exit 1, drain EOF true/status 1,
385,319 bytes and zero cleanup survivors. Private
`A/broker-log-diagnostic/child.log` hashes to
`dd4721b3954520770360bf374a9f0201247778273f66670ca6d21a47e45dee8d`.
At line 8433 DynamiteLoaderImpl reports `NoClassDefFoundError` resolving
`Landroid/content/Context;`. The uncaught StandaloneSchedulingEngine
RuntimeException at 8647 wraps that failure through
`Class.getDeclaredMethodInternal` → `DynamiteModuleApi.onApkLoaded` → Cronet
provider creation. The ClassNotFoundException at 8701 names a DexPathList
containing `CronetDynamite.uncompressed.apk` and native directories, with
`aegb.loadClass` in the stack. Context instances appear elsewhere in the same
log. The app calls killProcess on itself; System.exit and native VM exit report
status 0 at 8708–8709, followed by broker input disconnection. This establishes
the failure path; its class-loader cause requires separate source tracing.

Guest input stayed idle through complete automatic export END. The unchanged
strict collector passed 21 entries, 2,831 chunks and 1,449,120 bytes, archive
`d4c136423997bc7f3e6caacb46fe40cc9e5a2158dc8cdce0739b6eb0368b754d`.
The subsequent complete private-log transfer matched guest length and SHA-256;
qualified canonical-base64 decoding and a separate fresh check passed without
repair. Private logs remain outside the strict account archive apart from hashes.

Owned 12 GiB/four-CPU VM 63658 launched at 00:31:59 UTC. One SIGTERM was
requested at 00:39:13; QEMU records signal 15. Initial stop returned 1 on an
ownership race. Qualified reconciliation returned zero, wrote gone.json at
00:39:29 and an independent ps query returned exit 1 with empty output. No
second signal was sent. Final UART equals immutable after-broker-log/full.log,
2,891,504 bytes, SHA-256
`352af2ca946a8eec3adf107408607e7cee9ccde8f465647f1e4fce0702499383`.
No task compiler or Java ran while the VM was live. All 19 preflight tool,
fixture, firmware and kernel identities passed final readback.

All 16 complete runtime roots, including the failed kernel attempt and its
original cleanup receipt, passed sealing and separate fresh-process readback:
1,097 typed entries. Manifest at
`S/maps-webview-package-runtime-sealed-2026-11-03-r1/sealed/manifest.json`
hashes to
`95c61848a3a3ca89db14e30d67b2a499a11231fa44e350a9cf6a722902e3c88f`.
Seal/readback took 16,873/5,437 ms, sampled RSS 27,590,656/22,986,752 bytes,
detailed RSS 26,345,472/23,543,808 bytes and growth 13,037,568/7,663,616 bytes.
Both guards/children exited zero, reasons empty, cleanup complete and swaps
zero under unchanged 600 MiB RSS, 900-second, 64 MiB growth and 1 GiB reserve
limits. No seal attempt failed; original output/file caps remain unchanged.
