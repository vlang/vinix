# Headless native service overlay

The native runtime at `d14ef1ef61f3f675a49ce4bb9a526e24bf2ec925`
starts an exact enabled manifest service without creating a graphical runtime.
The root-authenticated lifetime channel is checked before loading native code;
startup requires a nonnull bound Binder before READY. Controller loss and
startup or main-loop errors share bounded service teardown. CLOSED is emitted
only after successful unbind and destruction.

The complete preserved build bundle is:
`/Users/alex/.local/state/vinix/android/headless-service-native-build-2026-10-26-r5`.
Its `sha256.json` SHA-256 is
`d99195272b8af813679cf54fed9f1e0341e6f1115804ac09c1cd2d5a8f942e3e`.
The bundle contains exact source archives, frozen launcher closures, compiler
and reused-input hashes, command receipts, generated C and compiled outputs.
The maintained builder is `headless-service-native-build.v`; its frozen source
SHA-256 is `26af7c355ad7cfe0301273afa195fc897e72e8f319b5457171ddbf482b0e716c`.

| Bundle file | SHA-256 | Runtime destination |
| --- | --- | --- |
| `native/libvinix-android-native.so` | `643426fa3f910774985e04e5b7903e823093003d081298f81bf459396e705abc` | `usr/lib/art/libvinix-android-native.so` |
| `bin/vinix-android-native` | `1e0e3f94d888e48672f00344afd24bdd5e455d450d8371e5d4e6224b9ce7f413` | `usr/bin/vinix-android-native` |
| `bin/run-android` | `96264b2210a4e7bf62f7c134f398a8df62a8cc6903f7333705518c72d58cdb5a` | `usr/bin/run-android` |
| `bin/headless-service-controller` | `de14d42bba8cc3293a4a671f83d01fa62ad598622fb7c0b8d16673d4e66c9d50` | Test controller |

The overlay uses the unchanged 2098-class companion framework and native
baseline `aa460c06686e2d1f60ea6dd27ab8f158a3b9794440499c6cdc5e7840cafda0cb`
from `account-contract-companion-build-2026-10-26`, whose `sha256.json` hash is
`0ee86be7fd8168eb5dd14d8e6672fb9d54424a7da449dd91945140b75ca736ae`.
The builder verifies reused toolchain and runtime bytes before and after use.
The independent account RPC codec is explicitly excluded from these launcher
builds; this bundle exercises the service lifetime channel only.

Validation completed:

- Native AArch64 shared-library build with `-Wall -Wextra -Werror`.
- AArch64 entry build with musl dynamic loader support, plus static launcher
  and controller builds. ELF architecture and static program headers checked.
- Full defined-symbol comparison: only `vinix_android_native_service_main`
  added; no existing export removed.
- `check-headless-service.v`: 29 channel cases and 12 startup-contract mutants.
- `check-headless-service-lifecycle.v` at `1b7fe5d28`: 24 extracted-runtime
  lifecycle cases and 14 behavioral mutants.
- Independent read-only lifecycle and builder provenance reviews.

This report qualifies source checks and cross-builds. Guest ART lifecycle,
production Google Play Services dispatch and Google account login require
separate execution evidence. The fixture APK at
`headless-service-fixture-2026-10-26/probe.apk` has SHA-256
`4df9e3cd757b463259c73dc038eb84d149d7ec1461a1889bc8f2d531f6980634`;
its maintained source was committed at `8830d1e26b2e55db5912d944ae54eaf61135e221`.
