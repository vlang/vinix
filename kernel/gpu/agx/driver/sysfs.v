// SPDX-License-Identifier: GPL-2.0-or-later
module driver

import drm.gem
import fs
import gpu.agx.gpu
import lib

// Linux's device-tree identity of the base M1 GPU node, gpu@206400000 in
// t8103.dtsi, which libdrm reads from the device's uevent.
const t8103_compatible = ['apple,agx-t8103', 'apple,agx-g13g']!

// The directory Linux gives the GPU's platform device, named after its node's
// unit address: devices/platform/soc/206400000.gpu on M1.
fn gpu_sysfs_path(unit_address u64) string {
	mut path := lib.new_text(48)
	path.add('devices/platform/soc/')
	path.add_radix(unit_address, 16, 0)
	path.add('.gpu')
	return lib.finish_text(path)
}

// The platform device's own files, beside the drm directory the DRM core made
// for its minors: Linux's uevent, modalias and subsystem link, which libdrm
// reads to describe the device, and Asahi's agx_stats and gpu_memory.
fn (mut driver AgxDriver) publish_sysfs(mgr &gpu.GpuManager) {
	if mgr.hw_config.gpu_gen != .g13 || driver.unit_address == 0 { return }
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
	fs.sysfs_text(uevent_path, uevent)
	fs.sysfs_text(modalias_path, modalias_line)
	// devices/platform/soc/206400000.gpu/subsystem -> ../../../../bus/platform
	subsystem := sysfs_child(directory, '/', 'subsystem')
	fs.sysfs_directory('bus/platform')
	fs.sysfs_link(subsystem, '../../../../bus/platform')
	stats := sysfs_child(directory, '/', 'agx_stats')
	memory_path := sysfs_child(directory, '/', 'gpu_memory')
	fs.sysfs_attribute(stats, 0o444, show_agx_stats, unsafe { nil }, voidptr(mgr))
	fs.sysfs_attribute(memory_path, 0o444, show_gpu_memory, unsafe { nil }, voidptr(mgr))
	unsafe {
		modalias.free()
		uevent.free()
		modalias_line.free()
		uevent_path.free()
		modalias_path.free()
		subsystem.free()
		stats.free()
		memory_path.free()
	}
	driver.sysfs_device = directory
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

// Removal waits for any read still running, so the manager outlives them. The
// DRM core removes its minors' class and dev/char links when it unregisters.
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
