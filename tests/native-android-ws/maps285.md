# Maps285 search and route preview

Google Maps reached the map, live Paris search suggestions, place details/photos,
Directions, and route Preview. Next visibly advanced from **Head toward Pont
d’Iéna** to **750 m / Turn left onto Pont de l’Alma**, with turn/lane arrows and
a changed map camera. Previous returned to the first instruction. These are
manual observations of the retained screenshots; the startup suite's raw
`functional_passed: null` remains unchanged.

The run completed its 600-second observation naturally with exit 0. Maps was
still alive before capture, the native backend and Maps markers were present,
and the classifier found no failure markers (`window_observed`). The driver
requested “Eiffel Tower”, but the input screenshot shows “Eifl Tower”; the correct
suggestion was selected. Blue overview geometry was not established. This replay
does not establish general Maps correctness or a causal performance improvement.
GPS, sign-in and voice were not exercised; recorded UI lag remains.

| UTC, 2026-10-25 | Observed step |
| --- | --- |
| 02:46:15 → 02:47:03 | Skip, then visible map |
| 02:47:58 → 02:48:17 | Paris input, then live suggestions |
| 02:48:20 → 02:49:06 | First result, then details/photos |
| 02:49:13 → 02:50:20 | Directions, origin entry, correct Eiffel Tower suggestion selected |
| 02:51:20 → 02:51:42 | Preview opened with Head toward Pont d’Iéna |
| 02:51:48 → 02:52:06 | Next advanced to Turn left onto Pont de l’Alma |
| 02:52:21 → 02:52:47 | Previous returned to Head toward Pont d’Iéna |

The complete new bundle is
`/Users/alex/.local/state/vinix/android/maps285-2026-10-25`, manifest SHA256
`c4eb3b9197c4f3b3bc77585013abb7da87071efde0e6f66bd8459a2579c6f5c7`.
The three reviewed images are under `results/attempt285/google-maps/`:

| Image | SHA256 |
| --- | --- |
| `preview-open.png` | `45f537ad6635517dbf00b6d6c5d882db98601d7bbb3e8f2bb9f844e5091304aa` |
| `preview-next.png` | `be3cf4f66c171ad86b9f6de2090302fecfbf8b4001c1bfad36f49cffe9819230` |
| `preview-previous.png` | `1212730de7938767423d1d4536e92187041b358a6211a0872ff96b73914cf13a` |

Maps285 consumes sealed Maps283, replacing only the native library among its 109
regular runtime files. Framework282, the clean launcher, Maps APK, identity and
companions remain unchanged. Preparation also compares directory types, symlink
targets and permission modes against the canonical runtime tar. Fresh boot and
firmware-variable media use APFS clones. The assertion-enabled suite changes the
budget from 420 to 600 seconds; its original `observation()` body is byte-identical.

Historical inputs remain complete pinned references:

- Maps283: `/Users/alex/.local/state/vinix/android/maps283-2026-10-25`,
  manifest `643adb9d5c778a1f388e9334aebebd7955d1efb02e29f9e332fcb4d25aebf43a`.
- Queue284: `/Users/alex/.local/state/vinix/android/compound284-2026-10-25`,
  prelaunch manifest `c90e705c8a03044dac321190f02a8678d6050f749fa17f800db786c45d084699`.
  The bounded queue/runtime fix is committed as `016a50ea3`. Selected native SHA256:
  `2687a6df361f3173499fcae7ffeeb9318d2c83363cee1fce0deedf17f9ee0585`.

Tooling revisions are `949970e46`, `66891d15d` and `e70adf7db`.
The retained compiler SHA256 is
`109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e`;
builds use explicit `VROOT`, `-nocache`, `-cc cc`, `-cflags -O2` and assertions.
The completed bundle retains the consumed source/tool closures, actual build and
launch argv, timestamps, exits, complete combined stdout/stderr, prelaunch inputs,
results and postrun media. No result sockets were omitted.

Preparation/parser checks passed, including all 304 typed entries (109 regular
files), mode/symlink cases and nine malformed archives. Runner checks rejected
wrong/missing pins before launch, retained all 20,000 capture-probe payload lines
and both stdout/stderr sentinels, and rejected production mode. The final no-VM
input gate passed. The earlier relative-path gate failure remains retained.
Actual preparation and runner build roots and receipts are included in the
completed bundle; their manifests are respectively
`4cdde83512e06b97a0d0e529cf09a3dd870d0d9304936d8892df30f633b49677`
and `54f62d97952c7417d6c9c1ce61be0a540bbf946852125c7ddefd935cdf1db7ee`.

The recorded suite launch ran from 02:39:06 to 02:54:26 UTC. Its complete merged
output is 379 bytes, SHA256
`15d4fec15caacfef5d7a819135d02e784664032db6ebb212f2ff30ac1d5c9b44`.
This includes setup and capture time around the 600-second observation.

Independent completed-bundle readback passed for all 1,584 entries. Eleven negative
selftests and the production-mode guard also passed. Checker evidence is retained
at `/Users/alex/.local/state/vinix/android/maps285-completed-check-2026-10-25`,
sealed and independently read back at 444 entries, manifest SHA256
`9b870cc3310498b9f8bd3d047f9d1391c042a44eee72bcde4bb9e0b574ab6504`.
Checker source SHA256 is
`a2631a4e497144e60344fcc393f6dd8d0b61e2b5e44e18c16a1a4cf6513647fa`;
binary SHA256 is
`afe0958020a20d08f14d633be07c9566c7bb08184a4ea32480905fc48a2f54c4`.
`maps285-check.v` verifies the new complete inventory, nested build/prelaunch
manifests, launch before/completed fields and output, native-only runtime/typed
modes, postrun pins, original classifier, raw/gzip serial, actual observation
duration/liveness and the reviewed image hashes. It does not re-audit historical
bundles or infer visual semantics from changed image bytes.

The descriptive Maps283/285 timing output is retained at
`/Users/alex/.local/state/vinix/android/maps-timing-2026-10-25/`.
`maps283-vs285.json` SHA256 is
`5a78e1cbd646bc0ffbfc361d5d49b6a2fbfb1365c19ce86718f8f97b94e8390d`;
the text output is
`0aee8b189d95e5b6bac3b9e54ba3df812570f8b68a7f865ef0e18aa6584c9ac2`.
Analyzer source revision is `43dbf0b67`, binary SHA256
`ea20e0b2a9f09d7f7b59670a1822e78eb605cd40b90dff60beb7cabe64b9c6fc`.
Workloads differ and the host was heavily loaded. Logged samples exceeding
100 ms are descriptive diagnostics, not a controlled comparison.
