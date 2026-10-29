# Platform fragments host validation, 2026-10-29

Provider/checker/registration commit `05fbcfa9d95c1b212164c2c4bb665791ff5dd49f`
implements a stable per-Activity platform fragment manager, real tag queries,
deferred FIFO transactions and nonvisual lifecycle dispatch. The old Activity
fragment loops are replaced, preserving native entry points. Callback exceptions
retain their identity; terminal cleanup releases added and pending ownership.
The transaction scope remains nonvisual additions, commit and tag lookup,
without UI fragments or back stacks.

Fixture commit `4d1cbec06d095c6c7668d051fb82468c2b838c89` uses
`org.vinix.bootstrap.Main`. Two real Application callbacks inject a fragment and
then query that same fragment. It also checks asynchronous commits, lifecycle
order, late additions, host/tag isolation, null fragment state despite a non-null
Activity bundle, reentrant destruction, queued callback work and throwing teardown.

Paths below use `S=/Users/alex/.local/state/vinix/android`.
The complete host evidence binding is
`S/platform-fragments-host-sealed-2026-10-29-r1/manifest.json`, SHA-256
`37ca67c5e14475432a487a82fca15a16277094f848b16e2ac0f9e2a1cd7e38c1`.
Its 22 roots and 7,732 typed entries bind all ten checker compile controls,
all five source/DEX attempts, their retained tools, the fixture and its controls,
the intentional assertion failure, source captures and baseline/tool inputs.
An independent fresh streamed readback passed, including files, modes, symlinks
and empty failed-attempt directories. The unchanged sealer is retained inside
the binding; seal/readback commands and guard receipts are adjacent in
`S/platform-fragments-host-seal-controls-2026-10-29-r1`.
The independent readback guard SHA-256 is
`94f884cf30f582cd97e85b1d2d4552a92699bff8289cfa024b3a786a310724f6`.
The guard and adjacent timing log record exit zero, complete cleanup,
0.417 seconds, 23,887,872 bytes sampled RSS and zero swaps.
Sealing/readback used 600 MiB RSS caps with the same 300-second deadline,
1 GiB reserve and 512 MiB growth limit; neither compiled an executable.

Final artifact identities:

| Artifact | SHA-256 |
| --- | --- |
| Provider source | `838192c98ee5f782b926bb167756d589f5baf86e32f47b35913c29bdf9dfa7a0` |
| Source/DEX r5 `sha256.json` | `ba4b2c72c94e9aa282e0abacd3a4fe83ae0cb3e8ebe57a717642ae04a8b8ae7c` |
| Focused five-class `classes.dex` | `d201f2ab912209acec6e3c680485b07242d9a834656ae3a30c811c77ed2de52e` |
| Fixture r1 `sha256.json` | `ec4d2f33cbbead24b7eabca0bfd4cfb91941052715dfa658014ea21da666466c` |
| Signed fixture `probe.apk` | `f2e08f444782607a408bd25766da399100e908cf2b99edeebcfb80d267dc21de` |

Source/DEX r5 is `S/platform-fragments-source-dex-2026-10-29-r5`;
the APK is in `S/platform-fragments-fixture-2026-10-29-r1`.
The final checker executable is retained under
`platform-fragments-checks-2026-10-29-r1/tools/checker-final`, SHA-256
`2112c626800ebbbe86ebd9e62ffd60bd6440b56c3b0ca82b755d7ab16d154aa2`.

| Final check | Seconds | Sampled RSS, bytes | `/usr/bin/time` RSS, bytes |
| --- | ---: | ---: | ---: |
| Checker compile r10 | 4.439 | 564,133,888 | 594,821,120 |
| Source/DEX r5 | 1.165 | 212,238,336 | 137,084,928 |
| Fixture generator compile | 1.235 | 335,233,024 | 352,501,760 |
| Signed APK build | 5.431 | 165,855,232 | 110,657,536 |

All four passed with child/guard exit zero, complete cleanup and zero swaps.
Their caps were 1 GiB aggregate RSS, 300 seconds, 1 GiB disk reserve,
512 MiB observed growth and 4 MiB output. The source checker verifies exactly
20 changed methods, 15 additions and 14 added fields, rejects 13 mutated inputs,
and assembles/roundtrips five classes. The fixture's non-production generator
keeps assertions, verifies the v3 APK signature and roundtrips seven classes.
Replacing Java with `/usr/bin/true` intentionally exits one at its assembly
assertion; this expected failure is preserved separately with complete cleanup.

Failed and provisional evidence remains distinct. The first checker compile
failed on an option-block identifier; compile r7 stopped at the disk-growth
guard: 539,701,248 bytes exceeded 536,870,912, guard 125/child 137, cleanup true.
That shared-volume observation does not attribute the growth to the compiler.
Source/DEX r1 stopped at the loop parser check; r2 detected an accepted duplicate
Activity method. Both defects were corrected before the final check. R3 ran an older
binary after the failed compile and is explicitly **not** final source validation;
runtime-recorded source hashes cannot repair that mismatch. R4 passed before
the final destroyed-flag/drain corrections and is superseded. Completed timing
logs show zero swaps; the killed r7 has no complete timing summary. Earlier
executables were reused or overwritten, so these attempts are retained history,
not fully reproducible historical builds.

The four final source copies in `platform-fragments-host-provenance-2026-10-29-r1`
are an explicit post-execution capture matching the commits and final input pins.
They do not reconstruct a contemporaneous complete imported V closure or a
hermetic C/SDK/runtime-library environment.

ART execution, a fresh Maps retry and Google authentication remain pending.
Host DEX assembly and signed APK readiness do not establish runtime success.
