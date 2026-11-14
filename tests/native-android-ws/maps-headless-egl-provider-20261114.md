# Headless EGL provider initialization, 2026-11-14

After the bitmap transfer and route qualification in 7796d94ba / 1f7af2db4,
r93's retained Google services log repeatedly showed four workers inside
EGLImpl.eglGetDisplay, including the CheckinIntentOperation executor. The full
private broker log is retained under
`/Users/alex/.local/state/vinix/android/maps-current-20261114-r93/private-readback/r93-private/results/broker.log`,
SHA256 ffdf402d45784cdc3b02b7d29db1a9e30719b88a82da530b1664681c11620e5f.

The headless entry point omitted EGL initialization. ws_egl_symbol passed the
null provider to dlsym, permitting lookup of the adapter's own exported
EGL entry point and recursion. Opening the optional account UI later initialized
the provider, but also recreated the TLS keys and mutex despite existing workers.
This establishes a provider-dispatch defect; it does not alone prove every
Google check-in timeout has the same cause.

The headless entry now prepares synchronization/TLS state before Java starts.
It still creates no surface, fonts, codecs, graphics provider, drawing state,
Activity or Canvas. The first real EGL call loads the existing surfaceless Mesa
provider under a dedicated lock. Repeated calls and later UI attachment preserve
the provider, TLS keys, worker bindings and display leases. Provider/symbol load
failure prints a fixed diagnostic and aborts the affected app process instead
of looking up the global namespace or invoking a null function pointer.
These are required provider errors, not a fabricated EGL capability.

Current V: V 0.5.2 cbfc1be at /Users/alex/code/v/v, executable SHA256
9bde2851cedea03c3e488b0793a356aeb90644d13cf49e10fae6bf5518fff000.
Evidence stems below are under `/Users/alex/.local/state/vinix/android`.
All successful guards used RSS 629145600, wall 300000 ms, reserve 1073741824,
growth 536870912, output 4194304 bytes, exit/child 0/0 and complete cleanup.

| Check | Evidence stem | Time ms | Peak sampled RSS | Observed growth |
| --- | --- | ---: | ---: | ---: |
| Production provider code; eight pthread callers/800 queries; lazy load; repeat UI initialization and stable TLS keys; missing provider/symbol failures; two compiled negative mutations | headless-egl-checks-20261114-r1 | 3331 | 181092352 | 6832128 |
| Unmodified historical headless checker: 29 channel cases, binding ABI mutations, startup/teardown mutations and no-display contract | headless-egl-legacy-check-20261114-r1 | 3193 | 453771264 | 86958080 |
| Full current-source native producer and AArch64 GCC -Werror link | headless-egl-native-20261114-r1 | 18126 | 577650688 | 395587584 |

The initial checker compiler attempt used result propagation on an Option;
that failed attempt is retained. The corrected checker build and checks passed.
Deployable library: headless-egl-native-20261114-r1/native/libvinix-android-native.so,
SHA256 db177fa5a3acbbada0d604a9699ef200b35ae25bfe1eafd060982287fb0c23d2.
It is coupled to framework-bitmap-buffers-20261114-r2 and the unchanged signed
current-api-bitmap-buffers-20261114-r2 shared-display fixture.

r94 was stopped before any protected broker/API run when this defect was found;
owned QEMU34920 stopped with no open image handles. Fresh r95 is staged for
ARM/API validation and an actual Google services/account retry.

The full signed ARM suite passed in r95: runner child exit 0, readiness/pass,
BITMAP-BUFFER-PASS, EGL-SHARED-DISPLAY-PASS and CURRENT-API-PASS. Its UART
archive reconstructed without removals (22567 bytes, 45 chunks).

| ARM evidence | SHA256 |
| --- | --- |
| maps-headless-egl-api-uart-20261114-r1/full.log | 95e2dacac23269d2676001936d431aec67c8bb0f9090c95fc9cd3d92d1e41fb7 |
| maps-headless-egl-api-readback-20261114-r1/archive.json | 077ba3e58e4e943e2cd974798b28549ea52eaf0a86aa5a7ec88dbfc7bd2f6aec |
| maps-headless-egl-api-child-20261114-r1/child.log | d19c6d525ed78ab4219459e830668a36f207b8c172221e0812f238d7327a956f |

The real headless Google services/account retry remains in progress. These
checks alone do not establish that sign-in or full Maps works.
