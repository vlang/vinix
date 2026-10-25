# Tooltip280: state assertions pass, fixture SDK setup fails

On 2026-10-24 UTC, the same signed regression APK failed against both
baseline278 and attempted framework280. Baseline278 exited with the expected
missing `View.getTooltipText()` API. Framework280 printed
`BOOTSTRAP-TOOLTIP-STATE-PASS`, then exited with
`java.lang.AssertionError: present attribute invokes override once` at
`TooltipProbe.inflation(Unknown Source:102)`. This attempt is **unqualified**.

The fixture declared minimum SDK 23. Inspection of the runtime SDK selection
and aapt2's API-26 tooltip style variant indicates that the style was excluded
by the fixture setup. This diagnosis comes from implementation and resources;
the failed run did not print its effective SDK. A fresh fixture declares API 26
and asserts both effective SDK values before repeating all style assertions.
No global SDK policy change is justified by this run.

The state marker establishes mutable text identity, independent views,
replacement/clearing, whitespace, content-description separation and inherited
access during virtual button text dispatch. The compiled XML/style/theme
constructor-initialization phase did not finish; neither its pass marker nor
`BOOTSTRAP-READY` appeared. Native WS tooltip popup rendering is outside this
change. No subsequent successful Maps run is established.

Both suite invocations completed naturally with suite exit zero and raw fixture
exit one. The fixed-side observation lasted five seconds, with native library
mappings observed, backend readiness false, process exit true and QEMU alive
before capture. Both raw outcomes remain `startup_failed` with
`functional_passed: null`.

| Artifact | SHA-256 |
| --- | --- |
| Baseline278 framework JAR | `a1b839c77a575a40ddab8d6e264e92c9abcc9de54ae6c3dcefcc0e725c938eba` |
| Fixed280 framework JAR | `360cbd485640fcc6bcf32cd28388b6d48285f21220cb592e00a6b3bbabe71ad5` |
| Shared signed fixture APK | `198c61b8dc48ae9aaeeddf41dc9829d12c77b3bc890f3a745d2cd05142a62a34` |
| Shared qualified276 native library | `5fe27a87c179b97121c368f417936ceebb75752c4a4204b937312ee28da531ca` |
| Completed280 external prelaunch inventory | `716ba4e9f9aeddd8b49543d35f09e74d16d4f7ef8ed8e809f5a0eed3926b68b9` |
| Baseline raw results | `dca068f251f79cd27f803519d908da02a42f8db920bd0108e11f484ef9d29bac` |
| Fixed raw results | `dc29257986f006d9f9524f4f99b624a4b149ac94871505c0fe2b40ab2bdd28be` |
| Complete failed inventory | `0bc40c9a4ae227bcadd77f58672eb88a9a5db3692ec4dc3e4d3193482ff6a9a1` |
| Original positive-check rejection receipt | `bb358a7ab9fdd5eca97461b561e925f0760064b16717e19aab8cab57afc4f142` |
| Complete failure-check log | `920a86cf6c026937f7558d0a5ce0833dfdc1306bf260aeb8fd789273b0ad52ce` |

The tooltip implementation is committed in `1ed005eb5`; that commit also
contains the corrected API-26 fixture. Build tooling for this failed attempt is
committed in `440b2cd10`. The retained source closure contains
127 framework and 83 native files; only the tooltip helper and its registration
change from completed278. Six actual build/assembly/self-test receipt triplets
have exit zero. Native276 is reused, with its independent qualification manifest
`37bfa8ec3449adf8a294e0b1f3ff3cabfa49123c228f308d9919cab7531d5fa4`.
Completed278 manifest
`aa10e659faf39ab1a9b4bf01d2dde791f4ab1fbb9eff007d71e8226fce370995`
supplies build/prelaunch provenance; its runtime qualification is separate.

The failed audit bundle is retained outside Git at
`/Users/alex/.local/state/vinix/android/compound280-2026-10-25`.
The original frozen positive checker rejected this attempt with exit one;
`qualification-rejected-before.json`, `qualification-rejected-receipt.json`
and `qualification-rejected.log` preserve that invocation and assertion. Its
source and binary remain unchanged. A separate failure checker has archived
the complete closure as `failed-sha256.json`, explicitly marked unqualified.
Its independent complete check exited zero, and the wrong-pin negative exited
one. The check log is retained beside the bundle as
`compound280-failure-check.log`; no positive qualification seal is claimed.

From the repository directory, reproduce the archival integrity check with the
retained assertion-enabled checker:

```sh
/Users/alex/.local/state/vinix/android/compound280-2026-10-25/failure-checker/tooltip-evidence check-failed \
  /Users/alex/.local/state/vinix/android/compound280-2026-10-25 \
  0bc40c9a4ae227bcadd77f58672eb88a9a5db3692ec4dc3e4d3193482ff6a9a1
```
