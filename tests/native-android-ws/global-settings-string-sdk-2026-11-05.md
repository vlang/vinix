# Global String writer SDK host qualification

The adapter and [focused qualification](../native-android-tools/global-settings-string-source-check.md)
are committed in `8db2b7541`. The complete SDK producer build passed against
the exact process-package predecessor. Only `android/provider/Settings$Global`
changed: one added public static String writer, zero changed old methods,
zero field/class additions and 2,116 other classes unchanged. Class count
remains 2,117. Independent instruction/member checks passed before and after
API-28 DEX assembly. All historical producer profiles remain preserved.

Paths use `S=/Users/alex/.local/state/vinix/android`. The complete output is
`S/combined-account-webview-global-settings-string-framework-2026-11-05-r1`:

| Artifact | SHA-256 |
| --- | --- |
| `sha256.json` | `cadfaa0105eb24580f1cdcef590f707e52aab334e9d7bf164524a403f1b43cbc` |
| `build.json` | `29300cf133e8786b1d7e80a101129d6664a0ce6a0af5315e7eee39ab97d57c37` |
| `api-impl.jar` | `9207dab7a6a37e09fb049bb636ba6ebad3e63e43bfe7fd95821f67fc2aebeeb7` |
| `classes.dex` | `ac3f264e0dc77918845bb6ab2015e8c37724cbfaa47339f86f55e5750f7ccc32` |

The baseline manifest is
`4a354ead173048b39fb26cce709922f8954e27e53e2d3a5d92ecdf427db0645d`,
JAR `875f854ddf662dcaf55ebe05df06f5833eb5ca1e15f94066ffdf0fef18e829a8`.
Production source revision is `8db2b7541db2ce479a86a4770dff84a9fc852e7d`;
producer source SHA-256 is
`f3be838d97f5c962c1a09cdd5419cc9d5655dafd96bd8617bc96d2c7b312de6b`.
The SDK preserves original baseline inventories, exact provider/helper and
builder source closures, copied compiler/tools and before/after input pins.

The first optimized host-producer compile was stopped for aggregate RSS:
631,701,504 bytes exceeded the 600 MiB cap after9,396 ms, guard125/child137,
complete cleanup. Keep both `global-settings-string-sdk-tools-2026-11-05-r1`
and `global-settings-string-sdk-controls-2026-11-05-r1` intact.

The same source compiled without host optimization in the fresh `r2` roots;
no limit was raised. Compile, producer self-test and SDK build passed0/0,
empty reasons and complete cleanup. Controls are at
`S/global-settings-string-sdk-controls-2026-11-05-r2`, with matching logs:

| Phase | Elapsed ms | Sampled RSS bytes | Shared growth bytes |
| --- | ---: | ---: | ---: |
| Compile | 3,711 | 430,047,232 | 557,056 |
| Self-test | 342 | 14,647,296 | 16,384 |
| SDK build | 52,545 | 501,071,872 | 322,920,448 |

Producer self-tests passed 23 method, ten member and six class refusal controls,
along with the historical self-tests. Each phase retained 600 MiB RSS,
300 seconds, 512 MiB shared growth, 1 GiB disk reserve and 4 MiB output; the
shell file cap was8 GiB. Frozen sources/executable and compiler input listing
are at `S/global-settings-string-sdk-tools-2026-11-05-r2`.

Full retained-native compatibility, signed fixture, delivery, image and ARM
qualification remain outstanding. No successor GMS stability, Maps rendering
or authentication result is established. Complete original bundles and failed
attempts remain required; aggregate evidence sealing/readback is separate.
