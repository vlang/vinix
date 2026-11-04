# TrafficStats ARM replay blocked by disk reserve

Core `417211d3a` implements the TrafficStats UID APIs. The complete
[SDK/native/fixture qualification](traffic-stats-uid-pair-2026-11-04.md)
is committed in `09120d4ca`; [image tools](maps-traffic-stats-stage.md)
in `0b435b712`; successful [preparation and exact clone](maps-traffic-stats-preparation-2026-11-04.md)
in `b4ebd742c`. The signed TrafficStats fixture has **not executed on ARM**.
There is no successor GMS, Maps rendering, imagery or authentication result.

Paths use `S=/Users/alex/.local/state/vinix/android`. The qualified coexistence
runner freshly admitted and started the exact clone at
`S/maps-traffic-stats-vm-2026-11-04-r1` (`VM`), owned PID 44857, with the fixed
12 GiB/four-CPU allocation. CI PID 23708 remained untouched. Complete live
controls are in `S/maps-traffic-stats-live-controls-2026-11-04-r1` (`C`).
The prepared source `S/maps-traffic-stats-r1` remains closed and unbooted.

The desktop booted. Its automatic Maps launch encountered the expected
single-linked SQLite input check; the separate broker's audited replacement
procedure has not run in this guest. A root terminal verified UID/GID 10156
and fixture paths were unused, then provisioned `traffic-stats-uid-probe` and
the dedicated `/opt/traffic-stats-uid-runtime` bind mount. Guest mount readback
confirmed `ro,nosuid,nodev,wxallowed,relatime` without `noexec`.

Before either download, the original transfer guard refused preflight with
reason `disk reserve`: initial free space 421,101,568 bytes, below the required
1 GiB reserve plus 512 MiB growth allowance. Its receipt records PID 0,
guard exit125, child exit-1, zero RSS samples and no supervised groups.
`cleanup_complete=false` accompanies this preflight refusal; no server child
was launched. Receipt SHA-256:
`6e3e3d2a8226731f49012cae54e2d89427d672cd25f427aec8c0fd5de06ca67f`.
No APK/runner transfer, fixture invocation or manual GMS/Maps launch followed.
The absent transfer output path is
`S/traffic-stats-uid-api-transfer-live-2026-11-04-r1`.

The qualified lifecycle runner stopped only owned PID 44857 at
2026-11-04 18:18:22 UTC. Stop and gone receipts confirm SIGTERM and a fresh
process snapshot with exit1 and empty stdout/stderr for that PID. No further
signal or stale-socket cleanup was needed. Receipt SHA-256 values:

| Evidence | SHA-256 |
| --- | --- |
| `VM/stop.json` | `0bb00cde2ccd7a150035fe28a0ed611d1bdab652ae78207e659597604ed29f28` |
| `VM/gone.json` | `915776068844396a3881304cc4b9a4999dc90c57e2adee60a891c42828a3f6a4` |
| `VM/serial.log` (95,598 bytes) | `bf6aea2a7fde6fd7ed505d683af7ac6ce697b2c6a2c8263996be88b90d497048` |

Complete UART, screenshots, input/launch records, mutable VM media, controls
and the original clone tool/source/receipt sidecars remain outside Git.
Neither the 1 GiB reserve nor the 64 MiB aggregate-seal growth cap was relaxed.
Four interrupted prepared-evidence seals remain intact; aggregate sealing and
fresh readback are still pending. The original prepared inventory and exact
clone checks passed independently of that pending aggregate.

Resume after sufficient free space is available: retain all complete original
bundles, finish aggregate sealing/readback under the original cap, and clone
the closed prepared image to a fresh VM/control path. Do not reboot or mutate
this stopped runtime VM. Use the qualified 64 GiB coexistence admission policy
against the then-current foreign identity and leave CI running. Run the
[signed TrafficStats fixture](traffic-stats-uid-fixture-run.md), validate the
complete receipt and UART export, release its mount, then retry GMS stability
and Maps. No SDK/native rebuild is required to reach that ARM check.
