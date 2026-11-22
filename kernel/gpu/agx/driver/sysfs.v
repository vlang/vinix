// SPDX-License-Identifier: GPL-2.0-or-later
module driver

import drm
import drm.gem
import fs
import gpu.agx.gpu
import lib
import time

// Linux's device-tree identity of the base M1 GPU node, gpu@206400000 in
// t8103.dtsi, which libdrm reads from the device's uevent.
const t8103_compatible = ['apple,agx-t8103', 'apple,agx-g13g']!
const gpu_sysfs_prefix = 'devices/platform/soc/'

// The directory Linux gives the GPU's platform device, named after its node's
// unit address: devices/platform/soc/206400000.gpu on M1.
fn gpu_sysfs_path(unit_address u64) string {
	mut path := lib.new_text(48)
	path.add(gpu_sysfs_prefix)
	path.add_radix(unit_address, 16, 0)
	path.add('.gpu')
	return lib.finish_text(path)
}

// The platform device's own files, beside the drm directory the DRM core made
// for its minors: Linux's uevent, modalias and subsystem link, which libdrm
// reads to describe the device, and Asahi's agx_stats and gpu_memory. The
// platform bus also lists the device by name.
fn (mut driver AgxDriver) publish_sysfs(mgr &gpu.GpuManager) {
	if mgr.hw_config.gpu_gen != .g13 || driver.unit_address == 0 { return }
	for path in driver.sysfs_entries {
		if path.len != 0 { return }
	}
	directory := gpu_sysfs_path(driver.unit_address)
	if !fs.sysfs_directory(directory) {
		unsafe { directory.free() }
		return
	}
	modalias := gpu_modalias()
	uevent := gpu_uevent(driver.unit_address, modalias)
	modalias_line := sysfs_child(modalias, '\n', '')
	uevent_path := sysfs_child(directory, '/', 'uevent')
	modalias_path := sysfs_child(directory, '/', 'modalias')
	// devices/platform/soc/206400000.gpu/subsystem -> ../../../../bus/platform
	subsystem := sysfs_child(directory, '/', 'subsystem')
	fs.sysfs_directory('bus/platform')
	stats := sysfs_child(directory, '/', 'agx_stats')
	memory_path := sysfs_child(directory, '/', 'gpu_memory')
	platform_name := unsafe { tos(directory.str + gpu_sysfs_prefix.len, directory.len - gpu_sysfs_prefix.len) }
	bus_device := sysfs_child('bus/platform/devices/', platform_name, '')
	bus_target := sysfs_child('../../../', directory, '')
	driver.sysfs_entries = [
		owned_sysfs_path(uevent_path, fs.sysfs_text(uevent_path, uevent)),
		owned_sysfs_path(modalias_path, fs.sysfs_text(modalias_path, modalias_line)),
		owned_sysfs_path(subsystem, fs.sysfs_link(subsystem, '../../../../bus/platform')),
		owned_sysfs_path(stats, fs.sysfs_attribute(stats, 0o444, show_agx_stats, unsafe { nil }, voidptr(mgr))),
		owned_sysfs_path(memory_path, fs.sysfs_attribute(memory_path, 0o444, show_gpu_memory, unsafe { nil }, voidptr(mgr))),
		owned_sysfs_path(bus_device, fs.sysfs_link(bus_device, bus_target)),
	]!
	unsafe {
		directory.free()
		modalias.free()
		uevent.free()
		modalias_line.free()
		bus_target.free()
	}
}

fn owned_sysfs_path(path string, created bool) string {
	if created { return path }
	unsafe { path.free() }
	return ''
}

// of:N<name>T<type>C<compatible>..., with Linux's "(null)" for a node that has
// no device_type.
fn gpu_modalias() string {
	mut text := lib.new_text(64)
	text.add('of:NgpuT(null)')
	for compatible in t8103_compatible {
		text.add_byte(`C`)
		text.add(compatible)
	}
	return lib.finish_text(text)
}

// DRIVER from the driver core, then of_device_uevent()'s OF_ lines and the
// modalias, as Linux writes a platform device's uevent.
fn gpu_uevent(unit_address u64, modalias string) string {
	mut text := lib.new_text(256)
	text.add('DRIVER=asahi\nOF_NAME=gpu\nOF_FULLNAME=/soc/gpu@')
	text.add_radix(unit_address, 16, 0)
	text.add_byte(`\n`)
	for index, compatible in t8103_compatible {
		text.add('OF_COMPATIBLE_')
		text.add_unsigned(u64(index))
		text.add_byte(`=`)
		text.add(compatible)
		text.add_byte(`\n`)
	}
	text.add('OF_COMPATIBLE_N=')
	text.add_unsigned(u64(t8103_compatible.len))
	text.add('\nMODALIAS=')
	text.add(modalias)
	text.add_byte(`\n`)
	return lib.finish_text(text)
}

fn sysfs_child(a string, b string, c string) string {
	mut text := lib.new_text(a.len + b.len + c.len)
	text.add(a)
	text.add(b)
	text.add(c)
	return lib.finish_text(text)
}

// Removal waits for any read still running, so the manager outlives them.
// Other owners can keep entries in the platform directory.
fn (mut driver AgxDriver) remove_sysfs() {
	for index, path in driver.sysfs_entries {
		if path.len == 0 { continue }
		fs.sysfs_remove(path)
		unsafe { path.free() }
		driver.sysfs_entries[index] = ''
	}
}

fn show_agx_stats(context voidptr, mut text lib.Text) {
	manager := unsafe { &gpu.GpuManager(context) }
	manager.g13_stats_text(mut text)
}

fn show_gpu_memory(context voidptr, mut text lib.Text) {
	mut manager := unsafe { &gpu.GpuManager(context) }
	manager.g13_memory_text(mut text, gem.user_committed())
}

// Asahi's raw firmware statistics, asahi_stats in the DRM device's debugfs
// directory, which Linux-Aurora's stats_raw.rs adds once the device is
// registered. The DRM core removes it when the device unregisters, before
// the manager it reads is stopped.
fn (mut driver AgxDriver) publish_debugfs(mgr &gpu.GpuManager) {
	if mgr.hw_config.gpu_gen != .g13 || driver.drm_dev == unsafe { nil } { return }
	drm.debugfs_add_file(driver.drm_dev, 'asahi_stats', show_asahi_stats, voidptr(mgr))
}

fn show_asahi_stats(context voidptr, mut text lib.Text) {
	mut manager := unsafe { &gpu.GpuManager(context) }
	manager.g13_raw_stats_text(mut text, agx_driver_inst.unit_address, time.monotonic_ns())
}
