// SPDX-License-Identifier: GPL-2.0-or-later
// Deterministic host hardware stand-in; the generator remains unmodified.
@[has_globals]
module hosthooks

#include <host-native-abi.h>
@[typedef]
struct C.vkrandom_host_va {}
fn C.vprintf(&char, C.vkrandom_host_va) i32

__global (
	krandom_host_hardware_on i32
	krandom_host_hardware_state = u64(0x243f6a8885a308d3)
)

@[export: 'vinix_test_set_hardware']
pub fn set_hardware(on i32) { krandom_host_hardware_on = on }

@[export: 'vinix_hw_random64']
pub fn hardware_random(out &u64) i32 {
	if krandom_host_hardware_on == 0 { return 0 }
	krandom_host_hardware_state = krandom_host_hardware_state * u64(6364136223846793005) + u64(1442695040888963407)
	unsafe { *out = krandom_host_hardware_state }
	return 1
}

// The instruction-only producer saves the complete native register banks.
// libc consumes this borrowed va_list synchronously before the producer returns.
@[export: 'vinix_krandom_host_vprintf']
pub fn format(format &char, native_va voidptr) i32 {
	return unsafe { C.vprintf(format, *(&C.vkrandom_host_va(native_va))) }
}
