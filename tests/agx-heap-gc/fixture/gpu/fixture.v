@[has_globals]
module gpu

import gpu.agx.alloc
import gpu.agx.channel
import gpu.agx.fw
import gpu.agx.hw
import klock
import aarch64.timer

#include <sanitizer/asan_interface.h>
fn C.__asan_address_is_poisoned(voidptr) int

pub enum GpuState { idle starting running error stopped }
pub struct GpuManager {
mut:
	state GpuState
	hw_config hw.HwConfig
	channels GpuChannels
	lock klock.Lock
	g13_private alloc.HeapAllocator
	g13_gpu_readonly alloc.HeapAllocator
	mode int
	doorbells int
	late_va u64
	late_ro_va u64
	acknowledged bool
}
struct GpuChannels { mut: device_ctrl channel.TxChannel }

__global active = unsafe { &GpuManager(nil) }

const device_control_bad_write = 17
const device_control_bad_read = 18
const device_control_latched_fault = 19
const device_control_unexpected_write = 20
const device_control_stopped = 21

fn acknowledge() {
	mut manager := unsafe { active }
	assert manager != unsafe { nil }
	assert manager.lock.is_held()
	if manager.mode == 1 && !manager.acknowledged {
		manager.acknowledged = true
		unsafe { *&u32(manager.channels.device_ctrl.state_phys) = *&u32(manager.channels.device_ctrl.state_phys + 0x20) }
	}
	if manager.mode == 4 { manager.state = .error }
	if manager.mode == 5 { manager.channels.device_ctrl.faulted = 1 }
}

fn (mut manager GpuManager) ring_device_control() bool {
	assert manager.lock.is_held()
	manager.doorbells++
	// The release snapshots must still be reserved before acknowledgement.
	pc, _ := manager.g13_private.garbage(); rc, _ := manager.g13_gpu_readonly.garbage()
	assert pc + rc > 0
	if manager.late_va != 0 { manager.g13_private.release(manager.late_va) }
	if manager.late_ro_va != 0 { manager.g13_gpu_readonly.release(manager.late_ro_va) }
	if manager.mode == 2 {
		// A failed doorbell send can race with firmware consuming a queued
		// command after an earlier wakeup. Publication failure still wins.
		unsafe { *&u32(manager.channels.device_ctrl.state_phys) = *&u32(manager.channels.device_ctrl.state_phys + 0x20) }
		return false
	}
	if manager.mode == 0 || manager.mode >= device_control_bad_write {
		manager.acknowledged = true
		unsafe { *&u32(manager.channels.device_ctrl.state_phys) = *&u32(manager.channels.device_ctrl.state_phys + 0x20) }
	}
	if manager.mode >= device_control_bad_write {
		mut header := unsafe { &channel.RingHeader(manager.channels.device_ctrl.state_phys) }
		match manager.mode {
			device_control_bad_write { header.write_ptr = 256 }
			device_control_bad_read { header.read_ptr = 256 }
			device_control_latched_fault { manager.channels.device_ctrl.faulted = 1 }
			device_control_unexpected_write { header.write_ptr = (header.write_ptr + 1) % 256 }
			device_control_stopped { manager.state = .stopped }
			else { panic('invalid device-control completion fixture') }
		}
	}
	return true
}

fn wire_test() {
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		message := fw.make_g13_cache_flush(abi) or { panic('supported ABI') }
		assert sizeof(message) == 0x30
		bytes := unsafe { &u8(&message) }
		context := if abi == .v12_3 { 20 } else { 17 }
		for index in 0 .. 48 {
			expected := if index == 0 { if abi == .v12_3 { u8(23) } else { u8(24) } } else if index == context || index == context + 1 { u8(255) } else { u8(0) }
			assert unsafe { bytes[index] } == expected, 'cache flush command must match every byte of the ABI'
		}
	}
	for abi in [hw.FirmwareAbi.unknown, .v12_3_partial, .g17_26_5_partial]! {
		if _ := fw.make_g13_cache_flush(abi) { assert false, 'unsupported ABI must not publish cache control' }
	}
}

fn threshold_test() {
	mut cases := 0
	for pc in [u64(0), 2048, 2049, ~u64(0)]! {
		for rc in [u64(0), 2048, 2049, ~u64(0)]! {
			for pb in [u64(0), 16_777_216, 16_777_217, ~u64(0)]! {
				for rb in [u64(0), 16_777_216, 16_777_217, ~u64(0)]! {
					// Independent boundary buckets avoid adding counts or bytes,
					// which would overflow and combine unrelated heap limits.
					expected := pc !in [u64(0), 2048]! || rc !in [u64(0), 2048]!
						|| pb !in [u64(0), 16_777_216]! || rb !in [u64(0), 16_777_216]!
					assert g13_heap_garbage_needs_collection(pc, pb, rc, rb) == expected,
						'collection thresholds must be strict and independent per heap'
					cases++
				}
			}
		}
	}
	assert cases == 256
}

