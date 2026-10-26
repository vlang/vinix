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

| APK under the bundle | SHA-256 |
| --- | --- |
| `client/probe.apk` | `1450307d74ee2581cffb516107e4b7bbbf7308d49f32cd9da828daf25926b891` |
| `companion/probe.apk` | `8d8ff1ab471bbcaee659d1a5f12b348a0953eb14a136a81427334cffb12daf3f` |
| `blocked/probe.apk` | `ff0e1edab41f4f847938e24f42f1abec7a5b5181dd4174e803c23de6a1e41994` |
| `disabled/probe.apk` | `9c59d18e48208977675d36eb2fd8673305cdac9b7b31588a7d31394b39419434` |

This establishes fixture construction and transformer validation. An isolated
framework overlay and ART execution remain required; no runtime pass or Google
account sign-in success is claimed here.
