// SPDX-License-Identifier: GPL-2.0-only
@[has_globals]
module configfixture

#include <native-abi.h>

@[typedef]
struct C.pthread_mutex_t {}
@[typedef]
struct C.pthread_t {}

@[c_extern] __global C.pci_interrupts bool
@[c_extern] __global C.pci_locked bool
@[c_extern] __global C.pci_saved_interrupts bool
@[c_extern] __global C.pci_pins u32
@[c_extern] __global C.pci_saved_pins u32
@[c_extern] __global C.pci_mutex_initializer C.pthread_mutex_t

fn C.assert(bool)
fn C.sched_yield() i32
fn C.pthread_mutex_lock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_unlock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_destroy(&C.pthread_mutex_t) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.puts(&char) i32
fn C.__atomic_load_n(&u32, i32) u32
fn C.__atomic_store_n(&u32, u32, i32)
fn C.__atomic_exchange_n(&u32, u32, i32) u32
fn C.__atomic_add_fetch(&u32, u32, i32) u32
fn C.vinix_pci_config_read(u32, u32, u32, u32, u64, u32, &u32) i32
fn C.vinix_pci_config_write(u32, u32, u32, u32, u64, u32, u32) i32
fn C.vinix_pci_config_update_command(u32, u32, u32, u32, u16, u16) i32
// The actual C wrapper is registered with pthread, rather than its V function.
fn C.pci_fixture_actor_run(voidptr) voidptr

struct TestDevice {
mut:
	bus u32
	slot u32
	function u32
	bytes [4096]u8
}

__global pci_devices = [TestDevice{bus: 0, slot: 1}, TestDevice{bus: 0, slot: 2},
	TestDevice{bus: 7, slot: 31, function: 7}, TestDevice{bus: 255, slot: 31, function: 7}]!
__global pci_transport = C.pci_mutex_initializer
__global pci_attempts u32
__global pci_locks u32
__global pci_unlocks u32
__global pci_limits u32
__global pci_reads u32
__global pci_writes u32
__global pci_allocations u32
__global pci_cf8 u32
__global pci_oversized_reads bool
__global pci_gate_armed u32
__global pci_gate_entered u32
__global pci_gate_release u32
__global pci_gate_slot u32
__global pci_gate_offset u32
__global pci_last_read_width u32
__global pci_last_write_width u32
__global pci_last_write_offset u32
__global pci_last_write_value u32

// Only production-core allocator imports are redirected to these traps.
// Fixture pthread/libc backing retains its original independent ownership.
@[export: 'vinix_pci_test_malloc']
fn trap_malloc(bytes usize) voidptr {
	unsafe { C.__atomic_add_fetch(&pci_allocations, 1, C.__ATOMIC_RELAXED) }
	return unsafe { nil }
}
@[export: 'vinix_pci_test_calloc']
fn trap_calloc(count usize, bytes usize) voidptr { return trap_malloc(bytes) }
@[export: 'vinix_pci_test_realloc']
fn trap_realloc(old voidptr, bytes usize) voidptr { return trap_malloc(bytes) }
@[export: 'vinix_pci_test_free']
fn trap_free(pointer voidptr) {
	unsafe { C.__atomic_add_fetch(&pci_allocations, 1, C.__ATOMIC_RELAXED) }
}

