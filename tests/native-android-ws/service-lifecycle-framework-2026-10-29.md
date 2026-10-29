# Service lifecycle framework successor, 2026-10-29

The explicit `--service-lifecycle` profile applies the Service cleanup from
`e550944d5` over the sealed Binder identity framework. It removes diagnostic
stdout writes from `attachBaseContext(Context)`, `onCreate()` and `onDestroy()`;
the superclass attachment call and all other members remain unchanged. All 2,104
classes remain present, with only those three Service methods changed and no
method, field or class additions. StrictMode and its thread-policy classes remain
unchanged. This host build does not establish the broker's exit cause or a
successful Maps/Google login run.

The producer retains the existing canonical JAR-cloning pipeline and historical
narrow profiles. Exact method/member and complete class inventories are compared
before and after DEX roundtrip; only the JAR's `classes.dex` member may change.
Negative controls cover field/member metadata, missing or added methods/classes,
incorrect counts, and changes to retained StrictMode, Binder and context classes.
Compatibility with the retained native artifact requires the image stage's
separate complete consumed-class membership and canonical-data checks.

Artifacts are relative to `/Users/alex/.local/state/vinix/android` (`S`):

- Builder, exact source/compiler and guarded command evidence (`B`):
  `S/service-lifecycle-framework-builder-2026-10-29-r1`.
- Completed framework (`P`):
  `S/combined-account-webview-service-lifecycle-framework-2026-10-29-r1`.
- Complete evidence seal and fresh readback:
  `S/service-lifecycle-framework-sealed-2026-10-29-r1`.

The pinned baseline is
`S/combined-account-webview-binder-identity-framework-2026-10-29-r1`, manifest
`739fc9c17258915b0ce7ee01fa3d9e03f47c9d4f4de05ef0c6178d624f8ff3c5`,
JAR `3f2e3220d6c38feb885044fdb4806d4d3ca7736352bbcc7813e2ee6510463636`.
The full producer records revision `32e4014cec5c84706117a5577aac4eecfa57ac34`,
with exact working builder source SHA-256
`6a53a10ab1f9c8a9b8a8af6ad3a5c98919ce89db28602d85f62d5aa695102a46`
and provider SHA-256
`5117e4a20d30ca738b442aa93de239bba6ef2a67349a1303650f237dca057436`.
Complete consumed source closures, compiler and smali tools are retained.

| Check | Seconds | Peak sampled aggregate RSS, bytes |
| --- | ---: | ---: |
| Builder compile | 1.381 | 340,164,608 |
| Full builder selftest | 0.277 | 2,342,912 |
| Full narrow producer | 42.792 | 497,958,912 |
| Evidence seal and inline check | 0.716 | 24,002,560 |
| Fresh-process complete readback | 0.611 | 13,402,112 |

All guards exited zero with completed cleanup; time reports record zero swaps.
Limits remained 600 MiB aggregate RSS, 300 seconds and a 1 GiB reserve.
Compile/selftest allowed 512 MiB observed shared-volume growth, the producer
1 GiB, and seal/readback 64 MiB. The producer observed 390,217,728 bytes global
growth; this does not isolate its own allocation. Complete input rechecks and
the output inventory readback passed. No native build or guest run was performed
by this producer.

| Retained artifact | SHA-256 |
| --- | --- |
| `B/tools/builder` | `ca4862b250924dd8c852f27788c7cd1ded03cf0e78cd5ba63fd05410787a7d01` |
| `P/sha256.json` | `9453286e07d3bd727782355413d4fa8059bd1332e89850748fb4db02680c9488` |
| `P/build.json` | `b90d3e561dd34903bc1d5fa1687dea9360d9496fc212dd02686d75cd1b1d75e0` |
| `P/api-impl.jar` | `7017b4845f91cb1c37057f6e8da07476b9b1b44c523827acaf00baad2432fe74` |
| `P/classes.dex` | `95073976c0936acdbf7d0cf5c13c190ef5f50f9eefedb6c20e303fea38007b8a` |
| Raw `Service.smali` | `3a956a18495fb47aa060f228f240ea5ef3b07cfba8f200b9dcb42d9897f11275` |
| Post-DEX `Service.smali` | `47929da39372e89dc5b2f46671583a41dff5b3f4eaee195474b650e1fa6492bf` |

Both closed roots and 7,489 entries are bound by
`S/service-lifecycle-framework-sealed-2026-10-29-r1/sealed/manifest.json`, SHA-256
`1cc9c69d50a34ae1c2d56094b37689735e7af72e2557a0387289e70f1a608799`.
The seal's inline check and a separate fresh-process complete readback passed.
Keep the original complete bundles unchanged; this report does not replace them.
