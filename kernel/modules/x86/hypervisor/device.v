// SPDX-License-Identifier: GPL-2.0-only
// Userspace interface for small VT-x virtual machines.
@[has_globals]
module hypervisor

import errno
import event.eventstruct
import fs
import katomic
import klock
import memory
import resource
import stat
import usercopy

pub const api_version = 1
pub const ioctl_get_api_version = u64(0x48560000)
pub const ioctl_create_vm = u64(0x48560001)
pub const ioctl_set_registers = u64(0x48560002)
pub const ioctl_get_registers = u64(0x48560003)
pub const ioctl_set_entry = u64(0x48560004)
pub const ioctl_get_entry = u64(0x48560005)
pub const ioctl_run = u64(0x48560006)
pub const ioctl_advance_rip = u64(0x48560007)

struct CreateRequest {
mut:
	memory_size u64
}

struct EntryRequest {
mut:
	rip    u64
	rsp    u64
	rflags u64
}

struct RunResult {
mut:
	reason             u32
	instruction_length u32
	qualification      u64
	interruption_info  u32
	reserved           u32
}

struct HypervisorDevice {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

struct HypervisorSession {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
	vm       &Vm = unsafe { nil }
}

__global (
	hypervisor_device = &HypervisorDevice(unsafe { nil })
)

fn reject_read(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn reject_write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn (mut device HypervisorDevice) open(_flags int) ?&resource.Resource {
	mut session := &HypervisorSession{
		can_mmap: true
	}
	// The opened session behaves like a seekable block of guest memory even
	// though the factory node itself is a character device.
	session.stat.mode = stat.ifblk | 0o600
	session.stat.blksize = int(page_size)
	return &resource.Resource(*session)
}

fn (mut device HypervisorDevice) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return reject_read(handle, buf, loc, count)
}

fn (mut device HypervisorDevice) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return reject_write(handle, buf, loc, count)
}

fn (mut device HypervisorDevice) ioctl(_handle voidptr, request u64, _argp voidptr) ?int {
	if request == ioctl_get_api_version {
		return api_version
	}
	errno.set(errno.enotty)
	return none
}

fn (mut device HypervisorDevice) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

fn (mut device HypervisorDevice) grow(_handle voidptr, _size u64) ? {
	errno.set(errno.eperm)
	return none
}

fn (mut device HypervisorDevice) unref(_handle voidptr) ? {
	katomic.dec(mut &device.refcount)
}

fn (mut device HypervisorDevice) link(_handle voidptr) ? {
	katomic.inc(mut &device.stat.nlink)
}

fn (mut device HypervisorDevice) unlink(_handle voidptr) ? {
	katomic.dec(mut &device.stat.nlink)
}

fn (mut session HypervisorSession) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if session.vm == unsafe { nil } || loc >= session.vm.memory_size() {
		return 0
	}
	remaining := session.vm.memory_size() - loc
	actual := if count < remaining { count } else { remaining }
	source := voidptr(u64(session.vm.guest_page(loc / page_size)) + memory_page_offset(loc) + memory_hhdm())
	if !usercopy.copy_to_user(u64(buf), source, actual) {
		errno.set(errno.efault)
		return none
	}
	return i64(actual)
}

fn (mut session HypervisorSession) write(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if session.vm == unsafe { nil } || loc > session.vm.memory_size()
		|| count > session.vm.memory_size() - loc {
		errno.set(errno.efbig)
		return none
	}
	if count == 0 {
		return 0
	}
	destination := voidptr(u64(session.vm.guest_page(loc / page_size)) + memory_page_offset(loc) + memory_hhdm())
	if !usercopy.copy_from_user(destination, u64(buf), count) {
		errno.set(errno.efault)
		return none
	}
	return i64(count)
}

// Kept as tiny helpers so device.v does not expose the VM's physical base.
fn memory_page_offset(address u64) u64 {
	return address & (page_size - 1)
}

fn memory_hhdm() u64 {
	return memory.get_hhdm_offset()
}

fn copy_in[T](argp voidptr, mut value T) bool {
	return argp != unsafe { nil }
		&& usercopy.copy_from_user(voidptr(value), u64(argp), sizeof(T))
}

fn copy_out[T](argp voidptr, value &T) bool {
	return argp != unsafe { nil }
		&& usercopy.copy_to_user(u64(argp), voidptr(value), sizeof(T))
}

