# Maps263: styled chips and advancing route preview

Manual screenshot review confirms the unchanged signed Maps APK passes Skip,
renders the map, returns live Paris and Eiffel Tower suggestions, opens Paris
details and calculates driving directions: **18 minutes, 6.1 km**. Preview
shows **“Head toward Pont d’Iéna”**; Next advances to **750 m, “Turn left onto
Pont de l’Alma”**, with changed geometry and lane arrows. Synthetic checkbox
squares on styled chips are removed. Spacing remains incorrect in these
frames; this is **not a full visual pass**. Search suggestion-circle behavior,
GPS, sign-in, voice navigation and 900-second endurance were not verified.

The configured **240-second** observation completed with QEMU alive before
final capture, backend/native Maps markers present and no recorded application
exit. The unchanged classifier reports **`startup_failed`** and
**`functional_passed: null`** because it counts four `ClassNotFoundException`
lines for `io.grpc.internal.JndiResourceResolverFactory` and
`io.grpc.override.ContextStorageOverride`. The manual working flow does not
alter that result. Retained serial has no previous thread-priority permission
failure, JNI fatal marker or recorded fatal signal 11.

Preparation records source revision `40084df93838e67861144835f3d55511a16f57bf`.
Its retained [`maps-styled-replay.v`](maps-styled-replay.v) preserves the frozen
Maps256 APKs and production identity launcher. All **109** regular runtime
files match the frozen baseline except the paired262 framework JAR and native
library. Their complete 125-file framework and 83-file native source closures,
build inputs, before/completed receipts and tools are retained. The actual FAT
payload was read back before and after replacement. Private media start from
the stopped Maps257 guest. Maps261’s prelaunch bundle remains sealed; that
attempt was not launched.

The complete bundle is
`/Users/alex/.local/state/vinix/android/maps263-prelaunch-2026-10-24`.
Its immutable 3,657-entry prelaunch inventory SHA256 is
`b8d2df5b5cb5da91836be48f4fd167113d4c9f0ddead57f92e924921e543e5ce`.
Postrun retention includes every ordinary output, all screenshots, serial and
its matching gzip, packet capture, actual attempt263 logs, stopped private
media, exact checker source and binary, build/validation recorder sources, receipts
and the operator’s UTC review timeline. Only the obsolete QMP socket is omitted.
The initial checker’s relative-path expectation failure and original tool are
preserved under `audit/failed-relative-argv`; the corrected checker matches the
suite’s absolute QEMU state paths.
The final **3,813-entry** inventory SHA256 is
`0543f52b782346c4c3010c3f9b60cda8c04df5493374f6551a36f422635c99c5`.

The assertion-enabled [`maps-styled-evidence.v`](maps-styled-evidence.v)
passed its independent full recheck, including the original byte-identical
classifier, complete archive shape and unchanged postrun boot image. All
interaction command streams have unique identities and successful matching
end records. Required `application`, `paris-result`, `route-ready`,
`route-first` and `route-next` captures each occur once. Polling probe images
may be overwritten and are attributed only to their final successful capture.
Parser self-tests reject ten malformed cases; actual wrong-pin and incomplete
bundle checks fail, the assertion probe exits 1 and a production build refuses
execution with exit 2. These are evidence consistency checks; they do not
declare an automated functional or visual pass.
Independent check and negative-test receipts are retained in
`/Users/alex/.local/state/vinix/android/maps263-validation-2026-10-24`, with
16-entry inventory SHA256
`afe4b709b2b88928b33bb06184e4f16b5f94040851a27a92203f8c72b7616e35`.

Recheck with the retained assertion-enabled tool:

```sh
/Users/alex/.local/state/vinix/android/maps263-prelaunch-2026-10-24/audit/maps-styled-evidence check \
  /Users/alex/.local/state/vinix/android/maps263-prelaunch-2026-10-24 \
  0543f52b782346c4c3010c3f9b60cda8c04df5493374f6551a36f422635c99c5
```
