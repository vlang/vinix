# Battery percentage in the desktop

Settings has Display and Battery categories. Battery shows current charge, its
numeric percentage, a read-only level bar, a 24-hour level graph, estimated
remaining time, status and a Refresh button. Display brightness controls are
unchanged. Battery does not expose charging controls.

The taskbar's notification area has a battery icon. Its glyph shows the level
in tenths, with a charging mark while the battery charges; its tooltip gives
the percentage and the state, and its flyout the percentage and one line of
estimate. When a sample is unavailable, Settings says `Unavailable` and the
flyout says `--%`; a genuine zero still displays `0%`.

## Where the reading comes from

The reader prefers a battery the kernel lists as a power supply: the first
entry of `/sys/class/power_supply/` whose `type` is `Battery` and whose
`present` is `1`. From it the desktop takes `capacity`, `status` and the
kernel's own `time_to_empty_now` and `time_to_full_now`, and on the way notes
whether any `Mains` supply has `online` at `1`. This is what a PC with an ACPI
battery has.

With no such battery it reads `/dev/battery` exactly as before. That is still
all an Apple M1 has: its SMC battery is not a power supply to the kernel, so
there the desktop knows a percentage and nothing else. A battery that is
listed but answers badly is still the source: its failure is the sample, and
`/dev/battery` is not asked instead.

What a power supply adds is shown as the kernel states it:

| `status` | Settings, under the level bar | Estimate | Taskbar tooltip |
| --- | --- | --- | --- |
| `Charging` | Charging | hours to full, under **Time until full**; `Charging` when the kernel has no estimate | `Battery: 73%, charging` |
| `Discharging` | On battery | hours remaining; `Calculating…` when the kernel has no estimate | `Battery: 73% remaining` |
| `Full` | Fully charged | `Fully charged` | `Battery: 100%, fully charged` |
| `Not charging` | Not charging | `Not charging` | `Battery: 80%, plugged in` |
| `Unknown` | Power adapter connected or On battery when a `Mains` supply says which; otherwise only that the driver reported a percentage | `Unavailable` | `…, plugged in` with a charger online, otherwise `… remaining` |

The kernel's seconds are shown in whole hours, rounded to the nearest, as the
inferred estimate always was; under half an hour is `Less than 1 hour`, and
more than 48 hours stays `Calculating…`. The flyout's line counts to full in
words of its own (`About 2 hours until full`). The charging glyph is used only
while `status` is `Charging`.

For `/dev/battery` nothing changes. The remaining-time estimate uses only the
current falling trend and appears after at least a 2% drop over 10 minutes. A
rise is shown as charging and resets the discharge estimate; because
`/dev/battery` reports percentage only, that state is inferred from the trend.
Implausibly slow estimates above 48 hours remain in `Calculating…` state.

## Reading, caching and parsing

Both views use the same five-second, monotonic-clock cache, which holds the
whole reading. Refresh or selecting Battery requests a new sample immediately.
A failed poll replaces the previous reading whole, so no status or estimate is
left beside a percentage that is gone. A monotonic-clock failure also
invalidates the cache. No read is performed on every repaint within the cache
interval.

`/dev/battery` is opened read-only/nonblocking/close-on-exec, read as one
bounded snapshot to EOF, and closed. Each poll reopens the device, as required
by the kernel per-open snapshot ABI. Its parser accepts only one to three
decimal digits in 0..100 followed by LF, rejects trailing data, and bounds
EINTR retries.

Each file of a power supply is opened read-only, read **once** into a buffer
larger than anything valid, and closed: `/sys` makes a file's text afresh for
every read, so a second read would continue some other snapshot. A read that
fills the buffer is rejected. Parsing accepts only what the kernel writes:
`Battery` and `Mains` for `type`, `0` and `1` for `present` and `online`, the
five status words in their exact spelling, and decimal counts no larger than
64 bits, each with its LF. A supply of another type, or one whose `type` or
`present` is anything else, is passed over. For the chosen battery a missing
`capacity` or `status`, or malformed text in any file read, fails the sample;
missing estimates read as the kernel having none.

The kernel writes a `capacity` of `0` for a battery whose full amount it does
not know. A battery reports energy or charge, not both, so the reader checks
`energy_full`, or `charge_full` when that is absent, and a full amount of zero
makes the sample invalid rather than an empty battery. A driver with neither
file has only its `capacity` to go by.

The listing keeps at most eight names of up to 31 bytes in fixed storage, paths
are built in a fixed buffer, and nothing in a poll allocates. A poll is about
ten small reads every five seconds.

The session history retains the most recent 64 percentage changes in a fixed
allocation-free ring. The graph places those samples on a real 24-hour time
axis and does not invent data before the desktop began sampling. History is not
persisted across reboots.

Absent devices, access denial, malformed text and I/O/stale-sample errors have
separate Settings messages. Static percentage and remaining-hour labels avoid
per-frame allocation of Settings text.

## Limits

- Only the first present battery is shown. A second battery is not added to
  it.
- The kernel keeps a supply's last reading when its driver stops answering,
  and `/sys` has no file that says so. The desktop cannot tell such a reading
  from a fresh one.
- `capacity_level`, `power_now`, `cycle_count`, `technology` and `model_name`
  are not read or shown.
- On an Apple M1 there is no status, charger or estimate from the kernel, as
  above.
- None of the power-supply path has run against a kernel: it is tested on the
  host against the text the kernel writes.

## Enable on an M1

Build and deploy the kernel and desktop using your existing working procedure.
Keep a known-good boot entry. The read-only battery driver is enabled by default
and remains independent of GPU/DCP; `vinix.apple_battery=0` disables it. Confirm
`cat /dev/battery` succeeds, then open Settings > Battery. Without the driver,
the desktop still starts and displays unavailable status. See
`../docs/m1-battery.md` for the kernel ABI and limitations.

## Tests and validation boundary

`battery_client.v` implements both bounded readers and the shared cache in V;
`platform.c.v` supplies the POSIX bindings. No custom C header is involved.

```sh
V=/path/to/v sh desktop/tools/test-battery.sh
V=/path/to/v sh desktop/tools/test-settings.sh
```

Native V client tests cover every percentage and short-read chunk size, strict
malformed/oversized input, read-only opens, reopen behavior, permissions, I/O,
bounded EINTR handling, descriptor cleanup, cache throttling, forced refresh,
clock rollback/failure and recovery. The tests use a native V `DeviceIO` mock.
They validate golden text ABI samples; unlike the removed C test, they do not
link the unrelated C SMC implementation. Its own driver tests remain separate.

For the power supply they use a mock of several files by path and cover every
status word, missing files, malformed and oversized content in each file, a
`Mains` supply on, off, absent and malformed, energy- and charge-based
batteries, a full amount of zero, the first present battery among several, the
bounds on the listing and on a path, one read per file, interrupted opens and
reads, descriptor accounting, each way of falling back to `/dev/battery`, the
cache keeping and dropping whole readings, and the estimate and state made
from a reading.

Settings tests also cover Battery/Display switching, no hidden brightness
writes, 0/100/unavailable states, narrow layouts, graph geometry, remaining-time
presentation and taskbar text, the pane and the taskbar icon for each status
with and without the kernel's estimate, and the fit of every new line in every
language. Client tests cover bounded history, charge trend, estimate gating and
clock rollback. Hardware rendering, the linked Vinix image, an ACPI battery in
QEMU and M1 battery behavior require validation on the target machine.
