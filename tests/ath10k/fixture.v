// SPDX-License-Identifier: ISC
module ath10k

fn fixture_blob(bytes []u8) Blob {
	return Blob{ data: bytes.data, len: u32(bytes.len) }
}

struct FakeHardware {
mut:
	registers [131080]u32
	time      u64
	complete  bool
}

fn fake_read(cookie voidptr, register u32) u32 {
	mut hw := unsafe { &FakeHardware(cookie) }
	return hw.registers[register / 4]
}

fn fake_write(cookie voidptr, register u32, value u32) {
	mut hw := unsafe { &FakeHardware(cookie) }
	hw.registers[register / 4] = value
	if hw.complete && register >= 0x34400 && register < 0x36400 && (register - 0x34400) % 0x400 == 0x3c {
		hw.registers[(register + 8) / 4] = value
	}
}

fn fake_clock(cookie voidptr) u64 {
	mut hw := unsafe { &FakeHardware(cookie) }
	hw.time += 100000
	return hw.time
}

fn fake_delay(cookie voidptr, us u32) {
	mut hw := unsafe { &FakeHardware(cookie) }
	hw.time += u64(us) * 1000
}

fn fake_barrier() {}

fn fixture_protocol(hw &FakeHardware, bytes []u8) Protocol {
	mut p := Protocol{
		wmi:          1
		htt:          2
		credit_size:  256
		credit_count: 32
		transport:    Transport{
			bus:      0x01000000
			pool:     fixture_blob(bytes)
			hardware: Hardware{
				cookie:  unsafe { hw }
				read:    fake_read
				write:   fake_write
				clock:   fake_clock
				delay:   fake_delay
				barrier: fake_barrier
			}
		}
	}
	p.credits[1] = 32
	assert p.transport.layout()
	p.transport.initialise_engines()
	return p
}
