# Maps255: startup reaches thread-priority permission failure

Maps255 starts the unchanged signed Maps APK through the production launcher
with the provisioned `maps255` UID/GID 10000 account and prepared ART cache.
The serial confirms account resolution before launch and reaches Java startup,
then reports uncaught `SecurityException: No permission to set thread priority`
on the `Sensors` and `JavaCronetEngine` threads. The VM and suite exit early
with status 10.
The original result remains **`startup_failed`**: `launcher_entered`,
`native_maps_observed` and `process_exited` are true; `backend_ready` is false
and `functional_passed` is null. The configured 900-second limit does not
establish endurance. No backend, map, search, route or bridge initialization
was validated, and no independent post-drop process credential tuple was emitted.

The prelaunch source revision is
`e32f5a2f16d8ff299ce336051837201165e986da`.
The external retention directory is
`/Users/alex/.local/state/vinix/android/maps255-2026-10-24`.
Its prelaunch `frozen-inputs.json` SHA256 is
`38c58ae9c21f75f5dff09cb33203f99fbf108054153ef826587ac0f97cf03940`.

After the suite and QEMU stopped, the assertion-enabled
[`maps-credential-collect.v`](maps-credential-collect.v) retained ordinary raw
output, harness stdout, runtime, post-run private boot media and firmware
variables, frozen sources and compiler identities. The collector verified the
frozen manifest pin and compiler identities against their retained receipts;
its exact source is retained under `audit/`, with SHA256
`75cb6336b371dddb1dd1d58ec67da8258d62cb0b91db0e9f311aa86d75457662`.
`run/omitted-special-files.json` is empty. The adjacent
`maps255-2026-10-24-collect.log` records successful clone-only retention.

This bundle has not received a complete inventory audit, post-run media
extraction or final sealed manifest. Its retention is distinct from the full
audit documented for [Maps253](maps253.md). No completed-run source or media
was modified during collection.
