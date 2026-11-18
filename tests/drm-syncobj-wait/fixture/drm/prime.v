// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.gem
import drm.ioctl
import errno
import file
import fs
import memory
import proc
import resource
import stat
import usercopy

const page_size = u64(4096)

struct DrmDriver {
	gem_export fn (&DrmDevice, voidptr, u32) ?&gem.GemObject
	gem_export_put fn (&DrmDevice, &gem.GemObject) = unsafe { nil }
	gem_import fn (&DrmDevice, voidptr, &gem.GemObject) ?u32
}

struct DrmDevice {
	driver &DrmDriver
}

__global prime_exported &gem.GemObject = unsafe { nil }
__global prime_export_calls = 0
__global prime_custom_puts = 0
__global prime_fd_to_close = -1

fn prime_export(_dev &DrmDevice, _handle voidptr, name u32) ?&gem.GemObject {
	file.assert_reservations(1)
	prime_export_calls++
	if prime_exported.handle != name { return none }
	gem.ref_obj(prime_exported)
	return prime_exported
}

fn prime_put(_dev &DrmDevice, object &gem.GemObject) {
	prime_custom_puts++
	gem.unref(object)
}

fn prime_import(_dev &DrmDevice, _handle voidptr, object &gem.GemObject) ?u32 {
	assert voidptr(object) == voidptr(prime_exported) && object.references == 2
	assert file.outstanding() == 1 && memory.outstanding() == 2
	return 19
}

fn close_prime_source() { file.close(prime_fd_to_close) }

fn check_prime_seek(mut descriptor file.FD, number int, size u64) {
	descriptor.handle.loc = 123
	for offset in [i64(0), 1, -1, i64(1) << 40, -i64(0x7fffffffffffffff) - 1]! {
		for whence in -1 .. fs.seek_hole + 2 {
			value, code := fs.syscall_seek(unsafe { nil }, number, offset, whence)
			if offset == 0 && (whence == fs.seek_set || whence == fs.seek_end) {
				assert code == 0 && value == if whence == fs.seek_end { size } else { u64(0) }
			} else {
				assert value == errno.err && code == errno.einval
			}
			assert descriptor.handle.loc == 123
		}
	}
	descriptor.handle.flags |= resource.o_path
	value, code := fs.syscall_seek(unsafe { nil }, number, 0, fs.seek_end)
	assert value == errno.err && code == errno.ebadf && descriptor.handle.loc == 123
	descriptor.handle.flags &= ~resource.o_path
}

fn prime_fd_ioctl(mut descriptor file.FD, request u64, address u64) int {
	mut backing := descriptor.handle.resource
	return backing.ioctl(voidptr(descriptor.handle), request, voidptr(address)) or { -int(errno.get()) }
}

fn check_prime_cpu_access(mut descriptor file.FD) {
	// The command is _IOW('b', 0, __u64), followed by exactly one flags word.
	request := u64(0x40086200)
	mut flags := u64(0)
	address := unsafe { u64(&flags) }
	for raw in 0 .. 16 {
		flags = u64(raw)
		usercopy.allow(address, sizeof(flags))
		valid := raw in [1, 2, 3, 5, 6, 7]!
		assert prime_fd_ioctl(mut descriptor, request, address) == if valid { 0 } else { -22 }
		assert flags == u64(raw) && usercopy.reads == 1 && usercopy.writes == 0
	}
	flags = (u64(1) << 63) | 1
	usercopy.allow(address, sizeof(flags))
	assert prime_fd_ioctl(mut descriptor, request, address) == -22
	assert prime_fd_ioctl(mut descriptor, request, 0) == -14
	flags = 0
	usercopy.allow(address, sizeof(flags) - 1)
	assert prime_fd_ioctl(mut descriptor, request, address) == -14 && usercopy.reads == 1

	flags = 1
	usercopy.allow(address, sizeof(flags))
	assert prime_fd_ioctl(mut descriptor, request | 0xa5a5a5a500000000, address) == 0
	usercopy.allow(address, sizeof(flags))
	for unknown in [u64(0x40046200), 0x80086200, 0x40086400, 0xc0086202]! {
		assert prime_fd_ioctl(mut descriptor, unknown, address) == -25
	}
	assert usercopy.reads == 0 && usercopy.writes == 0
	usercopy.allow(0, 0)
}

fn prime_fstat(number int) stat.Stat {
	mut metadata := stat.Stat{}
	result, code := fs.syscall_fstat(unsafe { nil }, number, unsafe { &metadata })
	assert result == 0 && code == 0
	return metadata
}

