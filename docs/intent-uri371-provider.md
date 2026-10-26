# Intent URI provider371

The first Intent369 ART run passed ordinary URI, modern fragment, extras and
flags checks, then failed `android-app package has no data`. Parsing correctly
left the data field null; the inherited `Intent.getDataString()` returned an
empty string. [API28 Intent.java](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r1/core/java/android/content/Intent.java)
returns null for null data and otherwise returns the URI text. The fixture's
null expectation is unchanged.

Commit `efac8e8a9dae0259caeb1fd735563485108b9d78` adds a unique-method guard and
replaces that accessor in the existing V provider. Its null branch explicitly
loads null before returning; the other branch calls `Uri.toString()`. Generation
continues to change only `Intent.smali`. The sealed369 framework and failed ART
evidence remain preserved.

`tests/native-android-ws/intent-uri371-provider-check.v` compiled the isolated
provider and checked rejection of malformed class input, missing accessor,
duplicate accessor and duplicate application. Each rejection preserved all four
input class hashes. It checked the generated accessor body, preserved the three
dependency classes and assembled a newly created nonempty four-class DEX. All
seven recorded commands exited 0. These host checks verify guards, generation
and assembly; the separate unchanged-fixture ART replay verifies runtime behavior.

Evidence is retained outside Git at
`/Users/alex/.local/state/vinix/android/intent-uri371-provider-host-2026-10-26`.

| Artifact | SHA-256 |
| --- | --- |
| `framework_intent_uri.v` | `4c9d6b1eb16df32614a41501482cd505292777af91a21fb6a823404340d3b097` |
| `intent-uri371-provider-check.v` | `5a8d4bc0b23c44b32f0ba67fc6adb9dcb1d63cc1d01e03cda46ab0a0d6d787eb` |
| `result.json` | `9a3db16badb328e5169709d70e390c5794bdac964d0a034e9c04fd94fb015381` |
| Input qualified367 `Intent.smali` | `95bdffa01af1b14b2aa01a39bead8e1846ae4f0e4571dc1d4d919ae6a7652064` |
| Output `Intent.smali` | `cf947375973e5e03b7df25c8288d9c899955e86ff0a20c5a299356e2e34a303d` |
| Four-class `classes.dex` | `1be0ff874000d3db0374783e17bee365c8262b48e763d8e784a7ac599971a48f` |
| `assemble.json` | `e48db5cebd4b83e16edeb2092a420473faa71d38c5d88826f6a4313e18a7ac15` |
| Unchanged semantic fixture | `c992874027c12aa7d7125246754a646749de01d7ea4034db0d7a3a150e27f36c` |
