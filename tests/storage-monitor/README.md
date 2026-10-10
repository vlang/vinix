# Periodic storage monitor qualification

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-monitor/run.v \
  --work /tmp/storage-monitor-host
```

The native V controller copies the production volume utility and replaces only
the monitor's open/close/ioctl/sleep/output boundary. ASan/UBSan tests exercise the
real argument parser, sampling loop, health validation, deltas and exit policy.
Two hundred samples use one read-only descriptor, flush every line, submit only
status/health requests and sleep only between samples. Tests cover warning then
recovery, unavailable health, historical and new errors, failed/offline queries,
identity changes before/during health, bad reports, failed open/status/print/flush,
interrupted sleep, numeric bounds and closing on every return. Output markers
check unknown warning bits, resets, unavailable/offline/query-failed states and
new-error reporting. Existing ATA/NVMe report tests run alongside them.

Hardware telemetry tests cover full-width comparison and subtraction, borrows
across every byte, values above 64 bits, all ten counter resets, historical versus
new media errors with no warning bit, query gaps and protocol changes. Bounded
format tests retain all counter bits, check thermal/spare/wear fields (including
wear above 100 and unavailable temperature), and reject truncation without
writing beyond the buffer. Output suffix failures close the descriptor without
flushing or sleeping. The ordinary 200-sample test includes telemetry output.

Both architectures' freestanding production CLI artifacts are checked for
implicit heap allocation and V runtime dependencies. The borrowed health report
uses one caller-stack slot outside the loop; it is cleared before each query.
The successful-query counter baseline also uses one fixed slot outside the loop.
Serial-capture tests cover every marker split position, sticky success/failure
results and 40 MB of simulated input with fixed boundary storage.

The ordinary [storage-plan guest suite](../storage-volumes/README.md) builds the
updated utility and runs it on disposable QEMU disks. Two physical samples
exercise actual AHCI health on AMD64 and unavailable VirtIO health on ARM.
Logical volumes retain their status/counters while reporting unavailable health;
regular files fail the status query. Both architectures also retain the existing
200-cycle allocation and reordered-device/reboot checks. The controller requires
the monitor result marker before accepting the first boot.
With `--nvme`, healthy and warning QEMU controllers run bounded monitor sessions
on both boots, and a separate NVMe monitor marker is required. This uses the
existing development-only activation policy and does not qualify physical drives.
