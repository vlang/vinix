# Platform fragments / account exception native producer — 2026-10-29

The complete AArch64 JNI provider built against the new platform-fragment
framework. It contains the account exception restoration fix `59879ee0b` and
uses the Java lifecycle implementation from `05fbcfa9d`. The producer records
source revision `c7805783f6b95fd65017401a31b75d7332aa8c0b`. This is host production
and link evidence; the coupled pair has not yet run on ART or authenticated a
Google account.

All paths below are relative to `/Users/alex/.local/state/vinix/android` (`S`).

- Successful closed output (`N`): `S/current-native-build-2026-10-29-exception-restore-r2`.
- Successful controls (`C`): `S/native-exception-restore-build-2026-10-29-r2`.
- Matching framework: `S/combined-account-webview-platform-fragments-framework-2026-10-29-r1`.

| Artifact | SHA-256 |
| --- | --- |
| `N/sha256.json` | `6a6410f9d62a2d28174d7cc8213acaabcca89b548402337dbb5e5bed34f99f72` |
| `N/build.json` | `962683e6e67f8d86f2b365034c6d87713c373af50bdd2ddead6daf2d74de2914` |
| `N/native/libvinix-android-native.so` | `613c6b2c7b1e816a5d7b0694d626a52a5b4df19604a6a224df99ad13055aa74c` |
| Framework `sha256.json` | `5b452702e033f72f9056f994b94295f7925958c62fcaad039827710368249bfb` |
| Framework `api-impl.jar` | `6970582da55b15dd30391491d2be2213abe665fe0256167f45cccdd3de25bcd4` |

The source-matching bootstrap at
`S/native-auth-worker-build-2026-10-29-r1/tools/bootstrap`
(`87fdd3470d639f1456eae758da4555b3f402a3adceea7793893d0c932d86d12d`)
executed a fresh retained frozen builder. The builder source remains
`a468758d4957f66703836da209b901e1344a2f889b27c2df868630d97adc4d33`.
The complete source/compiler closures, framework inventory, generated C,
commands, before/after input checks and export verification remain in `N`.
The shared link used AArch64 `-Werror` and `--no-undefined`; the output is an
AArch64 ELF shared object. Comparing the complete native source directory with
the Service predecessor found exactly the two expected account source changes;
the existing headless observer and other native sources remain identical.
The framework helper closure additionally contains the new provider and its
registration, as required by the coupled build.

The successful producer took 25.900 seconds with guard/child status zero and
complete cleanup. Original limits were 600 MiB aggregate RSS, 300 seconds,
2 GiB observed shared-volume growth and 1 GiB reserve. Peak sampled aggregate
RSS was 614,596,608 bytes; the time report gives 404,373,504 bytes peak process
RSS and zero swaps. Observed shared-volume growth was 88,371,200 bytes; minimum
free space was 9,699,647,488 bytes.

The earlier r1 output and `native-exception-restore-build-2026-10-29-r1` controls
are preserved. Its guard stopped after 1.782 seconds for 2,320,388,096 bytes
observed shared-volume growth, with complete cleanup and no compiler diagnostic.
Those volume measurements do not attribute growth to this producer. No limit
was changed for the fresh r2 retry.

The successful and failed outputs plus their controls are bound by a complete
four-root, 2,501-entry in-place seal:
`S/native-exception-restore-sealed-2026-10-29-r1/manifest.json`, SHA-256
`64be89c26b16bad93c2a6efeec4b421c3c3e19f0375da2f38fea5cf90c8572f8`.
Sealing and a fresh-process complete readback passed with zero status, complete
cleanup and zero swaps. They took 0.350/0.512 seconds and sampled
19,546,112/23,904,256 bytes RSS under unchanged 600 MiB, 900-second,
64 MiB observed-growth and 1 GiB reserve limits. Their controls remain at
`S/native-exception-restore-seal-controls-2026-10-29-r1`.

See the [framework producer](platform-fragments-framework-2026-10-29.md),
[fragment host checks](platform-fragments-host.md) and
[account exception checks](account-exception-restore.md) for their separate scope.
