# Browser CPU diagnostic preparation — 2026-10-26

The r9 browser build selects WebKit 2.48.1's Skia CPU rendering path,
disables initial compositing, and supplies its pinned relocated injected-bundle
directory before process startup. Source commit `50bc687fd` contains the
configuration and negative tests; `6ab1f9005` records the earlier guest failure.
The browser's JavaScript success conditions are unchanged.

The complete build is retained at
`/Users/alex/.local/state/vinix/android/browser-probe-build-2026-10-26-r9`.
Its `build.json` SHA-256 is
`2972666ece11534e4a57e5971b109ce64ba38788ec4ec046e28b2d217100a443`.
The builder froze 401 payload files and 15 dependency packages. The session
binary SHA-256 is
`42680036ee5233c9e5f516cc3d88fe6a52687b91a530175acd9c0c45cd1e2354`.

Fresh stage
`/Users/alex/.local/state/vinix/android/browser-probe-vm-2026-10-26-r7-cpu`
preserves all five original Maps372 boot modules and appends the browser
overlay. Its `stage.json` SHA-256 is
`6aa176666cfc35135e93808839e7a1a511025c8da8fccb5368102e58adb344f6`;
the overlay SHA-256 is
`82c915f006ad02491d01d7c07bc90b43677beffb30c22678e413dbc03d328083`.
The once-only installer from commit `9db52fa44` replaced only the kernel with
the AArch64 build already exercised by the r6 Unix socket regression:
`ac90558eac4f2ea6b74c72c3f519370e98e9f88b0a5384aa82cc386bdd1876ce`.
The final boot image SHA-256 is
`bfb7977303b633cbb2fb0a512a5977da7c19fbfd7bfaeb6843dc31fe7c818e13`.
The `kernel-patch.json` receipt SHA-256 is
`f6d7fb9714ad2bda36b377ca24a9b22b10f86c3f0acb81176109e253d588edc3`.
Exact FAT readback, module hashes, firmware state, Limine configuration,
original baseline, frozen inputs and tool provenance are retained beside the
stage. No full runtime composition was duplicated.

Host checks passed for the session, prepare tool, stager and kernel installer.
The checks reject an absent, unpinned or altered injected bundle, replace
conflicting inherited renderer settings, preserve unrelated environment
values, reject changed frozen kernel inputs and protect launched stages.
The FAT fixture verifies exact kernel readback and preservation of unrelated
modules, overlay, configuration and firmware. This preparation is not guest
execution evidence. The credential-free diagnostic disables the WebKit
sandbox and cannot establish production confinement or Google account login.
