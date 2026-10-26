# Intent URI provider369

Maps368 reached a missing `Intent.parseUri(String, int)` call in the GMS
Icing/AppIndexing worker. Source revision
`44ce06920f33b3a1d4c9ca0ae0c87642f2e6f665` adds the API28 parser and its
`getIntent`/`getIntentOld` entry points to the V framework generator. The provider
changes only `Intent.smali`; its dependencies already exist in qualified367.

The implementation follows [AOSP Android 9 Intent.java](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r1/core/java/android/content/Intent.java):
ordinary URLs, modern Intent fragments, typed extras, grant masking, selectors,
Android app URIs and the legacy fragment grammar. Source bounds have defensive
copying and ordinary-copy/filter-copy behavior matching API28. Independent source
review identified the filter-copy placement, which was corrected before assembly.

The bounded host check compiled the standalone V provider, rejected malformed
class input and duplicate application without mutation, preserved all three
dependency classes, and assembled the resulting four-class DEX. All five recorded
commands returned actual exit status 0, and the DEX was newly created and nonempty.
This verifies generation and assembly; ART semantics and Maps behavior require
the separate runtime runs.

Evidence is retained outside Git at
`/Users/alex/.local/state/vinix/android/intent-uri369-provider-host-2026-10-26`.
Its command JSON records preserve argv and actual status; logs, isolated V driver,
input/output Smali and DEX remain in the same directory.

| Artifact | SHA256 |
| --- | --- |
| `framework_intent_uri.v` | `26dfe4e84695f1e5287470a09cb2fb9e1e1d24479846cbb3325d854cc12c0403` |
| `intent-uri369-provider-check.v` | `2bc185767c4594388a233704c381d0c45adc96e4789430f1d96f6ec620b9df3b` |
| `result.json` | `844fba65c7a5f62a2afe50dd2860ccf1fa426b6f266fabd79ddb33f75d36492f` |
| Input qualified367 `Intent.smali` | `95bdffa01af1b14b2aa01a39bead8e1846ae4f0e4571dc1d4d919ae6a7652064` |
| Output `Intent.smali` | `424f5a97b4bb29e93965ad829920271ecdc9447433b378017ed05bb4bd0c9aca` |
| Four-class `classes.dex` | `5a8a1c9b2815385c025c39a734cdfe2d52b6d8a831ddd6c781cba8a75ea302a8` |
| `assemble.json` | `11f8d80a12f13305ff0d9a01134f29b4e6e978f8e07c4160ae45a034579d8e3c` |

The focused semantic fixture is independently committed as
`cac9f6367` in `tests/native-android-ws/startupfixture/intent_uri.v`.
No runtime result is claimed here.
