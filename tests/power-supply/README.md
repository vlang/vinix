# Power supply tests

`./run` tests the arithmetic in `kernel/psupply/estimate.v` on the host: the
smoothed time-left estimate, the percentage, `capacity_level`, and the
decision that a battery is low or critical. The file is copied unchanged next
to `estimate_test.v` in a scratch module; nothing of the kernel is built.

```sh
tests/power-supply/run
```

What it shows: a reported rate gives the time at once; a burst of load moves
the estimate only in proportion to how long it lasted; plugging in forgets the
discharge; a battery that reports no rate has one derived from how its charge
moves, and not from less than thirty seconds of it; estimates are bounded;
only a discharging battery raises an alarm.

What it does not show: that any battery's firmware reports what the estimate
is fed. The ACPI drivers are exercised against a scripted battery in
`tests/hardware-platform` (`acpi-power`); no physical battery has been read.
