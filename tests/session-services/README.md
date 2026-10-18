# Standalone desktop services

Run the host checks with:

```sh
V=/path/to/v v run desktop/tools/test-services.v
```

They build the actual `vinix-session`, `vinix-timesync` and
`vinix-service-runner` executables, then check authenticated IPC, legacy clock
configuration migration, durable alarms, clipboard revocation, service
dependency restarts and process-group cleanup after a broker crash. The idle
request and queue tests also check retained allocations with `-d track_heap`.
Compositor controls require a private inherited connection. Tests reject public
attachment with identical PID/UID credentials and check exec isolation, loss of
the connection, fresh-connection recovery and the real compositor startup wrapper.

`guest.v` is the PID 1 fixture for ARM64 and x86-64 QEMU boots. Its initramfs
needs the three matching static helpers in `/usr/bin`, built by
`desktop/tools/build-services.v`. No external network is needed. It verifies
each process's real `/proc` command line, the clock worker's ancestry,
graceful shutdown and cleanup after a killed broker. Including the newly built
`/usr/bin/vinix-desktop` also checks that the old `--session-services` command
execs `vinix-session` without opening a display. On x86-64, verdicts go to
`/dev/com1`. A successful boot prints `SESSION SERVICES PASS`.

The macOS desktop capture at `docs/screenshots/vinix-desktop-recreated.png`
uses the split executables and shows the real process list.