fn check_prime_inode(device &DrmDevice, object &gem.GemObject, number int) {
	first := prime_fstat(number)
	assert first.dev != 0 && first.ino != 0 && first.size == i64(object.size)
	duplicate := file.duplicate(number)
	alias := prime_fstat(duplicate)
	assert alias.dev == first.dev && alias.ino == first.ino
	file.close(duplicate)

	mut export := ioctl.DrmPrimeHandle{ handle: object.handle, fd: -1 }
	assert ioctl_prime_handle_to_fd(device, voidptr(12), &export) == 0
	assert export.fd != number
	reexport := prime_fstat(export.fd)
	assert reexport.dev == first.dev && reexport.ino == first.ino && reexport.size == first.size
	file.close(export.fd)

	// An unrelated GEM can reuse the handle while the original PRIME fd lives.
	mut replacement := gem.GemObject{handle: object.handle, size: object.size,
		mmap_offset: object.mmap_offset + object.size}
	prime_exported = unsafe { &replacement }
	assert ioctl_prime_handle_to_fd(device, voidptr(11), &export) == 0
	new_metadata := prime_fstat(export.fd)
	assert new_metadata.dev == first.dev && new_metadata.ino != first.ino && new_metadata.size == first.size
	mut ordinary := file.fd_from_fdnum(unsafe { nil }, export.fd) or { panic('ordinary PRIME fd') }
	assert prime_fd_ioctl(mut ordinary, 0x40086200, 0) == -25
	assert usercopy.reads == 0
	ordinary.unref()
	file.close(export.fd)
	assert replacement.references == 1 && object.references == 2
	assert prime_fstat(number).ino == first.ino
	prime_exported = unsafe { object }
}

fn check_prime_descriptors() {
	custom := DrmDriver{gem_export: prime_export, gem_export_put: prime_put, gem_import: prime_import}
	default_driver := DrmDriver{gem_export: prime_export, gem_import: prime_import}
	client := voidptr(11)
	mut offset := u64(0x10000000)
	for driver in [custom, default_driver]! {
		memory.reset()
		proc.reset()
		device := DrmDevice{driver: unsafe { &driver }}
		foreign := DrmDevice{driver: unsafe { &driver }}
		mut object := gem.GemObject{handle: 7, vm_private_identity: 99, size: 0x10000010000, file_scoped: true,
			mmap_offset: offset}
		offset += 2 * object.size
		prime_exported = unsafe { &object }
		mut request := ioctl.DrmPrimeHandle{handle: 7, fd: -123}
		for _ in 0 .. 200 {
			assert ioctl_prime_handle_to_fd(&device, client, &request) == -22
			assert request.fd == -123 && object.references == 1
			file.assert_reservations(0)
		}
		assert memory.attempts() == 0
		object.vm_private_identity = 0
		request.handle = 0
		calls_before := prime_export_calls
		file.fail_at(2)
		assert ioctl_prime_handle_to_fd(&device, client, &request) == -24
		request.flags = 0x80000000
		assert ioctl_prime_handle_to_fd(&device, client, &request) == -22
		assert prime_export_calls == calls_before && request.fd == -123
		file.clear_failure()
		request.flags = 0
		assert ioctl_prime_handle_to_fd(&device, client, &request) == -2
		file.assert_reservations(0)
		request.handle = 7
		for step in 0 .. 4 {
			match step {
				0, 1 { memory.fail_in(step) }
				2 { file.fail_at(1) }
				else { file.fail_at(3) }
			}
			assert ioctl_prime_handle_to_fd(&device, client, &request) == if step == 3 { -16 } else { -12 }
			assert request.fd == -123 && object.references == 1
			assert file.outstanding() == 0 && memory.outstanding() == 0
			file.assert_reservations(0)
		}
		request.flags = ioctl.drm_cloexec | ioctl.drm_rdwr
		assert ioctl_prime_handle_to_fd(&device, client, &request) == 0
		assert request.fd == 0 && object.references == 2
		file.assert_reservations(0)
		mut fd := file.fd_from_fdnum(unsafe { nil }, request.fd) or { panic('installed PRIME fd') }
		assert fd.flags & resource.o_cloexec != 0 && fd.handle.flags & resource.o_rdwr != 0
		check_prime_cpu_access(mut fd)
		check_prime_seek(mut fd, request.fd, object.size)
		fd.unref()
		check_prime_inode(&device, &object, request.fd)
		mut imported := ioctl.DrmPrimeHandle{handle: 55, flags: ~u32(0), fd: -1}
		assert ioctl_prime_fd_to_handle(&device, client, &imported) == -9
		assert imported.handle == 55
		imported.fd = request.fd
		assert ioctl_prime_fd_to_handle(&foreign, client, &imported) == -9
		assert imported.handle == 55
		other := test_eventfd(0)
		imported.fd = i32(other)
		assert ioctl_prime_fd_to_handle(&device, client, &imported) == -22
		mut other_fd := file.fd_from_fdnum(unsafe { nil }, other) or { panic('ordinary fd') }
		other_fd.handle.flags |= resource.o_path
		other_fd.unref()
		assert ioctl_prime_fd_to_handle(&device, client, &imported) == -9
		assert imported.handle == 55
		file.close(other)
		imported.fd = request.fd
		prime_fd_to_close = request.fd
		file.when_lookup(close_prime_source)
		assert ioctl_prime_fd_to_handle(&device, client, &imported) == 0
		assert imported.handle == 19 && imported.flags == ~u32(0) && object.references == 1
		assert file.outstanding() == 0 && memory.outstanding() == 0
		file.assert_reservations(0)
		prime_exported = unsafe { nil }
	}
	assert prime_custom_puts == 207
	println('DRM PRIME seek: 72 syscall cases cover size, zero, invalid seeks, O_PATH and unchanged position')
	println('DRM PRIME fstat: duplicate and re-export identities agree, distinct GEMs with reused handles differ')
	println('DRM PRIME CPU access: explicit START and END, invalid flags, copy faults and unsupported commands passed')
	println('DRM PRIME: 400 private refusals, reservation order, wrapper and fd failure cleanup, import errors and concurrent close passed')
}