fn wait_flag(flag &u32, wanted u32) {
	unsafe {
		for spin := u32(0); spin < 10000000; spin++ {
			if C.__atomic_load_n(flag, C.__ATOMIC_ACQUIRE) >= wanted { return }
			C.sched_yield()
		}
		C.assert(false) // Original: !"test actor/gate failed to progress".
	}
}
fn find_device(bus u32, slot u32, function u32) &TestDevice {
	unsafe {
		for i := usize(0); i < 4; i++ {
			if pci_devices[i].bus == bus && pci_devices[i].slot == slot && pci_devices[i].function == function {
				return &pci_devices[i]
			}
		}
		return nil
	}
}
fn check_locked() { unsafe { C.assert(C.pci_locked && !C.pci_interrupts && C.pci_pins == C.pci_saved_pins + 1) } }
@[export: 'vinix_pci_config_lock']
fn transport_lock() {
	unsafe {
		C.assert(!C.pci_locked)
		C.__atomic_add_fetch(&pci_attempts, 1, C.__ATOMIC_RELEASE)
		C.assert(C.pthread_mutex_lock(&pci_transport) == 0)
		C.pci_saved_interrupts = C.pci_interrupts
		C.pci_saved_pins = C.pci_pins
		C.pci_interrupts = false
		C.pci_pins++
		C.pci_locked = true
		C.__atomic_add_fetch(&pci_locks, 1, C.__ATOMIC_RELAXED)
	}
}
@[export: 'vinix_pci_config_unlock']
fn transport_unlock() {
	unsafe {
		check_locked()
		C.__atomic_add_fetch(&pci_unlocks, 1, C.__ATOMIC_RELAXED)
		C.pci_locked = false
		C.assert(C.pthread_mutex_unlock(&pci_transport) == 0)
		C.pci_pins = C.pci_saved_pins
		C.pci_interrupts = C.pci_saved_interrupts
	}
}
@[export: 'vinix_pci_config_limit']
fn transport_limit(bus u32) u32 {
	unsafe {
		check_locked()
		C.__atomic_add_fetch(&pci_limits, 1, C.__ATOMIC_RELAXED)
		if bus == 0 || bus == 255 { return 256 }
		if bus == 7 { return 4096 }
		return 0
	}
}
fn select_address(bus u32, slot u32, function u32, offset u32, actual_offset &u32) &TestDevice {
	unsafe {
		check_locked()
		if bus == 7 { *actual_offset = offset; return find_device(bus, slot, function) }
		mut address := u32(0x80000000) | (bus << 16) | (slot << 11) | (function << 8) | (offset & 0xfc)
		C.__atomic_store_n(&pci_cf8, address, C.__ATOMIC_RELEASE)
		// Original scheduling gate, after CF8 publication and under the lock.
		if bus == 0 && slot == pci_gate_slot && offset == pci_gate_offset
			&& C.__atomic_exchange_n(&pci_gate_armed, 0, C.__ATOMIC_ACQ_REL) != 0 {
			C.__atomic_store_n(&pci_gate_entered, 1, C.__ATOMIC_RELEASE)
			wait_flag(&pci_gate_release, 1)
		}
		address = C.__atomic_load_n(&pci_cf8, C.__ATOMIC_ACQUIRE)
		*actual_offset = (address & 0xfc) + (offset & 3)
		return find_device((address >> 16) & 255, (address >> 11) & 31, (address >> 8) & 7)
	}
}
@[export: 'vinix_pci_config_read_raw']
fn transport_read(bus u32, slot u32, function u32, offset u32, width u32) u32 {
	unsafe {
		mut actual_offset := u32(0)
		device := select_address(bus, slot, function, offset, &actual_offset)
		C.assert(width == 1 || width == 2 || width == 4)
		pci_last_read_width = width
		C.__atomic_add_fetch(&pci_reads, 1, C.__ATOMIC_RELAXED)
		if usize(device) == 0 { return ~u32(0) }
		mut value := u32(0)
		for i := u32(0); i < width; i++ { value |= u32(device.bytes[actual_offset + i]) << (8 * i) }
		if pci_oversized_reads && width < 4 { value |= if width == 1 { u32(0xa5a5a500) } else { u32(0xa5a50000) } }
		return value
	}
}
@[export: 'vinix_pci_config_write_raw']
fn transport_write(bus u32, slot u32, function u32, offset u32, width u32, value u32) {
	unsafe {
		mut actual_offset := u32(0)
		device := select_address(bus, slot, function, offset, &actual_offset)
		C.assert(width == 1 || width == 2 || width == 4)
		C.assert(width == 4 || value >> (8 * width) == 0)
		pci_last_write_width = width
		pci_last_write_offset = offset
		pci_last_write_value = value
		C.__atomic_add_fetch(&pci_writes, 1, C.__ATOMIC_RELAXED)
		if usize(device) == 0 { return }
		for i := u32(0); i < width; i++ {
			byte := u8(value >> (8 * i))
			if actual_offset + i == 6 || actual_offset + i == 7 { device.bytes[actual_offset + i] &= ~byte }
			else { device.bytes[actual_offset + i] = byte }
		}
	}
}

