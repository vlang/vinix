# Ordinary explicit service access: host validation

Core change `217dec6e350c9e99a152a48cd0736d487138e273` validates explicit
`Context.bindService` and `Context.startService` targets before registering a
binding or queuing startup. It requires a declared, enabled service in an enabled
application. Cross-package targets must be visible and exported, with no service
permission requirement. Permission-protected cross-package calls are rejected
until permission grants have a supported authority model; requesting a permission
does not grant it. Same-package calls retain private/protected service access.

The sole changed framework class is `android/app/ContextImpl`. The resolver uses
the Context's loaded-app owner and checks visibility before the app cache. This
is the current compatibility model, not protection against hostile APKs. The
pinned parser has no `<queries>` model. Implicit service behavior is retained.
There is no account broker exception or account forwarding in this change.

## Transformer checks

The V checker verifies unchanged unrelated methods and the original implicit
start body, metadata/access checks before registration, package visibility before
cache lookup, malformed source rejection and rejection of repeated application.
It also assembles the complete transformed ContextImpl into DEX.

The checked baseline is
`/Users/alex/.local/state/vinix/android/account-contract-response-build-2026-10-26/smali`.
The ContextImpl input SHA-256 is
`a2a94a98e52901c7ef03a0a0359552999856db5db73d7d989ba1749f62e4a94f`.
The command passed:

```sh
build/android-maps/check-service-access \
  /Users/alex/.local/state/vinix/android/account-contract-response-build-2026-10-26/smali \
  build/android-framework/tools /opt/homebrew/opt/openjdk@25/bin/java
```

Both TRANSFORM-PASS and ASSEMBLY-PASS are retained in
`/Users/alex/.local/state/vinix/android/service-access-check-2026-10-26.log`,
SHA-256 `fedbb90a9956de27f45f350f4cd02ddea46b29091381c05c02580c59c5ba0837`.

Follow-up `dcb2d755f` validates the lookup, result register, conditional branch,
registration and final false return structurally. Smali label names may change
after assembly/disassembly. Both the original source and canonical disassembly
pass transformation and assembly; inverted branches, missing destinations,
success-returning miss paths and changed return registers are rejected.

## Canonical framework overlay: historical host check

The complete 2,097-class candidate is retained at
`/Users/alex/.local/state/vinix/android/account-contract-service-access-build-2026-10-26-candidate-r2`.
Its sealed manifest SHA-256 is
`57703467f75b8425135ed31ed6b419b75ddba8c6a2ff637b76d36cc43460f0df`;
the JAR SHA-256 is
`7e01a5052c15ee4c5222eaa84cb633dd96d372ecfbbfeb49f1f212c0bba1a921`.
The build preserves the complete input/output trees and command receipts. Source
and DEX readback confirm ContextImpl is the only changed class, and classes.dex
is the only changed JAR member. Provider guards, malformed/reapplication probes,
class/JAR inventory self-tests and pre/post baseline/native integrity checks
passed. The retained native library reference remains
`aa460c06686e2d1f60ea6dd27ab8f158a3b9794440499c6cdc5e7840cafda0cb`.

This historical candidate is not the final runtime baseline. Separate ART tests
found that the shared baseline lacks `android.accounts.NetworkErrorException`;
the service overlay must be rebuilt over the repaired baseline before its ART
fixture can qualify the behavior.

## Repaired 2,098-class framework overlay

The rebuilt overlay is retained, without changing the historical candidate, at
`/Users/alex/.local/state/vinix/android/account-contract-service-access-build-2026-10-26-candidate-2098`.
It uses the repaired authenticator baseline with manifest SHA-256
`36a472320e71eb459896c1d52a8f211f475362fb2c6dada682870bf43b6a2b7b`
and input JAR SHA-256
`9e643451d4d82fc3839c91415947f04d3726aa81967a784d4d26db63e2c88cb1`.
The output pins are:

| Artifact | SHA-256 |
| --- | --- |
| Complete 6,792-file manifest | `4cb40ad627633304a1cab1b236032c148dd1095f6a92575029a9a01c5e94e94f` |
| `api-impl.jar` | `645731503cb26d422a95bf8e2cf5ca66d7d490d0c9c3031f3d6cbad45b333f74` |
| `classes.dex` | `aab3251c6c7263fcd28731731bc493b9cb44098680c291225b88a50daaf48d98` |

