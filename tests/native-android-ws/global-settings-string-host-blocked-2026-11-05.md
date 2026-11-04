# Global string-write draft; focused execution blocked by disk reserve

This checkpoint is superseded by the focused-check pass and adapter commit
`8db2b7541`, followed by [complete SDK host qualification](global-settings-string-sdk-2026-11-05.md).
The refusals below remain intact; shared free space later recovered without
another cleanup by this session.

The [process-package ARM regression passed](process-packages-runtime-2026-11-05.md).
The subsequent GMS failure identifies the missing static
`Settings.Global.putString(ContentResolver,String,String)Z` API. Its complete
caller trace is retained at
`S/gms-global-settings-write-audit-2026-11-05-r1/audit.md`, SHA-256
`845d819b96edcac2a70270226ceec71526e6033e7b0f665cbbf3e41321c6933b`,
where `S=/Users/alex/.local/state/vinix/android`. The caller discards the boolean
and forwards dynamic string/null arguments; the actual runtime arguments were
not captured. Original APK, DEX, tool and runtime bundles remain required.

The adapter, focused checker and SDK-profile source drafts passed independent
source review. They remain **unqualified and uncommitted**. They add a narrow
adapter matching the existing `Global.putInt` and `Secure.putString` path:
fresh String-valued `ContentValues`, the supplied resolver's single virtual
`insert(Global.CONTENT_URI, values)`, nonnull URI true, null/SQLException false.
Null-resolver and other runtime exceptions propagate. The provider owns key
validation, permissions, deletion and storage. Existing reads, all eleven old
Global methods and both fields remain unchanged; no persistence or per-user
AOSP-provider equivalence is claimed.

| Source draft | SHA-256 |
| --- | --- |
| `tests/native-android-tools/androidtools/framework_settings_global.v` | `07208bba49f9a283507b8da196aec55ec6277c23388710873606aa6eb83fc340` |
| `tests/native-android-tools/global-settings-string-source-check.v` | `04ad83019b71b9b29283b803caf094c293de260b14da83e37ca9916610e168fa` |
| `tests/native-android-tools/globalsettingsstringcheck/main.v` | `9ca2b0344ad2cbe17298c8121c516233d1a8b73435edeb770079f6f529ded402` |
| `tests/native-android-ws/combined-account-webview-build.v` | `f3be838d97f5c962c1a09cdd5419cc9d5655dafd96bd8617bc96d2c7b312de6b` |

Frozen focused-check inputs are at
`S/global-settings-string-source-tools-2026-11-05-r1/sources`; controls are at
`S/global-settings-string-source-controls-2026-11-05-r1`. The first driver
compilation was refused before launch for `disk reserve` (guard125/child-1,
PID0). The second compilation passed 0/0 with complete cleanup in 1,433 ms,
sampled RSS330,661,888 bytes and observed shared growth4,096 bytes. It used
the pinned V compiler under 600 MiB RSS, 300 seconds, 1 GiB reserve, 4 MiB output
and a stricter 64 MiB growth cap. Both attempts and full logs are preserved.
The resulting `tools/sourcecheck` SHA-256 is
`9cbad7bf34d01616a9e5dfa6af7e87a2f25c32f06b2b8d6bd0d8bfe43d00e29a`.

The actual focused qualification, `qualify-r1.guard.json`, was refused before
launch for `disk reserve`: initial free bytes723,496,960, guard125/child-1,
PID0, zero samples/groups/output and `cleanup_complete=false`. No checker,
internal compilation, Java assembly or DEX roundtrip ran. Its original limits
remain 600 MiB RSS, 300 seconds, 512 MiB growth, 1 GiB reserve and 4 MiB output.
The intended output `S/global-settings-string-source-check-2026-11-05-r1`
was not produced. No API qualification, successor SDK or successor ARM pass
is established by the successful outer-driver compilation.

Next complete the focused checks, commit the adapter/checker, then qualify the
SDK producer and full 2,117-class SDK delta. Only Global may change, adding
one method with no old-method or field changes. Global is outside the 70
native-bound classes; retaining the process-package DSO still requires the
complete canonical/native compatibility audit. Signed-fixture, delivery,
image and ARM qualification remain outstanding. Own VM6224 is stopped and
confirmed gone; the separate CI remains running and untouched. Preserve all
original evidence and failed attempts; do not lower reserves or weaken audits.