fn run_case(abi hw.FirmwareAbi, mode int, initial u32, trigger int, late bool, size u64) {
	mut header := channel.RingHeader{read_ptr: initial, write_ptr: initial}
	mut ring := [256]fw.FwDeviceControlMsg{}
	mut manager := GpuManager{
		state: .running
		hw_config: hw.HwConfig{gpu_gen: if mode == 9 { .g17 } else { .g13 }, firmware_abi: if mode == 10 { .unknown } else { abi }}
		g13_private: alloc.new_heap('private', alloc.g13_private_start, alloc.g13_private_end)
		g13_gpu_readonly: alloc.new_heap('readonly', alloc.g13_gpu_readonly_start, alloc.g13_gpu_readonly_end)
		channels: GpuChannels{device_ctrl: channel.new_tx_channel('control', 1, u64(&header), 1, u64(&ring), 256, 48)}
		mode: mode
	}
	active = unsafe { &manager }
	timer.on_tick(acknowledge); timer.reset()
	p := manager.g13_private.alloc(if trigger == 0 { size - alloc.gpu_page_size } else { u64(1) }, 0) or { panic('private') }
	r := manager.g13_gpu_readonly.alloc(if trigger == 1 { size } else { u64(1) }, 0) or { panic('readonly') }
	pp := manager.g13_private.allocations[0]; rp := manager.g13_gpu_readonly.allocations[0]
	extra := manager.g13_private.alloc(1, 0) or { panic('second private') }
	ep := manager.g13_private.allocations[1]
	manager.late_va = manager.g13_private.alloc(1, 0) or { panic('private pin') }
	manager.late_ro_va = manager.g13_gpu_readonly.alloc(1, 0) or { panic('readonly pin') }
	pl := manager.g13_private.allocations[2]; rl := manager.g13_gpu_readonly.allocations[1]
	manager.g13_private.release(p); manager.g13_gpu_readonly.release(r)
	manager.g13_private.release(extra)
	if !late { manager.late_va = 0; manager.late_ro_va = 0 }
	if mode == 6 { header.read_ptr = (initial + 1) % 256 }
	if mode == 7 { header.write_ptr = 256 }
	if mode == 8 { manager.state = .starting }
	manager.lock.acquire()
	manager.collect_g13_heap_garbage_locked()
	triggered := size > 16_777_216
	if triggered && mode >= device_control_bad_write {
		assert C.__asan_address_is_poisoned(pp) == 0 && C.__asan_address_is_poisoned(rp) == 0,
			'faulted or stopped device-control completion must retain both heap prefixes'
		assert manager.channels.device_ctrl.has_fault() == (mode != device_control_stopped)
		assert timer.get_ns() < u64(1_000_000_000)
	}
	manager.lock.release()
	succeeded := triggered && mode in [0, 1]!
	assert (C.__asan_address_is_poisoned(pp) != 0) == succeeded
	assert (C.__asan_address_is_poisoned(rp) != 0) == succeeded,
		'only an acknowledged cache barrier may retire the captured heap prefixes'
	assert (C.__asan_address_is_poisoned(ep) != 0) == succeeded,
		'each heap must collect its own captured count'
	assert C.__asan_address_is_poisoned(pl) == 0 && C.__asan_address_is_poisoned(rl) == 0,
		'live owners and releases after the snapshot must survive collection'
	should_ring := triggered && mode !in [6, 7, 8, 9, 10]!
	assert manager.doorbells == if should_ring { 1 } else { 0 }
	if manager.doorbells > 0 {
		assert ring[initial] == fw.make_g13_cache_flush(abi) or { panic('ABI') }
	}
	mut heaps := [&manager.g13_private, &manager.g13_gpu_readonly]!
	for heap_index, mut heap in heaps {
		count, _ := heap.garbage()
		expected := if succeeded { if late { 1 } else { 0 } } else { 1 + if heap_index == 0 { 1 } else { 0 } + if late && should_ring { 1 } else { 0 } }
		assert count == u64(expected),
			'collection must use pre-barrier counts and preserve failures'
		for record in heap.allocations { if record.in_use { heap.release(record.va) } }
		heap.gc(); unsafe { heap.allocations.free() }
	}
	active = unsafe { nil }
	timer.on_tick(fn () {})
}

pub fn check_heap_gc() {
	wire_test(); threshold_test()
	mut cases := 0
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		for initial in [u32(0), 254, 255]! {
			for mode in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, device_control_bad_write, device_control_bad_read,
				device_control_latched_fault, device_control_unexpected_write, device_control_stopped]! {
				for trigger in 0 .. 2 {
					for late in [false, true]! {
						for size in [u64(16_777_216), 16_793_600]! {
							run_case(abi, mode, initial, trigger, late, size); cases++
						}
					}
				}
			}
		}
	}
	assert cases == 768
	println('AGX heap GC: exact 48-byte cache commands for both ABIs, 256 threshold boundaries and 768 heap/channel barrier cases pass')
}
