module uacpi

import klock
import event
import event.eventstruct
import time
import x86.kio
import memory
import lib
import kprint
import lib.stubs
import x86.hpet

pub enum UACPIStatus {
	ok = 0
	mapping_failed = 1
	out_of_memory = 2
	bad_checksum = 3
	invalid_signature = 4
	invalid_table_length = 5
	not_found = 6
	invalid_argument = 7
	unimplemented = 8
	already_exists = 9
	internal_error = 10
	type_mismatch = 11
	init_level_mismatch = 12
	namespace_node_dangling = 13
	no_handler = 14
	no_resource_end_tag = 15
	compiled_out = 16
	hardware_timeout = 17
	timeout = 18
	overridden = 19
	denied = 20

	aml_undefined_reference = 0x0eff0000
	aml_invalid_namestring = 0x0eff0001
	aml_object_already_exists = 0x0eff0002
	aml_invalid_opcode = 0x0eff0003
	aml_incompatible_object_type = 0x0eff0004
	aml_bad_encoding = 0x0eff0005
	aml_out_of_bounds_index = 0x0eff0006
	aml_sync_level_too_high = 0x0eff0007
	aml_invalid_resource = 0x0eff0008
	aml_loop_timeout = 0x0eff0009
	aml_call_stack_depth_limit = 0x0eff000a
}

fn C.uacpi_initialize(flags u64) UACPIStatus
fn C.uacpi_namespace_load() UACPIStatus
fn C.uacpi_status_to_string(UACPIStatus) charptr

@[export: 'uacpi_kernel_log']
pub fn uacpi_kernel_log(level int, str charptr) {
	kprint.kwrite(str, stubs.strlen(str))
}

@[export: 'uacpi_kernel_get_rsdp']
pub fn uacpi_kernel_get_rsdp(phys &u64) UACPIStatus {
	unsafe { *phys = u64(rsdp) - higher_half }
	return UACPIStatus.ok
}

@[export: 'uacpi_kernel_create_spinlock']
pub fn uacpi_kernel_create_spinlock() voidptr {
	mut l := &klock.Lock{}
	return unsafe { voidptr(l) }
}

@[export: 'uacpi_kernel_free_spinlock']
pub fn uacpi_kernel_free_spinlock(handle voidptr) {
	mut l := unsafe { &klock.Lock(handle) }
	unsafe {
		l.free()
		free(l)
	}
}

@[export: 'uacpi_kernel_lock_spinlock']
pub fn uacpi_kernel_lock_spinlock(handle voidptr) u64 {
	mut l := unsafe { &klock.Lock(handle) }
	l.acquire()
	return 0
}

@[export: 'uacpi_kernel_unlock_spinlock']
pub fn uacpi_kernel_unlock_spinlock(handle voidptr, cpu_flags u64) {
	mut l := unsafe { &klock.Lock(handle) }
	l.release()
}

@[export: 'uacpi_kernel_acquire_mutex']
pub fn uacpi_kernel_acquire_mutex(handle voidptr, timeout u16) UACPIStatus {
	return UACPIStatus.ok
}

@[export: 'uacpi_kernel_release_mutex']
pub fn uacpi_kernel_release_mutex(handle voidptr) {

}

@[export: 'uacpi_kernel_create_mutex']
pub fn uacpi_kernel_create_mutex() voidptr {
	return unsafe { malloc(1) }
}

@[export: 'uacpi_kernel_free_mutex']
pub fn uacpi_kernel_free_mutex(handle voidptr) {
	unsafe { free(handle) }
}

@[export: 'uacpi_kernel_create_event']
pub fn uacpi_kernel_create_event() voidptr {
	mut e := &eventstruct.Event{}
	return unsafe { voidptr(e) }
}

@[export: 'uacpi_kernel_free_event']
pub fn uacpi_kernel_free_event(handle voidptr) {
	mut e := unsafe { &eventstruct.Event(handle) }
	unsafe {
		e.free()
		free(e)
	}
}

@[export: 'uacpi_kernel_signal_event']
pub fn uacpi_kernel_signal_event(handle voidptr) {
	mut e := unsafe { &eventstruct.Event(handle) }
	event.trigger(mut e, false)
}

