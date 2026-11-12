# Measured Internet validation

Maps' awma network monitor reports disconnected when none of its networks has
NET_CAPABILITY_VALIDATED. Vinix previously exposed route availability but never
this capability. This is a concrete compatibility gap; it does not by itself
prove the cause of the blank renderer. The contract is documented in Android's
[network-state guide](https://developer.android.com/develop/connectivity/network-ops/reading-network-state)
and [NetworkCapabilities reference](https://developer.android.com/reference/android/net/NetworkCapabilities).

The SDK now starts one asynchronous HTTPS probe per process when a configured
default link is queried. Only a successful, normally certificate/hostname-checked
HTTPS 204 response from https://www.google.com/generate_204 can grant validation.
Redirects and caching are disabled. Connect/read timeouts are 3000 ms; responses
taking over 10 seconds cannot grant validation. DNS itself may exceed those
socket timeouts; a stuck worker prevents more workers and cannot extend freshness.
There is no reachability claim before a successful probe.

Results expire after 60 seconds, failed probes revoke validation, and a change
in the selected kernel state invalidates the cached result and any in-flight
generation. Probes are normally at least 30 seconds apart. Public snapshots and
the existing callback poller use the same state bridge. App reports do not grant
validation. Metering, radio activation and network-activity events are unchanged.
The backend still supports one selected default link. Its state contains an
interface index, transport and route flags, not a complete route/address epoch;
changes invisible to that state cannot be distinguished between polls.

The signed API fixture explicitly checks a real HTTPS validation result,
INTERNET, conservative metering, and an offline manager that app reports cannot
promote. Offline synthetic callback tests retain their controlled state bridge;
the general startup suite remains usable without a working Internet endpoint.
Historical fixtures and evidence are unchanged.

Evidence under `/Users/alex/.local/state/vinix/android/`, available V 0.5.2
6f888d6. Final guarded runs explicitly retain RSS 629145600, wall 300000 ms,
reserve 1073741824, growth 536870912 and output 4194304; all exit 0/0 with cleanup:

| Artifact | Elapsed ms | Peak sampled RSS bytes | Shared growth bytes |
|---|---:|---:|---:|
| network-validation-builder-emit-20261113-r1 | 2358 | 454000640 | 3125248 |
| network-validation-builder-cc-20261113-r2 | 413 | 134856704 | 933888 |
| framework-network-validation-20261113-r2 | 2044 | 511393792 | 28704768 |
| current-api-network-validation-20261113-r3 | 903 | 128860160 | 737280 |
| maps-current-20261113-r74 staging | 4610 | 38551552 | 151392256 |

Source snapshots, generated host C, compiler logs and receipts remain external.
Earlier monolithic builder compilations used the guard's broader default and
sampled about 664 MB. They are not original-cap passes. The final producer emits
C and compiles it separately within the original cap, using V's normal Unix
signal-handler header. Earlier fixture versions without the explicit live probe
are also not Internet-validation qualifications. r73 was stopped before testing
and replaced with fresh r74 carrying that probe.

SDK jar SHA256 aba6c0b35243e103486b7cfbda62389e523ad067246987de9093a2f54802ff47;
signed APK 261f154253814e0f5cc076aff66827e44544bba1d45aac35779875281f4f5663.
r74 retains the non-JIT unbound-GL native r4, expiry-fixed protocol/launcher,
memory controller r4, mandatory core/TLS jars, 12 GiB/4 CPUs and 8 GiB app disk.
Volume identity 3cd95ec50d7947a382fd2e224536a596, inspection, read-only e2fsck
and initial hash passed before boot.

The signed ARM regression passed as UID/GID 10160, ready/pass once, drained EOF,
exit 0. Its child log records VINIX-NETWORK-VALIDATION HTTPS-204 followed by true
and NETWORK-VALIDATION-PASS, plus the existing GL and API markers. Snapshot
network-validation-api-uart-20261113-r1 full SHA256:
29b22a2bbdbf9cd9494311bcd4577a8cf6639a2fba9429899a5154d25c70b648;
receipt 2287e59c0ded3f89446bfcc497c26f8204f9f40682e5178201b952b31ebfd842.
Readback reconstructs the unchanged two-entry export with zero removals:
archive 86994281caccfc326e6808fb4af3438083b54a51205a07a1df239b7179191ea7;
child 642eac0f1afc2c428897a471183ef59b06f7bccc9148d61ff0858688b59cdb05.

r74's actual Maps log records an initial failed validation and repeated later
HTTPS-204 successes. Explore rendered with a blank map. During a Louvre search
attempt after confirmed focus, the main looper exited on the missing
JobParameters.getNetwork API. No search result, tiles or route geometry passed;
sign-in was not attempted in this run. The root broker remained ready.

The complete 600238 ms watch retained at least 4593424 KiB free memory and
7246233600 bytes free app storage. After sync returned a guest prompt, owned
QEMU PID 62482 was stopped and verified absent before read-only extraction.
maps-current-20261113-r74 retains screenshots, logs, receipt, complete UART,
raw image and retained.sha256. Final image SHA256:
c3af58cdf7422e4b2d82e849174ea9d55e76cdccd5612a2c424cc89b80118f1d;
Maps log 81845c2b5787b5d3a8f0dd8cf99a33a7485cf2613f26f5cd4cafd45e9ddaf6e2;
broker log 7f41f3ee3a1db6ad70b73b9d5079c2d37eb8f75bcd58162582244f811d68c088;
receipt 489f3e6dd507606b85fa35a432f1a20fcdd471b003e39702f2a864cf56695f9b;
UART bdf5734d90e166f5a833428323dfd6c9ba192d782221ccdbecd27237139f31d0.
The next [job/key-parameter repair](maps-job-network-keygen-runtime-20261113.md)
passes its signed ARM regression. Full Maps remains pending.
