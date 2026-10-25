# Maps332: layout-request fix replay

Maps332 selects new full Native332 and Framework332 payloads containing the
layout-request fix `13fe935f429089f74f5179c427f659cdbacea7c6`. The native
sources derive from sealed Native315 and the framework from sealed Framework329;
the bounded changes, exact baseline provenance, complete build inventories and
independent readbacks are in [layout-request332.md](layout-request332.md).
Native315's historical timing instrumentation remains in the frozen baseline.
Preparation's checkout revision is `88fecc8953916e972318531f77cad76bca3e6963`;
the payload snapshots and hashes below identify what was actually selected.

Generation, preparation and all three ART fixture controls passed. The
old framework loses the manual callback request; the new framework with the old
native library loses the next root measurement. Both new payloads pass the
manual, root and dialog checks and reach `BOOTSTRAP-READY`. The complete
877-file ART bundle and its independent readbacks are recorded in
[layout-request332.md](layout-request332.md). The 600-second Maps332 replay also
completed: map display, Paris search, driving and walking routes, preview
advancement and an options toggle were visually observed. The preceding baseline
is [Maps331](maps331.md).

All external paths below are relative to
`/Users/alex/.local/state/vinix/android/`. Timestamps are UTC on 2026-10-25.

| Selected full build | Manifest SHA256 | Payload SHA256 |
| --- | --- | --- |
| `layout-request332-native-build-2026-10-25` | `40b1099c58abe7fb3729ee2b48fd13d171f9ebaf70d1b83e26b5ad9f93aac163` | `2231ee3def626a72119cd80d646966ec5ba2fa6cd7dd74a790fe9bcb9db5869b` |
| `layout-request332-framework-build-2026-10-25` | `6f3d2a9ebcffa24cb61b4a765abb866d90914e96363af241e7cd67a5387d20cf` | `0229315058b2d24f1f84d886fc47b3fab6fd3b0b7cc7c32f0b9771908276d9ca` |

The payload paths are `native/libvinix-android-native.so` and
`framework/api-impl.jar`. The fresh six-key file
`maps332-replacement-build-pins-2026-10-25.json` contains the two absolute roots,
manifest pins and payload pins above. Its SHA256 is
`60f52ca38e15e6026a32bdf73cf94cc0c1fdf7cdf5db28c5e07bfb7955f5279b`.
Independent root build readbacks passed all 2,418 native and 7,061 framework files.

`maps332-host-tooling.v` freezes the parameterized `maps-replay-receipt.v` tool,
records its compiler command and generated C, checks the unchanged V source
closure before and after compilation, runs its host self-test and writes the
fresh replacement pins. It does not launch a guest. The recorded build exited
0 at 13:44:46–13:44:49; its host self-test exited 0 at 13:44:52–13:44:54.
The test accepts the actual absolute runner key, rejects four malformed or
mismatched pin selections and runs a child that asserts the filtered environment.
Empty and nonempty forbidden values are removed; unrelated names are preserved.

| Tool/input | SHA256 |
| --- | --- |
| `maps-replay-receipt.v` source | `ef464fa8ea251493bc2e9a907a0635e2412074a6e91a5837f9bf11d7c512aee3` |
| `build/android-maps/maps-replay-receipt332-recorded` | `30edced25287dcf09502a3db11c7023c2eb56d1cc8bdb84166f35a0303c715ca` |
| `maps332-host-tooling.v` source | `0822135e8435dd067d411d12246941b84a3a9f3b268c505e8dc9527883cb3e91` |
| Host-tooling bootstrap | `268299308ec4c563f57fc0db2e9797aa6a719b90813a8f61f65ace49df7d1db8` |
| V compiler `build/android-maps/queue284-tools/v_old276` | `109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e` |
| Existing `build/android-maps/maps-replay-generate314` | `75b69d07fdf23401b07ee8cad36d7ba2a47dfd5e48c13660c4307f91e882b453` |
| `maps-replay-generate.v` source | `39b9d763de6c5685021731ec877a276d2110f8cd457c4ff6bcf8bc1e399b6d84` |
| Original `maps298-run.v` source | `5d220b06590bc0823f12c6d5071dc60af51a9dc284a383afb77cb907c1f17ed1` |