fn (mut session HypervisorSession) ioctl(_handle voidptr, request u64, argp voidptr) ?int {
	if request == ioctl_get_api_version {
		return api_version
	}
	if request == ioctl_create_vm {
		if session.vm != unsafe { nil } {
			errno.set(errno.ebusy)
			return none
		}
		mut create_request := CreateRequest{}
		if !copy_in(argp, mut create_request) {
			errno.set(errno.efault)
			return none
		}
		if create_request.memory_size == 0 || create_request.memory_size > max_guest_memory {
			errno.set(errno.einval)
			return none
		}
		session.vm = create(create_request.memory_size) or {
			errno.set(errno.enomem)
			return none
		}
		session.stat.size = session.vm.memory_size()
		return 0
	}
	if session.vm == unsafe { nil } {
		errno.set(errno.enodev)
		return none
	}

	match request {
		ioctl_set_registers {
			mut registers := Registers{}
			if !copy_in(argp, mut registers) {
				errno.set(errno.efault)
				return none
			}
			if !session.vm.set_registers(registers) {
				errno.set(errno.eio)
				return none
			}
			return 0
		}
		ioctl_get_registers {
			registers := session.vm.get_registers() or {
				errno.set(errno.eio)
				return none
			}
			if !copy_out(argp, &registers) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl_set_entry {
			mut entry := EntryRequest{}
			if !copy_in(argp, mut entry) {
				errno.set(errno.efault)
				return none
			}
			if !session.vm.set_entry(entry.rip, entry.rsp, entry.rflags) {
				errno.set(errno.einval)
				return none
			}
			return 0
		}
		ioctl_get_entry {
			rip, rsp, rflags := session.vm.get_entry() or {
				errno.set(errno.eio)
				return none
			}
			entry := EntryRequest{ rip: rip, rsp: rsp, rflags: rflags }
			if !copy_out(argp, &entry) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl_run {
			exit := session.vm.run() or {
				errno.set(errno.eio)
				return none
			}
			result := RunResult{
				reason: exit.reason
				instruction_length: exit.instruction_length
				qualification: exit.qualification
				interruption_info: exit.interruption_info
			}
			if !copy_out(argp, &result) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl_advance_rip {
			mut length := u32(0)
			if !copy_in(argp, mut length) {
				errno.set(errno.efault)
				return none
			}
			if !session.vm.advance_rip(length) {
				errno.set(errno.eio)
				return none
			}
			return 0
		}
		else {
			errno.set(errno.enotty)
			return none
		}
	}
}

fn (mut session HypervisorSession) mmap(_handle voidptr, page u64, _flags int) voidptr {
	if session.vm == unsafe { nil } {
		return unsafe { nil }
	}
	return session.vm.guest_page(page)
}

fn (mut session HypervisorSession) grow(_handle voidptr, _size u64) ? {
	errno.set(errno.eperm)
	return none
}

fn (mut session HypervisorSession) unref(_handle voidptr) ? {
	if katomic.dec(mut &session.refcount) {
		return
	}
	if session.vm != unsafe { nil } {
		session.vm.destroy()
		unsafe { free(session.vm) }
	}
	destroy_session(session)
}

fn destroy_session(session &HypervisorSession) {
	unsafe { free(session) }
}

fn (mut session HypervisorSession) link(_handle voidptr) ? {
	katomic.inc(mut &session.stat.nlink)
}

fn (mut session HypervisorSession) unlink(_handle voidptr) ? {
	katomic.dec(mut &session.stat.nlink)
}

fn smoke_test() bool {
	mut vm := create(0x10000) or { return false }
	defer {
		vm.destroy()
		unsafe { free(vm) }
	}
	// mov dx, 0xe9; mov al, 'V'; out dx, al; hlt
	code := [u8(0xba), 0xe9, 0x00, 0xb0, 0x56, 0xee, 0xf4]
	if !vm.copy_to_guest(0x1000, unsafe { &code[0] }, u64(code.len))
		|| !vm.set_entry(0x1000, 0x8000, 2) {
		return false
	}
	first := vm.run() or { return false }
	registers := vm.get_registers() or { return false }
	if first.reason != 30 || first.instruction_length != 1
		|| u16(first.qualification >> 16) != 0xe9 || u8(registers.rax) != 0x56 {
		return false
	}
	if !vm.advance_rip(first.instruction_length) {
		return false
	}
	second := vm.run() or { return false }
	return second.reason == 12
}

// initialise validates one complete guest entry/exit before publishing the
// device. A faulty or incomplete VMX implementation is never exposed to EL0.
pub fn initialise() {
	if hypervisor_device != unsafe { nil } || !available() {
		return
	}
	if !smoke_test() {
		println('hypervisor: VMX self-test failed; device not registered')
		return
	}
	mut device := &HypervisorDevice{}
	device.stat.mode = stat.ifchr | 0o600
	device.stat.blksize = int(page_size)
	device.stat.rdev = resource.create_dev_id()
	hypervisor_device = device
	fs.devtmpfs_add_device(device, 'hypervisor')
	println('hypervisor: /dev/hypervisor ready')
}
