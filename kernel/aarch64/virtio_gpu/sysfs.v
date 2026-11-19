// SPDX-License-Identifier: GPL-2.0-or-later
module virtio_gpu

// Linux's sysfs entries for a GPU on the VirtIO-MMIO transport: the platform
// device of its device-tree node, virtio_mmio@a003e00 on QEMU's virt machine,
// and the virtio device in it, which is the DRM device's parent. libdrm finds
// the GPU through them. The node's subsystem link names the virtio bus, so it
// takes the bus from the virtio device's parent, the platform device, and the
// device's name from the virtio device's MODALIAS, there being no OF data.
// Mesa lists render nodes only through libdrm.
//
// Linux numbers virtio devices in the order it finds them; Vinix names the
// virtio device after its MMIO slot, which nothing reads.

import fs
import lib

// devices/platform/a003e00.virtio_mmio
fn virtio_platform_path(unit_address u64) string {
	mut text := lib.new_text(48)
	text.add('devices/platform/')
	text.add_radix(unit_address, 16, 0)
	text.add('.virtio_mmio')
	return lib.finish_text(text)
}

// devices/platform/a003e00.virtio_mmio/virtio31
fn virtio_device_path(unit_address u64, index u64) string {
	mut text := lib.new_text(56)
	text.add('devices/platform/')
	text.add_radix(unit_address, 16, 0)
	text.add('.virtio_mmio/virtio')
	text.add_unsigned(index)
	return lib.finish_text(text)
}

// What Linux writes in the virtio_mmio platform device's uevent.
fn virtio_platform_uevent(unit_address u64) string {
	mut text := lib.new_text(192)
	text.add('DRIVER=virtio-mmio\nOF_NAME=virtio_mmio\nOF_FULLNAME=/virtio_mmio@')
	text.add_radix(unit_address, 16, 0)
	text.add('\nOF_COMPATIBLE_0=virtio,mmio\nOF_COMPATIBLE_N=1\n')
	text.add('MODALIAS=of:Nvirtio_mmioT(null)Cvirtio,mmio\n')
	return lib.finish_text(text)
}

// What Linux writes in a virtio device's uevent: virtio:d<device>v<vendor>,
// each eight upper-case hexadecimal digits.
fn virtio_device_uevent(device_id u32, vendor_id u32) string {
	mut text := lib.new_text(64)
	text.add('DRIVER=virtio_gpu\nMODALIAS=virtio:d')
	add_hex8(mut text, device_id)
	text.add_byte(`v`)
	add_hex8(mut text, vendor_id)
	text.add_byte(`\n`)
	return lib.finish_text(text)
}

fn add_hex8(mut text lib.Text, value u32) {
	for shift := 28; shift >= 0; shift -= 4 {
		digit := u8((value >> u32(shift)) & 0xf)
		text.add_byte(if digit < 10 { `0` + digit } else { `A` + digit - 10 })
	}
}

// The two devices' own files, beside the drm directory the DRM core made for
// the minors. sysfs keeps copies; the strings made here are freed here.
fn publish_virtio_sysfs(unit_address u64, index u64, device_id u32, vendor_id u32) {
	platform := virtio_platform_path(unit_address)
	device := virtio_device_path(unit_address, index)
	platform_uevent := virtio_platform_uevent(unit_address)
	device_uevent := virtio_device_uevent(device_id, vendor_id)
	fs.sysfs_directory(device)
	publish_child(platform, 'uevent', platform_uevent, false)
	publish_child(platform, 'subsystem', '../../../bus/platform', true)
	publish_child(device, 'uevent', device_uevent, false)
	publish_child(device, 'subsystem', '../../../../bus/virtio', true)
	fs.sysfs_directory('bus/platform')
	fs.sysfs_directory('bus/virtio')
	unsafe {
		platform.free()
		device.free()
		platform_uevent.free()
		device_uevent.free()
	}
}

fn publish_child(directory string, name string, value string, link bool) {
	mut text := lib.new_text(directory.len + name.len + 1)
	text.add(directory)
	text.add_byte(`/`)
	text.add(name)
	path := lib.finish_text(text)
	if link {
		fs.sysfs_link(path, value)
	} else {
		fs.sysfs_text(path, value)
	}
	unsafe { path.free() }
}
