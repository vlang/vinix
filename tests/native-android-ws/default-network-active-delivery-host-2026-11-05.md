# Default network activity fixture delivery draft

The draft additive selectors are `--default-network-active` for the isolated
runner and `serve --default-network-active-api` for transfer. Distinct routes
are `/default-network-active-api-run` and `/default-network-active.apk`.
All historical profiles, eleven receipt checks, 180/20-second child deadlines,
4 MiB child log cap, 8,192-byte line cap and existing protocol/health refusals
remain preserved. Draft controls cover cross-profile marker rejection, exact
selector/arity, canonical ports and route/path/hash collisions.

The signed fixture is
`S/default-network-active-fixture-2026-11-05-r2/probe.apk`, SHA-256
`be0b524b85218bd0f570fe72a0154c97c06bc15c32271e140c3c39eb76090dd2`,
where `S=/Users/alex/.local/state/vinix/android`. Its exact expected marker is:

```text
DEFAULT-NETWORK-ACTIVE-PASS public-instance primitive-boolean no-monitor-active native-link-independent virtual-dispatch repeatable bounded-worker
```

This covers the public instance primitive boolean query, active result when no
default-network activity monitor exists, independence from native linkage,
virtual dispatch, repeated UI calls and a bounded plain worker. It establishes
no real network monitoring, traffic, GMS stability, Maps or authentication result.

Final successor SDK/JAR and freshly coupled native/DSO pins remain pending.
The runner's two pending hashes and transfer's pending static ARM runner hash
are deliberately empty; self-tests/serving refuse unqualified identities.
No delivery compilation, self-test, transfer qualification or successor ARM
execution has been performed. Do not commit the delivery source until the
final artifact pins replace these draft values and all five host delivery
phases pass under the original limits, followed by complete evidence sealing
and an independent fresh readback.