The exact generator ran with attempt `332`, the fresh replacement-pins file and
`--minimum-free-mib=1536`, exiting 0 at 13:46:21–13:46:31. The recorded policy
retains the 5,120 MiB default and explicitly selects the existing 1,536 MiB gate
for this attempt; no threshold was lowered after failure. The runner was derived
fresh from Maps298. Preparation exited 0 at 13:47:03–13:47:39 with the exact six
full-build pins. Both stages retained argv, timestamps, stdout/stderr, before/after
input hashes and disk snapshots. Each used 50 child environment entries, with no
`VINIX_ANDROID_TRACE_*` or `ATL_UGLY_ENABLE_LOCATION` keys remaining.

| Preparation output | SHA256 |
| --- | --- |
| `maps332-generation-2026-10-25/maps332-run.v` | `1f29c46271bd1318d6d94b9433ed136c8e000fd49c7210767c45bc3a1fc0aa5a` |
| `build/android-maps/maps332-run-recorded` | `1b36036bfc9befcd6eb9994af3ece597230d834ca0c1fd5456ea85989d352405` |
| `build/android-maps/maps332/launch-pins.json` | `fb741a3cf674606dd368616909eb7d3f6d8d930c608100a817e56a5532f038c9` |
| `maps332-2026-10-25/prelaunch-sha256.json` | `fcc7698060810d40227460227faf079cb87d0f1edfa15945552e9c59915cfcf7` |

Preparation authenticates the complete selected build bundles, preserves the
109-entry runtime comparison against Maps295 and verifies the FAT archive against
the module stream. Launch pins use the canonical absolute runner and generated
source keys. The application observation window remains **600 seconds**; the
unchanged classifier has not been rewritten to report functional success.

| Retained receipt bundle | Files | Manifest SHA256 |
| --- | --- | --- |
| `maps-replay-receipt332-build-2026-10-25` | 33 | `2da9ddb4c1cb7875ca67b0af5f937dd1386bd74fa0b05aca386afcc80ce1e68c` |
| `maps-replay-receipt332-recorded-selftest-2026-10-25` | 10 | `87b4f67d4b80df7c8bd10bcbb741a1d2a2d34d4c2f5832d5288283e744bed4c8` |
| `maps332-generation-receipt-2026-10-25` | 9 | `a78bccd09c514c16e1c6a58f6f2cc4bb605b93db4577f08a79e3eb67b1eda4c4` |
| `maps332-preparation-receipt-2026-10-25` | 9 | `aa235d7925f10a4faff2583e40b7bccbe80c220dc4f467a22d4fa566e21e3294` |

All four passed complete-file/hash readback by the tooling agent and independent
root readback at 13:49:48. Root receipts replace each bundle's `-2026-10-25`
suffix with `-root-readback-2026-10-25.json`. They pin the existing
`build/android-maps/build-bundle-check290` checker SHA256
`52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004`.
The exact recorded runner's read-only `check` then passed its complete launch
gate at 13:54:00–13:54:10, exiting 0 with `MAPS332-GATE-PASS`. Its fresh envelope
receipt is `maps332-check-receipt-2026-10-25`, manifest SHA256
`92e9d425487599bb2e08a4c597f602c8ae2e0873e7b0964d987d53804d60db4f`.
The tooling agent's complete nine-file readback passed; its sibling receipt is
`maps332-check-receipt-readback-2026-10-25.json`. The check used the exact launch
and prelaunch pins above, unchanged inputs and the same clean 50-entry environment.
It did not launch a guest. Independent root readback also passed all nine files
in `maps332-check-receipt-root-readback-2026-10-25.json`.

## Observed application behavior

The authenticated `run` envelope launched the selected full payloads. The real
guest was controlled using the existing `maps-interact-unique258` tool (SHA256
`abd2dfbb01fddc83ffffae481b5d1fcab35b9ebd279f3f47abae237b00134208`).
Its command receipts and screenshots are retained with the result. Pixel probes
only selected when to interact; the screenshots were visually reviewed.

| UTC | Observed behavior |
| --- | --- |
| 14:00:13–14:00:22 | Skip leaves onboarding; map tiles display North America. |
| 14:01:15–14:01:36 | Paris suggestions load; choosing Paris, France opens the place page with map and photos. |
| 14:02:32–14:03:52 | Eiffel Tower suggestions load; the first result produces a driving route to Paris, 23 min / 6.1 km. |
| 14:03:12 | Preview shows the first instruction, “Head toward Pont d’Iéna.” |
| 14:03:34 | Next advances to “Turn left onto Pont de l’Alma,” 750 m, and moves the map. |
| 14:04:16 | Walking mode shows the dotted route and 1 hr 3 min estimate. |
| 14:05:25–14:05:39 | Trip options opens; Avoid ferries changes from off to on. |

