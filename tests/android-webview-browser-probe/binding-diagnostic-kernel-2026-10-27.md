The protected-storage Maps kernel patcher now requires the exact binding-r2 JNI
manifest and input path. This permits the diagnostic stage carrying numeric
service-binding timeout evidence. The original r5 base, framework, retained
launcher, seven modules, diagnostic receipt kind and frozen PIDFD kernel contract
remain pinned. Existing browser and Maps profiles are unchanged.

Focused regressions reject the old native receipt, the old input path with
either native seal, and the new path with the old seal. The complete existing
digest, profile, browser/Maps/protected FAT and installation guard self-tests
also pass. Independent source review confirmed the narrow pin/path change and
these rejection cases.

The host build exited zero in 18.45 seconds with maximum RSS 368,377,856 bytes;
the full self-test exited zero in 2.41 seconds with maximum RSS 22,986,752 bytes.
Both recorded zero swaps. Build command:

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v -new-compiler -prod -gc boehm -path '@vlib|build-support|build-support/android' -o /Users/alex/.local/state/vinix/android/protected-storage-binding-kernel-patcher-2026-10-27-r1/patch-kernel tests/android-webview-browser-probe/patch-kernel.v
```

The complete small host audit is retained at
`/Users/alex/.local/state/vinix/android/protected-storage-binding-kernel-patcher-2026-10-27-r1`.
It includes the executable, exact entry source, local module source/header,
commands, compiler identity, qualification and complete build/self-test logs.
The sibling `protected-storage-binding-kernel-patcher-2026-10-27-r1-seal`
binds all 11 typed entries. Creation, internal check and a separate check pass;
manifest SHA256:
`14a46e4bf9f6e72d19f7ea755a889cade20708338c7949c4d1a8dd7d365c5acb`.
Original compiler, standard library, SDK and complete input bundles remain
required. No SDK copies or kernel builds were made.

| Artifact | SHA256 |
| --- | --- |
| Entry source | `55ec314d1d8954d05391ffb26a86ba08e0a6215251881f7646119e9b32d9ac02` |
| Host executable | `805df7e53d975542adcd6204a127c7b0d8e613cc2c83d82c7dd951828ee57c75` |
| V compiler | `0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe` |
| binding-r2 native manifest | `bd0e3902130f74877abaf269301377c7b5d2cbfe9e7732508838d84ec863d19d` |
| binding-r2 native SO | `8508d4acb9a96c15eddd3a4afd075855270e2dae48006a9675a86ead0b2f6f19` |

The new manifest and SO were directly hashed in the original
`/Users/alex/.local/state/vinix/android/current-native-build-2026-10-27-binding-r2`
bundle. The source snapshot is this change, built from parent revision
`e5cf5898c59cea60a6748724a30772485414fdaf`. The earlier protected-r1 patcher and
receipts remain immutable.

After cloning a complete, sealed, unlaunched stage with the new native input:

```sh
/Users/alex/.local/state/vinix/android/protected-storage-binding-kernel-patcher-2026-10-27-r1/patch-kernel --protected-storage-maps FRESH_CLONE /Users/alex/.local/state/vinix/android/pidfd-wait-kernel-build-2026-10-26-r1/kernel-aarch64-r2 1e9077779aaed08188e6f8111ca9ceb27b479517ece736a58157049f004fb36d
```

These results validate the host tool and installation fixtures. No guest was
launched for this change; Google account sign-in remains unverified.
