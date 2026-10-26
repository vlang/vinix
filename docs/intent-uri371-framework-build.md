# Intent URI framework371 build

Provider `efac8e8a9dae0259caeb1fd735563485108b9d78` corrects the inherited
`Intent.getDataString()` null return exposed by the first Intent369 ART run.
The [provider report](intent-uri371-provider.md) records API28 semantics, the
unchanged fixture and host guard checks. Original369 evidence remains preserved.

The builder and recorder in commit `11a1b17bfbce3153d161b414e99c9d49fb862e7b` retain
the complete qualified367 baseline and its complete 365/361/359/353 inputs. It
freezes the committed provider in a private VROOT with the authenticated353
method replacement helper. Compiler, host tools, generated C, before/after V
closures and actual command exits are retained.

The 648-file builder bootstrap is retained at
`/Users/alex/.local/state/vinix/android/intent-uri371-framework-builder-build-2026-10-26`.
Its manifest is
`9f062095b54c8c52e6797750529d0a241e592b21611db5c53e082d4c317b70cd`
and builder binary is
`081765f4e6a3ea94e20cd5fca3c25b535e71ba3ba90dd183e91fa3c231df2cc6`.
Compilation and six class-delta rejection tests exited 0; all 270 V inputs
remained unchanged. Own and independent original290 readbacks passed all 648
files. The independent reader in commit `4f265a4bf` also verified the exact
closure and all 12 command argv/status records. Its receipt is retained at
`/Users/alex/.local/state/vinix/android/intent-uri371-builder-bootstrap-peer-readback-2026-10-26/complete-receipt.json`,
SHA-256 `611dcb2383d9f956af96b77e0523b4502f371cf7788a698604dc3846b8e037ed`.

The framework bundle is retained at
`/Users/alex/.local/state/vinix/android/intent-uri371-framework-build-2026-10-26`.
Source and disassembled DEX each retain exactly 2,076 classes; only
`android/content/Intent.smali` changes. Only `classes.dex` changes among the
three JAR members. The generated Intent source matches the host-tested
`cf947375973e5e03b7df25c8288d9c899955e86ff0a20c5a299356e2e34a303d`.
All 33 recorded commands exited 0. Provider and builder V closures remained
unchanged at 144 and 270 inputs respectively.

| Artifact | SHA-256 |
| --- | --- |
| `sha256.json` | `71e311764ece295185656854294a514a9c641419c567d5f96ac66f52f4b89750` |
| `framework/api-impl.jar` | `3b345e1661ca9f5b616f5abe25c9f4abc1df383204d25333477dae69221a8d21` |
| `framework/classes.dex` | `09378963d2536f3358f30cc76e53d197c4029a6d9bef3801c77e1bd29b267724` |
| `validation.json` | `1cccdbdd3e17979c90b50b899b0fac5f3a28e7f096aa7ba394e34cd8ec809257` |

Original, cloned and post-build retained baseline checks passed. The final own
original290 readback verified all 50,901 file hashes and the exact file set,
exit 0, at 03:54:57–03:56:41 UTC on 2026-10-26. Adjacent receipts are:

| Own artifact | SHA-256 |
| --- | --- |
| `intent-uri371-framework-build-2026-10-26-own-readback.json` | `5588d3ecb69e644cd8ce9e4f52e6ff5404a16468b87fbb49f010404388768455` |
| `intent-uri371-framework-build-2026-10-26-own-readback-command.json` | `296e533ea957ebc18b3caff71b7c7e0adf0be9fcf1bb3e9fc5fb9c2977b31d12` |
| `intent-uri371-framework-build-2026-10-26-invocation.json` | `487f999211f04cb8d2a58a3d243980bad9c0e69b4f0f5b93907920a6ad08e28b` |

The sole independent full reader in commit `5beabc1de` passed all 33 commands,
414 closure inputs, actual source/DEX inventories, exact isolated provider and
helper, JAR delta, and both rejection guards. It also checked the exact repaired
accessor in source and disassembled DEX. Its original290 readback passed all
50,901 files and the exact file set at 03:57:18–03:59:14 UTC. The manifest stayed
unchanged before and after. Reader source and binary remain adjacent to:

| Independent artifact | SHA-256 |
| --- | --- |
| `intent-uri371-framework-peer-readback-2026-10-26.json` | `cb6975730ffa6c9281ca725100d0bb41c841e0f02438c850cc228dc912df99a7` |
| `intent-uri371-framework-peer-readback-2026-10-26-command.json` | `8eccaaedbc8b7677b280d3c38b34afbf8af8ba6fa1a87ecbcac8e3feebd7bce4` |
| `intent-uri371-framework-peer-readback-2026-10-26-inspection.json` | `df892ea49c853a3bdd92d21397347e7aaf4a0e22f179f9bdc472ef21ddae995c` |

This build performs no guest execution. The unchanged-fixture ART replay is a
separate runtime qualification.
