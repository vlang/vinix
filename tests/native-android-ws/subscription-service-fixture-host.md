# Subscription-service fixture host qualification

The signed standalone fixture passed host qualification on 2026-11-02. Its
receipt records source revision `64479fdaa625cf1779019671c5cb52cee1a1156e` and
retains both exact V source files. ARM execution remains required.

The one-Main APK uses real Activity and application contexts to check the cached
`telephony_subscription_service` string/class instance and actual provider class
identity. It checks null subscription lists and information for IDs `INT_MIN`,
`-1`, `0`, `1`, `7` and `INT_MAX`. Each phone-number request must throw
`IllegalStateException` with the exact message `subscription service unavailable.`
Fresh same-ID and different-ID TelephonyManager wrappers must remain distinct
and retain their requested private binding; reflection reads only those child
bindings and makes no claim about a public default-subscription-ID API.

Parent, child and explicitly constructed no-argument TelephonyManager instances
must report zero phone/active-modem counts. Repeated lookup after the queries
checks cache preservation. Existing unknown SIM-state and null line-number
results, typed-null StatsManager and cached DevicePolicyManager fallback are
positive controls. The Activity/application/Activity sequence repeats the probes.

The actual invoked nullable list/info helpers retain two
`SubscriptionInfo.getSimSlotIndex()I` references and one
`SubscriptionInfo.getSubscriptionId()I` reference behind the null branches.
The APK supplies no platform stubs. Host checks verify this exact tuple in the
generated Main and both canonical roundtrips; actual ART verification and runtime
health remain ARM gates. Preserve every verifier diagnostic and use no health
whitelist. No modem, SIM, phone number or backend success is simulated.

Evidence is external under `/Users/alex/.local/state/vinix/android/`:

| Artifact | Path relative to evidence root | SHA-256 |
| --- | --- | --- |
| Signed APK | `subscription-service-fixture-2026-11-02-r1/probe.apk` | `c841324557b839b051bceb8f847d9e943cb69139ebe09d0422b13938164853e5` |
| Build receipt | `subscription-service-fixture-2026-11-02-r1/build.json` | `311daae7d07a18b2ff6a88a9173e751a3f3d685373570646036c9873ed758cd8` |
| Checked DEX | `subscription-service-fixture-2026-11-02-r1/classes.dex` | `a01565e7ac792009129e5844ce70129ff5429970f18a8964dbd126c678864d01` |
| Generator source | Git `subscriptionservicefixture/main.v`, retained `inputs/main.v` | `2d085c310de911b22350ff72457d06a89aef2e5ede1c639d609fece188831d2f` |
| Probe source | Git `subscriptionservicefixture/sources.v`, retained `inputs/sources.v` | `5175711fa7e6623115f49b94cfb5299eb2d8e6d5402e9f6400138b0d37ad3b8e` |

Host checks passed exact Main-only membership, API-28 assembly and stable second
canonical DEX roundtrip, APK v3 signing/verification, unique archive membership,
signed DEX extraction equality, and unchanged complete source/tool inputs.
The two guards in `subscription-service-fixture-controls-2026-11-02-r1/` returned
actual exit 0 with cleanup complete. Compile/production elapsed times were
1.778/5.990 seconds, sampled aggregate RSS 325,648,384/80,035,840 bytes, and
`/usr/bin/time -l` maximum RSS 342,589,440/93,061,120 bytes; both recorded zero
swaps. Limits remained 629,145,600 bytes RSS, 300 seconds, 536,870,912 bytes growth,
1,073,741,824 bytes free reserve, 4,194,304 bytes output, and shell file-size limit
16,777,216 blocks. The compiler lane was released after production exit 0; both
evidence roots are closed.

The sole runtime success marker is:

```text
SUBSCRIPTION-SERVICE-PASS service-identity null-list null-info unavailable-phone zero-modems fresh-bound-wrappers dormant-getters fallback-controls
```

The failure marker is `SUBSCRIPTION-SERVICE-FAIL`; the original failure is
rethrown after printing. Runner identity, transfer qualification and future ARM
receipts belong in the distinct `subscription-service-fixture-run.md`.
