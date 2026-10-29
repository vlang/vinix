# GMS lifecycle caller audit — 2026-10-29

The captured startup failure names `pdo.onActivityCreated:22`. Its null receiver
is the result of the platform fragment lookup for
`androidx.lifecycle.LifecycleDispatcher.report_fragment_tag`, rather than the
Activity or saved-state argument. The deployed Service-lifecycle framework's
`FragmentManager.findFragmentByTag(String)` currently returns null
unconditionally. This audit makes no runtime change and does not claim that Maps
startup or Google sign-in succeeds.

The method reads `Build.VERSION.SDK_INT` and skips this lookup at API 29 or newer.
On the older-API branch, it calls `Activity.getFragmentManager()` at DEX offset
`0xb`, `findFragmentByTag()` at `0x11`, then `Object.getClass()` on the returned
fragment at `0x15` / DEX `.line 22` (`selected/pdo.smali:108`).
`bjbq.onCreate` calls its Chimera delegate's `public_onCreate(Bundle)` at `0x42` /
`.line 67` (`selected/bjbq.smali:2512`), matching the lower captured frame.

Let `S=/Users/alex/.local/state/vinix/android`.

- Complete bundle: `S/gms-lifecycle-class-audit-2026-10-29-r1`.
- Final `sha256.json`: `22f570a70323f79165f0fa0c0d8d6506ead604f3e7209cdc30d7bdf016011a1a`.
- External guard receipts: `S/gms-lifecycle-class-controls-2026-10-29-r1`.
- Source SHA-256: `1dd16bcf5419576ed252466b179e38302382a5cf6221a6fdc7a616963d7fa180`.
- Retained executable: `7c104847b3741b29c0b353233aede373239ea2f06f08f0145d8ce1a4e5ebbfb2`.
- Recorded checkout HEAD: `59879ee0b24423faa360adeadec11bffd1b51231`.

The complete original baseline is retained under `baseline/`, including its
nested manifest `bfdfc413af353e175b802672efa96475f5e7e07799016b9a19bc136b060954ee`.
The immutable root GMS APK was verified before and after production against
`a34d6a3ccea3ceba491369517e8f12e11df3791e86fec38b1cdf693785e35707`;
the baseline's APK-origin receipts were checked too. The extraction consumes no
guest logs, account identities or credentials.

Actual `class_defs` across all fifteen root DEX files select exactly these two
classes. Both belong to `dex/classes.dex`, SHA-256
`6e8eee316e1e39898ac815bedc2ad6d146a2d2274b52d57fd826209c88b45828`.
Baksmali runs only with these two `--classes` selectors, `--jobs 2`, and
`--code-offsets`; each Java command uses a 256 MiB heap and two active processors.

| Selected file | SHA-256 |
| --- | --- |
| `selected/pdo.smali` | `4ec212f914be89a253aa024a659d0241e8d3f16d49cb77ebb9478c8f72b380d4` |
| `selected/bjbq.smali` | `6f29b95e9c04cbc23193558e476289b9ebdd5fad00c65c6b2a706e66fd7a2e2c` |

Independent source review passed. The retained build, complete baseline checks,
exact selection, producer-receipt seal and final complete readback passed.
Self-tests reject unsafe paths, malformed DEX, missing/duplicate/unexpected
owners, reference-only class matches and duplicate class declarations. All five
guarded phases exited zero, completed cleanup, reported zero swaps, and retained
the 600 MiB aggregate RSS, 300 s, 1 GiB reserve and 512 MiB growth limits.

| Phase | Peak sampled RSS (bytes) | Wall (ms) |
| --- | ---: | ---: |
| Bootstrap | 363151360 | 1883 |
| Retained build and self-tests | 383041536 | 17899 |
| Extraction and initial seal | 164397056 | 76115 |
| Producer receipt seal | 75120640 | 22837 |
| Final complete readback | 66912256 | 14827 |

Readback: `ROOT/tools/audit check ROOT`. Build/extraction argv, compiler and native
input closure, generated C, owner index and producer receipts remain in the
complete bundle. Host SDK provenance is not a hermetic toolchain claim.

The historical three-class auditor and its bundles remain unchanged. An earlier
unexecuted draft incorrectly targeted `drod`; its complete source is preserved
at `S/gms-lifecycle-class-source-checkpoints-2026-10-29-r1/` under its SHA-256
`0c904cec53b9a98bbe5f5cc33917254c4665850b8d563557b2eb11a1aac85d73`.
The private runtime frame was viewed before correcting the target to `pdo`;
no build or extraction used the draft.
