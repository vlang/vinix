# Authenticator descriptions: host validation, 2026-10-26

Provider source: `0a52b1112`. ART fixture source: `a05d244b3`,
`tests/native-android-ws/account-token-fixture.v`. The value contract follows
[AOSP Android 14](https://android.googlesource.com/platform/frameworks/base/+/android-14.0.0_r1/core/java/android/accounts/AuthenticatorDescription.java).
Discovery remains native and reads authenticated installed authenticator metadata.
The provider contains no fixture authenticator descriptions.

Provider guards and DEX assembly/disassembly **PASS**. The isolated source closure,
commands, logs, binary, DEX and input hashes are retained at:

`/Users/alex/.local/state/vinix/android/authenticator-descriptions-check-2026-10-26-r2`

`receipt.json` SHA-256:
`7bfbaab6336ca9536ceeb416d67d5aa770d730f4b24f220595f0fa6dde060629`.
Reproduce with the committed `authenticator-description-source-check.v` runner,
passing the pinned V compiler, repository root, fresh output, smali tools and Java.
It checks query replacement/rejection, class fields, constructor null behavior
guards, parcel order, Creator bridges, and a DEX round trip. Independent review
identified and corrected a merge of distinct uninitialized exception references
before source freeze; assembly alone cannot detect that ART verifier error.

The fixture generator host build and its `--smali-check OUTPUT TOOLS JAVA` mode
**PASS**. Complete generated source/DEX evidence is retained at:

`/Users/alex/.local/state/vinix/android/account-token-authenticator-smali-2026-10-26-r2`

`sha256.json` SHA-256:
`0250a3f91ec33def13853351b075fc35ba55a905196a3ed9f1d2f7dcd4e48813`.
The bundle includes the exact fixture source and host binary, Java and jar input
hashes checked before/after validation, command records, generated smali, DEX and
disassembled classes. These hashes identify the listed inputs, not a complete
compiler/JVM installation. Independent source review found the final generated
registers, constructor argument counts, exception handlers and interface calls valid.

For subsequent ART execution, ordinary `TokenCacheClient.run()` first invokes
`AuthenticatorDescriptionProbe`: both constructors, null rejection/messages,
empty strings, signed resource IDs, key defaults, equality/hash, Parcelable order,
erased Creator methods, array typing/zero slots, negative length, and byte values
2/-1 decoding as false. It then queries real fixture metadata and resolves the
label through Resources, requiring exact type/package/customTokens, nonzero equal
icon IDs, and zero preferences. Its marker is `ACCOUNT-AUTHENTICATORS-PASS`.
The service declares the standard action and binding permission plus metadata XML;
the older cache action remains available.

No APK was regenerated for this validation, and ART was not executed here.
The later APK resource/manifest build and actual guest run must pass before
claiming these behaviors work at runtime. These checks use no Google credentials
and establish no Google login success.
