# Embedded controller protocol tests

Host tests of `kernel/x86/acpiec/protocol.v`: the exchanges an ACPI embedded
controller is spoken to with, their timeouts and restarts, when a controller
is given up on, and how its events are taken out of it.

```sh
sh tests/acpi-ec/run.sh
```

`acpiec/` is the kernel's module `acpiec` without the kernel. Two of its
files are links into `kernel/x86/acpiec`:

- `protocol.v`, the protocol, which imports nothing;
- `sim.v`, which is `sim_d_acpiec_selftest.v`: the simulated controller a
  kernel built with `-d acpiec_selftest` has in place of the two ports.

`bench.v` puts the one on the other: the protocol's six port functions call
the simulated controller, a clock that moves only when the protocol reads a
register or waits, and a lock that only remembers whether it is held. A test
can therefore ask how long an exchange took, to the microsecond and in no
real time at all, and whether anything touched a register without the lock.

## What is tested

`transaction_test.v` (22 tests):

- a byte written is the byte read; accesses of two, four and eight bytes are
  bytes, lowest first; nothing past the 256th byte is reached;
- a slow controller is waited for, and looked at a thousand times a second
  once it has not answered within two milliseconds;
- an answer that takes longer than one attempt is waited for and not asked
  for twice, and a slow query keeps the event it named;
- a byte left in the output buffer is not taken for the answer;
- an input buffer that never empties, a controller that takes the command
  and nothing after it, one that never answers, and a write that is never
  taken all end in a timeout, after five attempts of 500 ms and no more;
- a controller that never answered is given up on after one failed exchange,
  one that used to after three in a row, and a success in between starts the
  count again; afterwards every caller is turned away with the clock and the
  registers untouched;
- ports nothing answers at (every read 0xff) fail in about a millisecond,
  with nothing written;
- a given-up controller can be tried again, and while it is being tried
  nobody else waits behind the try;
- a lock that cannot be taken is reported and nothing is touched;
- no exchange outlasts its budget, whichever byte the controller stops at
  and however slow it is.

`events_test.v` (13 tests):

- a controller with nothing to report is not queried; events come out in
  order until the event bit goes down;
- the method for an event runs with nothing held and may itself use the
  controller;
- a query that names nothing ends the drain; an event bit stuck up is asked
  about once, and not again by the exchanges that see it, until it has been
  seen down;
- a controller that never runs out of events is left at the limit of 32;
- clearing asks whatever the event bit says, up to 100 events;
- a controller that dies in the middle ends the drain, and a given-up one is
  not drained;
- a general purpose event raised more than 64 times a second for nothing is
  taken for stuck, and a busy one is not.

`choose_test.v` (5 tests): which of the ECDT's and the namespace device's
descriptions is believed.

## What this does not show

The simulated controller is this repository's reading of the ACPI
specification and of Linux's driver. That a real controller behaves as it
does -- that one exists which is slow in the ways tried here and in no other
-- is not shown by anything in this directory. The kernel side, with the same
simulation behind uACPI and a table describing a controller, is the
`acpi-ec-selftest` scenario of [the hardware tests](../hardware-platform/README.md).
