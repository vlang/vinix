# Current-V APK memory qualification (r66)

Source: b3a7646ca. Artifacts are under
`/Users/alex/.local/state/vinix/android/maps-current-20261112-r66`.
The fresh VM retains the12GiB/4CPU limit and all original build caps.

The full signed API fixture passed through the rebuilt native launcher as
UID/GID10160, ready/pass once, drained EOF and exit0. UART snapshot
`apk-memory-api-uart-20261112-r1` full SHA256 is
`4cced5c8a4380bdc000a1fea3a449e93270a59720516e63b019c7947193034b5`.
Plan/readback r1 reconstruct with zero removals, archive SHA256
`8fd2a3d7f7e3030d5e61a65b5e629dc4cb86805cc40ac3b48ca08c03e1b05b7c`.

The retained smaps samples show the intended preparation-storage reduction:

| Role | r65 RSS KiB | r66 RSS KiB |
|---|---:|---:|
| Root controller | 2094288 | 205424 |
| Root broker | 655840 | 17632 |
| Service launcher | 1022288 | 81120 |
| GMS ART process | 688816 | 677168 |
| Maps launcher (later sample) | 1083968 | 53664 |

Process names/UIDs and stable start times identify these roles. These are
non-atomic samples at different elapsed times, not simultaneous physical-memory
totals; shared pages may appear in multiple processes. Maps ART's smaps again
exceeded the2MiB capture limit, so its complete smaps is unavailable. That
absence is retained explicitly. Host extraction preserves file contents but
cannot reproduce guest-root ownership; the stopped data image is authoritative.
`memory-retained.sha256` has SHA256
`d3c7750d3f1e12dddc46d82b131bef98a6a2a399df6ef030ba0d93a8485792e9`.

The storage watch completed600238ms with minimum app-data space7227637760
bytes and MemFree4758096KiB (about4.5GiB). No kernel OOM kill was logged.
This establishes that observation, not indefinite stability or Maps completion.
Louvre search loaded real Museum details,4.7 stars/382540 reviews and photos.
The map remained beige, without tiles/geometry. Routes were not retried in r66.

After the completed watch, avatar / Sign in reached GMS PreAddAccount/check-in
and FRP processing, then a native SIGSEGV at address0x898,
PC0x8010d9e1b94 on thread33081. The preceding diagnostic reports a missing
BOOT_COUNT static String field; r65 also reported missing APP_OPS_SERVICE.
Their absence is a concrete SDK gap, but is not yet proven to cause the native
fault. The broker then reported account input disconnected and the desktop
reported the app stopped. No login page, credentials or authentication success
was observed. Low memory is no longer a sufficient explanation for this retry.

Read-only focus investigation: neg.onWindowFocusChanged emits nxq, but the
first-DEX subscribers inspected feed performance telemetry. They do not
establish a missing rendering transition. No app flags or focus were forced.
The DEX inspection tool now also lists method references by parameter type;
the original interface query still returns bkue/axmw for blfb. Its parameter
query finds MotionEvent references. No typed nxq parameter consumers appeared;
the handlers above use erased event arguments. Full first-DEX Smali readback
`maps-focus-full-dex1-20261112-r1` passed the unchanged guard:0/0, complete
cleanup,2061ms, RSS277577728, shared growth139747328 bytes.

Only verified owned QEMU99741 was synced and stopped before offline access.
Complete retained SHA256 values:

| Artifact | SHA256 |
|---|---|
| Maps log | cd4bb59c7bf7ee631456faf8c8ab70e7459d612ec14261c2bcb6cf5558210c1a |
| Broker log | 6aef5237f2b02322e296c8188d80464f133b6f5201762fb268cf285b2ccc685d |
| Receipt | 32d78452ec60485754b64914c230dacb54630f1272cdbf39702ed8410a0f4afe |
| Serial | f5917890e9e9726a5ae7cac464882db911a66c23c60a52c2ac3d44a520c6158f |
| Data image | eccfeabc7c255ad60d7ad3b4b5d6f04a43ca924aea8275bd9961d75ac67b63e2 |
