module uacpi

import klock
import x86.kio
import memory
import lib
import kprint
import lib.stubs
// Aliased: the hpet module also has a global named `hpet`, and V3 resolves
// `hpet.nanoseconds()` against the variable in a -prod build.
import x86.hpet as hpet_clock
import pci
import acpisync

pub enum UACPIStatus {
	ok                      = 0
	mapping_failed          = 1
	out_of_memory           = 2
	bad_checksum            = 3
	invalid_signature       = 4
	invalid_table_length    = 5
	not_found               = 6
	invalid_argument        = 7
	unimplemented           = 8
	already_exists          = 9
	internal_error          = 10
	type_mismatch           = 11
	init_level_mismatch     = 12
	namespace_node_dangling = 13
	no_handler              = 14
	no_resource_end_tag     = 15
	compiled_out            = 16
	hardware_timeout        = 17
	timeout                 = 18
	overridden              = 19
	denied                  = 20
}

pub enum InterruptModel {
	pic     = 0
	ioapic  = 1
	iosapic = 2
}

@[c_extern]
fn C.uacpi_initialize(flags u64) UACPIStatus
@[c_extern]
fn C.uacpi_namespace_load() UACPIStatus
@[c_extern]
fn C.uacpi_namespace_initialize() UACPIStatus
@[c_extern]
fn C.uacpi_set_interrupt_model(InterruptModel) UACPIStatus
@[c_extern]
fn C.uacpi_status_to_string(UACPIStatus) charptr
@[c_extern]
fn C.uacpi_prepare_for_sleep_state(state int) UACPIStatus
@[c_extern]
fn C.uacpi_enter_sleep_state(state int) UACPIStatus
@[c_extern]
fn C.uacpi_reboot() UACPIStatus

// UACPI_SLEEP_STATE_S5, soft off.
const sleep_state_s5 = 5

// Turn the machine off through ACPI's S5 state. Returns only if that failed.
pub fn power_off() {
	if C.uacpi_prepare_for_sleep_state(sleep_state_s5) != .ok {
		return
	}
	asm volatile amd64 {
		cli
	}
	C.uacpi_enter_sleep_state(sleep_state_s5)
	asm volatile amd64 {
		sti
	}
}

// Reset the machine through the FADT reset register, then through the
// keyboard controller, which every PC and every PC emulator has. Returns only
// if neither did anything.
pub fn reboot() {
	C.uacpi_reboot()
	kio.port_out[u8](0x64, 0xfe)
}

@[export: 'uacpi_kernel_log']
pub fn uacpi_kernel_log(level int, str charptr) {
	kprint.kwrite(str, stubs.strlen(str))
}

@[export: 'uacpi_kernel_get_rsdp']
pub fn uacpi_kernel_get_rsdp(phys &u64) UACPIStatus {
	unsafe {
		*phys = u64(rsdp) - higher_half
	}
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
	return unsafe { UACPIStatus(acpisync.wait(handle, timeout)) }
}

@[export: 'uacpi_kernel_release_mutex']
pub fn uacpi_kernel_release_mutex(handle voidptr) {
	if !acpisync.signal(handle) {
		C.kprintf(c'uacpi: rejected mutex release by a non-owner\n')
	}
}

@[export: 'uacpi_kernel_create_mutex']
pub fn uacpi_kernel_create_mutex() voidptr {
	return acpisync.create(true)
}

@[export: 'uacpi_kernel_free_mutex']
pub fn uacpi_kernel_free_mutex(handle voidptr) {
	if !acpisync.destroy(handle) {
		C.kprintf(c'uacpi: refused to destroy an active mutex\n')
	}
}

@[export: 'uacpi_kernel_create_event']
pub fn uacpi_kernel_create_event() voidptr {
	return acpisync.create(false)
}

@[export: 'uacpi_kernel_free_event']
pub fn uacpi_kernel_free_event(handle voidptr) {
	if !acpisync.destroy(handle) {
		C.kprintf(c'uacpi: refused to destroy an active event\n')
	}
}

@[export: 'uacpi_kernel_signal_event']
pub fn uacpi_kernel_signal_event(handle voidptr) {
	acpisync.signal(handle)
}

@[export: 'uacpi_kernel_wait_for_event']
pub fn uacpi_kernel_wait_for_event(handle voidptr, timeout u16) bool {
	return acpisync.wait(handle, timeout) == 0
}

@[export: 'uacpi_kernel_reset_event']
pub fn uacpi_kernel_reset_event(handle voidptr) {
	acpisync.reset(handle)
}

@[export: 'uacpi_kernel_stall']
pub fn uacpi_kernel_stall(usec u8) {
	started := hpet_clock.nanoseconds()
	for hpet_clock.nanoseconds() - started < u64(usec) * 1000 {
		klock.spin_hint()
	}
}