@[export: 'uacpi_kernel_wait_for_event']
pub fn uacpi_kernel_wait_for_event(handle voidptr, timeout u16) bool {
	target_time := time.TimeSpec{
		tv_sec: u64(timeout) / 1000
		tv_nsec: (u64(timeout) % 1000) * 1000000
	}
	mut timer := time.new_timer(target_time)
	defer {
		timer.disarm()
		unsafe {
			timer.free()
			free(timer)
		}
	}
	mut events := if timeout == 0xffff {
		[ unsafe { &eventstruct.Event(handle) } ]
	} else {
	    [ unsafe { &eventstruct.Event(handle) }, &timer.event ]
	}
	event.await(mut events, true) or {
		return false
	}
	return true
}

@[export: 'uacpi_kernel_reset_event']
pub fn uacpi_kernel_reset_event(handle voidptr) {

}

@[export: 'uacpi_kernel_stall']
pub fn uacpi_kernel_stall(usec u8) {
	for i := 0; i < usec; i++ {
		kio.port_in[u8](0x80)
	}
}

@[export: 'uacpi_kernel_sleep']
pub fn uacpi_kernel_sleep(msec u64) {
	target_time := time.TimeSpec{
		tv_sec: u64(msec) / 1000
		tv_nsec: (u64(msec) % 1000) * 1000000
	}
	mut timer := time.new_timer(target_time)
	defer {
		timer.disarm()
		unsafe {
			timer.free()
			free(timer)
		}
	}
	mut events := [ &timer.event ]
	event.await(mut events, true) or {}
}

@[export: 'uacpi_kernel_alloc']
pub fn uacpi_kernel_alloc(size u64) voidptr {
	return unsafe { malloc(size) }
}

@[export: 'uacpi_kernel_free']
pub fn uacpi_kernel_free(ptr voidptr) {
	unsafe { free(ptr) }
}

@[export: 'uacpi_kernel_schedule_work']
pub fn uacpi_kernel_schedule_work(
	work_type int, work_handler voidptr, handle voidptr) UACPIStatus {
	return UACPIStatus.unimplemented
}

@[export: 'uacpi_kernel_wait_for_work_completion']
pub fn uacpi_kernel_wait_for_work_completion() UACPIStatus {
	return UACPIStatus.unimplemented
}

@[export: 'uacpi_kernel_install_interrupt_handler']
pub fn uacpi_kernel_install_interrupt_handler(
	irq u32, interrupt_handler voidptr,
	ctx voidptr, out_irq_handle &voidptr) UACPIStatus {
	return UACPIStatus.ok
}

@[export: 'uacpi_kernel_uninstall_interrupt_handler']
pub fn uacpi_kernel_uninstall_interrupt_handler(interrupt_handler voidptr, irq_handle voidptr) UACPIStatus {
	return UACPIStatus.ok
}

@[export: 'uacpi_kernel_handle_firmware_request']
pub fn uacpi_kernel_handle_firmware_request(req voidptr) UACPIStatus {
	return UACPIStatus.unimplemented
}

@[export: 'uacpi_kernel_map']
pub fn uacpi_kernel_map(phys u64, len u64) voidptr {
	aligned_len := lib.align_up(len, page_size)

	for i := u64(0); i < aligned_len; i += page_size {
		kernel_pagemap.map_page(higher_half + phys + i, phys + i,
			memory.pte_present | memory.pte_noexec | memory.pte_writable) or {
				panic('uacpi_kernel_map() failure')
			}
	}

	return voidptr(higher_half + phys)
}

@[export: 'uacpi_kernel_unmap']
pub fn uacpi_kernel_unmap(addr voidptr, len u64) {

}

@[export: 'uacpi_kernel_get_nanoseconds_since_boot']
pub fn uacpi_kernel_get_nanoseconds_since_boot() u64 {
	return hpet.read_counter() * (1000000000 / hpet_frequency)
}

