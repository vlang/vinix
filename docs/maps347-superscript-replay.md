# Maps347 SuperscriptSpan replay

Maps347 passed onboarding, rendered Paris with loaded photos, displayed
Attractions results and opened Pinky Tour - Paris with its rating, hours,
Eiffel Tower/car photos and booking options. Directions rendered a driving
route from Louvre Museum to Pinky Tour - Paris with a 24-minute estimate.
Route preview opened and advanced to `120 m / Slight right to stay on Pl. du
Carrousel`, with changed map position and a Street View thumbnail. The earlier
fatal `SuperscriptSpan` failure does not recur. Live navigation and broader
Maps compatibility remain unverified.

Qualified framework source: `1458d5facbcbbfe496322b49d111284869ea7e02`.
Deriver: `1cc69c60e8afb3300250b138b8b8225a3b65a43e`; generated tooling:
`7555b224310d2634c17ddc31c8274c6478cd9b42`. The qualified346 framework JAR is
the sole changed entry among the authenticated Maps335 prelaunch runtime's
109 files; native332, diagnostic launcher, kernel, base media and classifier
are unchanged. The fourth boot module carries the qualified JAR overlay.

All times are UTC on 2026-10-25. The recorded envelope ran 18:07:48–18:18:59;
the application suite ran 18:08:09–18:18:24. Both exited 0. The envelope records
unchanged input pins, 50 clean environment entries and no forbidden keys.
The original **600-second** observation completed with **600 seconds observed**,
`window_observed`, `process_exited=false`, `backend_ready=true`,
`native_maps_observed=true`, `qemu_alive_before_capture=true` and
`functional_passed=null`. Functional observations above come from actual UI checks.

Background Play Services failures remain: missing Chimera config, services
without a Chimera implementation and unavailable Phenotype.API (serial
2696–3913). ART logs `VerifyError` for `hwv` extending erroneous class `hqa`;
`hqa.V(long,long)` copies undefined register `v3` (21187/21202, 37616/37631).
These errors are nonfatal here; later details, Directions and preview render.
No `ANDROID-WS-FAIL`, APK-exit, `NoClassDefFoundError` or `NoSuchMethodError`
marker appears in the raw serial. Video playback remains unverified.

Artifact paths below are relative to `/Users/alex/.local/state/vinix/android/`.
Actual QMP PNGs, input receipts and logs are retained under
`maps347-2026-10-25/results/attempt347/google-maps/`:

| Command time | Visually reviewed PNG | SHA256 |
| --- | --- | --- |
| 18:11:19 | `paris-loaded.png` — Paris map and two loaded photos | `ca64c9880c1b1e3061f4f209f0903b0b01309e2af1937145c4e173b9c21e5587` |
| 18:12:18 | `attraction-details.png` — Pinky Tour details and photos | `d7e088eaf8e86a66235de9bc57265738e77252d2e8d84e47f70a62fb4dde4ba0` |
| 18:13:22–23 | `directions-route.png` — 24-minute driving route | `e03d8aa4cd789e9ba6ce47c54c7704356012a9edd748b1e24920ef43eceb1f64` |
| 18:13:50 | `route-preview.png` — first instruction | `46bf8fe7cb75261f11d14889b17f4fb936b219dd1bc461af17b138222ef81852` |
| 18:14:09 | `route-preview-next.png` — next instruction and thumbnail | `44dc83c24caeaf62f06dbd41527411bc5270a1f96a1a98b5bbc210efb0338ada` |
| 18:18:24 | `application.png` — final capture, Maps still on preview | `ba28374680b597cb988843c100389ee858042cedc3b4eb472a613615d0489a05` |

`interaction.log` records Skip at 18:08:34–35, Paris selection at
18:08:59–18:09:00, Attractions at 18:11:25–26, the result at 18:11:54,
Directions at 18:12:21–22, Louvre selection at 18:13:01, Preview at
18:13:41–42 and next arrow at 18:13:59–18:14:00. Last manual capture completed
18:14:09; the automatic final capture is also collected.

Retained bundle manifests (`sha256.json` SHA256):

| Artifact directory | Manifest SHA256 |
| --- | --- |
| `superscript-span346-2026-10-25` | `6d5205fce48faea0c406efb68ec9134c039aa106e591d20e4501f2826d65064b` |
| `maps347-preparation-receipt-2026-10-25` | `07746a358dd69af83e12bc97b5994155d2c4bc9e844f1a68b58029f664284b91` |
| `maps347-2026-10-25` | `32581aa151fe09b82f6e0109d60ebdf6c1de7b7e20a9c38ff0899999b6f785a2` |
| `maps347-launch-receipt-2026-10-25` | `8a5d4a31006e251c37225ebcb76ddf35eecb7ebc3a3b823426c3e1bf9cd5c749` |
| `maps347-results-compare-build-2026-10-25` | `b6e962089f2f7b987c7840cba2de60e8d2eed187feda46e05a50f04f714e06ef` |
| `maps347-results-comparison-2026-10-25` | `9cfe7f5528e682d51a0c11b7ccb1cdd7d7e0a3d29c6e0b778df1b9bb2cd2ff80` |

Qualified JAR SHA256: `b33472257a59c9b8dffca155c2f1ecd77e0f10c3dae230a23a3afafee9e7c840`.
Generated runner source: `maps347-generation-2026-10-25/maps347-run.v`,
SHA256 `214aa01cfaa3abe1561f9ad468e8a5fd33a4431b9935ccdebc84088882de0f41`.
Recorded runner: `build/android-maps/maps347-run-recorded`, SHA256
`e6ce0a642a1235a9ef103e7e13d4167579baeb0a1fcfeab070dae4928ed6e8e2`.
Launch pin: `327c59fb0aa4aa94ca7ccdfc95a1a3237a993bee232e938bfdd535a63c9434e7`;
prelaunch typed manifest: `a98414faf962dbb7bc86e0ce9691d43342e8c07f09f7424bffc276e86acfb6a7`.
The canonical bundle retains source/compiler closures, generated C, input pins,
command receipts, serial, packet capture, PNGs and postrun media.

Full typed canonical verification passed **43,386 entries** independently for
the report author, replay owner, root and peer. The comparator retains its
canonical readback log; sibling logs include
`maps347-completed-own-readback-2026-10-25.log` and
`maps347-completed-peer-readback-2026-10-25.log`. The unchanged complete
checker290 passed all **9 launch-envelope files**, **293 recorded-build files**
and **299 comparison files**, also independently checked by root and peer.

The tracked `tests/native-android-ws/maps347-results-compare.v` authenticates
the canonical and launch pins before comparing complete live/captured typed
inventories twice, including hashes, directories, modes and symlink targets.
All **146 application entries** match; both socket inventories and the delta
are empty. No late interaction supplement is needed. Original bundles remain
untouched. Its recorded build retains equal before/after source/compiler
closures, compiler/CC pins, generated C and command receipts; the separate
bootstrap invocation only entered recorded-build mode.

Own complete-check receipts are
`maps347-launch-child-readback-2026-10-25.json`,
`maps347-results-compare-build-child-readback-2026-10-25.json` and
`maps347-results-comparison-child-readback-2026-10-25.json`.
Root and peer retain separate readbacks alongside these artifacts.

Reproduce complete canonical verification from the repository:

```sh
build/android-maps/maps347-run-recorded verify 32581aa151fe09b82f6e0109d60ebdf6c1de7b7e20a9c38ff0899999b6f785a2
```
