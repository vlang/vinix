// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module simple

// A render-only DRM node for the boot framebuffer.
//
// Vinix presents through /dev/fb0, so this driver intentionally has no KMS
// connectors or page flips. Its purpose is to give Mesa's kms_swrast GBM
// backend ordinary dumb GEM buffers. Aquamarine renders Hyprland into those
// buffers and copies the completed frame to the firmware framebuffer. On
// Apple Silicon it uses AGX instead and this node is a software fallback.

import drm
import drm.gem
import drm.ioctl
import klock
import lib

struct SimpleFile {
mut:
	objects      []&gem.GemObject
	mmap_objects []&gem.GemObject
	lock         klock.Lock
}

__global (
	simple_files_lock klock.Lock
	simple_files      = map[u64]&SimpleFile{}
	simple_registered = false
)

fn get_file(handle voidptr) ?&SimpleFile {
	if handle == unsafe { nil } {
		return none
	}
	key := u64(handle)
	simple_files_lock.acquire()
	if key in simple_files {
		file := simple_files[key] or {
			simple_files_lock.release()
			return none
		}
		simple_files_lock.release()
		return file
	}
	mut file := &SimpleFile{}
	simple_files[key] = file
	simple_files_lock.release()
	return file
}

fn owned_object(mut file SimpleFile, handle u32) ?&gem.GemObject {
	for obj in file.objects {
		if obj.handle == handle {
			return obj
		}
	}
	return none
}

fn close_object(mut file SimpleFile, handle u32) int {
	file.lock.acquire()
	for index, obj in file.objects {
		if obj.handle == handle {
			file.objects.delete(index)
			file.lock.release()
			gem.unref(obj)
			return 0
		}
	}
	file.lock.release()
	return -2 // ENOENT
}

fn create_dumb_handler(_dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	if data == unsafe { nil } {
		return -14 // EFAULT
	}
	mut request := unsafe { &ioctl.DrmModeCreateDumb(data) }
	if request.flags != 0 || request.width == 0 || request.height == 0 || request.bpp == 0
		|| request.bpp > 32 {
		return -22 // EINVAL
	}
	bytes_per_pixel := (u64(request.bpp) + 7) / 8
	row_bytes := u64(request.width) * bytes_per_pixel
	if row_bytes > u64(-1) - 63 {
		return -75 // EOVERFLOW
	}
	pitch := lib.align_up(row_bytes, 64)
	if pitch > u64(-1) / u64(request.height) {
		return -75
	}
	size := pitch * u64(request.height)
	obj := gem.create(size) or { return -12 }
	mut file := get_file(handle) or {
		gem.unref(obj)
		return -12
	}
	file.lock.acquire()
	file.objects << obj
	file.lock.release()
	request.handle = obj.handle
	request.pitch = u32(pitch)
	request.size = obj.size
	return 0
}

fn map_dumb_handler(_dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	if data == unsafe { nil } {
		return -14
	}
	mut request := unsafe { &ioctl.DrmModeMapDumb(data) }
	if request.pad != 0 {
		return -22
	}
	mut file := get_file(handle) or { return -9 }
	file.lock.acquire()
	obj := owned_object(mut file, request.handle) or {
		file.lock.release()
		return -2
	}
	mut already_authorized := false
	for mapped in file.mmap_objects {
		if mapped == obj {
			already_authorized = true
			break
		}
	}
	if !already_authorized {
		gem.ref_obj(obj)
		file.mmap_objects << obj
	}
	request.offset = gem.create_mmap_offset(obj)
	file.lock.release()
	return 0
}

fn destroy_dumb_handler(_dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	if data == unsafe { nil } {
		return -14
	}
	request := unsafe { &ioctl.DrmModeDestroyDumb(data) }
	mut file := get_file(handle) or { return -9 }
	return close_object(mut file, request.handle)
}

fn export_object(_dev &drm.DrmDevice, handle voidptr, object_handle u32) ?&gem.GemObject {
	mut file := get_file(handle) or { return none }
	file.lock.acquire()
	obj := owned_object(mut file, object_handle) or {
		file.lock.release()
		return none
	}
	gem.ref_obj(obj)
	file.lock.release()
	return obj
}

fn import_object(_dev &drm.DrmDevice, handle voidptr, obj &gem.GemObject) ?u32 {
	if obj == unsafe { nil } {
		return none
	}
	mut file := get_file(handle) or { return none }
	file.lock.acquire()
	for existing in file.objects {
		if existing == obj {
			file.lock.release()
			return existing.handle
		}
	}
	gem.ref_obj(obj)
	file.objects << obj
	file.lock.release()
	return obj.handle
}

fn close_handle(_dev &drm.DrmDevice, handle voidptr, object_handle u32) int {
	mut file := get_file(handle) or { return -9 }
	return close_object(mut file, object_handle)
}

fn mmap_object(_dev &drm.DrmDevice, handle voidptr, page u64, _flags int) voidptr {
	mut file := get_file(handle) or { return unsafe { nil } }
	file.lock.acquire()
	for obj in file.mmap_objects {
		if physical := gem.get_object_mmap_page(obj, page) {
			file.lock.release()
			return physical
		}
	}
	file.lock.release()
	return unsafe { nil }
}

fn close_file(_dev &drm.DrmDevice, handle voidptr) {
	if handle == unsafe { nil } {
		return
	}
	key := u64(handle)
	simple_files_lock.acquire()
	mut file := simple_files[key] or {
		simple_files_lock.release()
		return
	}
	simple_files.delete(key)
	simple_files_lock.release()

	file.lock.acquire()
	objects := file.objects.clone()
	mapped := file.mmap_objects.clone()
	file.objects.clear()
	file.mmap_objects.clear()
	file.lock.release()
	for obj in objects {
		gem.unref(obj)
	}
	for obj in mapped {
		gem.unref(obj)
	}
	unsafe { free(voidptr(file)) }
}

// Multiple firmware framebuffers share one allocator.
pub fn register() {
	if simple_registered {
		return
	}
	simple_registered = true
	mut driver := &drm.DrmDriver{
		name: 'vinix-dumb'
		desc: 'Vinix framebuffer dumb-buffer allocator'
		major: 1
		minor: 0
		patchlevel: 0
		features: drm.driver_gem | drm.driver_dumb_buffer
		ioctls: [
			drm.DrmIoctl{ cmd: ioctl.drm_ioctl_mode_create_dumb, handler: create_dumb_handler },
			drm.DrmIoctl{ cmd: ioctl.drm_ioctl_mode_map_dumb, handler: map_dumb_handler },
			drm.DrmIoctl{ cmd: ioctl.drm_ioctl_mode_destroy_dumb, handler: destroy_dumb_handler },
		]
		file_close: close_file
		gem_close: close_handle
		gem_export: export_object
		gem_import: import_object
		mmap: mmap_object
	}
	drm.register_driver(driver) or {
		simple_registered = false
		println('simpledrm: failed to register dumb-buffer allocator')
		return
	}
	println('simpledrm: software GBM allocator ready')
}
