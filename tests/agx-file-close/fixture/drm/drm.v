@[has_globals]
module drm

import drm.gem
import drm.ioctl

pub struct DrmDriver {
pub:
	ioctls []DrmIoctl
	ioctl_abi fn (&DrmDevice, voidptr) u32 = unsafe { nil }
	gem_close fn (&DrmDevice, voidptr, u32) int = unsafe { nil }
	gem_close_request fn (&DrmDevice, voidptr, &ioctl.DrmGemClose) int = unsafe { nil }
	gem_export fn (&DrmDevice, voidptr, u32) ?&gem.GemObject = unsafe { nil }
	gem_export_put fn (&DrmDevice, &gem.GemObject) = unsafe { nil }
	mmap_attributes fn (&DrmDevice, voidptr, u64) u64 = unsafe { nil }
	mmap fn (&DrmDevice, voidptr, u64, int) voidptr = unsafe { nil }
	mmap_admit fn (&DrmDevice, voidptr, u64, u64, bool) int = unsafe { nil }
	mmap_no_expand bool
	mmap_retain fn (&DrmDevice, voidptr, u64, u64) bool = unsafe { nil }
	mmap_release fn (&DrmDevice, voidptr, u64, u64) = unsafe { nil }
}

pub struct DrmDevice {
pub:
	driver &DrmDriver = unsafe { nil }
	driver_data voidptr
pub mut:
	registered bool = true
}

pub fn (dev &DrmDevice) is_registered() bool { return dev.registered }

pub struct MemoryStats {
pub:
	shared    u64
	private   u64
	resident  u64
	purgeable u64
	active    u64
	supported u32
}

pub const memory_stats_resident = u32(1)
