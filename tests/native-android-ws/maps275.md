# Maps275: suggestion pins and route preview

On 2026-10-24 UTC, the signed Google Maps 26.42.01.997557324 APK completed
onboarding Skip, live Paris search/details, an Eiffel Tower → Paris route,
Preview and Next in the native runtime. All nine visible Paris suggestion
pins have holes and pale gray circular backgrounds; the former opaque black
disks and square edges are absent. The calculated route was 18 minutes.
Next showed “750 m — Turn left onto Pont de l’Alma,” changed bridge/river
geometry and lane arrows. These are manual observations of retained frames.

| UTC | Retained frame | Observation |
| --- | --- | --- |
| 21:17:51 | `after-skip` | Main map, search bar and bottom navigation |
| 21:18:26 | `paris-suggestions-loaded` | Nine readable suggestion pins |
| 21:18:47 | `paris-loaded` | Paris streets, boundary, chips, actions and photos |
| 21:19:20 | `route-ready-loaded` | Eiffel Tower → Paris, 18 min, Preview; map initially beige |
| 21:19:36 / 21:19:54 | `route-overview-held` / `route-overview-stable` | Streets, river, green areas and blue route geometry/shading |
| 21:20:07 | `route-first-loaded` | Head toward Pont d’Iéna; bridge/river close-up |
| 21:20:19 | `route-next` | Next instruction, changed map and lane arrows |

There was no input between the two overview captures. Preview was clicked
37 seconds after the first loaded-route capture; this does not isolate network
versus GL delay. Initial `paris-suggestions`, `paris-result` and `route-ready`
captures were early. An early click opened sign-in, which was cancelled before
search resumed. All early frames and command streams remain unchanged.

The suite completed its configured 420-second observation naturally.
Backend readiness and native Maps were observed; `process_exited` was false
and QEMU was alive before final capture. The unchanged Maps256 classifier
reports `startup_failed`, with `functional_passed: null`, because it records
gRPC `ClassNotFoundException` markers for `JndiResourceResolverFactory` and
`ContextStorageOverride`. Manual observations do not override that outcome.

The replay uses the original Maps256 signed APKs, identity runner and 109-file
runtime base, with exactly the paired274 JAR and native library overlaid.
The Path fill and DST_IN production changes are commits
`e4999db8854bd2fb60c4f1fa2705e8a382e445bb` and
`b50aab72d68639fedc983ac2b18da11aabf9b194`, respectively.
Preparation recorded repository revision
`8479f21ae07812c60ac3ea871bf1cd498e83204c`; the actual built source snapshots
are retained separately, including changes not yet committed at preparation.
The six actual paired274 build receipts and the generated suite build receipt
bind those sources and tools to these artifacts:

| Input | SHA-256 |
| --- | --- |
| Framework JAR | `1a026975748c693f11c09c7fc080f8b72c20c0638c01996f226698cc740f92f6` |
| Native library | `27f1ec2604f93f55d8b3557fb7e34dc754daedde854a6041939503cb72cf12a7` |
| Framework source map | `aa68c5f9f63ffaad9f984a767a91e65d97c1ce78ea76c1bea085aacf692569ab` |
| Native source map | `a7d69d7439fd2b62974d2d6f0a82f48b42d184bdd13e65cf803a3d027013bab6` |
| Signed Maps APK | `6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2` |

The independent 3,326-entry prelaunch check passed before launch. Its bundle is
`/Users/alex/.local/state/vinix/android/maps275-prelaunch-2026-10-24`, manifest
`3f92980b482d7858f508ef9f6329e68815449c6b3ee5f638051dec79a28486b5`.
The completed 3,475-entry bundle is
`/Users/alex/.local/state/vinix/android/maps275-2026-10-24`, manifest
`9156da6d7557475e4ef20a451c7d2a0e9446bd9f3c755bc0d2c5634c4c627663`.
It retains launch/source/build inputs, raw results, 18 PNGs at 1024 × 768,
serial bytes and gzip, packet capture, command streams, supplemental logs and
independent prelaunch/postrun media. Raw and supplemental source inventories
were rechecked after copying; the recorded special-file omission list is empty.
Seal and independent complete check passed; the wrong-pin negative was
rejected. Historical bundles and checkers remain unchanged.

The receipts are at
`/Users/alex/.local/state/vinix/android/maps275-postrun-2026-10-24`, manifest
`03ab51829359bfdbc691d943a368ade9013aa7a06bd5f1cbb92d33e2fdfe4721`.
They also pin corrected root visual notes: the initial retained notes labelled
the lower-right location/control glyph as a compass. The original notes stay
unchanged; `visual-notes-corrected.md` and its old/new hash receipt preserve
the correction separately. That control remains fragmented or unreadable;
compass fidelity was not established. Street-label completeness, GPS, sign-in,
voice guidance and long endurance were not validated.

The maintained staging and evidence tools were committed as `815a04c79` and
`03a0f90c3`. Their fresh collector workflow and preparation receipts are retained
under the completed bundle’s `audit/` directory. Recheck from this checkout
using the retained assertion-enabled checker:

```sh
maps275_bundle=/Users/alex/.local/state/vinix/android/maps275-2026-10-24
"$maps275_bundle/audit/maps275-collector-workflow-2026-10-24/maps-replay-evidence" \
  check "$maps275_bundle" \
  9156da6d7557475e4ef20a451c7d2a0e9446bd9f3c755bc0d2c5634c4c627663
```
