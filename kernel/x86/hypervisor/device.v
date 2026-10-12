// SPDX-License-Identifier: GPL-2.0-only
// Userspace interface for small VT-x virtual machines.
@[has_globals]
module hypervisor

import errno
import dev.serial
import event.eventstruct
import fs
import katomic
import klock
import memory.mmap
import resource
import stat
import usercopy
import x86.cpu

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
	creating bool
	deferred bool
	// The interface box its descriptors share, freed with the session.
	box &resource.Resource = unsafe { nil }
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
	} @[freed]
	// The opened session behaves like a seekable block of guest memory even
	// though the factory node itself is a character device.
	session.stat.mode = stat.ifblk | 0o600
	session.stat.blksize = int(page_size)
	// Box the session itself, not a copy of it, which left this allocation
	// behind. unref() frees both.
	session.box = &resource.Resource(unsafe { session }) @[freed]
	return session.box
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

// The syscall's handle or mapping retains this session until the operation
// completes. Acquire publication under the same lock used by CREATE_VM.
fn (mut session HypervisorSession) guest_vm() &Vm {
	session.l.acquire()
	vm := session.vm
	session.l.release()
	return vm
}

fn (mut session HypervisorSession) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	vm := session.guest_vm()
	if vm == unsafe { nil } || loc >= vm.memory_size() {
		return 0
	}
	remaining := vm.memory_size() - loc
	actual := if count < remaining { count } else { remaining }
	if !vm.copy_from_guest(buf, loc, actual) {
		errno.set(errno.eio)
		return none
	}
	return i64(actual)
}

fn (mut session HypervisorSession) write(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	vm := session.guest_vm()
	if vm == unsafe { nil } || loc > vm.memory_size()
		|| count > vm.memory_size() - loc {
		errno.set(errno.efbig)
		return none
	}
	if count == 0 {
		return 0
	}
	if !vm.copy_to_guest(loc, buf, count) {
		errno.set(errno.eio)
		return none
	}
	return i64(count)
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
		mut create_request := CreateRequest{}
		if !copy_in(argp, mut create_request) {
			errno.set(errno.efault)
			return none
		}
		if create_request.memory_size == 0 || create_request.memory_size > max_guest_memory {
			errno.set(errno.einval)
			return none
		}
		// Reserve the one creation slot briefly. Holding a spinlock while
		// allocating up to 1 GiB would disable interrupts for that whole time.
		session.l.acquire()
		if session.vm != unsafe { nil } || session.creating {
			session.l.release()
			errno.set(errno.ebusy)
			return none
		}
		session.creating = true
		session.l.release()
		mut vm := create(create_request.memory_size) or {
			session.l.acquire()
			session.creating = false
			session.l.release()
			errno.set(errno.enomem)
			return none
		}
		session.l.acquire()
		session.stat.size = vm.memory_size()
		session.vm = vm
		session.creating = false
		session.l.release()
		return 0
	}
	mut vm := session.guest_vm()
	if vm == unsafe { nil } {
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
			if !vm.set_registers(registers) {
				errno.set(errno.eio)
				return none
			}
			return 0
		}
		ioctl_get_registers {
			registers := vm.get_registers() or {
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
			if !vm.set_entry(entry.rip, entry.rsp, entry.rflags) {
				errno.set(errno.einval)
				return none
			}
			return 0
		}
		ioctl_get_entry {
			rip, rsp, rflags := vm.get_entry() or {
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
			exit := vm.run() or {
				errno.set(errno.eio)
				return none
			}
			result := RunResult{
				reason:             exit.reason
				instruction_length: exit.instruction_length
				qualification:      exit.qualification
				interruption_info:  exit.interruption_info
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
			if !vm.advance_rip(length) {
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
	vm := session.guest_vm()
	if vm == unsafe { nil } {
		return unsafe { nil }
	}
	return vm.guest_page(page)
}

// Guest RAM is shared device memory, without private COW-page ownership.
// Reject private mappings rather than letting fork retain frames for which
// this resource has no private-page release callback.
fn (mut session HypervisorSession) retain_mapping_range(_handle voidptr, offset u64, length u64, flags int) bool {
	vm := session.guest_vm()
	if vm == unsafe { nil } || flags & (mmap.map_shared | mmap.map_private) != mmap.map_shared
		|| offset > vm.memory_size() || length > vm.memory_size() - offset {
		errno.set(errno.einval)
		return false
	}
	return true
}

fn (mut session HypervisorSession) release_mapping_range(_handle voidptr, _offset u64, _length u64, _flags int) {}

fn (mut session HypervisorSession) grow(_handle voidptr, _size u64) ? {
	errno.set(errno.eperm)
	return none
}

fn (mut session HypervisorSession) unref(_handle voidptr) ? {
	if katomic.dec(mut &session.refcount) {
		return
	}
	// Final unmap/close may hold a pagemap or descriptor spinlock. Hand one
	// reference to the existing maintenance reaper so poisoning/freeing a
	// large RAM tree runs outside those locks. Queueing never invokes unref.
	if !session.deferred && !cpu.interrupt_state() {
		session.deferred = true
		katomic.inc(mut &session.refcount)
		fs.release_resource_after_grace(session.box)
		return
	}
	if session.vm != unsafe { nil } {
		session.vm.destroy()
		unsafe { free(session.vm) }
	}
	destroy_session(session)
}

fn destroy_session(session &HypervisorSession) {
	unsafe {
		free(voidptr(session.box))
		free(session)
	}
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
	code := [u8(0xba), 0xe9, 0x00, 0xb0, 0x56, 0xee, 0xf4]!
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
	if hypervisor_device != unsafe { nil } {
		return
	}
	$if hv_memory_fixture ? {
		println('hypervisor: memory fixture; VM entry disabled')
		for byte in 'hypervisor: memory fixture; VM entry disabled\n' { serial.out(byte) }
	} $else {
		if !available() { return }
		if !smoke_test() {
			println('hypervisor: VMX self-test failed; device not registered')
			return
		}
	}
	mut device := &HypervisorDevice{}
	device.stat.mode = stat.ifchr | 0o600
	device.stat.blksize = int(page_size)
	device.stat.rdev = resource.create_dev_id()
	hypervisor_device = device
	fs.devtmpfs_add_device(device, 'hypervisor')
	println('hypervisor: /dev/hypervisor ready')
}
