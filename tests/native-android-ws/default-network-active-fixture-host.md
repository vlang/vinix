# Default network activity signed fixture host checks

`defaultnetworkactivefixture/main.v` generates a signed four-class regression
for the actual public instance `ConnectivityManager.isDefaultNetworkActive()Z`
API. It encodes Vinix's no-activity-monitor policy: the actual Context service
and a directly constructed framework instance return true. This is a network
activity/power hint, without a route or Internet-access assertion.

`NoLinkManager` inherits the real framework method while both protected native
link-state hooks throw. `OverrideManager` supplies a false public override,
called through the framework receiver type. These controls distinguish native
link-state polling from the intended policy and verify virtual dispatch.
Neither fixture class replaces a platform class. Reflection checks the actual
declaring class, primitive boolean return and public, nonstatic, non-native,
nonfinal modifiers; a separate null receiver must throw NPE.

Each suite repeats the four receiver roles sixteen times. Two suites run on
the actual UI Looper, alongside one plain daemon-worker suite without a Looper.
The worker uses an eight-second join and one-second interrupt/join cleanup,
preserving the primary failure and publishing completion/failure explicitly.
Source and canonical DEX checks retain these numeric bounds. The fixture
requires the actual aarch64/64-bit process and makes no network changes,
callback registrations or permission requests. These behaviors are encoded
by the fixture; **ARM execution remains pending**.

Host production passed from source SHA-256
`dc66c88fd343844373ba6205b2c3d53dde55121cea89a6079ad0e6c3439adecd`,
with predecessor revision `4c5928ba030ddb4ecbc0949c4b12b35f4836ec4e` plus
the exact fixture source committed with this report. Using
`S=/Users/alex/.local/state/vinix/android`, the complete output is
`S/default-network-active-fixture-2026-11-05-r2`:

| Artifact | SHA-256 |
| --- | --- |
| `probe.apk` | `be0b524b85218bd0f570fe72a0154c97c06bc15c32271e140c3c39eb76090dd2` |
| `build.json` | `e5df2c626e05d30e25acd78b2d803a6134805dd73b00b63e18a8bbe97344987b` |

Fresh API-28 assembly, disassembly, reassembly and second disassembly passed
with exactly Main, NoLinkManager, OverrideManager and Worker, with stable
canonical sources. Signature verification requires v3 and exactly one signer;
signed DEX extraction equals the generated DEX. Signed manifest readback
requires positive manifest/application/activity nodes before checking absence
of permission requests. Package, launcher, tool/source membership and complete
before/after input-hash checks passed. No SDK or native binary is consumed by
this host assembly/signing producer; successor SDK/native and ARM qualification
remain separate.

Frozen source/executable, compiler input listing and complete controls are at
`S/default-network-active-fixture-build-2026-11-05-r2` and
`S/default-network-active-fixture-controls-2026-11-05-r2`. Compile/build passed
0/0 with empty reasons and complete cleanup in 9,792/42,468 ms. Sampled RSS
was 306,937,856/94,470,144 bytes and observed shared growth was
39,194,624/65,351,680 bytes. Both retained 600 MiB RSS, 300 seconds,
512 MiB growth, 1 GiB reserve, 4 MiB output and an 8 GiB shell file cap.
The builder is compiled without `-prod`, keeping its assertions active.

Preserve the complete `r1` build/control roots too. Its successful producer
compile was superseded after independent source review strengthened the
signed-manifest check to reject empty XML output, before any APK production.
The corrected `r2` frozen source matches the committed source byte for byte;
its full signed-fixture production passed. All signing material, command
results, generated sources and original tools remain outside Git. Aggregate
sealing/readback, delivery, ARM execution and GMS/Maps results remain separate.
