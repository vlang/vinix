# Default network activity listener

Based on 596f48829. r69's real GMS account attempt terminated on an uncaught
NoClassDefFoundError for ConnectivityManager.OnNetworkActiveListener. The SDK
had isDefaultNetworkActive but lacked the nested interface and registration API.
The new adapter provides the public static nested interface and its abstract
onNetworkActive method, plus addDefaultNetworkActiveListener and
removeDefaultNetworkActiveListener. Registration is per manager and thread-safe,
duplicate registration retains one listener entry, and removal releases it.
Removing an unknown listener throws IllegalArgumentException; null arguments
throw NullPointerException. The source contracts are the
[interface documentation](https://developer.android.com/reference/android/net/ConnectivityManager.OnNetworkActiveListener)
and [AOSP removal implementation](https://android.googlesource.com/platform/packages/modules/Connectivity/+/8f2c30664d2791000b09912e0a4a340ca33b597f/framework/src/android/net/ConnectivityManager.java).

Vinix has no radio idle-timer monitor. The existing no-monitor-active scheduling
query remains unchanged. Registrations emit no fabricated power transitions,
link changes, connectivity snapshots or Internet-reachability claims. This does
not add a radio power-state backend.

The ordinary SDK extension and complete current SDK builder install the adapter.
Selected DEX readback includes the interface and ConnectivityManager. The signed
regression checks reflection modifiers/declaring class, registration and removal,
duplicate registration, separation between manager instances, null rejection,
unknown-listener rejection and zero synthetic callbacks.

Evidence remains under `/Users/alex/.local/state/vinix/android/`. Available
V 0.5.2 6f888d6 produced the following under the original guard; each exited
0/0 with complete cleanup:

| Artifact | Elapsed ms | Peak sampled RSS bytes | Shared growth bytes |
|---|---:|---:|---:|
| framework-network-active-listener-20261113-r1 | 4404 | 476971008 | 30326784 |
| current-api-fixture-20261113-r2 | 1461 | 189857792 | 80953344 |
| maps-current-20261113-r70 staging | 12436 | 38174720 | 519720960 |

The guard remained RSS 629145600, wall 300000 ms, reserve 1073741824,
growth 536870912 and output 4194304. Source copies and hashes are retained in
network-active-inputs-20261113-r1. SDK jar SHA256:
e8fd203aa2db80f4ce57979d370d54d4cdfb3010f6692a8d31e800a9f673638d;
signed APK e251d3257f813fc4fec1cf822de3ab7011ff2bd5af7889cb6ef10005cc0573bb.

Fresh r70 retains the qualified unbound-GL native r4, memory controller r4,
paired protocol/launcher r2, mandatory core/TLS jars, 12 GiB/4 CPUs and 8 GiB
app-data disk. Volume identity 1989e0d269854f17b4eae7b033b89812, read-only
e2fsck and initial hash passed before boot. The full signed regression passed
on ARM as UID/GID 10160: ready/pass once, drained EOF, exit 0.
Snapshot network-active-api-uart-20261113-r1 full SHA256:
9506677021728f424c0289b021ff4996478167df1af0e1aab8eec1f1b28f60f4;
receipt 5808d20bcf714175ddf6254dacc47d4e61abfa0b8d67837e14bed906b654b56e.
Plan/readback r1 reconstruct the unchanged export with zero removals,
archive 126fa5dd80fd8d54e70d3cf12425ab5ceeff04f637ff2f470955a5dbb232e0f5.
The extracted child log includes NETWORK-ACTIVE-LISTENER-PASS and CURRENT-API-PASS;
SHA256 94c048b526a489f0d6368c464da428f2d89cf807342f714ed0a7cd932c0c2994.
These are byte-export/regression results, not a new historical strict-import pass.

The API bind was released before broker preparation. The real r70 Maps retry
uses normal --broker operation, with extra onboarding/tree/thread/TLS/surface
diagnostics disabled to avoid their timing overhead. Its account result and
map geometry remain pending; the API regression alone qualifies neither.
