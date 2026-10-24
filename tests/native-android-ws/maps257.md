# Maps257: map, search and advancing route preview

Manually reviewed screenshots show the unchanged signed Maps APK progressing
past onboarding to a rendered map, live Paris suggestions, Paris place details
and photos, and live Eiffel Tower suggestions. Driving directions show
**21 minutes, 6.1 km**. Route preview displays **“Head toward Pont d’Iéna”**;
after the next-step click, the retained screenshot shows **750 m, “Turn left
onto Pont de l’Alma”**, changed map geometry and lane arrows. GPS, sign-in and
voice navigation were not verified.

The suite completed its configured **240-second** observation and published
`results.json`, a final screenshot and compressed serial log. At final capture,
QEMU was alive, the backend and native Maps markers were present, and no
application exit was recorded. The unchanged classifier reports
**`startup_failed`**, with **`functional_passed: null`**, because it counts four
logged `ClassNotFoundException` lines for `io.grpc.internal.JndiResourceResolverFactory`
and `io.grpc.override.ContextStorageOverride`. The manual working flow does not
change that recorded classification. Serial contains neither the previous
thread-priority permission failure nor a recorded JNI fatal error.

This run reuses the frozen Maps256 APKs, runtime and production launcher. The
Maps256 prelaunch source revision is
`52d20c9ca4743379f27841b6436acc1e615a4ae7`; the replay generator is committed in
`acb621696`. The generator retains the original observation classifier exactly,
uses a bounded final capture and saves its observation before capture. No APK,
framework, native library or production launcher was rebuilt for Maps257.

The complete bundle is
`/Users/alex/.local/state/vinix/android/maps257-2026-10-24`. The immutable
prelaunch inventory SHA256 is
`8870428fa649fe8c1a9f335328ba0c9c3471210f601034bda02375c2019688a8`.
It retains all 73 frozen inputs, the complete runtime, exact generated suite,
configuration, build receipt, pinned source and tool binaries, and independent
private boot and firmware clones. Both prelaunch media files match the retained
Maps256 postrun media byte-for-byte. Maps256 independently sealed those media
under inventory pin
`2d664ac6bf11a10fcb84fd96493c6084ba17ff9b6d56b2523b32f24b004bc196`.

Postrun retention includes every ordinary raw output, all screenshots,
uncompressed and compressed serial, packet capture, harness and both driver
logs, and independent postrun media. The obsolete QMP socket is the sole
permitted omitted special file. The checker inventories hidden files, symlink
targets and empty directories, verifies the preliminary and final observations,
preserves the original outcome, and requires the complete postrun boot image to
match the sealed prelaunch image, retaining its unchanged FAT payload.

The separate map polling driver was manually stopped around **18:01:44 UTC**
once the UI was ready for search while its tile probe was still waiting. This
was not a suite failure. A historical driver naming collision reused
`command-37333.stdout.log` and `.stderr.log` for `search-ready` and `paris-query`;
the first pair of stream contents was overwritten. Original logs and both
screenshots remain retained; this bundle does not establish complete stream
contents for those two commands. The checker explicitly recognizes this one
collision and rejects other duplicate stream paths.

The complete 397-entry inventory `sha256.json` has SHA256
`e9a2592fa95bd7f56619a46080f0177b124b5db6ea2cb0e898ab9b6d8e3a9ae9`.
The assertion-enabled [`maps-replay-retain.v`](maps-replay-retain.v) rejects an
authentic partial bundle, a wrong inventory pin and execution of a `-prod` build.
Validation receipts are retained beside the bundle in
`maps257-2026-10-24-negative/`. The independent full recheck passed:
`MAPS257-EVIDENCE PASS complete configured observation; original startup_failed classification preserved; manual UI review documented`.
This is an evidence consistency check, not an automated functional pass.

Recheck from the repository with the retained, assertion-enabled tool:

```sh
build/android-maps/maps-replay-retain check \
  /Users/alex/.local/state/vinix/android/maps257-2026-10-24 \
  e9a2592fa95bd7f56619a46080f0177b124b5db6ea2cb0e898ab9b6d8e3a9ae9
```
