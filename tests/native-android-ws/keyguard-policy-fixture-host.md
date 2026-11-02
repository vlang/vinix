# Keyguard policy fixture host qualification

The fixture uses the real cached DevicePolicyManager through string and typed
lookups in Activity, application and Activity contexts. Three cycles per context
query a null admin and three actual ComponentName objects, requiring zero
keyguard-disabled feature bits while preserving component package/class fields
and hash codes. Reflection requires a public instance method with the exact
ComponentName parameter and primitive int return type. Existing absent device
owner, profile owner, active-admin and managed-device results remain controls,
along with the real KeyguardManager's absent Android-device-credential result.

An invoked helper matches the audited GMS prefix: query a null admin, mask 0x10,
then return false when the bit is clear. The same loaded Main retains the absent
`getTrustAgentConfiguration(ComponentName,ComponentName)` reference in its
unexecuted nonzero continuation. That continuation deliberately fails if reached;
it does not implement or simulate trust-agent configuration. The APK contains
only Main and no platform/policy stub. ARM must still establish runtime verifier
behavior and actual execution; these host results establish neither GMS startup
nor an enabled policy, administrator, credential or authentication result.

The V builder and production pass succeeded on their first attempts. API-28
assembly, two disassemblies around reassembly, canonical class equality, exact
reference assertions, single-class membership, v3 APK signature and extraction
of the signed DEX passed. Production, signed-extracted and canonical roundtrip
DEX hashes all match. Every source/tool input was rehashed after production;
current sources equal the frozen copies. Independent source and generated
artifact reviews passed.

Both guard/child exits are zero, reasons empty, cleanup complete and swaps zero
under the unchanged 600 MiB aggregate RSS, 300-second, 512 MiB observed-growth,
1 GiB reserve, 4 MiB output and shell file-size 16777216 limits. Compile elapsed
1.274 seconds, sampled RSS 312,246,272 bytes and detailed maximum 358,973,440
bytes. Production elapsed 5.814 seconds, sampled RSS 89,833,472 bytes and detailed
maximum 93,421,568 bytes. The compiler/Java lane was released after actual exit.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Artifact | SHA-256 |
| --- | --- |
| `S/keyguard-policy-fixture-2026-11-02-r1/probe.apk` | `e02a832fa82b6531fe8928d119e6113bc1abfe94c722e020f4ede1b4179f0454` |
| Build receipt | `0fd31a84498ecacb324fb58ff5900ddce95d4783a189133d18f0739494c916b4` |
| Production / signed / roundtrip DEX | `5e831bd3a924f9ac1d8fbb63238bf91d1111c7a977f3b78ce61eb04ba6c6d1d4` |
| Both canonical Main classes | `e6ddae939dc18b01ace62d6d3a827173180eb2a55ac79d51ba4ffa3fb912ccd4` |

Complete artifact/input closure is retained in the fixture directory; guard
receipts and logs are in `S/keyguard-policy-fixture-controls-2026-11-02-r1`.
The immutable build receipt records source revision
`d8b6cf50b4700179a5c105048c9c41d5159209bd`. Its exact success marker is:

```text
KEYGUARD-POLICY-PASS cached-manager public-instance zero-flags null-admin component-preservation trust-mask dormant-config unmanaged-controls
```
