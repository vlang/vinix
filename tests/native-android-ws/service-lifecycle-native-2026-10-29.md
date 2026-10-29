# Service lifecycle native producer — 2026-10-29

The current JNI provider built and linked for AArch64 with the native terminal
observer from `fc0c44be97a26a027679aef7fe70a10d815ef9a5`. It uses the matching
Service framework that removes three lifecycle diagnostic writes. This is host
production and link evidence; it does not establish guest execution, the earlier
broker exit's cause, map imagery or Google authentication.

Artifacts remain under `/Users/alex/.local/state/vinix/android` (`S`):

- Closed producer output (`N`): `S/current-native-build-2026-10-29-service-lifecycle-r1`.
- Closed control receipts/log (`C`): `S/native-service-lifecycle-build-2026-10-29-r1`.
- Matching framework: `S/combined-account-webview-service-lifecycle-framework-2026-10-29-r1`.

| Artifact | SHA-256 |
| --- | --- |
| `N/sha256.json` | `2c61783de1aab68bbf8177329215b27881e95afaa87d16272f03ba7fda98c401` |
| `N/build.json` | `f5c1638e7d486336379d21e27f3fdd7519dca5a9aceff806983c90d7402f3afa` |
| `N/native/libvinix-android-native.so` | `ea8b899971ac96335c1f53a32eb3dee8e5e8f87600c0bcd5b7edaa683b9a8136` |
| `N/native/atlframework/headless.v` | `d22892cc47def3c2e830a6e29873acd5c0eb08b944f68d131e39f4922c1663ff` |
| Framework `sha256.json` | `9453286e07d3bd727782355413d4fa8059bd1332e89850748fb4db02680c9488` |
| Framework `api-impl.jar` | `7017b4845f91cb1c37057f6e8da07476b9b1b44c523827acaf00baad2432fe74` |

The reused bootstrap at `S/native-auth-worker-build-2026-10-29-r1/tools/bootstrap`
has SHA-256 `87fdd3470d639f1456eae758da4555b3f402a3adceea7793893d0c932d86d12d`.
It retains builder source `a468758d4957f66703836da209b901e1344a2f889b27c2df868630d97adc4d33`
and executed the fresh frozen builder in `N` with SHA-256
`d3c741a265482e27034bf481275e3cb23bb226dad05f7a1dc938f447c6be416b`.
The frozen execution receipt, copied source/header closures, framework inventory,
input rechecks, generated C and command receipts remain in `N`.
`commands/build-native.json` records the real `aarch64-linux-musl-gcc` shared
link with `-Werror` and `--no-undefined`, exit zero. The export check also passed.

The producer passed in 25.461 seconds with exit/child status zero and complete
cleanup. Its unchanged guard caps were 600 MiB aggregate RSS, 300 seconds,
2 GiB observed shared-volume growth and 1 GiB reserve. Peak sampled RSS was
611,549,184 bytes; the time report gives 404,439,040 bytes peak process RSS and
zero swaps. Observed shared-volume growth was 3,801,088 bytes, with minimum
free space 11,819,720,704 bytes. Shared-volume changes are not isolated producer
allocation measurements.

`N` and `C` are bound unchanged by a complete in-place seal at
`S/service-lifecycle-native-sealed-2026-10-29-r1/manifest.json`, SHA-256
`ffef80c30f90459c3c7e97520b114fcd9a6dd211a7c102c45c853229c09515df`.
The seal's own readback and a separate fresh-process full readback passed for
two roots and 1,759 entries. Seal/check guards retained 600 MiB RSS, 900 seconds,
64 MiB observed growth and 1 GiB reserve; both exited zero with complete cleanup
and zero swaps. They took 0.239/0.816 seconds and peaked at
12,353,536/22,855,680 bytes sampled RSS. The earlier observer-source seal
`3f3a9910977d8ca01c0c03370cabb5961325295562de2bd18db31d810959d8eb`
remains unchanged; see [the observer report](service-terminal-observer.md).

Independent read-only review matched the producer/source/framework identities,
measured receipts, ARM link scope and complete seal readback.
