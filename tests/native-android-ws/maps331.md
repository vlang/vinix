# Maps331: native map, driving directions and walking route

Maps331 selects sealed Native315 and Framework329. The Android framework
implementation revision is `18fd4ec91aaaf581c4b30b4da1ae1703bb7122b5`;
its passing paired guest qualification is recorded in revision `6152dba6e`
and [system-package329.md](system-package329.md). Preparation records source
revision `527785d36a3284b1c3b2bf47f3dd18e7c4c065cd`. The newer pending-layout
fix `13fe935f429089f74f5179c427f659cdbacea7c6` is excluded from this replay's
pinned payloads.

The clean envelope started the recorded runner at 2026-10-25 13:11:18 UTC.
Its launch-before receipt records 50 child environment entries, no remaining
`VINIX_ANDROID_TRACE_*` or `ATL_UGLY_ENABLE_LOCATION` keys, and the exact
runner, launch and prelaunch pins below. The root session observed QEMU
alive at 13:11:33 UTC. Maps rendered its native map, selected the Paris place
card, calculated a driving route from the manually entered Eiffel Tower
origin, opened route preview, changed to a walking route and enabled Avoid
ferries in Trip options. Collection completed with exit 0. The exact recorded
runner's complete typed readback passed 22,898 entries. The unchanged
observation window is 600 seconds.

The root session performed the following interactions. Retained captures are
in `/Users/alex/.local/state/vinix/android/maps331-2026-10-25/results/attempt331/google-maps/`.
All interaction times below are UTC on 2026-10-25.

| Flow | Observed capture and result |
| --- | --- |
| Onboarding | Skip at 13:14:31; `map-after-skip.png` at 13:14:42 shows the native map |
| Paris search | Focused retype at 13:15:47; suggestions at 13:15:52; Paris, France selected once at 13:16:03; `paris-place-settled.png` at 13:16:27 shows the place card and photos |
| Manual route origin | Directions at 13:16:46; choose-start screen at 13:16:52; Eiffel Tower entered at 13:17:02 |
| Driving route | `route-first-result.png` at 13:17:59 shows Eiffel Tower to Paris, a rendered route and 22-minute driving selection; `route-after-preview.png` at 13:19:35 confirms the 22-minute, 6.1-km route |
| Route preview | Preview selected at 13:18:11; successful `route-preview-retry.png` at 13:19:08 shows the route and first instruction, “Head toward Pont d'Iéna” |
| Preview next and Back | Next selected at 13:19:24; immediate `route-preview-next.png` is unchanged, so maneuver advancement is unqualified; Back at 13:19:29 returns to the route |
| Walking route | Walking selected at 13:19:46; `walking-route.png` at 13:20:05 shows a dotted route and 1 hr 3 min |
| Route menu | Menu at 13:20:22; `route-menu.png` at 13:20:23 shows Options, Edit stops, Refresh and other entries; Options selected at 13:20:33 |
| Trip options | `route-options-settled.png` at 13:20:55 shows Wheelchair accessible and Avoid ferries off; Avoid ferries selected at 13:21:30; `trip-option-toggle.png` at 13:21:36 shows it on |

The first preview capture request at 13:18:27 failed while opening its stdout
file with ENOSPC, before a command BEGIN record or output files existed.
This failed request is supported only by the root tool transcript; it does
not establish an application failure. The retry above succeeded after disk
space recovered without deleting retained evidence bundles. No location
permission grant, location-provider behavior, active navigation or later
preview-maneuver advancement is qualified by these interactions.

The unchanged result classifier reports `backend_ready=true`,
`launcher_entered=true`, `native_maps_observed=true`,
`failure_markers=[]`, `functional_passed=null`, `process_exited=false`,
and `outcome="window_observed"`. Its observation elapsed time is 600 seconds
and QEMU was alive before capture. The collected window and the specific
manual interactions above are separate evidence; `functional_passed` was
not rewritten to claim an automated end-to-end pass.

The root session's targeted scan of 16,875 retained serial-log lines found
no fatal AndroidRuntime/signal report or the prior
`collectCertificates`/`String.concat`/NullPointerException signature.
Repeated Google Play Services lock-finalizer errors remained nonfatal while
the process heartbeat continued; the scan does not claim an absence of all
exceptions.

All external paths below use the prefix
`/Users/alex/.local/state/vinix/android/` unless fully specified.

The retained typed manifest at `maps331-2026-10-25/sha256.json` has SHA256
`f15440a9e0cf8f57b4cf9f1e1a18845c7afe9643840f41c3b1844916a8e80cf7`.
The result audit verified each of the following PNGs against its sealed
manifest entry and checked the PNG signature and 1024×768 IHDR dimensions:

