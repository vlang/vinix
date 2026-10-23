# Optional notification broker cancellation

The same actual-source host harness fails against the pre-fix bridge because
canceling with an absent broker throws `IllegalStateException`. The fixed bridge
passes 11 scenario groups: synchronous and asynchronous absence, preserved
connection/status/transport errors, rejected replies and invalid framing,
successful cancellation and posting payloads, posting failure without a broker,
unsupported actions, and socket cleanup.

The harness substitutes deterministic socket, clock and Java exception helpers;
the production encoding, connection classification, transfer loop and public
notification functions run unchanged. This verifies native bridge behavior,
not a live session broker or Java integration. Existing reply parsing is outside
this change; framing cases here cover zero/oversized lengths and truncated data.
Maps233 evidence is retained separately in `../maps-input-latency/`.

The frozen sources and runner are archived in `sources.json.gz`; no binaries
are retained. Run the current production regression with:

```sh
/Users/alex/code/v/v_old -nocache -cc cc run tests/native-android-ws/notifications-host.v
```

Validate retained hashes or replay both frozen versions with:

```sh
/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/notification-cancel/validate.v
/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/notification-cancel/replay.v
```
