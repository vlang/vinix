@[has_globals]
module serial

import x86.kio
import klock

// These survive _vinit: early_initialise runs before the V runtime. All
// early-path register values and bounds below are literals for the same reason.
@[cinit]
__global (
	com1_present = false
	com1_tx_failed = false
)

__global (
	com1_lock klock.Lock
)

// No allocator, runtime constants, locks or IRQ infrastructure required.
pub fn early_initialise() {
	com1_present = initialise_port(0x3f8)
	com1_tx_failed = false
}

fn initialise_port(port u16) bool {
	// Probe both patterns: floating/all-zero buses must not look present.
	scratch := kio.port_in[u8](port + 7)
	kio.port_out[u8](port + 7, 0x55)
	first := kio.port_in[u8](port + 7)
	kio.port_out[u8](port + 7, 0xaa)
	second := kio.port_in[u8](port + 7)
	kio.port_out[u8](port + 7, scratch)
	if first != 0x55 || second != 0xaa {
		return false
	}

	// Clear DLAB before accessing IER; firmware may leave it set.
	kio.port_out[u8](port + 3, 0x03)
	kio.port_out[u8](port + 1, 0x00)
	kio.port_out[u8](port + 3, 0x80)
	kio.port_out[u8](port + 0, 0x01) // 115200 baud
	kio.port_out[u8](port + 1, 0x00)
	kio.port_out[u8](port + 3, 0x03) // 8N1, DLAB off
	kio.port_out[u8](port + 2, 0xc7) // FIFO on, clear RX/TX
	kio.port_out[u8](port + 4, 0x0b) // DTR/RTS/OUT2; IER remains disabled
	return true
}

// Only late device setup and resume may enable RX interrupts.
fn enable_port_interrupts(port u16) {
	kio.port_out[u8](port + 1, 0x01)
}

fn console_byte(value u8) bool {
	// A bounded number of port reads, independent of clocks and interrupts.
	for poll := 0; poll < 65536; poll++ {
		status := kio.port_in[u8](0x3fd)
		if status == 0xff {
			break
		}
		if status & 0x20 != 0 { // THR empty, not necessarily shift register empty
			kio.port_out[u8](0x3f8, value)
			return true
		}
	}
	// Do not pay the timeout again for every byte in a panic or boot log.
	com1_tx_failed = true
	return false
}

// Unlocked, allocation-free reporting also used before runtime and in panic.
@[markused]
pub fn panic_out(value u8) {
	if !com1_present || com1_tx_failed {
		return
	}
	if value == `\n` && !console_byte(`\r`) {
		return
	}
	console_byte(value)
}

pub fn out(value u8) {
	com1_lock.acquire()
	panic_out(value)
	com1_lock.release()
}
