# Maps331: disk preflight stopped before generation

The Android implementation revision is
`18fd4ec91aaaf581c4b30b4da1ae1703bb7122b5`; its passing paired guest
qualification is recorded in revision `6152dba6e` and
[system-package329.md](system-package329.md). This fresh replay selected
that Framework329 with unchanged Native315.

At 2026-10-25 12:48:12–12:48:13 UTC, the existing
`build/android-maps/maps-replay-generate314` was invoked once for attempt331,
with the supported explicit `--minimum-free-mib=1536` policy. Its first
checkpoint observed 840,624 KiB, below the required 1,572,864 KiB, and exited
1. All seven canonical generation/build/runner/attempt destinations remained
absent. No preparation, guest, interaction, new screenshot or route result
is claimed. The default 5,120 MiB policy and 600-second observation remain
unchanged.

The retained preflight bundle is
`/Users/alex/.local/state/vinix/android/maps331-generation-preflight-2026-10-25`,
manifest SHA256
`b23b577133848c6ccc3a3c4a92fc02a476c40def42184a68b6dbce0abee62bd1`.
Independent full readback passed all 21 files. It retains the exact V wrapper,
compiler command, failed compile log, corrected build, stdout/stderr, disk
observation, invocation, exit code and destination-absence receipt.

| Input | SHA256 |
| --- | --- |
| Existing generator binary | `75b69d07fdf23401b07ee8cad36d7ba2a47dfd5e48c13660c4307f91e882b453` |
| Generator source | `39b9d763de6c5685021731ec877a276d2110f8cd457c4ff6bcf8bc1e399b6d84` |
| Six replacement build pins | `f83ba17c15d0715e5d3d268056a72e214163682fb2a1372e2a8263cdc4cf126d` |

The unused clean launch envelope removes all `VINIX_ANDROID_TRACE_*` and
`ATL_UGLY_ENABLE_LOCATION` variables, including empty entries, and records
the filtering separately from the static build bundle. Its host self-test
and independent full readback passed 40 files at
`/Users/alex/.local/state/vinix/android/maps331-launch-envelope-2026-10-25`,
manifest SHA256
`fa9162d8a0cd261560f38f9548bc4dffd728566c93ca9d413fff9545eb27133e`.
It was not used to launch Maps. The repository V tools retain the exact
frozen sources; their fixed external paths require the retained bundles.
Do not rerun `--build` or `--self-test` against the sealed envelope;
`--verify-build` is read-only. The preflight rejects a repeat invocation.

The latest genuine running-Maps PNG and application observations remain in
[maps327.md](maps327.md). Directions on Framework329 and the cause of the
Attractions loading sheet remain unqualified. Resume with the same generator
and pins when its existing disk checkpoints pass; preserve the failed
preflight bundle and use fresh receipts.
