@[has_globals]
module gpu

import gpu.agx.alloc
import gpu.agx.channel
import gpu.agx.fw
import gpu.agx.hw
import aarch64.timer
import memory

__global higher_half = u64(0)
__global pressure_host_page_size = u64(4096)
__global uat_storage = HostUat{}
__global uat_mgr = unsafe { &HostUat(nil) }
struct HostUat {}
fn (_ &HostUat) map_kernel(_ u64, _ u64, _ u64, _ u64) bool { panic('exhaustion must fail before page-table publication') }

fn pressure_case(class int, mode int, abi hw.FirmwareAbi, release_high bool, size u64) {
	mut header := channel.RingHeader{}
	mut ring := [256]fw.FwDeviceControlMsg{}
	mut manager := GpuManager{state: .running, mode: mode,
		hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi},
		g13_private: g13_private_heap(), g13_gpu_readonly: g13_gpu_readonly_heap(),
		channels: GpuChannels{device_ctrl: channel.new_tx_channel('pressure', 1, u64(&header), 1, u64(&ring), 256, 48)}}
	mut heap := if class == 0 { &manager.g13_private } else { &manager.g13_gpu_readonly }
	heap.end = heap.start + 3 * size
	low := heap.alloc(size, 0) or { panic('low') }
	middle := heap.alloc(size, 0) or { panic('middle') }
	high := heap.alloc(size, 0) or { panic('high') }
	live := heap.allocations[1]
	first := heap.allocations[if release_high { 2 } else { 0 }]
	second := heap.allocations[if release_high { 0 } else { 2 }]
	heap.release(if release_high { high } else { low })
	heap.release(if release_high { low } else { high })
	count, bytes := heap.garbage()
	assert count == 2 && bytes == 2 * size
	active = unsafe { &manager }; timer.on_tick(acknowledge); timer.reset()
	if mode == 6 { header.read_ptr = 1 }
	if mode == 7 { header.write_ptr = 256 }
	manager.lock.acquire(); manager.collect_g13_heap_garbage_locked(); manager.lock.release()
	success := mode in [0, 1]! && 2 * size > 16_777_216
	if success {
		assert C.__asan_address_is_poisoned(first) != 0 && C.__asan_address_is_poisoned(second) != 0
		address := heap.alloc(size, 0) or { panic('acknowledged ranges must be reusable') }
		assert address == if release_high { low } else { high }, 'acknowledged FIFO order must preserve hole history'
		heap.release(address)
	} else {
		for _ in 0 .. 3 {
			if _ := heap.alloc(size, 0) { panic('allocation pressure must not collect unacknowledged firmware ranges') }
			assert C.__asan_address_is_poisoned(first) == 0 && C.__asan_address_is_poisoned(second) == 0
			assert heap.allocations.len == 3 && heap.allocations[1] == live && live.va == middle
			pending, pending_bytes := heap.garbage(); assert pending == count && pending_bytes == bytes
			if _ := alloc_buffer_from_heap(mut heap, 1, 0, 0) { panic('exhausted buffer allocation must fail') }
			memory.check_balanced()
		}
		heap.collect_garbage(1)
		assert C.__asan_address_is_poisoned(first) != 0 && C.__asan_address_is_poisoned(second) == 0
		address := heap.alloc(size, 0) or { panic('explicitly collected range must be reusable') }
		assert address == if release_high { high } else { low }
		heap.release(address)
	}
	assert C.__asan_address_is_poisoned(live) == 0 && live.in_use
	heap.release(middle); heap.gc(); assert heap.allocations.len == 0
	unsafe { manager.g13_private.allocations.free(); manager.g13_gpu_readonly.allocations.free() }
	active = unsafe { nil }; timer.on_tick(fn () {})
}

pub fn check_pressure() {
	uat_mgr = unsafe { &uat_storage }
	mut cases := 0
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		for class in 0 .. 2 { for mode in [0, 1, 2, 3, 4, 5, 6, 7]! {
			for high in [false, true]! { for size in [alloc.gpu_page_size, u64(16_793_600)]! {
				pressure_case(class, mode, abi, high, size); cases++
			} }
		} }
	}
	assert cases == 128
	memory.check_total(336)
	// The generic heap retains its historical allocation-pressure retry.
	mut legacy := alloc.new_heap('legacy', 0x4000, 0x8000)
	va := legacy.alloc(1, 0) or { panic('legacy') }; legacy.release(va)
	assert legacy.alloc(1, 0) or { panic('legacy retry') } == va
	legacy.release(va); legacy.gc(); unsafe { legacy.allocations.free() }
	uat_mgr = unsafe { nil }
	println('AGX pressure: 128 real heap/channel cases retain pending ranges until explicit collection; legacy retry preserved')
}
