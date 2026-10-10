// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// An energy counter the hardware keeps in a register too small for it.
//
// A RAPL counter is 32 bits of some fraction of a joule and wraps within the
// hour on a busy machine. Read often enough -- more than once per wrap, which
// once a second is by three orders of magnitude -- the difference between two
// readings is right whether or not the register wrapped between them, and the
// differences add up in 64 bits of microjoules that outlast the machine.
//
// Nothing in this file may import the kernel.
module thermal

pub struct EnergyCounter {
pub mut:
	// A first reading has been taken.
	primed   bool
	last_raw u64
	// Energy so far. It starts at what the register held when first read, as
	// Linux's energy_uj does, and then only grows.
	microjoules u64
	// Nanojoules not yet a whole microjoule.
	remainder u64
}

// The counter after the register read `raw`. `mask` is the register's width
// and `unit` what one count of it is worth, in nanojoules.
//
// A register that reads less than it did has wrapped, once. One that seems to
// have gone more than halfway round between two readings has not: no machine
// uses that much in the second between them. It was reset -- the processor
// lost power in a sleep -- or was read on a CPU that keeps a count of its
// own. Counting starts again from that reading, and nothing is added for the
// gap.
pub fn (counter EnergyCounter) advanced(raw u64, mask u64, unit u64) EnergyCounter {
	mut next := counter
	reading := raw & mask
	if counter.primed && (reading - counter.last_raw) & mask > mask / 2 {
		next.last_raw = reading
		return next
	}
	delta := if counter.primed { (reading - counter.last_raw) & mask } else { reading }
	// 32 bits of counts times less than 2^31 nanojoules each: no overflow.
	nanojoules := delta * unit + counter.remainder
	next.microjoules = counter.microjoules + nanojoules / 1000
	next.remainder = nanojoules % 1000
	next.last_raw = reading
	next.primed = true
	return next
}

// The energy the whole of a register of width `mask` stands for, in
// microjoules: Linux's max_energy_range_uj for the register itself.
pub fn register_range_microjoules(mask u64, unit u64) u64 {
	return mask / 1000 * unit + mask % 1000 * unit / 1000
}

// The energy at a moment.
pub struct EnergySample {
pub mut:
	valid       bool
	microjoules u64
	nanoseconds u64
}

// The average power between two samples, in milliwatts; none unless both are
// samples and time has passed between them.
pub fn average_milliwatts(before EnergySample, after EnergySample) ?u64 {
	if !before.valid || !after.valid || after.nanoseconds <= before.nanoseconds
		|| after.microjoules < before.microjoules {
		return none
	}
	energy := after.microjoules - before.microjoules
	elapsed := after.nanoseconds - before.nanoseconds
	// Microjoules per nanosecond are kilowatts. More energy than fits the
	// multiplication is not a reading of any machine.
	if energy > ~u64(0) / 1000000 {
		return none
	}
	return energy * 1000000 / elapsed
}
