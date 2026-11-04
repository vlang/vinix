# TrafficStats UID fixture delivery

The additive runner selector `--traffic-stats-uid` and transfer selector
`serve --traffic-stats-uid-api` deliver the signed TrafficStats thread-local UID
fixture. Historical selectors, pins, protocol checks and shared-APK exceptions
remain unchanged. This profile has distinct runner/APK routes and no shared
artifact exception.

All five host qualification phases passed: host runner build and self-test,
static ARM runner build, transfer build and transfer self-test. The runner
self-test rejected 5,293 cases; ELF readback verifies a static AArch64 EXEC
without INTERP/DYNAMIC segments. Transfer tests passed all historical cases
and six new URL/path/hash collision controls. Actual ARM execution remains
pending; no guest or GMS/Maps result is claimed by this document.

Paths use `S=/Users/alex/.local/state/vinix/android`.

| Input | Path or SHA-256 |
| --- | --- |
| Signed APK | `S/traffic-stats-uid-fixture-2026-11-04-r1/probe.apk` |
| APK SHA-256 | `bf1045fb4fd9c5fb468c7c59f7f594654de15cd6b54f9e07bc3f2aa4bc199cc1` |
| Retained native SHA-256 | `13cf020729373ad8d20cfa4c5588c0878eee4be4fdf85700f2cf911ded08e81e` |
| Successor JAR SHA-256 | `dd3af0444459410f28d20f04928e37a19eb6b076d433498b05eac9a922b49f0e` |
| ARM runner | `S/traffic-stats-uid-api-run-2026-11-04-r1/run` |
| ARM runner SHA-256 | `370beb2dbfc5418dc53db6cc422968932f7e0a3a8e65ec66bd382f4d2fa9cac2` |
| Transfer | `S/traffic-stats-uid-api-transfer-build-2026-11-04-r1/transfer` |
| Transfer SHA-256 | `c6e8bf4aadbba69acd52e08b3664424dd7a71212838f5d58ec78f281cddec2f5` |

Runner source SHA-256:
`07593f81c838785a4e7d7323b9428aec9783ab7a61befb3308aea8b94a5b65b4`.
Transfer source SHA-256:
`7212965e497b9eb7ead97b50de4f2f8c6aa0b78b59357bb6f5d6e25f139073cf`.

The first transfer check used `selftest` instead of `--self-test` and returned
usage exit 2; that invocation remains preserved. The correct same-binary
`--self-test` passed in 4,197 ms with guard/child zero and complete cleanup.
The original 600 MiB RSS, 300-second, 512 MiB growth, 1 GiB reserve and
output/file limits remained unchanged.

The [SDK/native and host qualification](traffic-stats-uid-pair-2026-11-04.md)
aggregate covers 18 complete roots and 8,093 entries, including both earlier
64 MiB shared-growth seal stops with their original controls. Manifest at
`S/traffic-stats-uid-host-sealed-2026-11-04-r3/sealed/manifest.json` hashes to
`6d6735fe5defdf92fef8b34ff833e26811622e42e7957c4a6c2c1ff5605cb3c4`.
Seal and separate fresh readback passed guard/child zero with complete cleanup
in 6,679/2,337 ms under the unchanged 900-second/64 MiB-growth seal limits.
Retain all complete original roots and historical auditors. This establishes
host qualification and retained storage integrity; ARM execution is separate.

Before ARM execution, select unused account `traffic-stats-uid-probe`, UID/GID
10156, mount `/opt/traffic-stats-uid-runtime` and output
`/var/lib/traffic-stats-uid-r1`. Follow the original standalone recipe's unused
identity/input/output checks and require a dedicated read-only runtime mount
with `nosuid,nodev,wxallowed`, without `noexec`.

Start the qualified transfer only when the guest is ready to fetch:

```text
S=/Users/alex/.local/state/vinix/android
"$S/traffic-stats-uid-api-transfer-build-2026-11-04-r1/transfer" serve --traffic-stats-uid-api FRESH_HOST_OUTPUT 55547
```

Fetch `/traffic-stats-uid-api-run` to `/opt/input/traffic-stats-uid-run` and
`/traffic-stats-uid.apk` to `/opt/input/traffic-stats-uid.apk`. Verify the final
qualified runner hash and APK hash above, then executable/read permissions.
The intended invocation is:

```text
/opt/input/traffic-stats-uid-run --traffic-stats-uid /opt/traffic-stats-uid-runtime /opt/input/traffic-stats-uid.apk 10156 10156 /var/lib/traffic-stats-uid-r1
```

The exact success marker is:

```text
TRAFFIC-STATS-UID-PASS public-static-reflection signed-uid clear-default tag-independent thread-isolation no-inheritance bounded-worker
```

Require receipt profile `traffic-stats-uid`, the selected UID/GID, all six input
identities, all eleven unchanged checks, sole exact PASS and native READY,
drained EOF and clean child exit. Retain the original 180/20-second deadlines,
4 MiB child log and 8,192-byte line bounds. Keep input idle through complete
UART export END; preserve full snapshots and derive exactly one interval using
the unchanged zero-removal reconstruction and child extraction tools.

Release the dedicated mount only after validated fixture completion and before
a separate GMS/Maps replay. Preserve failures without weakening fixture health
or protocol checks. The fixture covers public static metadata, signed UID
values, clear/default state, tag independence and bounded thread isolation; it
does not establish socket attribution, kernel accounting or Google behavior.
