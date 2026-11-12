# Maps JIT experiment

The experiment changes only ART's -Xusejit:false option to true. It retains JNI
checks, image compilation policy, memory guards and session deadlines. It is
not enabled in the repository default: the runtime results below do not
establish a Maps improvement.

Evidence is retained under `/Users/alex/.local/state/vinix/android/`.
current-native-jit-20261113-r1 was built with available V 0.5.2 6f888d6;
native DSO SHA256 b73335584754d62e43f87d4445aaaad83238930f681f8160c00aa1710e78988c.
The native producer passed its original guard: 11768 ms, peak sampled RSS
477380608 bytes, shared growth 15065088 bytes, exit 0/0, complete cleanup.
Both fresh ARM guests used 12 GiB/4 CPUs, listener SDK r1 and signed API APK r2.

r71 passed the signed API regression. GMS actually compiled methods according
to jit.cc logs; a retained single-process maps/stat sample also records its JIT
mapping and matching process start ticks. Maps was launched too late to finish
onboarding before the unchanged 15-minute broker limit. Its white screen is an
incomplete UI attempt, not evidence of a JIT crash or completed Maps test.

r72 additionally deployed the expiry-fixed broker/DSO/launcher pair from
auth-expiry-protocol-build-20261113-r1. It passed the signed ARM API regression:
ready/pass once, drained EOF, exit 0. jit-expiry-api-uart-20261113-r1 has full
SHA256 8894b1808ae37cd8e5a437f052b1276ceff7ed3a43a4a39ea424615e45f0f38f,
receipt 18130dcadd6ccce1be4de00aa48821847ca9e33ed9291be59f8c34f6becb3aea.
The unchanged byte export reconstructs with zero removals, archive SHA256
274ecffad3e2839858f390282d398c7555303da53242841d65310d1258e1c703;
child log 1c4639d876c07b83ffadbbaf4a6b6a73e57a75c36a6b9200208d2bc1cc6d2072.
These API checks do not include the general startup connectivity scenario.

Maps rendered onboarding and the Add account chooser. The account window
reached the Google server communication error page. Maps subsequently exited;
its retained log includes an uncaught UnsupportedOperationException from
AccountManager.vinixAccounts (account query failed or timed out), followed by
self-termination. The broker receipt reports failure after GMS exited. No
authentication or successful Explore/search/tiles/routes result is qualified.
Further inspection of the retained GMS log found an uncaught missing
KeyGenParameterSpec.Builder.setUserAuthenticationValidityDurationSeconds in
TapAndPay initialization before GMS exits. The corresponding
[API repair](maps-job-network-keygen-runtime-20261113.md) is qualified separately.
There are no recorded auth-pump failures; this retry does not qualify the
five-minute local-expiry crossing or establish JIT as the cause of the exit.

r72's complete 600218 ms watch retained at least 3523936 KiB free memory and
7240908800 bytes free app storage. After sync returned a guest prompt, exact
owned QEMU PID 40882 was stopped and verified absent before read-only extraction.
maps-current-20261113-r72 retains the raw image, screenshots, complete UART,
private logs, receipt and retained.sha256. Final image SHA256:
c6132136ac8384852f430a99d5160af9609e50d8c74a8984ab3afa0b5d1f5fe5.
Maps log 7b13576f4682b9884a50bb1161b970b7b655a5b5c456b0ba3681e5ca63e8a0e6;
broker log b10a44635c74de667458622e62b0a4831ff34e932a21f1b5225ffc2bc22abf86;
receipt 544c49ad1fdd0fe0afaaba2b450b7f40d89a0a3d0c99b7a5713ce3915e68c22b;
UART 2dda7070313b7dd78a047f5c165a0cdc563a0558a77664521fae29ff272f490e.
