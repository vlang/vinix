@[has_globals]
module hpet

import acpi
import x86.cpu
import x86.kio

@[packed]
pub struct HPETTable {
pub mut:
	header acpi.SDT

	hardware_rev_id     u8
	misc_bits           u8
	pci_vendor_id       u16
	address_space_id    u8
	register_bit_width  u8
	register_bit_offset u8
	reserved1           u8
	address             u64
	hpet_number         u8
	minimum_tick        u16
	page_protection     u8
}

pub struct HPET {
pub mut:
	general_capabilities  u64
	unused0               u64
	general_configuration u64
	unused1               u64
	general_int_status    u64
	unused2               u64
	unused3               [24]u64
	main_counter_value    u64
	unused4               u64
}

__global (
	hpet           &HPET
	hpet_frequency u64
	// A machine without an HPET -- VirtualBox by default -- counts time with
	// the TSC instead, calibrated against the ACPI PM timer or the PIT.
	// hpet_frequency is then the TSC's.
	hpet_uses_tsc bool
	hpet_tsc_base u64
)

const pit_frequency = u64(1193182)

pub fn read_counter() u64 {
	if hpet_uses_tsc {
		return cpu.rdtsc() - hpet_tsc_base
	}
	return kio.mmin(&hpet.main_counter_value)
}

// Time since initialise(), in nanoseconds.
pub fn nanoseconds() u64 {
	ticks := read_counter()
	return (ticks / hpet_frequency) * 1000000000 +
		(ticks % hpet_frequency) * 1000000000 / hpet_frequency
}

fn pit_count() u64 {
	// Latch channel 0, then read its count low byte first.
	kio.port_out[u8](0x43, 0)
	lo := kio.port_in[u8](0x40)
	hi := kio.port_in[u8](0x40)
	return (u64(hi) << 8) | u64(lo)
}

const pm_timer_frequency = u64(3579545)

// The ACPI PM timer's I/O port, from the FADT, or 0 when there is none.
fn pm_timer_port() u16 {
	fadt := acpi.find_sdt('FACP', 0) or { return 0 }
	length := unsafe { *&u32(u64(fadt) + 4) }
	if length < 92 {
		return 0
	}
	port := unsafe { *&u32(u64(fadt) + 76) }
	width := unsafe { *&u8(u64(fadt) + 91) }
	if port == 0 || port > 0xffff || width != 4 {
		return 0
	}
	return u16(port)
}

// TSC ticks per second across 50 ms of the PM timer. It is 24 bits wide at
// the least and wraps only every 4.7 s, so a virtual CPU that the host sets
// aside for a while still measures the time that really passed. 0 when the
// timer does not move: a tick is 280 ns, far shorter than a million port
// reads, so a timer the FADT names but that does not count is given up on
// instead of hanging the boot.
fn tsc_rate_from_pm_timer(port u16) u64 {
	mask := u64(0xffffff)
	start := u64(kio.port_in[u32](port)) & mask
	tsc_start := cpu.rdtsc()
	mut elapsed := u64(0)
	mut unchanged := 0
	for elapsed < pm_timer_frequency / 20 {
		now := (u64(kio.port_in[u32](port)) - start) & mask
		if now == elapsed {
			unchanged++
			if unchanged > 1000000 {
				return 0
			}
		} else {
			unchanged = 0
		}
		elapsed = now
	}
	tsc_end := cpu.rdtsc()
	return (tsc_end - tsc_start) * pm_timer_frequency / elapsed
}

// TSC ticks per second across ~27 ms of the PIT, or 0 when the count is seen
// to go up: a whole 55 ms period passed between two reads, as it does when
// the host sets a virtual CPU aside, and how much time that was cannot be
// known. Channel 0 is reprogrammed later by time.pit_initialise(), so it is
// free to borrow here.
fn tsc_rate_from_pit() u64 {
	// Rate generator counting down from 0xffff, a 55 ms period.
	kio.port_out[u8](0x43, 0x34)
	kio.port_out[u8](0x40, 0xff)
	kio.port_out[u8](0x40, 0xff)
	// The new count is loaded on the next PIT clock. Until then a read can
	// return whatever channel 0 held before.
	for pit_count() < 0xf000 {}

	mut previous := pit_count()
	tsc_start := cpu.rdtsc()
	mut elapsed := u64(0)
	for elapsed < 0x8000 {
		now := pit_count()
		if now > previous {
			return 0
		}
		elapsed += previous - now
		previous = now
	}
	return (cpu.rdtsc() - tsc_start) * pit_frequency / elapsed
}

fn median_of_three(a u64, b u64, c u64) u64 {
	if (a <= b && b <= c) || (c <= b && b <= a) {
		return b
	}
	if (b <= a && a <= c) || (c <= a && a <= b) {
		return a
	}
	return c
}

// Calibrate the TSC for a machine without an HPET. Every x86-64 TSC runs at
// hundreds of MHz at least, so a rate below 50 MHz is a measurement the host
// disturbed, and is taken again. The median of three keeps one disturbed
// measurement from counting.
fn calibrate_tsc() {
	mut port := pm_timer_port()
	mut rates := [3]u64{}
	mut taken := 0
	for attempt := 0; attempt < 12 && taken < 3; attempt++ {
		rate := if port != 0 { tsc_rate_from_pm_timer(port) } else { tsc_rate_from_pit() }
		if rate == 0 && port != 0 {
			// The PM timer is stuck; the PIT is all there is.
			port = 0
			continue
		}
		if rate >= 50000000 {
			rates[taken] = rate
			taken++
		}
	}
	hpet_frequency = match taken {
		// Nothing plausible: keep the machine's time moving at a guess rather
		// than dividing by nothing.
		0 { u64(1000000000) }
		1 { rates[0] }
		2 { (rates[0] + rates[1]) / 2 }
		else { median_of_three(rates[0], rates[1], rates[2]) }
	}
	hpet_tsc_base = cpu.rdtsc()
	hpet_uses_tsc = true
	source := if port != 0 { c'ACPI PM timer' } else { c'PIT' }
	C.kprintf(c'hpet: No HPET; using the TSC at %llu Hz (calibrated against the %s)\n',
		u64(hpet_frequency), source)
}

pub fn initialise() {
	hpet_table := unsafe {
		&HPETTable(acpi.find_sdt('HPET', 0) or {
			calibrate_tsc()
			return
		})
	}

	hpet = unsafe { &HPET(hpet_table.address + higher_half) }

	mut tmp := kio.mmin(&hpet.general_capabilities)

	counter_clk_period := tmp >> 32
	hpet_frequency = u64(1000000000000000) / counter_clk_period

	C.kprintf(c'hpet: Detected frequency of %llu Hz\n', u64(hpet_frequency))

	kio.mmout(&hpet.main_counter_value, 0)

	println('hpet: Enabling')
	tmp = kio.mmin(&hpet.general_configuration)
	tmp |= 0b01
	kio.mmout(&hpet.general_configuration, tmp)
}
