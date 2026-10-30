# ImageView bounds fixture tools, 2026-10-30

`onboarding-api-run.v --image-bounds` selects the signed ImageView property
regression and its exact coupled framework/native pair. The standard protected
fixture setup, bounded child lifetime, single PASS/readiness checks and clean
exit requirements remain in place. Transfer selector `serve --image-bounds-api`
serves only `/image-bounds-api-run` and `/image-bounds.apk`.

The fixed marker is:

```text
IMAGE-BOUNDS-PASS defaults setters axis-isolation instance-isolation styled-dimensions
```

Paths below are relative to `S=/Users/alex/.local/state/vinix/android`.
Actual runtime inputs were rehashed before pinning:

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Signed APK | `image-bounds-fixture-2026-10-30-r1/probe.apk` | `7d11a0e6d71b6c556a57f84fd5f27610157f0a49735282f0bb31aaac0ff00a62` |
| Framework JAR | `combined-account-webview-imageview-bounds-framework-2026-10-30-r1/api-impl.jar` | `9cfdbeaff047b693837508c3f7676510a63c05af118e864964b4b432fb813af9` |
| Native DSO | `current-native-build-2026-10-30-imageview-bounds-r1/native/libvinix-android-native.so` | `fd38d7f8e3c0d17934617242cb95b0412a0c6ed676cb4454e5a52c8cf494dc2c` |

The runner selftest rejected 475 malformed, duplicate, mixed-profile and failure
cases, including 35 actual malformed-CLI refusals. Transfer tests retain exact
pin/snapshot/binary/HTTP/deadline checks and add ten malformed-selector/port
refusals without creating outputs. ELF inspection confirms a static AArch64
executable with no interpreter. Independent selector review passed. The exact
coupled native output is pinned without requiring inequality from older builds.

All five final checks passed under 600 MiB aggregate RSS, 300 seconds, 512 MiB
observed shared-volume growth and 1 GiB reserve. Guards record child/guard exit
zero and complete cleanup; timing reports record zero swaps.

| Check | Guard seconds | Sampled RSS bytes | Timing maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 11.104 | 355221504 | 356335616 |
| Static ARM runner compile | 14.439 | 374882304 | 359251968 |
| Final host runner selftest | 1.481 | 20185088 | 17547264 |
| Host transfer compile | 11.375 | 365953024 | 368508928 |
| Transfer selftest | 0.989 | 9699328 | 8519680 |

An additional preliminary runner selftest passed while briefly overlapping the
ARM compile. Its original controls remain retained; the final ordered selftest
ran after ARM compilation and before transfer compilation. Compilers did not
overlap.

Runner: `S/image-bounds-api-run-2026-10-30-r1/run`, SHA-256
`52cfbb82ec2d3cb5034a6a84bf15fce44c52a45829e4de6005c7c15778103305`.
Transfer: `S/image-bounds-api-transfer-build-2026-10-30-r1/transfer`, SHA-256
`669d13f1a91e2cc634189c0a8de8e44c794e0fee153861fc5c81b2c6b89a0a97`.
Runner/transfer source hashes are respectively
`053f5d461e4756bf594e495501325f25249a2b8a04aece63da01179df17d46e3`
and `1ad53afcd557925457871457d4bfa8740736b8bf0771be7006a4213ad15c1572`.
The captured base revision is `52f55817144cda6c30bffcc0e03dccf2b2d09287`;
exact changed source copies, command receipts, tool/input hashes and checks are
retained in the runner build, transfer build and transfer control roots.

The complete four-root, 36-entry seal and separate-process full readback passed:
`S/image-bounds-api-tools-sealed-2026-10-30-r1/manifest.json`, SHA-256
`07e2344887a8255b8480c8c255c50788da2cb10762568731e8104201b06e2b3e`.
Both controls used 600 MiB RSS, 300 seconds, 64 MiB observed shared-volume
growth and 1 GiB reserve, with exit zero and complete cleanup. All roots are
closed; original producer bundles remain required to audit their inputs.
These host checks do not establish ART execution, map rendering or Google
authentication.