| Retained PNG | SHA256 |
| --- | --- |
| `map-after-skip.png` | `b18efe59cd8b048c0e89bf8c3fc237b8d6a0742355beb12e20b545795ccbf321` |
| `paris-place-settled.png` | `df697d6698ad387945d1f7f9738cac1065b4727414d2f36653d93355adeaf45d` |
| `route-first-result.png` | `4caf057cc3b5cd3ac7a7514fb78bd224c96798f9689af1f35495bc3b0a73dbb0` |
| `route-preview-retry.png` | `9dd0a19aeeae01119da59d880592e1f1e9ffbe7e8cfbe499d65a7fae3d134479` |
| `walking-route.png` | `27edbc7472aef66d35d35295f7871236c6947f910d5ca2d161005877b450b551` |
| `route-options-settled.png` | `a71ced0b340f7affb1d731bad24840f766119700a50a2095118fb541be1e92b0` |
| `trip-option-toggle.png` | `ea4549047f1bc0e292f289edda04e315374e37ff4bdd2ddd850e14ae6df2d02f` |

`maps331-result-audit.v` repeated the exact recorded runner's complete
typed readback at 13:27:17–13:27:24 UTC, requiring exit 0 and
`MAPS331-COMPLETED-READBACK-PASS` with 22,898 entries. This retained repeat
preserves stdout/stderr, argv, timestamps and source/binary pins; the earlier
root-session readback also passed the same entry count. The audit retains
byte-identical original classifier JSON rather than modifying its values:

| Result-audit evidence | SHA256 |
| --- | --- |
| `maps331-result-audit-2026-10-25/sha256.json` | `8243eddefdff9e8b1c17343cc4ffb70bbb75270e64901298d1aaaf904b52c3b4` |
| `result-audit.v` | `0d86510a1e694e32d59be706a7228433b570314978ff5185e9ccf9229ea93026` |
| `result-audit` | `c28510ea55ec154ff2e34920c40e1aea9107fff457e7b819da2521b4c58bbf8e` |
| `original-results.json` | `46baaed79d83822cef2738174701a15a4abbe6931e32e71b5552eb6fb015906c` |
| `original-observation-before-capture.json` | `3e7c89dc5b5b2108a56bab5cf5aea3bf51d5b1362c5be3bae8a9435b958bb7fd` |

The audit build exited 0 at 13:27:11–13:27:13 UTC with the pinned V compiler
listed below. It retains the compiler command, generated C and unchanged
before/after V source closure inventories without copying the compiler
binary. Independent ordinary-file readback passed all 40 audit-bundle
files. Its proof is retained in
`maps331-result-audit-readback-2026-10-25`, manifest SHA256
`ebc87e10a0911e6a8d4aa2b9743e20337fad56cc7ad75b61ceb848b4093c12d6`.

The exact six replacement build pins are retained in
`maps331-replacement-build-pins-2026-10-25.json`, SHA256
`f83ba17c15d0715e5d3d268056a72e214163682fb2a1372e2a8263cdc4cf126d`:

| Key | Value |
| --- | --- |
| `native_root` | `/Users/alex/.local/state/vinix/android/nine-patch-tint315-native-build-2026-10-25` |
| `native_manifest_sha256` | `09c2c82ff7feb169733c7f77fc11683f409b2114e409fe9e70a8346c277d5aee` |
| `native_sha256` | `54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab` |
| `framework_root` | `/Users/alex/.local/state/vinix/android/system-package329-framework-build-2026-10-25` |
| `framework_manifest_sha256` | `4f526669c32b91db3da92d3508b6aa97297d8a8b48b89fef29f6cd3f1f64559e` |
| `framework_sha256` | `c88b7f8a7ee34776641fc235922d0d86a0d8eefc60d09e50d55836aabb624934` |

At 12:48:12–12:48:13 UTC, the original preflight invoked the existing
generator once with its supported explicit `--minimum-free-mib=1536`
policy. Its first checkpoint observed 840,624 KiB, below the required
1,572,864 KiB, and exited 1. All seven canonical destinations remained absent.
The original default 5,120 MiB policy is unchanged. This failed preflight
remains at `maps331-generation-preflight-2026-10-25`, manifest SHA256
`b23b577133848c6ccc3a3c4a92fc02a476c40def42184a68b6dbce0abee62bd1`;
independent full readback passed all 21 files. Its one-shot wrapper was not
rerun, and its original source and artifacts remain unchanged.

After disk space recovered, the unchanged generator was retried exactly once:

```
build/android-maps/maps-replay-generate314 331 /Users/alex/.local/state/vinix/android/maps331-replacement-build-pins-2026-10-25.json --minimum-free-mib=1536
```

The retry passed both existing disk checkpoints and exited 0 at
13:02:34–13:02:45 UTC. Preparation then exited 0 at 13:04:41–13:05:19 UTC.
`maps331-resume.v` records each invocation in a fresh receipt directory with
argv, source/compiler/tool pins, timestamps, separate stdout/stderr and exit
status. Each bundle retains the wrapper source used for that invocation;
later checker additions do not change those retained snapshots.

