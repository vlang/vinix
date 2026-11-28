@[has_globals]
module kio

#include <assert.h>
fn C.assert(bool)

__global (
	registers [8]u8
	mode int
	status_reads int
	delay int
	output [64]u8
	output_len int
)

// 0: present; 1: absent/floating; 2: stuck TX; 3: floating LSR after probe.
pub fn setup(kind int, wait int) {
	mode = kind
	delay = wait
	status_reads = 0
	output_len = 0
	registers[3] = 0x80 // Firmware left DLAB set.
	registers[1] = 1
	registers[7] = 0x19
}

pub fn port_in[T](port u16) T {
	if port < 0x3f8 || port > 0x3ff || mode == 1 { return T(0xff) }
	if port == 0x3fd {
		status_reads++
		if mode == 3 { return T(0xff) }
		return T(if mode == 2 || status_reads <= delay { 0 } else { 0x20 })
	}
	return T(registers[int(port - 0x3f8)])
}

pub fn port_out[T](port u16, value T) {
	if port < 0x3f8 || port > 0x3ff || mode == 1 { return }
	if port == 0x3f8 && registers[3] & 0x80 == 0 {
		C.assert(output_len < 64)
		output[output_len] = u8(value)
		output_len++
	} else {
		registers[int(port - 0x3f8)] = u8(value)
	}
}

pub fn reads() int { return status_reads }
pub fn size() int { return output_len }
pub fn byte_at(index int) u8 { return output[index] }
pub fn ier() u8 { return registers[1] }
pub fn scratch() u8 { return registers[7] }