The first Paris typing attempt arrived before the search field acquired focus;
its screenshot still shows the placeholder. A second click and typing attempt
produced the reviewed suggestions. That unsuccessful attempt and every command
receipt remain in the bundle. The preview-next observation is stronger than the
unchanged screen in Maps331, but a single replay does not establish its cause.

The PNGs below are real 1024×768 QMP guest captures under
`maps332-2026-10-25/results/attempt332/google-maps/` in the sealed result.

| PNG | SHA256 |
| --- | --- |
| `map-after-skip.png` | `b2ee0365230e65d7e9b577159349177e2b48a5c83da8747037b0471d21f526e3` |
| `paris-suggestions-focused.png` | `ec72867b665a49ce480fe53c6211a94f8b1c5fa04bd764a5329cf737b7868bc8` |
| `paris-place.png` | `7059cdb85c61aeb124d551175b38573d9d6671b63374e847961b018655141a06` |
| `driving-return.png` | `a966f45636a72b8b62528331ba38c1ce9308e6878438f4a499e369821e10a5ac` |
| `route-preview.png` | `66173ec31899c2048a4b31ec629e87edb10b7e0905c7600e186a1d7f5f463c06` |
| `route-preview-next.png` | `d41210eff7ab76405bc5a69af79e76a9af279be52d8ffa320693c1bbfe4f0ec2` |
| `walking-route.png` | `e97ecc375c1ebe18e654184a881f731ce5def38b690c460224be871d9dc69193` |
| `trip-options-before.png` | `7080fe8c2f27b9882b3b6622777016e712a4b2debc96fa260c80717ae7193204` |
| `trip-options-avoid-ferries.png` | `98b098136f33530517192d72b6a8653660fe17b96ce71cf9584802961c3411fd` |

## Completed observation and readback

The suite ran 13:59:45–14:10:00 and exited 0. Its unchanged raw classifier records
`backend_ready=true`, `native_maps_observed=true`, `failure_markers=[]`,
`functional_passed=null`, `outcome=window_observed`,
`observation_elapsed_seconds=600`, `process_exited=false` and
`qemu_alive_before_capture=true`. Manual interaction results above supply the
scoped functional observations; the startup classifier remains unmodified.

The enclosing recorded `run` command ran 13:59:36–14:10:12 and exited 0. It used
the same clean 50-entry environment, no forbidden keys and unchanged input pins.
Its launch disk snapshot records 1,716,116 KiB available, above this attempt's
1,536 MiB policy. The complete nine-file envelope bundle is
`maps332-run-receipt-2026-10-25`, manifest SHA256
`501bb465001f9bbbe68e0193c0347a3b9976e1129b5f1034ca8e14453547c10f`.
Root complete readback passed in the sibling
`maps332-run-receipt-root-readback-2026-10-25.json`.

The canonical complete result is `maps332-2026-10-25`, typed manifest SHA256
`1a07738c22f4bb84181e34975f483521f12bcd3dfbc84a28643e2f9d334a96f1`.
Root ran the authenticated `maps332-run-recorded verify` with that exact pin;
full readback passed all 23,108 typed entries. Independent agent execution of the
same command and pin also exited 0 with
`MAPS332-COMPLETED-READBACK-PASS entries=23108`; stdout is retained in
`maps332-agent-readback-2026-10-25.log` (SHA256
`13b2871edd252e3597896209e5aae97cc8ab6b8c4a6887513ccb33f1cf39f327`),
with empty sibling `maps332-agent-readback-2026-10-25.stderr.log`.
The bundle retains source/build
closure records, consumed media, post-run media, serial/network logs, all
successful and unsuccessful interaction receipts and screenshots. Post-run
non-media input, module and selected full-build checks passed. QMP sockets are
explicitly omitted by the existing result collector.

The log contains nonfatal GMS lock-finalizer errors, missing Chimera
configuration and unavailable-service NullBinder errors. No framework failure
marker, `FATAL EXCEPTION`, fatal signal or certificate-collector failure signature
was observed. These scoped checks do not qualify live GPS navigation, sign-in,
rerouting, persistence across restart or the earlier Attractions loading sheet;
they do not establish that the layout fix caused the changed preview behavior.