@[export: 'uacpi_kernel_sleep']
pub fn uacpi_kernel_sleep(msec u64) {
	acpisync.sleep(msec)
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
pub fn uacpi_kernel_schedule_work(work_type int, work_handler voidptr, handle voidptr) UACPIStatus {
	return UACPIStatus.unimplemented
}

@[export: 'uacpi_kernel_wait_for_work_completion']
pub fn uacpi_kernel_wait_for_work_completion() UACPIStatus {
	return UACPIStatus.unimplemented
}

@[export: 'uacpi_kernel_install_interrupt_handler']
pub fn uacpi_kernel_install_interrupt_handler(irq u32, interrupt_handler voidptr,
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
	aligned_len := lib.align_up(len, memory.kernel_page_size)

	for i := u64(0); i < aligned_len; i += memory.kernel_page_size {
		kernel_pagemap.map_page(higher_half + phys + i, phys + i, memory.pte_present | memory.pte_noexec | memory.pte_writable) or {
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
	return hpet_clock.nanoseconds()
}

@[export: 'uacpi_kernel_io_map']
pub fn uacpi_kernel_io_map(base u64, len u64, out_handle &voidptr) UACPIStatus {
	unsafe {
		*out_handle = voidptr(base)
	}
	return UACPIStatus.ok
}

@[export: 'uacpi_kernel_io_unmap']
pub fn uacpi_kernel_io_unmap(handle voidptr) {
}

@[export: 'uacpi_kernel_io_read8']
pub fn uacpi_kernel_io_read8(handle voidptr, offset u64, out_value &u8) UACPIStatus {
	unsafe {
		*out_value = kio.port_in[u8](u16(u64(handle) + offset))
	}
	return UACPIStatus.ok
}

@[export: 'uacpi_kernel_io_read16']
pub fn uacpi_kernel_io_read16(handle voidptr, offset u64, out_value &u16) UACPIStatus {
	unsafe {
		*out_value = kio.port_in[u16](u16(u64(handle) + offset))
	}
	return UACPIStatus.ok
}

@[export: 'uacpi_kernel_io_read32']
pub fn uacpi_kernel_io_read32(handle voidptr, offset u64, out_value &u32) UACPIStatus {
	unsafe {
		*out_value = kio.port_in[u32](u16(u64(handle) + offset))
	}
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
	return voidptr(acpisync.thread_id())
}

struct UACPIPCIAddress {
	segment  u16
	bus      u8
	device   u8
	function u8
}

@[export: 'uacpi_kernel_pci_device_open']
pub fn uacpi_kernel_pci_device_open(addr UACPIPCIAddress, out_handle &voidptr) UACPIStatus {
	if out_handle == unsafe { nil } || addr.device > 31 || addr.function > 7 {
		return UACPIStatus.invalid_argument
	}
	if addr.segment != 0 {
		return UACPIStatus.not_found
	}
	mut pci_device := pci.get_device_by_coordinates(addr.bus, addr.device, addr.function,
		0) or { return UACPIStatus.not_found }
	unsafe {
		*out_handle = voidptr(pci_device)
	}
	return UACPIStatus.ok
}

@[export: 'uacpi_kernel_pci_device_close']
pub fn uacpi_kernel_pci_device_close(handle voidptr) {
}

fn pci_config_status(status int) UACPIStatus {
	return match status {
		pci.config_ok { UACPIStatus.ok }
		pci.config_bad_register { UACPIStatus.invalid_argument }
		else { UACPIStatus.not_found }
	}
}

@[export: 'uacpi_kernel_pci_read8']
pub fn uacpi_kernel_pci_read8(handle voidptr, offset u64, value &u8) UACPIStatus {
	if handle == unsafe { nil } || value == unsafe { nil } {
		return UACPIStatus.invalid_argument
	}
	pci_device := unsafe { &pci.PCIDevice(handle) }
	mut result := u32(0)
	status := pci_device.config_read(offset, 1, unsafe { &result })
	if status == pci.config_ok {
		unsafe { *value = u8(result) }
	}
	return pci_config_status(status)
}

@[export: 'uacpi_kernel_pci_read16']
pub fn uacpi_kernel_pci_read16(handle voidptr, offset u64, value &u16) UACPIStatus {
	if handle == unsafe { nil } || value == unsafe { nil } {
		return UACPIStatus.invalid_argument
	}
	pci_device := unsafe { &pci.PCIDevice(handle) }
	mut result := u32(0)
	status := pci_device.config_read(offset, 2, unsafe { &result })
	if status == pci.config_ok {
		unsafe { *value = u16(result) }
	}
	return pci_config_status(status)
}

@[export: 'uacpi_kernel_pci_read32']
pub fn uacpi_kernel_pci_read32(handle voidptr, offset u64, value &u32) UACPIStatus {
	if handle == unsafe { nil } || value == unsafe { nil } {
		return UACPIStatus.invalid_argument
	}
	pci_device := unsafe { &pci.PCIDevice(handle) }
	mut result := u32(0)
	status := pci_device.config_read(offset, 4, unsafe { &result })
	if status == pci.config_ok {
		unsafe { *value = u32(result) }
	}
	return pci_config_status(status)
}

@[export: 'uacpi_kernel_pci_write8']
pub fn uacpi_kernel_pci_write8(handle voidptr, offset u64, value u8) UACPIStatus {
	if handle == unsafe { nil } {
		return UACPIStatus.invalid_argument
	}
	pci_device := unsafe { &pci.PCIDevice(handle) }
	return pci_config_status(pci_device.config_write(offset, 1, u32(value)))
}

@[export: 'uacpi_kernel_pci_write16']
pub fn uacpi_kernel_pci_write16(handle voidptr, offset u64, value u16) UACPIStatus {
	if handle == unsafe { nil } {
		return UACPIStatus.invalid_argument
	}
	pci_device := unsafe { &pci.PCIDevice(handle) }
	return pci_config_status(pci_device.config_write(offset, 2, u32(value)))
}

@[export: 'uacpi_kernel_pci_write32']
pub fn uacpi_kernel_pci_write32(handle voidptr, offset u64, value u32) UACPIStatus {
	if handle == unsafe { nil } {
		return UACPIStatus.invalid_argument
	}
	pci_device := unsafe { &pci.PCIDevice(handle) }
	return pci_config_status(pci_device.config_write(offset, 4, u32(value)))
}