@[export: 'uacpi_kernel_io_map']
pub fn uacpi_kernel_io_map(base u64, len u64, out_handle &voidptr) UACPIStatus {
	unsafe { *out_handle = voidptr(base) }
	return UACPIStatus.ok
}

@[export: 'uacpi_kernel_io_unmap']
pub fn uacpi_kernel_io_unmap(handle voidptr) {

}

@[export: 'uacpi_kernel_io_read8']
pub fn uacpi_kernel_io_read8(handle voidptr, offset u64, out_value &u8) UACPIStatus {
	unsafe { *out_value = kio.port_in[u8](u16(u64(handle) + offset)) }
	return UACPIStatus.ok
}

@[export: 'uacpi_kernel_io_read16']
pub fn uacpi_kernel_io_read16(handle voidptr, offset u64, out_value &u16) UACPIStatus {
	unsafe { *out_value = kio.port_in[u16](u16(u64(handle) + offset)) }
	return UACPIStatus.ok
}

@[export: 'uacpi_kernel_io_read32']
pub fn uacpi_kernel_io_read32(handle voidptr, offset u64, out_value &u32) UACPIStatus {
	unsafe { *out_value = kio.port_in[u32](u16(u64(handle) + offset)) }
	return UACPIStatus.ok
}

@[export: 'uacpi_kernel_io_write8']
pub fn uacpi_kernel_io_write8(handle voidptr, offset u64, value u8) UACPIStatus {
	kio.port_out[u8](u16(u64(handle) + offset), value)
	return UACPIStatus.ok
}

@[export: 'uacpi_kernel_io_write16']
pub fn uacpi_kernel_io_write16(handle voidptr, offset u64, value u16) UACPIStatus {
	kio.port_out[u16](u16(u64(handle) + offset), value)
	return UACPIStatus.ok
}

@[export: 'uacpi_kernel_io_write32']
pub fn uacpi_kernel_io_write32(handle voidptr, offset u64, value u32) UACPIStatus {
	kio.port_out[u32](u16(u64(handle) + offset), value)
	return UACPIStatus.ok
}

@[export: 'uacpi_kernel_get_thread_id']
pub fn uacpi_kernel_get_thread_id() voidptr {
	return unsafe { nil }
}

struct UACPIPCIAddress {
	segment u16
	bus u8
	device u8
	function u8
}

@[export: 'uacpi_kernel_pci_device_open']
pub fn uacpi_kernel_pci_device_open(addr UACPIPCIAddress, out_handle &voidptr) UACPIStatus {
	dev := u64(addr.segment) << 32 | u64(addr.bus) << 16 | u64(addr.device) << 8 | u64(addr.function)
	unsafe { *out_handle = voidptr(dev) }
	return UACPIStatus.ok
}

@[export: 'uacpi_kernel_pci_device_close']
pub fn uacpi_kernel_pci_device_close(handle voidptr) {

}

@[export: 'uacpi_kernel_pci_read8']
pub fn uacpi_kernel_pci_read8(handle voidptr, offset u64, value &u8) UACPIStatus {
	return UACPIStatus.unimplemented
}

@[export: 'uacpi_kernel_pci_read16']
pub fn uacpi_kernel_pci_read16(handle voidptr, offset u64, value &u16) UACPIStatus {
	return UACPIStatus.unimplemented
}

@[export: 'uacpi_kernel_pci_read32']
pub fn uacpi_kernel_pci_read32(handle voidptr, offset u64, value &u32) UACPIStatus {
	return UACPIStatus.unimplemented
}

@[export: 'uacpi_kernel_pci_write8']
pub fn uacpi_kernel_pci_write8(handle voidptr, offset u64, value u8) UACPIStatus {
	return UACPIStatus.unimplemented
}

@[export: 'uacpi_kernel_pci_write16']
pub fn uacpi_kernel_pci_write16(handle voidptr, offset u64, value u16) UACPIStatus {
	return UACPIStatus.unimplemented
}

@[export: 'uacpi_kernel_pci_write32']
pub fn uacpi_kernel_pci_write32(handle voidptr, offset u64, value u32) UACPIStatus {
	return UACPIStatus.unimplemented
}
