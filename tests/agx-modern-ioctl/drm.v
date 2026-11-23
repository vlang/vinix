module drm

import errno
import drm.ioctl

pub struct DrmIoctl {
pub:
	cmd        u32
	size       u32
	direction  u32
	handler    fn (&DrmDevice, voidptr, voidptr) int = unsafe { nil }
	flags      u32
	abi        u32
	extensible bool
}

struct DrmNode {
	dev &DrmDevice
	render bool
}

fn drm_ioctl(dev &DrmDevice, cmd u32, data voidptr, handle voidptr) int {
	if cmd == ioctl.drm_ioctl_gem_close { return ioctl_gem_close(dev, handle, data) }
	return -95
}

fn account_activity(_dev &DrmDevice, _cmd u32) {}

fn update_client_process(_ voidptr) {}

pub fn request(cmd u32, size u32, direction u32) u64 {
	return u64((direction << 30) | (size << 16) | (u32(`d`) << 8) | cmd)
}

pub fn invoke(dev &DrmDevice, handle u64, cmd u32, size u32, direction u32, data voidptr) int {
	mut node := DrmNode{ dev: unsafe { dev } }
	return node.ioctl(voidptr(handle), request(cmd, size, direction), data) or { -int(errno.get()) }
}

pub fn admit_mapping(dev &DrmDevice, handle voidptr, offset u64, length u64, flags int) int {
	mut node := DrmNode{dev: unsafe { dev }}
	mut request := MappingAdmission{flags: flags}
	return if node.admit_mapping_range(handle, offset, length, mut request) { 0 } else { -int(errno.get()) }
}

pub fn mapping_can_grow(dev &DrmDevice) bool {
	mut node := DrmNode{dev: unsafe { dev }}
	return node.mapping_can_grow()
}

pub fn retain_mapping(dev &DrmDevice, handle voidptr, offset u64, length u64) bool {
	mut node := DrmNode{dev: unsafe { dev }}
	return node.retain_mapping_range(handle, offset, length, 0)
}

pub fn release_mapping(dev &DrmDevice, handle voidptr, offset u64, length u64) {
	mut node := DrmNode{dev: unsafe { dev }}
	node.release_mapping_range(handle, offset, length, 0)
}
