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

fn check_prime_descriptors() {
	custom := DrmDriver{gem_export: prime_export, gem_export_put: prime_put, gem_import: prime_import}
	default_driver := DrmDriver{gem_export: prime_export, gem_import: prime_import}
	client := voidptr(11)
	for driver in [custom, default_driver]! {
		memory.reset()
		proc.reset()
		device := DrmDevice{driver: unsafe { &driver }}
		foreign := DrmDevice{driver: unsafe { &driver }}
		mut object := gem.GemObject{handle: 7, vm_private_identity: 99, size: 0x10000010000}
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
		check_prime_seek(mut fd, request.fd, object.size)
		fd.unref()
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
	assert prime_custom_puts == 205
	println('DRM PRIME seek: 72 syscall cases cover size, zero, invalid seeks, O_PATH and unchanged position')
	println('DRM PRIME: 400 private refusals, reservation order, wrapper and fd failure cleanup, import errors and concurrent close passed')
}
