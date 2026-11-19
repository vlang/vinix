// SPDX-License-Identifier: GPL-2.0-or-later
module driver

import drm.gem
import fs
import gpu.agx.gpu
import lib

// Asahi's agx_stats and gpu_memory, in the directory Linux gives the GPU's
// platform device: /sys/devices/platform/soc/<base>.gpu, 206400000.gpu on M1.
fn (mut driver AgxDriver) publish_sysfs(mgr &gpu.GpuManager) {
	if mgr.hw_config.gpu_gen != .g13 || mgr.hw_config.gpu_mmio_base == 0 { return }
	mut path := lib.new_text(48)
	path.add('devices/platform/soc/')
	path.add_radix(mgr.hw_config.gpu_mmio_base, 16, 0)
	path.add('.gpu')
	directory := lib.finish_text(path)
	if !fs.sysfs_directory(directory) {
		unsafe { directory.free() }
		return
	}
	stats := sysfs_child(directory, 'agx_stats')
	memory_path := sysfs_child(directory, 'gpu_memory')
	fs.sysfs_attribute(stats, 0o444, show_agx_stats, unsafe { nil }, voidptr(mgr))
	fs.sysfs_attribute(memory_path, 0o444, show_gpu_memory, unsafe { nil }, voidptr(mgr))
	unsafe {
		stats.free()
		memory_path.free()
	}
	driver.sysfs_device = directory
}

fn sysfs_child(directory string, name string) string {
	mut text := lib.new_text(directory.len + name.len + 1)
	text.add(directory)
	text.add_byte(`/`)
	text.add(name)
	return lib.finish_text(text)
}

// Removal waits for any read still running, so the manager outlives them.
fn (mut driver AgxDriver) remove_sysfs() {
	if driver.sysfs_device.len == 0 { return }
	fs.sysfs_remove(driver.sysfs_device)
	unsafe { driver.sysfs_device.free() }
	driver.sysfs_device = ''
}

fn show_agx_stats(context voidptr, mut text lib.Text) {
	manager := unsafe { &gpu.GpuManager(context) }
	manager.g13_stats_text(mut text)
}

fn show_gpu_memory(context voidptr, mut text lib.Text) {
	mut manager := unsafe { &gpu.GpuManager(context) }
	manager.g13_memory_text(mut text, gem.user_committed())
}
