# Apple SMC client tests

Host tests of `kernel/apple/smc/core`: the mailbox protocol of Apple's System
Management Controller, which keys an SMC has, and what the kernel makes of
their values ([M1 battery](../../docs/m1-battery.md)).

```sh
sh tests/apple_smc/run-host.sh
```

`core/` is the kernel's module `core` without the kernel. Four of its files
are links into `kernel/apple/smc/core`:

- `core.v`, the protocol: RTKit start-up, and the commands that read,
  describe and write a key;
- `keys.v`, the keys and how the bytes of each type are read;
- `supply.v`, what is asked of an SMC (`discover`), read on each pass
  (`sample`) and made of it (`judge`), and the charge limit;
- `sim.v`, which is `sim_d_applesmc_selftest.v`: the simulated SMC a kernel
  built with `-d applesmc_selftest` has in place of its mailbox.

`bench.v` puts the one on the other: the protocol's mailbox and shared-memory
callbacks call the simulated SMC, and the clock moves a millisecond each time
it is read, so a timeout takes no real time and a test can say how long one
took. `include/` holds a link to the one C header the core includes.

## What is tested

`keys_test.v` (8 tests): a float cut off towards zero at the scale asked
for, with values read from a real SMC; one too big for the integer; what is
not a number; 48.16 fixed point; byte order; key names; which temperatures
are possible.

`protocol_test.v` (16 tests):

- what the device nodes use sends the address request and reads, and
  nothing that describes or stores a key;
- a key is described; one that is not there is that key's matter;
- values of one, two, four, eight, 21 and 32 bytes come back in the SMC's
  order, the longer ones through the shared memory;
- a key that is absent, asked for with the wrong size or not readable fails
  that read and no more; an answer of another size is refused and the
  channel kept, except for the capacity key, which keeps the older rule;
- a value is written through the shared memory; a key that may not be
  written, is not there or is of another size refuses it;
- without the shared memory, what needs it is refused unsent;
- lengths and buffers are checked before anything is sent;
- a read, and a write, that is never answered ends the channel in half a
  second by the clock, and nothing is sent afterwards; a stopped clock does
  not hold a read for ever;
- what the firmware says unasked is not taken for an answer; the four-bit
  request number wraps; a mailbox that fails ends the channel.

`supply_test.v` (27 tests):

- what is found on a laptop with everything, on one without a fan or a
  charge limit, with the sensors and the limit asked to be left alone, with
  keys of another size, on a desktop's SMC, with more fans than there is room
  for, and when the channel goes or there is no shared memory;
- the first pass reads everything and later ones what is due, to the
  exchange; a key that keeps failing is asked less often and comes back; a
  pass ends when the channel is gone;
- temperatures in both types and the fan; readings that cannot be a
  temperature or a speed are not one;
- charging, the charger pulled, low, critical and full;
- the state for fifteen combinations of flags as Linux reads them, and
  unknown when a key it rests on was not read;
- one wild percentage is not believed, a real fall is followed at once, and
  after a sleep the first reading stands;
- "about to give out" has to be said twice, in both sizes of the key;
- figures that cannot be what they claim are left out; a remaining charge
  whose byte order is not known is worked out from the percentage;
- the charge limit: set, read back and shown; only 80 and 100 are sent; no
  key, no limit; one that did not take, was refused or was never answered
  is reported.

## The older fixture

`run.sh`, `run.v`, `fixture/` and `compile-fixture` are the original test of
the capacity and telemetry path: a mailbox model compiled to C and compared
with a frozen C original. Its driver is V. It asserts that every command
on the wire is GET_SRAM_ADDR or READ_KEY, which still holds for the three
calls it exercises (`vinix_smc_refresh`, `vinix_smc_refresh_power`,
`vinix_smc_poll`); the first test of `protocol_test.v` says the same against
the simulated SMC.

The native command retains all 27 original golden checks, strict allocator
guards, the standalone full-core producer and serial/native guest recipe.
`--host-arch` also selects a real host SDK ABI; `--build-only` stops before
guest launch. The current compiler emits undeclared `memdup` calls in the
independent mailbox fixture, so its strict comparison still fails before a
verdict. No passing current mailbox fixture or guest is claimed. See
[qualification](../apple-protocols/mailbox-hotplug.md).

## What this does not show

The simulated SMC is this repository's reading of Linux's
`drivers/mfd/macsmc.c` and of the RTKit start-up the client was written
against. That a real SMC behaves as it does is not shown by anything in this
directory. The kernel side, with the same simulation behind the driver's
thread, the power supply and thermal classes and `/sys`, is the
`apple-smc-selftest` scenarios of
[the hardware tests](../hardware-platform/README.md).
