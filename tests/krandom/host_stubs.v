// SPDX-License-Identifier: GPL-2.0-or-later
module krandom

#include "@VMODROOT/host_stubs.h"

// What the host test puts in place of the kernel's hardware hooks; run.sh
// copies the generator in random.v unchanged next to this. Predictable bytes
// are never trusted.
fn architecture_seed(mut output [64]u8) bool {
	for i in 0 .. output.len {
		output[i] = u8(i)
	}
	return false
}

__global (
	host_cycles = u64(1000)
)

fn cycle_counter() u64 {
	host_cycles += 97
	return host_cycles
}

fn C.kprintf(fmt charptr, ...voidptr) i32