struct Observed {
	attempts u32
	locks u32
	unlocks u32
	limits u32
	reads u32
	writes u32
	allocations u32
	pins u32
	interrupts bool
}
fn observe() Observed {
	unsafe {
		return Observed{
			attempts: C.__atomic_load_n(&pci_attempts, C.__ATOMIC_ACQUIRE)
			locks: C.__atomic_load_n(&pci_locks, C.__ATOMIC_RELAXED)
			unlocks: C.__atomic_load_n(&pci_unlocks, C.__ATOMIC_RELAXED)
			limits: C.__atomic_load_n(&pci_limits, C.__ATOMIC_RELAXED)
			reads: C.__atomic_load_n(&pci_reads, C.__ATOMIC_RELAXED)
			writes: C.__atomic_load_n(&pci_writes, C.__ATOMIC_RELAXED)
			allocations: C.__atomic_load_n(&pci_allocations, C.__ATOMIC_RELAXED)
			pins: C.pci_pins
			interrupts: C.pci_interrupts
		}
	}
}
fn preserved(before Observed) {
	unsafe {
		C.assert(!C.pci_locked && C.pci_interrupts == before.interrupts && C.pci_pins == before.pins)
		C.assert(C.__atomic_load_n(&pci_allocations, C.__ATOMIC_RELAXED) == before.allocations)
	}
}
fn check_bad(domain u32, bus u32, slot u32, function u32, offset u64, width u32, expected i32, result bool, takes_lock bool) {
	unsafe {
		mut before := observe()
		mut value := u32(0x12345678)
		output := if result { &value } else { &u32(nil) }
		C.assert(C.vinix_pci_config_read(domain, bus, slot, function, offset, width, output) == expected)
		C.assert(value == 0x12345678)
		preserved(before)
		mut after := observe()
		C.assert(after.reads == before.reads && after.writes == before.writes)
		C.assert(after.attempts - before.attempts == u32(takes_lock))
		C.assert(after.locks - before.locks == u32(takes_lock))
		C.assert(after.unlocks - before.unlocks == u32(takes_lock))
		C.assert(after.limits - before.limits == u32(takes_lock))
		if !result { return }
		before = observe()
		C.assert(C.vinix_pci_config_write(domain, bus, slot, function, offset, width, ~u32(0)) == expected)
		preserved(before)
		after = observe()
		C.assert(after.reads == before.reads && after.writes == before.writes)
		C.assert(after.attempts - before.attempts == u32(takes_lock))
		C.assert(after.locks - before.locks == u32(takes_lock))
		C.assert(after.unlocks - before.unlocks == u32(takes_lock))
		C.assert(after.limits - before.limits == u32(takes_lock))
	}
}
fn validation_tests() {
	unsafe {
		for state := u32(0); state < 2; state++ {
			C.pci_interrupts = state == 0
			C.pci_pins = if state != 0 { u32(2) } else { u32(0) }
			check_bad(0, 0, 1, 0, 0, 4, C.VINIX_PCI_CONFIG_BAD_REGISTER, false, false)
			check_bad(1, 0, 1, 0, 0, 4, C.VINIX_PCI_CONFIG_BAD_REGISTER, false, false)
			check_bad(0, 256, 1, 0, 0, 4, C.VINIX_PCI_CONFIG_BAD_REGISTER, true, false)
			check_bad(0, ~u32(0), 1, 0, 0, 4, C.VINIX_PCI_CONFIG_BAD_REGISTER, true, false)
			check_bad(0, 0, 32, 0, 0, 4, C.VINIX_PCI_CONFIG_BAD_REGISTER, true, false)
			check_bad(0, 0, 1, 8, 0, 4, C.VINIX_PCI_CONFIG_BAD_REGISTER, true, false)
			invalid_widths := [u32(0), u32(3), u32(8), ~u32(0)]!
			for i := usize(0); i < 4; i++ { check_bad(0, 0, 1, 0, 0, invalid_widths[i], C.VINIX_PCI_CONFIG_BAD_REGISTER, true, false) }
			check_bad(0, 0, 1, 0, 1, 2, C.VINIX_PCI_CONFIG_BAD_REGISTER, true, false)
			check_bad(0, 0, 1, 0, 2, 4, C.VINIX_PCI_CONFIG_BAD_REGISTER, true, false)
			check_bad(1, 0, 1, 0, 0, 4, C.VINIX_PCI_CONFIG_UNAVAILABLE, true, false)
			check_bad(~u32(0), 0, 1, 0, ~u64(0), 1, C.VINIX_PCI_CONFIG_UNAVAILABLE, true, false)
			check_bad(1, 256, 1, 0, 0, 4, C.VINIX_PCI_CONFIG_BAD_REGISTER, true, false)
			check_bad(0, 3, 1, 0, 0, 4, C.VINIX_PCI_CONFIG_UNAVAILABLE, true, true)
			check_bad(0, 0, 1, 0, 256, 1, C.VINIX_PCI_CONFIG_BAD_REGISTER, true, true)
			check_bad(0, 7, 31, 7, 4096, 4, C.VINIX_PCI_CONFIG_BAD_REGISTER, true, true)
			check_bad(0, 0, 1, 0, u64(0x100000000), 4, C.VINIX_PCI_CONFIG_BAD_REGISTER, true, true)
			check_bad(0, 0, 1, 0, ~u64(0), 1, C.VINIX_PCI_CONFIG_BAD_REGISTER, true, true)
			check_bad(0, 0, 1, 0, ~u64(0) - 1, 2, C.VINIX_PCI_CONFIG_BAD_REGISTER, true, true)
			check_bad(0, 7, 31, 7, ~u64(0) - 3, 4, C.VINIX_PCI_CONFIG_BAD_REGISTER, true, true)
		}
		C.pci_interrupts = true
		C.pci_pins = 0
	}
}
fn word(bytes &u8, width u32) u32 {
	unsafe {
		mut value := u32(0)
		for i := u32(0); i < width; i++ { value |= u32(bytes[i]) << (8 * i) }
		return value
	}
}
struct Interior { offset u32 width u32 value u32 result u32 }
fn width_tests() {
	unsafe {
		widths := [u32(1), u32(2), u32(4)]!
		for device_index := usize(0); device_index < 4; device_index++ {
			device := &pci_devices[device_index]
			limit := if device.bus == 7 { u32(4096) } else { u32(256) }
			for byte := u32(0); byte < 4096; byte++ { device.bytes[byte] = u8(byte * 37 + device_index) }
			for w := usize(0); w < 3; w++ {
				width := widths[w]
				for offset := u32(0); offset < limit; offset += width {
					before := observe()
					mut value := u32(0)
					C.assert(C.vinix_pci_config_read(0, device.bus, device.slot, device.function, offset, width, &value) == 0)
					C.assert(value == word(&device.bytes[offset], width))
					preserved(before)
					if width > 1 { check_bad(0, device.bus, device.slot, device.function, offset + 1, width, C.VINIX_PCI_CONFIG_BAD_REGISTER, true, false) }
				}
				mut expected := [4096]u8{}
				C.memcpy(&expected[0], &device.bytes[0], sizeof(expected))
				offset := limit - width
				for i := u32(0); i < width; i++ { expected[offset + i] = u8(u32(0xa1b2c3d4) >> (8 * i)) }
				before := observe()
				C.assert(C.vinix_pci_config_write(0, device.bus, device.slot, device.function, offset, width, 0xa1b2c3d4) == 0)
				C.assert(C.memcmp(&expected[0], &device.bytes[0], sizeof(expected)) == 0)
				C.assert(pci_last_write_width == width && pci_last_write_offset == offset)
				preserved(before)
			}
			interior := [Interior{33, 1, 0xdeadbe76, 0x76}, Interior{34, 2, 0xbeef4321, 0x4321},
				Interior{36, 4, 0x98765432, 0x98765432}]!
			for i := usize(0); i < 3; i++ {
				mut expected := [4096]u8{}
				C.memcpy(&expected[0], &device.bytes[0], sizeof(expected))
				for byte := u32(0); byte < interior[i].width; byte++ {
					expected[interior[i].offset + byte] = u8(interior[i].result >> (8 * byte))
				}
				before := observe()
				C.assert(C.vinix_pci_config_write(0, device.bus, device.slot, device.function, interior[i].offset, interior[i].width, interior[i].value) == 0)
				C.assert(C.memcmp(&expected[0], &device.bytes[0], sizeof(expected)) == 0)
				C.assert(pci_last_write_width == interior[i].width && pci_last_write_offset == interior[i].offset && pci_last_write_value == interior[i].result)
				mut result := u32(0)
				C.assert(C.vinix_pci_config_read(0, device.bus, device.slot, device.function, interior[i].offset, interior[i].width, &result) == 0)
				C.assert(result == interior[i].result)
				preserved(before)
			}
		}
		pci_oversized_reads = true
		for w := usize(0); w < 3; w++ {
			mut value := u32(0)
			C.assert(C.vinix_pci_config_read(0, 0, 1, 0, 16, widths[w], &value) == 0)
			C.assert(value == word(&pci_devices[0].bytes[16], widths[w]))
			C.assert(C.vinix_pci_config_read(0, 7, 30, 6, 0, widths[w], &value) == 0)
			C.assert(value == if widths[w] == 1 { u32(0xff) } else if widths[w] == 2 { u32(0xffff) } else { ~u32(0) })
			mut before := [4096]u8{}
			C.memcpy(&before[0], &pci_devices[2].bytes[0], sizeof(before))
			C.assert(C.vinix_pci_config_write(0, 7, 30, 6, 0, widths[w], ~u32(0)) == 0)
			C.assert(C.memcmp(&before[0], &pci_devices[2].bytes[0], sizeof(before)) == 0)
		}
		pci_oversized_reads = false
	}
}
struct CommandCase { initial u16 clear u16 set u16 expected u16 changed bool }
fn command_tests() {
	unsafe {
		cases := [CommandCase{0x1234, 0x000f, 0x0003, 0x1233, true},
			CommandCase{0xffff, 0xffff, 0x5a3c, 0x5a3c, true},
			CommandCase{0x1234, 0, 0, 0x1234, false}, CommandCase{0x1234, 0x0004, 0x0004, 0x1234, false}]!
		for i := usize(0); i < 4; i++ {
			device := &pci_devices[0]
			device.bytes[4] = u8(cases[i].initial)
			device.bytes[5] = u8(cases[i].initial >> 8)
			device.bytes[6] = 0xa5
			device.bytes[7] = 0x5a
			before := observe()
			C.assert(C.vinix_pci_config_update_command(0, 0, 1, 0, cases[i].clear, cases[i].set) == 0)
			C.assert(word(&device.bytes[4], 2) == cases[i].expected)
			C.assert(device.bytes[6] == 0xa5 && device.bytes[7] == 0x5a)
			after := observe()
			C.assert(after.locks == before.locks + 1 && after.unlocks == before.unlocks + 1)
			C.assert(after.reads == before.reads + 1 && after.writes == before.writes + u32(cases[i].changed))
			C.assert(pci_last_read_width == 2)
			if cases[i].changed { C.assert(pci_last_write_width == 2 && pci_last_write_offset == 4 && pci_last_write_value == cases[i].expected) }
			preserved(before)
		}
		pci_devices[0].bytes[6] = 0xff
		pci_devices[0].bytes[7] = 0xff
		C.assert(C.vinix_pci_config_write(0, 0, 1, 0, 6, 1, 0x0f) == 0)
		C.assert(pci_devices[0].bytes[6] == 0xf0 && pci_devices[0].bytes[7] == 0xff)
		C.assert(C.vinix_pci_config_write(0, 0, 1, 0, 6, 2, 0xf00f) == 0)
		C.assert(pci_devices[0].bytes[6] == 0xf0 && pci_devices[0].bytes[7] == 0x0f)
		before := observe()
		C.assert(C.vinix_pci_config_update_command(1, 0, 1, 0, 0, 1) == C.VINIX_PCI_CONFIG_UNAVAILABLE)
		C.assert(C.vinix_pci_config_update_command(0, 256, 1, 0, 0, 1) == C.VINIX_PCI_CONFIG_BAD_REGISTER)
		C.assert(C.vinix_pci_config_update_command(0, 0, 32, 0, 0, 1) == C.VINIX_PCI_CONFIG_BAD_REGISTER)
		C.assert(C.vinix_pci_config_update_command(0, 0, 1, 8, 0, 1) == C.VINIX_PCI_CONFIG_BAD_REGISTER)
		C.assert(observe().locks == before.locks && observe().reads == before.reads && observe().writes == before.writes)
		C.assert(C.vinix_pci_config_update_command(0, 3, 1, 0, 0, 1) == C.VINIX_PCI_CONFIG_UNAVAILABLE)
		C.assert(C.vinix_pci_config_update_command(0, 0, 30, 0, 1, 0) == 0)
		preserved(before)
	}
}
struct Actor {
mut:
	slot u32
	value u32
	set u16
	done u32
	command bool
}
@[export: 'pci_fixture_actor_run']
fn actor_run(argument voidptr) voidptr {
	unsafe {
		actor := &Actor(argument)
		C.pci_interrupts = false
		C.pci_pins = 2
		before := observe()
		if actor.command { C.assert(C.vinix_pci_config_update_command(0, 0, actor.slot, 0, 0, actor.set) == 0) }
		else { C.assert(C.vinix_pci_config_read(0, 0, actor.slot, 0, 0x40, 4, &actor.value) == 0) }
		preserved(before)
		C.__atomic_store_n(&actor.done, 1, C.__ATOMIC_RELEASE)
		return nil
	}
}
fn concurrent_tests() {
	unsafe {
		for command := u32(0); command < 2; command++ {
			pci_devices[0].bytes[4] = 0
			pci_devices[0].bytes[5] = 0
			pci_devices[0].bytes[6] = 0xa5
			pci_devices[0].bytes[7] = 0x5a
			pci_devices[0].bytes[0x40] = 0x11
			pci_devices[1].bytes[0x40] = 0x22
			pci_devices[0].bytes[0x41] = 0
			pci_devices[0].bytes[0x42] = 0
			pci_devices[0].bytes[0x43] = 0
			pci_devices[1].bytes[0x41] = 0
			pci_devices[1].bytes[0x42] = 0
			pci_devices[1].bytes[0x43] = 0
			mut a := Actor{slot: 1, set: 1, command: command != 0}
			mut b := Actor{slot: if command != 0 { u32(1) } else { u32(2) }, set: 2, command: command != 0}
			mut first := C.pthread_t{}
			mut second := C.pthread_t{}
			pci_gate_slot = 1
			pci_gate_offset = if command != 0 { u32(4) } else { u32(0x40) }
			C.__atomic_store_n(&pci_gate_entered, 0, C.__ATOMIC_RELEASE)
			C.__atomic_store_n(&pci_gate_release, 0, C.__ATOMIC_RELEASE)
			C.__atomic_store_n(&pci_gate_armed, 1, C.__ATOMIC_RELEASE)
			start_attempts := observe().attempts
			C.assert(C.pthread_create(&first, nil, C.pci_fixture_actor_run, &a) == 0)
			wait_flag(&pci_gate_entered, 1)
			captured := C.__atomic_load_n(&pci_cf8, C.__ATOMIC_ACQUIRE)
			C.assert(C.pthread_create(&second, nil, C.pci_fixture_actor_run, &b) == 0)
			wait_flag(&pci_attempts, start_attempts + 2)
			C.assert(C.__atomic_load_n(&a.done, C.__ATOMIC_ACQUIRE) == 0 && C.__atomic_load_n(&b.done, C.__ATOMIC_ACQUIRE) == 0)
			C.assert(C.__atomic_load_n(&pci_cf8, C.__ATOMIC_ACQUIRE) == captured)
			C.__atomic_store_n(&pci_gate_release, 1, C.__ATOMIC_RELEASE)
			C.assert(C.pthread_join(first, nil) == 0 && C.pthread_join(second, nil) == 0)
			C.assert(a.done != 0 && b.done != 0)
			if command != 0 {
				C.assert(word(&pci_devices[0].bytes[4], 2) == 3)
				C.assert(pci_devices[0].bytes[6] == 0xa5 && pci_devices[0].bytes[7] == 0x5a)
			} else { C.assert(a.value == 0x11 && b.value == 0x22) }
		}
	}
}
@[export: 'main']
fn fixture_main() i32 {
	unsafe {
		validation_tests()
		width_tests()
		command_tests()
		concurrent_tests()
		C.assert(!C.pci_locked && C.pci_interrupts && C.pci_pins == 0 && pci_allocations == 0)
		C.assert(observe().locks == observe().unlocks)
		C.assert(C.pthread_mutex_destroy(&pci_transport) == 0)
		C.puts(c'PCI config: PASS (actual core, widths/bounds, CF8 serialization, RW1C-safe COMMAND, no core allocations; host model only)')
		return 0
	}
}
