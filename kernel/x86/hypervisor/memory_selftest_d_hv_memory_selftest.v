// SPDX-License-Identifier: GPL-2.0-only
@[has_globals]
module hypervisor

import memory
import dev.serial

__global memory_test_fail_after = int(-1)

fn memory_report(message string) {
	for byte in message { serial.out(byte) }
}

fn memory_number(value u64) {
	mut digits := [20]u8{}
	mut count := 0
	mut remaining := value
	for {
		digits[count] = u8(remaining % 10) + `0`
		count++
		remaining /= 10
		if remaining == 0 { break }
	}
	for count > 0 {
		count--
		serial.out(digits[count])
	}
}

fn memory_check(ok bool, line int) {
	if !ok {
		memory_report('HYPERVISOR MEMORY SELFTEST FAIL line=')
		memory_number(u64(line))
		memory_report('\n')
		C.kprintf(c'HYPERVISOR MEMORY SELFTEST FAIL line=%d\n', line)
		for {}
	}
}

fn memory_exercise(size u64) {
	before := memory.free_bytes()
	mut ram := GuestMemory{}
	memory_check(ram.initialise(size), 20)
	memory_check(ram.size() == (size + 4095) & ~u64(4095), 21)
	memory_check(guest_memory_entry(ram.pml4, 0) == ram.pdpt | 7, 22)
	memory_check(guest_memory_entry(ram.pdpt, 0) == ram.pd | 7, 23)
	for page := u64(0); page < ram.pages; page++ {
		frame := ram.page(page)
		memory_check(frame != unsafe { nil }, 26)
		unsafe {
			mapped := &u64(u64(frame) + memory.get_hhdm_offset())
			memory_check(mapped[0] == 0 && mapped[511] == 0, 29)
		}
		table := guest_memory_entry(ram.pd, page / 512) & ept_address_mask
		memory_check(guest_memory_entry(table, page % 512) == u64(frame) | 0x37, 32)
	}
	mut input := [8192]u8{}
	mut output := [8192]u8{}
	for i in 0 .. input.len { input[i] = u8(i * 31 + 7) }
	for address in [u64(0), u64(4093), u64(2 * 1024 * 1024 - 3), ram.size() - 1]! {
		if address >= ram.size() { continue }
		length := if ram.size() - address < 8192 { ram.size() - address } else { u64(8192) }
		memory_check(ram.copy(address, unsafe { &input[0] }, length, true), 41)
		memory_check(ram.copy(address, unsafe { &output[0] }, length, false), 42)
		for i := u64(0); i < length; i++ { memory_check(input[i] == output[i], 43) }
	}
	memory_check(!ram.copy(ram.size(), unsafe { &input[0] }, 1, true), 45)
	memory_check(!ram.copy(~u64(0), unsafe { &input[0] }, 1, false), 46)
	memory_check(!ram.copy(0, unsafe { &input[0] }, ~u64(0), true), 47)
	memory_check(!ram.copy(0, unsafe { nil }, 1, false), 48)
	memory_check(ram.copy(ram.size(), unsafe { nil }, 0, false), 49)
	memory_check(ram.page(ram.pages) == unsafe { nil }, 50)
	ram.release()
	ram.release()
	memory_check(memory.free_bytes() == before, 53)
	memory_check(!ram.copy(0, unsafe { &input[0] }, 1, true), 54)
}

// Runs before secondary CPUs and the scheduler start, so free_bytes gives an
// exact physical-page oracle rather than a noisy before/after estimate.
pub fn memory_selftest() {
	mut empty := GuestMemory{}
	memory_check(!empty.initialise(0) && !empty.initialise(max_guest_memory + 1), 61)
	for size in [u64(1), u64(4096), u64(4097), u64(2 * 1024 * 1024 + 1), u64(16 * 1024 * 1024),
		max_guest_memory]! {
		memory_exercise(size)
		memory_report('HYPERVISOR MEMORY SIZE PASS bytes=')
		memory_number(size)
		memory_report('\n')
	}
	// Both sides of PT allocation boundaries, the last RAM page and both FPU
	// allocations. All use the production VM allocation/rollback path.
	memory.heap_trim()
	before := memory.free_bytes()
	for failure in [0, 1, 2, 3, 4, 5, 6, 515, 516, 517, 518, 1028, 1029, 1030, 4107, 4108, 4109,
		4110]! {
		memory_test_fail_after = failure
		mut vm := allocate_vm(16 * 1024 * 1024) or {
			memory_check(failure < 4110, 80)
			memory_test_fail_after = -1
			memory.heap_trim()
			memory_check(memory.free_bytes() == before, 81)
			continue
		}
		memory_check(failure == 4110, 85)
		memory_test_fail_after = -1
		vm.destroy()
		unsafe { free(vm) }
		memory.heap_trim()
		memory_check(memory.free_bytes() == before, 88)
	}
	for _ in 0 .. 100 {
		mut vm := allocate_vm(8 * 1024 * 1024) or {
			memory_check(false, 91)
			return
		}
		vm.destroy()
		vm.destroy()
		unsafe { free(vm) }
		memory.heap_trim()
		memory_check(memory.free_bytes() == before, 96)
	}
	memory_report('HYPERVISOR MEMORY SELFTEST PASS: 1 GiB, boundaries, rollback, 100 VM lifetimes\n')
}
