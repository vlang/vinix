# Maps native heartbeat diagnostic successor

`maps-native-heartbeat-stage.v` adds an opt-in native main-stage heartbeat and
input-read checkpoints to the sealed `maps-onboarding-framework-r1` image. It
retains the repaired framework JAR/DEX, controller aliases, launcher, all 17
existing modules, and all 32 complete dependency bundles. The new eighteenth
module contains five regular files: the native library, its two producer
receipts, the headless input receipt, and the Maps deployment receipt. Only four
deployment input pins and its native manifest identity change; the headless
receipt changes only the library pin.

The separate `maps-native-heartbeat-source-delta.v` checker compares the new
native source closure with the deployed `current-native-build-2026-10-27-onboarding-r5`
bundle. Exactly `diagnostics.v`, `runtime.v`, and `ws_views.v` may change to the
reviewed hashes from commit `206610088`; the other 84 production sources,
binding inventory, generator helpers, generated JNI, and consumed broadcast
framework remain identical. The historical source checker and profiles remain
available with their original inputs.

The producer reuses the sealed private-VROOT bootstrap and old broadcast
framework for identical generated JNI. The guest retains the later onboarding
framework. The stager verifies both complete producer bundles and all inherited
dependencies before and after preparation, uses fresh APFS clones, preserves
existing inode modes, and checks every media module before and after the append.
Its accounting retains a 1 GiB reserve and a cumulative 512 MiB write budget;
each exact 68-byte digest receipt consumes a separate 1 MiB allocation within
that budget. Explicit read-only audits refresh the shared-volume baseline without
refunding writes. The outer process guard measures aggregate RSS, elapsed time,
volume growth and bounded output; no shell file-size limit is claimed.

`patch-kernel.v --maps-native-heartbeat` accepts only this exact profile: 17
preserved modules plus the heartbeat overlay, 34 complete dependency seals,
strict receipt deltas, and the frozen pidfd/wait kernel. Generic fresh-clone
validation remains unchanged. Runtime validation and Google login remain pending
until the new sealed image is booted and exercised.

Preparation, build identities and measured validation will be recorded here
after the strict native producer and successor checks finish. Generated evidence
stays outside Git under `/Users/alex/.local/state/vinix/android`.