The retained builder source is byte-identical to
`tests/native-android-ws/service-access-build.v` at commit
`e55d8f0614b7d74b791cae52f1a3c87351952ee8`. The bundle was built immediately
before that source was committed, so its original receipt records parent
`ae81933fb51667b9594d2eccc98fb6e876a0c8db`. The receipt and sealed bundle are
preserved unchanged. Direct byte comparisons also confirmed the retained
service provider and complete helper source files match the checkout.

The builder disassembles the pinned JAR, retains both canonical DEX trees and
checks the complete class sets before and after assembly. All 2,098 classes
remain present; only ContextImpl changes. Only `classes.dex` changes in the JAR.
Eight invalid class inventories and four invalid JAR inventories are rejected
by the builder self-test. Provider guards and reapplication rejection pass,
and the baseline and native-reference integrity checks pass before and after
the build. The native reference remains `aa460c06686e2d1f60ea6dd27ab8f158a3b9794440499c6cdc5e7840cafda0cb`.
An independent full integrity recheck is retained in
`/Users/alex/.local/state/vinix/android/service-access-final-source-readback-2026-10-26.log`.

This qualifies the rebuilt host artifact for an isolated ART run. Runtime
service-access behavior and Google account sign-in remain unverified here.

## Signed runtime fixture: host build only

`tests/native-android-ws/service-access-fixture.v` builds four signed APKs. The
client tests start and bind rejection for missing declarations/APKs, disabled
services/applications, and private/protected cross-package targets, including a
requested permission. Denied Application startup, service construction or
binding callbacks fail the probe. Own-package private/protected services must
start and bind successfully.

After the client's services have started and its bindings complete, the allowed
companion tests reverse visibility to an already running client service. It also
checks its own Application startup order/count, class loader, resources, returned
component identity, and isolation of queued Intent snapshots from mutations by
the caller and service. A delayed settling turn precedes the pass marker.

The complete host build bundle is
`/Users/alex/.local/state/vinix/android/service-access-fixture-2026-10-26-r3`.
Its `build.json` records revision `14de592a26b1e874aa382c5f2bbf4cf5424181ac`
and the fixture source hash
`4174217f9e06ff67a058b5f43b266f0adba3dae9de560ca613d6a9dd160c63ee`.
The receipt SHA-256 is
`d15ecbc00c4c5bb123b6a69b233d2321e887ee15dcb11d8e5e86c8fe9732869a`.
A V readback verified all 24 inputs and 88 inventoried artifacts, the exact output
file set and both APK hash maps. All 29 command receipts exited zero; all four
smali assemblies had empty output and all four signature checks verified v3.
The adjacent readback is `service-access-fixture-2026-10-26-r3-verify.log`.

The reusable checker is `tests/native-android-ws/check-service-access-fixture.v`.
It reads the complete historical bundle, including preserved generator source,
binary and signing key. Its `--self-test BUNDLE FRESH_OUTPUT` mode rejects ten
copied bundles with missing, extra, nonregular or changed artifacts, incomplete
maps, failed commands, noisy assembly or failed v3 verification. All ten probes
passed without changing the original bundle; evidence is
`/Users/alex/.local/state/vinix/android/service-access-checker-selftest-2026-10-26.log`,
SHA-256 `2f68c43aed0395a4836a8f9922eb95106d19d26d6a52c70438d16234ff336729`.

| APK under the bundle | SHA-256 |
| --- | --- |
| `client/probe.apk` | `1450307d74ee2581cffb516107e4b7bbbf7308d49f32cd9da828daf25926b891` |
| `companion/probe.apk` | `8d8ff1ab471bbcaee659d1a5f12b348a0953eb14a136a81427334cffb12daf3f` |
| `blocked/probe.apk` | `ff0e1edab41f4f847938e24f42f1abec7a5b5181dd4174e803c23de6a1e41994` |
| `disabled/probe.apk` | `9c59d18e48208977675d36eb2fd8673305cdac9b7b31588a7d31394b39419434` |

This establishes fixture construction and transformer validation. ART execution
of the repaired isolated framework overlay remains required; no runtime pass or Google
account sign-in success is claimed here.
