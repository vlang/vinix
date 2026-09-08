// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module fake

// A deliberately software-only AGX address space for exercising the G17 DRM
// path in a VM. This module owns GEM references and translates fake GPU VAs to
// CPU mappings; it has no dependency on DART, UAT, PMP, RTKit, MMIO, or the
// native AGX global manager.

import drm.gem
import gpu.agx.vm as agxvm
import klock

pub const vm_page_size = agxvm.page_size
pub const vm_page_mask = agxvm.page_mask
pub const vm_user_start = agxvm.user_start
pub const vm_user_end = agxvm.user_end
pub const vm_kernel_min_size = agxvm.kernel_min_size

pub const vm_read = u32(1) << 0
pub const vm_write = u32(1) << 1

pub struct FakeG17VmMapping {
pub:
	address       u64
	size          u64
	object_offset u64
	flags         u32
	object_handle u32
mut:
	object &gem.GemObject = unsafe { nil }
}

// A resolved range retains its own GEM reference so an ioctl can safely drop
// the VM lock before reading or writing the CPU mapping.
pub struct FakeG17ResolvedRange {
pub:
	gpu_address u64
	cpu_address u64
	size        u64
	object      &gem.GemObject = unsafe { nil }
}

pub fn (range &FakeG17ResolvedRange) release() {
	gem.unref(range.object)
}

@[heap]
pub struct FakeG17Vm {
pub:
	id           u32
	kernel_start u64
	kernel_end   u64
mut:
	mappings []FakeG17VmMapping
	lock     klock.Lock
}

pub fn new_vm(id u32, kernel_start u64, kernel_end u64) ?&FakeG17Vm {
	if id == 0 || !agxvm.valid_window(kernel_start, kernel_end) {
		return none
	}
	return &FakeG17Vm{
		id: id
		kernel_start: kernel_start
		kernel_end: kernel_end
	}
}

fn ranges_overlap(first_address u64, first_size u64, second_address u64,
	second_size u64) bool {
	return first_address < second_address + second_size
		&& second_address < first_address + first_size
}

// USC base values identify a VM region, not necessarily a BO-backed byte.
pub fn (vm &FakeG17Vm) contains_address(address u64) bool {
	return address >= vm_user_start && address < vm_user_end
		&& (address < vm.kernel_start || address >= vm.kernel_end)
}

// Bind one complete, non-overlapping VA range. The VM takes an independent
// GEM reference on success.
pub fn (mut vm FakeG17Vm) bind(object &gem.GemObject, address u64, size u64,
	object_offset u64, flags u32) int {
	if object == unsafe { nil } || flags == 0 || flags & ~(vm_read | vm_write) != 0
		|| !agxvm.valid_user_range(address, size, vm.kernel_start, vm.kernel_end)
		|| object_offset & vm_page_mask != 0
		|| object_offset > object.size || size > object.size - object_offset {
		return -22 // EINVAL
	}
	vm.lock.acquire()
	for mapping in vm.mappings {
		if ranges_overlap(mapping.address, mapping.size, address, size) {
			vm.lock.release()
			return -16 // EBUSY
		}
	}
	gem.ref_obj(object)
	vm.mappings << FakeG17VmMapping{
		address: address
		size: size
		object_offset: object_offset
		flags: flags
		object_handle: object.handle
		object: unsafe { object }
	}
	vm.lock.release()
	return 0
}

pub fn (mut vm FakeG17Vm) unbind(address u64, size u64) int {
	if !agxvm.valid_user_range(address, size, vm.kernel_start, vm.kernel_end) {
		return -22
	}
	vm.lock.acquire()
	for index, mapping in vm.mappings {
		if mapping.address == address && mapping.size == size {
			vm.mappings.delete(index)
			vm.lock.release()
			gem.unref(mapping.object)
			return 0
		}
	}
	vm.lock.release()
	return -22
}

pub fn (mut vm FakeG17Vm) unbind_object(object &gem.GemObject) int {
	if object == unsafe { nil } {
		return -22
	}
	vm.lock.acquire()
	mut removed := []&gem.GemObject{}
	for index := vm.mappings.len - 1; index >= 0; index-- {
		mapping := vm.mappings[index]
		if voidptr(mapping.object) == voidptr(object) {
			removed << mapping.object
			vm.mappings.delete(index)
		}
	}
	vm.lock.release()
	for mapped_object in removed {
		gem.unref(mapped_object)
	}
	return 0
}

// Resolve a range wholly contained in one binding and retain the BO until the
// caller invokes release(). Writable resolution enforces the binding mode.
pub fn (mut vm FakeG17Vm) resolve(address u64, size u64,
	writable bool) ?FakeG17ResolvedRange {
	if size == 0 || address > ~u64(0) - size {
		return none
	}
	vm.lock.acquire()
	for mapping in vm.mappings {
		if address < mapping.address || address - mapping.address > mapping.size
			|| size > mapping.size - (address - mapping.address)
			|| (writable && mapping.flags & vm_write == 0) {
			continue
		}
		offset := mapping.object_offset + address - mapping.address
		if offset > mapping.object.size || size > mapping.object.size - offset
			|| mapping.object.virt_addr > ~u64(0) - offset {
			vm.lock.release()
			return none
		}
		gem.ref_obj(mapping.object)
		resolved := FakeG17ResolvedRange{
			gpu_address: address
			cpu_address: mapping.object.virt_addr + offset
			size: size
			object: mapping.object
		}
		vm.lock.release()
		return resolved
	}
	vm.lock.release()
	return none
}

pub fn (mut vm FakeG17Vm) address_ranges() []FakeG17AddressRange {
	vm.lock.acquire()
	mut ranges := []FakeG17AddressRange{cap: vm.mappings.len}
	for mapping in vm.mappings {
		ranges << FakeG17AddressRange{
			address: mapping.address
			size: mapping.size
			access: mapping.flags
			object_handle: mapping.object_handle
		}
	}
	vm.lock.release()
	return ranges
}

pub fn (mut vm FakeG17Vm) has_mappings() bool {
	vm.lock.acquire()
	present := vm.mappings.len != 0
	vm.lock.release()
	return present
}

pub fn (mut vm FakeG17Vm) destroy() {
	vm.lock.acquire()
	mut objects := []&gem.GemObject{cap: vm.mappings.len}
	for mapping in vm.mappings {
		objects << mapping.object
	}
	vm.mappings.clear()
	vm.lock.release()
	for object in objects {
		gem.unref(object)
	}
}
