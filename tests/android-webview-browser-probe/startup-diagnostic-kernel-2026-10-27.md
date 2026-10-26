The protected-storage Maps patcher now requires the exact startup-r1 JNI
manifest and input path for the startup-budget diagnostic. The original r5
base, framework, retained launcher, seven modules, receipt kind and frozen
PIDFD kernel contract remain pinned. Other profiles are unchanged.

The positive fixture uses the new input. Existing rejection tests now target
the immediate prior binding-r2 receipt, old path with either seal, and new path
with the old seal. All digest, profile, browser/Maps/protected FAT and
installation guard self-tests pass. Independent source review by root and
maps_evidence passed the six string replacements.

The host build exited zero in 7.59 seconds, maximum RSS 379,142,144 bytes. The
complete self-test exited zero in 3.27 seconds, maximum RSS 27,508,736 bytes.
Both recorded zero swaps. Build command:

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v -new-compiler -prod -gc boehm -path '@vlib|build-support|build-support/android' -o /Users/alex/.local/state/vinix/android/protected-storage-startup-kernel-patcher-2026-10-27-r1/patch-kernel tests/android-webview-browser-probe/patch-kernel.v
```

The complete small host audit is retained at
`/Users/alex/.local/state/vinix/android/protected-storage-startup-kernel-patcher-2026-10-27-r1`:
exact source, local module source/header, executable, commands, qualification
and complete build/self-test logs. Its sibling
`protected-storage-startup-kernel-patcher-2026-10-27-r1-seal` binds all 11 typed
entries. Creation, internal and separate checks pass; manifest SHA256:
`24c41639ecc1f144e01cebe2ad874b2213718222c34ce1cea004bf2bf1e25cad`.
The original compiler, standard library, SDK, native bundle and frozen kernel
build remain required. No SDK copies or kernel builds were made.

| Artifact | SHA256 |
| --- | --- |
| Entry source | `586280c1ec1ae16e8b8fcadf8a6a7deee48298b1cbeaa60926e6e28e53d96907` |
| Host executable | `48cdde112d338f1b94575344e9b71ea2a0825e190624eecfb86648d532d40523` |
| V compiler | `0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe` |
| startup-r1 native manifest | `a62bf4a8a4ef8d1c000f82395ec64b145c9c4d6df25f12077f75d96d341e0a20` |
| startup-r1 native SO | `82e4bdb907a300634b304b37339b2e9a836f6f1a61d01a369d0f5aa707fddca7` |

The native manifest and SO were directly hashed in the complete original
`/Users/alex/.local/state/vinix/android/current-native-build-2026-10-27-startup-r1`
bundle. The source snapshot is this change, built from parent revision
`302628d15c27306e6f394237010af59fdd63a413`; entry, local dependencies and compiler
hashes remained unchanged before/after build and self-test. Earlier patchers
and receipts remain immutable.

After cloning a complete, sealed, unlaunched stage with the new native input:

```sh
/Users/alex/.local/state/vinix/android/protected-storage-startup-kernel-patcher-2026-10-27-r1/patch-kernel --protected-storage-maps FRESH_CLONE /Users/alex/.local/state/vinix/android/pidfd-wait-kernel-build-2026-10-26-r1/kernel-aarch64-r2 1e9077779aaed08188e6f8111ca9ceb27b479517ece736a58157049f004fb36d
```

These results validate the host tool and installation fixtures. No guest was
launched for this change; Google account sign-in remains unverified.
