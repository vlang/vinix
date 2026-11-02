# Subscription service without cellular hardware

The new ContextImpl subscription service returns one cached SubscriptionManager
per ContextImpl through both lookup forms. Its explicit monitor covers every
cache read/write; construction completes before publication and catchall cleanup
releases the monitor before rethrowing. Existing service fallback instructions
remain intact, including unavailable stats/hardware services and device policy.

Subscription information/list queries return null for an unavailable backend.
The audited Android 13 phone-number query throws IllegalStateException with the
exact unavailable-service message. The existing WS target has no voice, SMS or
data modem, so phone/modem counts are zero. Subscription-specific TelephonyManager
factories return fresh wrappers storing the requested ID; all 24 previous methods,
the original constructor and existing carrier sentinels remain unchanged. No
default-ID meaning is assigned to the old wrapper's implicit new-field value.

This follows AOSP's [cached subscription-wrapper registration](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-10.0.0_r1/core/java/android/app/SystemServiceRegistry.java#L556),
[unavailable subscription information](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-11.0.0_r1/telephony/java/android/telephony/SubscriptionManager.java#L1173),
[phone-number service exception](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-13.0.0_r1/telephony/java/android/telephony/SubscriptionManager.java#L3758)
and [hardware counts/fresh bound wrappers](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-11.0.0_r1/telephony/java/android/telephony/TelephonyManager.java#L409).
Wrapper availability does not advertise a modem, SIM, backend or permission grant.

The actual failure is cjvx.a's getClass requirement after the string lookup.
Its direct cjzs consumer requires these query/factory APIs and checks subscription
info/list null before record getters. A memberless final SubscriptionInfo type
supports the null return/cast path; records, Parcelable compatibility and getters
are not implemented. The signed fixture preserves the actual missing getters in
the same loaded Main's null-guarded branches to test ART verification separately.
The independent RemoteDevice/Base64 null-array stack's fatal role is unproven.

Source parent: 64479fdaa625cf1779019671c5cb52cee1a1156e. Tested source SHA256:

- framework_subscription_service.v: 770cdcac247adcdd734af33a4bf5d99a678460758bac0385df14f5da11d42add
- framework.v: 83a6706f6c31fa1c78db346f05d0e4222c09dcd06e794260b9e53fbc4e15d1c4
- subscriptionservicecheck/main.v: ed9c979e3f2d9b74ece7f53eba97269ad8e052ca1bed509940f5656eba2cf35f
- subscription-service-source-check.v: 6eb3e2a095643f9846297e83342629fc12e77d4507e213feea89fee3fcad0714

Focused checks passed 116 input/repeat/path-collision refusals and 22 independent
output controls. They cover monitor/error release/catch range, nonzero modem
claims, wrong factory IDs, wrong null/exception behavior and changed old members.
Validation precedes all writes, including a missing later input and regular,
directory or dangling-symlink new-type collisions. The full-builder `.locals 1`/raw
labels and canonical spelling both pass. API 28 assembly/DEX roundtrips retain
exactly 3 original/4 successor classes and stable second-roundtrip sources; the
monitor oracle preserves exact instruction/catch address relationships despite
canonical catch placement and alias labels. Independent source review passed.

Evidence under S=/Users/alex/.local/state/vinix/android:

- gms-required-provider-method-audit-2026-11-02-r1: 9 complete selected classes,
  6 guarded extractions and 2 pinned earlier API outlines. audit.md SHA256
  85d99161ea8c6a4f56ad97aab2c5b1188373b36bc749bd77084e26f896987486;
  SHA256SUMS 688c9e5e6b5b2d2ec74b15e936cab683189b19010e9d6e4f40ce22d0b8eb9b1c.
  Unrelated bmgd extraction is retained and the corrected ibgm stack recorded.
- subscription-service-source-check-2026-11-02-r1: serial generated C project,
  complete Makefile build, final proof-check-r3 and original failed attempts.
  Final receipt 824d06777ef8d887388435a41b25d23ba7350c0732d53059ab9c782ffdc8dc03.
  First checker compile rejected array concatenation; clone/append preserves the
  inventory. Second checker compared an unnormalized expected blank line; its
  whitespace normalization was corrected. Neither changed production behavior.

The final host guard/child exited 0 with complete cleanup and zero swaps. Its 8.048s run
peaked at 246611968 sampled RSS bytes with 40570880B observed shared-volume growth.
All phases stayed within the unchanged 600 MiB/300s/512 MiB growth/1 GiB reserve and
output/file caps; maximum sampled/detailed RSS were 274235392/278331392B. Complete
SDK production, native 70-class equality, ARM verification and live GMS remain separate
gates. This report establishes no authentication or current imagery result.
