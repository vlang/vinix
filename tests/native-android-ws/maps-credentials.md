# Maps credential experiments

`credential-launcher.v` is an administrator fixture for the unchanged Maps APK.
It keeps the root compositor's inherited input and fresh `/tmp` surface while
launching Android with real Unix UID/GID 10000. It does not establish a general
application sandbox or delegate the root session's notification broker.

The experiments isolate three requirements:

- 251 drops real/effective/saved UID/GID and verifies root cannot be regained.
  The unapproved private ART loader fails with `EPERM` under the kernel's W^X
  policy.
- 252 first self-binds the dedicated Android runtime and remounts it read-only,
  `nosuid,nodev,wxallowed`. ART starts as UID 10000, then fails because that UID
  has no Unix passwd account.
- 253 also prepares an owned data directory, home and real passwd/group account.
  It executes the production launcher as root with explicit
  `VINIX_ANDROID_UID`, `VINIX_ANDROID_GID`, `VINIX_ANDROID_HOME` and
  `ANDROID_APP_DATA_DIR`; the production launcher performs the credential drop.
  Exact original account database bytes are retained in serial provenance.
- 254 retains that production launcher and enables an administrator spectator
  for at most 15 seconds to capture ART's live mappings and status around the
  crash. Its account, paths and serial markers identify 254; its production
  source bytes come from the frozen 253 inputs, permitting concurrent fixes.
  In the retained run the spectator expired during APK library installation,
  before ART execution; it did not capture ART library mappings.
- 255 uses the production launcher with ART cache preparation and disables the
  root spectator. Its configured 900-second observation window leaves time for
  search and route interaction; the configured limit is not endurance evidence.

Build the preparation and checking tools without `-prod`. This V compiler
removes assertions in production builds. Use `-cflags -O2` for optimization:

```sh
v -nocache -cc cc -cflags -O2 -o /tmp/maps-credential-image tests/native-android-ws/maps-credential-image.v
v -nocache -cc cc -cflags -O2 -o /tmp/maps-credential-inputs tests/native-android-ws/maps-credential-inputs.v
v -nocache -cc cc -cflags -O2 -o /tmp/maps-credential-media tests/native-android-ws/maps-credential-media.v
```

The image generator uses the retained Maps250 staging and original private boot
image under `build/android-maps`, creates a fresh experiment directory, builds
the ARM64 static wrapper and records its compiler/source/binary receipt. It
preserves all original regular-file bytes, including hidden companion payloads,
and reads the actual FAT runtime archive back. The generator and generated
suite refuse `-prod`.

These tools use the historical experiment paths. Reproduction requires the
original complete inputs and matching frozen source in a separate workspace;
do not replace a retained canonical experiment to rerun preparation.

Before launching 255, run `maps-credential-inputs 255 /external/fresh-directory`.
It independently verifies the baseline, staging, actual archive, source and
compiler receipts, then freezes the exact launch inputs. Run
`maps-credential-media hash 255` and
`maps-credential-media publish /external/directory 255`
to retain the prelaunch image hashes without a second image copy. Preserve the
complete post-run media and raw outputs separately, as described in
[`docs/test-artifacts.md`](../../docs/test-artifacts.md).

After the suite and QEMU have exited, `maps-credential-collect EXPERIMENT
/external/directory FROZEN-INPUT-PIN` retains the completed run, including hidden
files, symlinks and empty directories, plus its staging and post-run media using
APFS clones. It preserves the prelaunch input manifest and rejects an existing
collection or incorrect input pin. It performs no archive extraction or full
post-run audit; retain and run the experiment's independent checker separately.

Run the account preflight regression on the host without launching a guest:

```sh
v -nocache -cc cc -cflags -O2 -o /tmp/credential-account-test tests/native-android-ws/credential-launcher.v
/tmp/credential-account-test --account-self-test
```

The test uses private temporary databases. It checks that a group collision or
changed group input leaves passwd untouched, original prefixes are retained,
and account preparation is idempotent. Both databases are validated before
either is written; publication rechecks both inputs before the first write.
This is not a transaction across filesystem write failures.

The original 252 generator and suite used `-prod`; their assertions did not
execute. The observed guest failure remains evidence, while artifact
comparisons require the independent retained auditor. The 253 launch inputs
were independently replayed with assertions enabled before launch. Its frozen
wrapper predates the maintained account preflight regression and two-database
preflight cleanup; retain that exact frozen source when auditing 253.
