# Battery percentage in the desktop

Settings has Display and Battery categories. Battery shows remaining charge,
its numeric percentage, a read-only level bar, status and a Refresh button.
Display brightness controls are unchanged. Battery does not expose charging
controls or infer charging state from a percentage.

The bottom-right taskbar shows percentage immediately before the clock, for
example `73%  |  18:54:22`, with the existing date beneath it. The reserved clock
area is widened so open-window task buttons stop before the battery/time area.
When a sample is unavailable, Settings says `Unavailable` and the taskbar says
`--%`; a genuine zero still displays `0%`.

Both views use the same five-second, monotonic-clock cache. Refresh or selecting
Battery requests a new sample immediately. The reader opens `/dev/battery`
read-only/nonblocking/close-on-exec, reads one bounded snapshot to EOF, and closes
it. Each poll reopens the device, as required by the kernel per-open snapshot
ABI. A failed poll replaces the previous percentage rather than retaining it
indefinitely. A monotonic-clock failure also invalidates the cache. No read is
performed on every repaint within the cache interval.

Absent devices, access denial, malformed text and I/O/stale-sample errors have
separate Settings messages. The parser accepts only one to three decimal digits
in 0..100 followed by LF, rejects trailing data, and bounds EINTR retries.
Static percentage labels avoid per-frame allocation of Settings text.

## Enable on an M1

Build and deploy the kernel and desktop using your existing working procedure.
Keep a known-good boot entry and add `vinix.apple_battery=1` to the test kernel
command line. The experimental driver remains off by default and independent of
GPU/DCP. Confirm `cat /dev/battery` succeeds, then open Settings > Battery.
Without the driver, the desktop still starts and displays unavailable status.
See `../docs/m1-battery.md` for the kernel ABI and limitations.

## Tests and validation boundary

`battery_client.v` implements the bounded reader and shared cache in V;
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

Settings tests also cover Battery/Display switching, no hidden brightness
writes, 0/100/unavailable states, narrow layouts and taskbar text. These tests
and the complete native desktop build pass. Hardware rendering, the linked
Vinix image and M1 battery behavior have not been tested by this port.
