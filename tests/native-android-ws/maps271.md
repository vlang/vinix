# Maps271: route preview after CompoundButton text fixes

On 2026-10-24, the signed Google Maps APK completed onboarding Skip, Paris
search/details, an Eiffel Tower → Paris route calculation, Preview and Next in
the native runtime. Category and action chips have readable spacing and no
synthetic checkbox squares. The observed route was 18 minutes; Next changed the
instruction, map geometry and lane arrows. This is a manual workflow observation.
The unchanged Maps256 classifier still reports `startup_failed`, with
`functional_passed: null`, because its failure list includes gRPC
`ClassNotFoundException` markers. The raw classification is preserved.

Production revision `f1b8ed0bd4defa39e9caf2b03733b52f60878045` fixes
CompoundButton text dispatch and gravity. Paired270 uses paired266 as its source
baseline. Its fixed smoke and full paired fixture passed before Maps271 launch.
The prelaunch contract verifies all 125 framework and 83 native baseline/fixed
sources, changes restricted to `framework_text_widgets`, `framework_check_widgets`
and `ws_draw_content`, unchanged paired266 bindings, six actual build receipts,
and exactly two overlays in the 109-file runtime. The framework SHA-256 is
`b1364aa6d21f3293bef534a939cafa93bb4194e13deb9c0864bec7e9b18f9413`;
native SHA-256 is
`ce78582105a8e2e29e29d0fa843769549d5fa4deba02067b41749643bb4b0c32`.
The signed Maps APK remains
`6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2`;
the identity256 runner remains unchanged.

The suite started at 20:17:17 UTC and completed its configured 420-second
observation naturally. Backend readiness and native Maps were observed;
`process_exited` was false and QEMU was alive before final capture. The suite
captured the final application frame, stopped and waited for QEMU, then froze
the serial bytes, hash and gzip. Capture times below are unique258 command BEGIN
timestamps in the retained interaction log:

| UTC | Retained frame or action | Observed state |
| --- | --- | --- |
| 20:18:59 | Skip | Leaves onboarding |
| 20:20:06 | `paris-result` | Paris details |
| 20:20:20 | `paris-loaded` | Paris street tiles and boundary |
| 20:22:54 | `route-ready` | Captured early; still suggestions |
| 20:23:35 | `route-ready-loaded` | Eiffel Tower → Paris, 18 minutes, Preview |
| 20:23:43 | `route-first` | Head toward Pont d’Iéna |
| 20:23:49 | `route-next` | 750 m, turn left onto Pont de l’Alma; changed geometry/lanes |
| 20:24:42 | `application` | Final application capture |

The original `route-ready` image and its complete command streams remain
unchanged. It does not demonstrate a loaded route. The frozen checker keeps its
original five-frame requirement. Separately pinned collection and retention
wrappers add `route-ready-loaded` as a mandatory sixth unique capture; the
checker verifies every listed capture exactly once. The final list contains 13
unique names: `application`, `paris-result`, `route-ready`, `route-ready-loaded`,
`route-first`, `route-next`, `after-skip`, `paris-suggestions`, `paris-loaded`,
`directions-entry`, `origin-suggestions`, `origin-selected2`, `paris-reselected`.
Polling probes are retained with their stated overwrite limitation.

The complete bundle is
`/Users/alex/.local/state/vinix/android/maps271-prelaunch-2026-10-24`.
Its 3,672-entry prelaunch manifest SHA-256 is
`c3a6ae9df254f5291e9a44a39827fd5df9daa913c9ffa8e4e09a053ebb4a4824`.
The independent prelaunch inventory/media check and the separate source-contract
check passed before launch. Final seal and independent full check passed with
4,111 entries; completed manifest SHA-256 is
`0041be9439b85aec2f084fe1b1b77a7d9a33e6b204b6b6a518f2d413ecfc8cac`.
Wrong-pin and incomplete-bundle negatives were rejected as required. Their
receipts, logs and retained fixture are in the separate 16-entry bundle
`/Users/alex/.local/state/vinix/android/maps271-validation-2026-10-24`, manifest
`c5fd489dd0f7546ad44ba5abd32158e663c0e049ca72d6e4d23e4741aa7ac0a4`.
Recheck using the retained assertion-enabled executable from this checkout:

```sh
cd /Users/alex/code/vinix
maps271_bundle=/Users/alex/.local/state/vinix/android/maps271-prelaunch-2026-10-24
"$maps271_bundle/audit/maps-compound-text-evidence" check "$maps271_bundle" \
  0041be9439b85aec2f084fe1b1b77a7d9a33e6b204b6b6a518f2d413ecfc8cac
```

The immutable assertion-enabled checker workflow has 32 entries, manifest
`a070198737d63ae792c8e480a3f9fd64dd3d1eacbfcbb2a6c84c452f633ea149`,
at `/Users/alex/.local/state/vinix/android/maps271-checker-2026-10-24`.
Its source-boundary tests, ten interaction-parser negatives, inventory checks
and original-classifier comparison passed. Its assertion probe failed as
required, and its production build refused to run checks. The maintained
[`maps-compound-text-postrun.v`](maps-compound-text-postrun.v) reproduces the four
postrun wrappers byte-for-byte; its recorded assertion-enabled build and
`--verify` check passed in the distinct R2 workflow.

The original 37-entry postrun workflow remains at
`/Users/alex/.local/state/vinix/android/maps271-postrun-workflow-2026-10-24`,
manifest `4951695af03e4a125d88c50b8a6d2e3ce7f7b58de7cbf4be583e1453bac8ad35`.
Its supplement failed on inherited preparation-receipt field names. Its partial
tree and observed error remain under `audit/failed-extra-audit-r1`; the error
receipt explicitly records that it was written after the failure. R2 checks the
genuine preparation/full-check receipt schemas and preserves before-to-done
equality, exact argv/tool hashes, manifest-covered logs and handoff pins. The
successful R2 supplement and its 31-entry workflow are separate, at
`/Users/alex/.local/state/vinix/android/maps271-postrun-r2-workflow-2026-10-24`,
manifest `04d300929303348036eb519fe5eb666cf27bd1ce0b901ff2f00a9048a7226ee5`.
The keeper, original collector and all historical bundles remain unchanged.
A later `v run` retention attempt rejected its temporary executable in the
protected workflow directory before mutation. Its observed failure is preserved;
the same source then passed with an explicit binary output and before/after
receipts.

The loaded overview has a large flat beige tile region, so it does not establish
a continuous route polyline. The subsequent preview frames show street tiles
and changed geometry. The compass is incomplete and suggestion circles remain
black. GPS, sign-in, voice navigation, 900-second endurance and independent
post-drop identity were not measured. This report does not claim complete visual
fidelity or a full automated functional PASS.