| Evidence | Manifest SHA256 | Independent full readback |
| --- | --- | --- |
| `maps331-generation-retry1-2026-10-25` | `30d7703d5c78ddbbe0b0d92a873bd5435a7e40be2701f400ed61e33141bbf4dd` | 7 files passed |
| `maps331-preparation-retry1-2026-10-25` | `619a97f0ee4c6d1dfff6faaaf2bfc71b4ad8a58138aa6b26981f8f72a4e2c379` | 8 files passed |

Readback receipts are retained in the corresponding
`maps331-generation-retry1-readback-2026-10-25` and
`maps331-preparation-retry1-readback-2026-10-25` directories, with manifest
SHA256 `95ba4d9279571b4e06da8babd467ee75ea6a4b3f03df915e88d74c3910acc24f`
and `be37fb263b70d0f8dd7106515227fccdb54ce3c775cbf32fa1377187469ab88c`.
The V checker compares every ordinary file against the complete sealed map
and rejects symlinks, missing files and extra files.

| Input or prepared output | SHA256 |
| --- | --- |
| Existing generator binary | `75b69d07fdf23401b07ee8cad36d7ba2a47dfd5e48c13660c4307f91e882b453` |
| Generator source | `39b9d763de6c5685021731ec877a276d2110f8cd457c4ff6bcf8bc1e399b6d84` |
| Pinned V compiler | `109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e` |
| Generated runner source | `074fe84008f0e2443b09f111606354ea16b4268685d210ae5f841220f13f5e4d` |
| Recorded runner binary | `26eb66be3ffb5a70ce82b27ff57c53823e667e38d8851aeb2b6b108df8903bea` |
| Launch pins | `a8cce23a63e86954cc1bed5214a931c898021aefe58cdcc8b04462b64fcfd589` |
| Prelaunch manifest | `bbfbd57500dab625dfbee9cfbeb03fab04589f71126166287d3ac396f09a6242` |

The root session reviewed these pins and the recorded runner's read-only
`check` passed before launch. Generated source and build receipts remain in
`maps331-generation-2026-10-25` and `maps331-run-build-c-2026-10-25`;
the retained prelaunch inputs are in `maps331-2026-10-25`.

The first envelope's host environment tests and 40-file readback had passed,
but its actual launch attempt exited 1 with `V panic: map key does not exist`.
It selected the relative runner-map key while the authenticated launch-pins
map uses the absolute repository path. This failure preceded creation of its
runtime receipt directory and guest launch. The original failure time was
not recorded; the root tool transcript is its original output evidence.
The old sealed envelope remains unchanged at
`maps331-launch-envelope-2026-10-25`, manifest SHA256
`fa9162d8a0cd261560f38f9548bc4dffd728566c93ca9d413fff9545eb27133e`.

The fresh `maps331-launch-envelope-v2.v` uses the same absolute runner-key
selection in its host self-test and launch path. Its tests select the actual
runner and reject a relative key, noncanonical hash and mismatched hash.
The clean-environment child test also passed. The build retains the compiler
command, generated C, unchanged before/after V source inventories and the
root-reported original failure metadata, explicitly marked with no original
timestamp and no reproduction. Independent full readback passed 28 files.

| V2 envelope evidence | SHA256 |
| --- | --- |
| `maps331-launch-envelope-v2-2026-10-25/sha256.json` | `42ae0f3ecc46b0bcf3a8a03ef86c38c51eab251be685727b4edeb4999376d2cc` |
| `launch-envelope.v` | `8c9648ba9a6ac96801ac7cebfd51a26d89ba50e2e3c0178847daf229a4d181ad` |
| `launch-envelope` | `afa71290bed4c6411f6ed61b0204f9c5d0e9e7213327179849425e49525a7325` |

The runtime receipt directory
`maps331-launch-envelope-v2-run-2026-10-25` records 13:11:18–13:21:52 UTC
and exit 0. Its manifest SHA256 is
`35481e0175c52bdf309bf973ab2efb0e1f3c56d1ead55aa094c58ad4e02fcd44`.
Independent V readback passed all three files; its proof is retained in
`maps331-launch-envelope-v2-run-readback-2026-10-25`, manifest SHA256
`2a7b3ed60be3dfe750779e020e1e0d12548e75003428201215bbef13864106ff`.
The runner hash is unchanged before and after the invocation, and the
environment receipt records no removed keys or forbidden remaining keys.
Do not rerun `--build` or `--self-test` against either sealed build bundle.
`--verify-build` is read-only. Earlier running-Maps PNGs and
application observations remain in [maps327.md](maps327.md). This replay
qualifies the manual-origin driving and walking flows described above;
the prior Attractions loading sheet's cause remains undetermined.
