# Intent URI ART regression369

The new369 ART regression failed: the unchanged fixture exposed an inherited
`Intent.getDataString()` null-handling bug. The old367 control passed its
expected missing-method check. Both outcomes and the failed host action remain
preserved; no success-only seal was invoked.

The [framework369 build](intent-uri369-framework-build.md) adds the API28
Intent URI parser to qualified framework367. Fixture
`cac9f6367c79fc7de92deb45809502798ddcb123` calls `Intent.parseUri` directly and
checks ordinary URLs, modern Intent URIs, all nine typed extras, grant masking,
Android app URIs, selectors, legacy syntax and malformed-input exception types.
The fixture has eight phase markers and a final pass marker.

Harness `0722b8485772e7325c96a3d90f331bea597180f1` requires the old framework's
exact direct `NoSuchMethodError`, the three ordered application frames before
guest exit 1, and no successful phase. The new framework must emit all nine
pass markers in order and survive the complete 35-second observation window.
Negative semantic self-tests reject missing, duplicated, reordered and altered
markers, exception frames and raw-result fields. Maps has a separate replay.

The same signed APK, native351 library and launcher353 run in both guests;
only the framework JAR differs. Original startup classification remains
unchanged, including the nullable `functional_passed` field.

The corrected harness bootstrap is retained at
`/Users/alex/.local/state/vinix/android/intent-uri369-run-bootstrap-build-b-2026-10-26`,
manifest `0de15d5f6e3f96dabba630779e3b17e34c8c50fff33ddd8a705d8a14191b591a`.
Compilation, semantic self-test and original290 complete readback exited 0.
Independent reader `b25ba56f2` verified all 653 files, the exact file set, the
270 frozen compiler inputs, actual command statuses and linkage to the
preserved original 649-file bootstrap. Its receipt is adjacent at
`intent-uri369-run-bootstrap-peer-readback-2026-10-26/complete-receipt.json`,
SHA-256 `76b6307acc2d7944130d01d264677493e8654910505c637e32a12acc0fb96987`.
The first bootstrap remains intact; the correction strengthens the requirement
that application frames precede guest exit and adds a negative self-test.

Action recorder build helper `a5e6f896a` retains its exact source, executable,
generated C and actual compile/closure command receipts outside the sealed
bootstrap. Its root is `intent-uri369-action-recorder-build-2026-10-26` under
the same state directory. Independent bounded source and receipt review
confirmed actual exit 0, identical 270-file before/after closures, and recorder
SHA-256 `74816f7773b207caf2aa463d4dbaf9a9f7de22cc5f709ae008feab0dead48f24`.
This bounded action-tool review is separate from complete bundle audits.

Recorded preparation exited 0 from 03:15:04 to 03:22:06 UTC on 2026-10-26.
The fixture root is
`/Users/alex/.local/state/vinix/android/intent-uri369-fixture-2026-10-26`.

| Prepared input | SHA-256 |
| --- | --- |
| Fixture source | `c992874027c12aa7d7125246754a646749de01d7ea4034db0d7a3a150e27f36c` |
| Harness source | `09b717df537cb6d320224b53e74405c5ba62b994114443bdfe64d93d4218fd1b` |
| Bootstrap executable | `6244cdb6e9a61cf0ddc438b90b833e3a991049d2031793f3ac2424362b1f9f5e` |
| Checked runner | `3229369e8b908233b6d6dcd0a8b7aa2d45697c734de3e11ebe38c84082e10d33` |
| Signed APK | `710eeaa6cc2b5f0d5ddd0fde5b3b62e71e844220c20584846f121dbbe13eec85` |
| Old framework367 JAR | `fece4cb639fb8745557032f872d13d45767768656ae879f065324696bbf99694` |
| New framework369 JAR | `74e1d74b9ecf51e302f2802a2d291ff15f1d1793495d67c7c108d1d5350a884b` |

The old367 suite ran from 03:27:35 to 03:28:04 UTC and exited 0. Its guest
exited 1 after the first direct parser invocation, as expected. The serial has
one probe start, the exact missing static-method error, and only the ordered
`ordinary`, `check` and `Main.onCreate` application frames before guest exit.
There are no successful phase markers. The unchanged host semantic validator
and recorded old action exited 0 at 03:30:50 UTC.

The new369 suite ran from 03:34:14 to 03:34:48 UTC and exited 0, while the guest
exited 1. It emitted the ordinary, modern, extras and flags pass markers, then
`java.lang.AssertionError: android-app package has no data`. The unchanged host
validator rejected the missing Android app pass marker; the recorded new action
exited **1** at 03:37:56 UTC. No new semantic-pass receipt exists. The action
log SHA-256 is `a68acdc523d229b07feab1d6604200700d4a99194272e88fafba42f254e41cf4`.

Framework369 correctly leaves null data for a package-only Android app URI,
but its inherited getter returns an empty string. API28 requires null there:
the [pinned Android9 Intent source](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r1/core/java/android/content/Intent.java)
leaves `mData` unset for this case and returns null from `getDataString()` when
`mData` is null (lines6037–6046,6083–6085 and6720–6721). Two independent source
reviews agreed that the provider needs correction and the fixture must remain
unchanged. Fresh371 evidence will cover that correction separately.

Read-only preservation helper `tests/native-android-ws/intent-uri369-failure-readback.v`
verified all **52,112** original regular files, shared-input hashes, actual
suite/action statuses, old semantic receipt and exact new failure. Its fresh
output is `/Users/alex/.local/state/vinix/android/intent-uri369-failure-readback-b-2026-10-26`.
The complete external inventory SHA-256 is
`6e2288faa9a4eb14f3a5495a751b1298d1e179e181eba247627880748181da4b`;
the preservation receipt SHA-256 is
`0f91fd7499563acb0cb863b04e078d2390210986d53e8888f9c1f7558a706e96`.
This is a failure inventory and outcome check, not an original290 successful
final-bundle audit. The first readback attempt used an incorrect adjacent action
prefix and exited1; its source and binary remain in the unsuffixed readback
root. The corrected attempt leaves the original fixture root untouched.
