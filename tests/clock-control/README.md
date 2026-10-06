# Clock setting and discipline

`tests/clock-control/run-host.sh` tests production integer clock arithmetic,
including read-cadence independence, negative slews, frequency limits, and
securelevel wall-step checks. It also runs the capability policy tests.

`python3 tests/clock-control/run.py` builds the independent V fixture as a
static AArch64 guest and uses the
existing isolated real-time VM driver. Set `VINIX_AARCH64_SYSROOT` for its musl
sysroot; `VINIX_VM_RUNNER_ROOT` can select the original checkout's cached boot
tools while `VINIX_KERNEL_DIR` selects a separately built worktree kernel.
`VINIX_QEMU_RT_NO_BUILD=1` uses that existing kernel binary.

The guest checks Linux `clock_settime`, `settimeofday`, `adjtimex`, and
`clock_adjtime` layouts, privilege and pointer failures, uptime independence,
backward-step prohibition at securelevel 2, absolute realtime sleep/timerfd/
POSIX timer behavior across clock steps, and `TFD_TIMER_CANCEL_ON_SET`.

The supported discipline is a signed frequency correction up to 500 ppm and
`ADJ_OFFSET_SINGLESHOT` phase slewing at up to 500 ppm. Both affect monotonic
and realtime clock rates; `CLOCK_MONOTONIC_RAW` excludes them. Relative kernel
timers expire on disciplined monotonic deadlines. Wall-clock steps preserve
monotonic time, while absolute realtime deadlines retain their wall-clock
meaning. Slews and oscillator corrections accumulate fractional nanoseconds
together, so reading a clock frequently does not change its rate.

This is partial coverage of finding SC6. NTP PLL/FLL/PPS, leap-second state,
TAI, hardware RTC persistence, and RTC timezone warping remain unimplemented.
Unsupported adjustment modes return `EOPNOTSUPP`; the supported modes report
`STA_UNSYNC` and `TIME_ERROR` rather than claiming NTP synchronization. Queries
are unprivileged; changes require effective root and `CAP_SYS_TIME`.
