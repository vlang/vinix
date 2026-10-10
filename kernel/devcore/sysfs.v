// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The device core as /sys shows it, in Linux's layout:
//
//	/sys/devices/pci0000:00/0000:00:03.0/     the device itself
//	    vendor device class revision config   what it is (PCI)
//	    modalias uevent                       what would drive it
//	    driver -> ../../../bus/pci/drivers/e1000
//	    state health                          Vinix's: bound, failed; its history
//	    reset remove                          write 1 to ask
//	    power/wakeup power/wakeup_count       may it end a sleep; did it
//	/sys/bus/pci/devices/0000:00:03.0 -> ../../../devices/pci0000:00/0000:00:03.0
//	/sys/bus/pci/drivers/e1000/
//	    bind unbind                           write a device's name
//	    0000:00:03.0 -> ../../../../devices/pci0000:00/0000:00:03.0
//	/sys/bus/pci/rescan                       write 1 to look for new devices
//
// Devices are found, and drivers started, long before /sys is mounted, so
// nothing is published until publish() is called; what exists then is
// published at once and everything later as it happens.
@[has_globals]
module devcore

import errno
import fs
import lib

__global (
	devcore_published bool
)

// Paths are put together in a builder on the stack, as procfs does: one made
// as a local value is moved to the heap by the compiler and left there.
fn text2(a string, b string) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(a.len + b.len) }
	text.add(a)
	text.add(b)
	return text.str()
}

fn text3(a string, b string, c string) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(a.len + b.len + c.len) }
	text.add(a)
	text.add(b)
	text.add(c)
	return text.str()
}

// `depth` times "../", then `rest`: a link's way up to /sys and down again.
fn up_and_over(depth int, rest string) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(depth * 3 + rest.len) }
	for _ in 0 .. depth {
		text.add('../')
	}
	text.add(rest)
	return text.str()
}

fn components(path string) int {
	mut count := 1
	for i in 0 .. path.len {
		if path[i] == `/` {
			count++
		}
	}
	return count
}

// The directory a bus's top-level devices appear in.
fn bus_root(bus Bus) string {
	return match bus {
		.pci { 'devices/pci0000:00/' }
		.acpi { 'devices/LNXSYSTM:00/' }
		.platform { 'devices/platform/' }
		.virtio { 'devices/virtio/' }
		.usb { 'devices/usb/' }
	}
}

// Publish everything, and from now on every change. Called once /sys is
// mounted.
pub fn publish() {
	gate_enter()
	defer {
		gate_leave()
	}
	if devcore_published {
		return
	}
	devcore_published = true
	fs.sysfs_directory('devices/platform')
	fs.sysfs_directory('bus')
	fs.sysfs_attribute('bus/pci/rescan', 0o200, unsafe { nil }, store_rescan_pci, unsafe { nil })
	for i in 0 .. devcore_driver_count {
		publish_driver(unsafe { &devcore_drivers[i] })
	}
	for i in 0 .. devcore_device_count {
		mut dev := devcore_devices[i]
		publish_device(mut dev)
		if dev.state == .bound || (dev.state == .failed && dev.driver != unsafe { nil }) {
			publish_binding(dev)
		}
	}
}

fn publish_driver(driver &Driver) {
	if !devcore_published {
		return
	}
	bus := bus_name(driver.bus)
	mut base := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *base = lib.new_text(64) }
	base.add('bus/')
	base.add(bus)
	base.add('/drivers/')
	base.add(driver.name)
	directory := base.str()
	bind := text2(directory, '/bind')
	unbind := text2(directory, '/unbind')
	fs.sysfs_directory(directory)
	if driver.probe != unsafe { nil } {
		fs.sysfs_attribute(bind, 0o200, unsafe { nil }, store_bind, voidptr(driver))
	}
	if driver.remove != unsafe { nil } {
		fs.sysfs_attribute(unbind, 0o200, unsafe { nil }, store_unbind, voidptr(driver))
	}
	unsafe {
		directory.free()
		bind.free()
		unbind.free()
	}
}

fn attribute(dev &Device, name string, mode u32, show fs.SysfsShow, store fs.SysfsStore) {
	path := text3(dev.sysfs_path, '/', name)
	fs.sysfs_attribute(path, mode, show, store, voidptr(dev))
	unsafe { path.free() }
}

fn publish_device(mut dev Device) {
	if !devcore_published || dev.published {
		return
	}
	if dev.sysfs_path.len == 0 {
		dev.sysfs_path = if dev.parent != unsafe { nil } && dev.parent.sysfs_path.len != 0 {
			text3(dev.parent.sysfs_path, '/', dev.name)
		} else {
			text2(bus_root(dev.bus), dev.name)
		}
	}
	fs.sysfs_directory(dev.sysfs_path)
	if dev.bus == .pci {
		attribute(dev, 'vendor', 0o444, show_vendor, unsafe { nil })
		attribute(dev, 'device', 0o444, show_device, unsafe { nil })
		attribute(dev, 'class', 0o444, show_class, unsafe { nil })
		attribute(dev, 'revision', 0o444, show_revision, unsafe { nil })
		attribute(dev, 'config', 0o400, show_config, unsafe { nil })
	} else if dev.compatible.len != 0 {
		attribute(dev, 'compatible', 0o444, show_compatible, unsafe { nil })
	}
	attribute(dev, 'modalias', 0o444, show_modalias, unsafe { nil })
	attribute(dev, 'uevent', 0o444, show_uevent, unsafe { nil })
	attribute(dev, 'state', 0o444, show_state, unsafe { nil })
	attribute(dev, 'health', 0o444, show_health, unsafe { nil })
	attribute(dev, 'dma', 0o444, show_dma, unsafe { nil })
	attribute(dev, 'reset', 0o200, unsafe { nil }, store_reset)
	attribute(dev, 'remove', 0o200, unsafe { nil }, store_remove)
	attribute(dev, 'power/wakeup', 0o644, show_wakeup, store_wakeup)
	attribute(dev, 'power/wakeup_count', 0o444, show_wakeup_count, unsafe { nil })
	attribute(dev, 'power/runtime_status', 0o444, show_runtime_status, unsafe { nil })

	// /sys/bus/<bus>/devices/<name>
	bus := bus_name(dev.bus)
	mut link := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *link = lib.new_text(64) }
	link.add('bus/')
	link.add(bus)
	link.add('/devices/')
	link.add(dev.name)
	link_path := link.str()
	target := up_and_over(3, dev.sysfs_path)
	fs.sysfs_link(link_path, target)
	unsafe {
		link_path.free()
		target.free()
	}
	dev.published = true
}

fn unpublish_device(mut dev Device) {
	if !dev.published {
		return
	}
	bus := bus_name(dev.bus)
	mut link := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *link = lib.new_text(64) }
	link.add('bus/')
	link.add(bus)
	link.add('/devices/')
	link.add(dev.name)
	link_path := link.str()
	fs.sysfs_remove(link_path)
	unsafe { link_path.free() }
	fs.sysfs_remove(dev.sysfs_path)
	dev.published = false
}

// The two links that say who drives a device: its own `driver`, and its entry
// in the driver's directory.
fn publish_binding(dev &Device) {
	if !devcore_published || !dev.published || dev.driver == unsafe { nil } {
		return
	}
	bus := bus_name(dev.bus)
	mut driver := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *driver = lib.new_text(64) }
	driver.add('bus/')
	driver.add(bus)
	driver.add('/drivers/')
	driver.add(dev.driver.name)
	driver_directory := driver.str()

	own := text2(dev.sysfs_path, '/driver')
	own_target := up_and_over(components(dev.sysfs_path), driver_directory)
	fs.sysfs_link(own, own_target)

	listed := text3(driver_directory, '/', dev.name)
	listed_target := up_and_over(4, dev.sysfs_path)
	fs.sysfs_link(listed, listed_target)
	unsafe {
		driver_directory.free()
		own.free()
		own_target.free()
		listed.free()
		listed_target.free()
	}
}

fn unpublish_binding(dev &Device) {
	if !devcore_published || !dev.published || dev.driver == unsafe { nil } {
		return
	}
	own := text2(dev.sysfs_path, '/driver')
	fs.sysfs_remove(own)
	mut listed := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *listed = lib.new_text(64) }
	listed.add('bus/')
	listed.add(bus_name(dev.bus))
	listed.add('/drivers/')
	listed.add(dev.driver.name)
	listed.add('/')
	listed.add(dev.name)
	listed_path := listed.str()
	fs.sysfs_remove(listed_path)
	unsafe {
		own.free()
		listed_path.free()
	}
}

// ── What the files say ──────────────────────────────────────────────────────

fn hex_line(mut text lib.Text, value u64, width int) {
	text.add('0x')
	text.add_radix(value, 16, width)
	text.add_byte(`\n`)
}

fn show_vendor(context voidptr, mut text lib.Text) {
	dev := unsafe { &Device(context) }
	hex_line(mut text, u64(dev.vendor), 4)
}

fn show_device(context voidptr, mut text lib.Text) {
	dev := unsafe { &Device(context) }
	hex_line(mut text, u64(dev.device), 4)
}

fn show_class(context voidptr, mut text lib.Text) {
	dev := unsafe { &Device(context) }
	hex_line(mut text, (u64(dev.class) << 16) | (u64(dev.subclass) << 8) | u64(dev.prog_if), 6)
}

fn show_revision(context voidptr, mut text lib.Text) {
	dev := unsafe { &Device(context) }
	hex_line(mut text, u64(dev.revision), 2)
}

fn show_compatible(context voidptr, mut text lib.Text) {
	dev := unsafe { &Device(context) }
	text.add(dev.compatible)
	text.add_byte(`\n`)
}

// The first 256 bytes of a PCI function's configuration space, which is what
// lspci decodes. A register that cannot be read reads as all ones, as it does
// on the bus.
fn show_config(context voidptr, mut text lib.Text) {
	dev := unsafe { &Device(context) }
	if dev.pci == unsafe { nil } {
		return
	}
	for offset := u64(0); offset < 256; offset += 4 {
		mut value := u32(0xffffffff)
		dev.pci.config_read(offset, 4, unsafe { &value })
		for shift := u32(0); shift < 32; shift += 8 {
			text.add_byte(u8(value >> shift))
		}
	}
}

fn add_modalias(mut text lib.Text, dev &Device) {
	if dev.bus == .pci {
		// Linux's form, so that a tool matching on it matches here.
		text.add('pci:v')
		text.add_radix(u64(dev.vendor), 16, 8)
		text.add('d')
		text.add_radix(u64(dev.device), 16, 8)
		text.add('bc')
		text.add_radix(u64(dev.class), 16, 2)
		text.add('sc')
		text.add_radix(u64(dev.subclass), 16, 2)
		text.add('i')
		text.add_radix(u64(dev.prog_if), 16, 2)
		return
	}
	text.add(bus_name(dev.bus))
	text.add_byte(`:`)
	text.add(if dev.compatible.len != 0 { dev.compatible } else { dev.name })
}

fn show_modalias(context voidptr, mut text lib.Text) {
	dev := unsafe { &Device(context) }
	add_modalias(mut text, dev)
	text.add_byte(`\n`)
}

fn show_uevent(context voidptr, mut text lib.Text) {
	dev := unsafe { &Device(context) }
	driver := dev.driver
	if driver != unsafe { nil } {
		text.add('DRIVER=')
		text.add(driver.name)
		text.add_byte(`\n`)
	}
	if dev.bus == .pci {
		text.add('PCI_CLASS=')
		text.add_radix((u64(dev.class) << 16) | (u64(dev.subclass) << 8) | u64(dev.prog_if),
			16, 0)
		text.add('\nPCI_ID=')
		text.add_radix(u64(dev.vendor), 16, 4)
		text.add_byte(`:`)
		text.add_radix(u64(dev.device), 16, 4)
		text.add('\nPCI_SLOT_NAME=')
		text.add(dev.name)
		text.add_byte(`\n`)
	}
	text.add('MODALIAS=')
	add_modalias(mut text, dev)
	text.add_byte(`\n`)
}

fn show_state(context voidptr, mut text lib.Text) {
	dev := unsafe { &Device(context) }
	text.add(state_name(dev.state))
	text.add_byte(`\n`)
}

fn show_health(context voidptr, mut text lib.Text) {
	dev := unsafe { &Device(context) }
	text.add('timeouts: ')
	text.add_unsigned(dev.timeouts)
	text.add('\nfailures: ')
	text.add_unsigned(dev.failures)
	text.add('\nresets: ')
	text.add_unsigned(dev.resets)
	text.add('\nprobe_failures: ')
	text.add_unsigned(dev.probe_failures)
	text.add('\nrecovering: ')
	text.add_unsigned(u64(dev.recovering))
	text.add_byte(`\n`)
}

fn show_dma(context voidptr, mut text lib.Text) {
	dev := unsafe { &Device(context) }
	if dev.dma == unsafe { nil } || devcore_hooks.dma_describe == unsafe { nil } {
		text.add('domain: none\n')
		return
	}
	devcore_hooks.dma_describe(dev, mut text)
}

fn show_wakeup(context voidptr, mut text lib.Text) {
	dev := unsafe { &Device(context) }
	// Linux leaves the file empty for a device that cannot wake the machine.
	if !dev.wakeup_capable {
		text.add_byte(`\n`)
		return
	}
	text.add(if dev.wakeup_enabled { 'enabled\n' } else { 'disabled\n' })
}

fn store_wakeup(context voidptr, data &u8, length u64) u64 {
	mut dev := unsafe { &Device(context) }
	word := fs.sysfs_word(data, length)
	if !dev.wakeup_capable {
		return errno.einval
	}
	if word == 'enabled' {
		dev.wakeup_enabled = true
	} else if word == 'disabled' {
		dev.wakeup_enabled = false
	} else {
		return errno.einval
	}
	return 0
}

fn show_wakeup_count(context voidptr, mut text lib.Text) {
	dev := unsafe { &Device(context) }
	text.add_unsigned(dev.wakeups)
	text.add_byte(`\n`)
}

fn show_runtime_status(context voidptr, mut text lib.Text) {
	dev := unsafe { &Device(context) }
	text.add(if dev.suspended {
		'suspended\n'
	} else if dev.state == .bound {
		'active\n'
	} else {
		'unsupported\n'
	})
}

fn wrote_one(data &u8, length u64) bool {
	value := fs.sysfs_unsigned(data, length) or { return false }
	return value == 1
}

fn store_reset(context voidptr, data &u8, length u64) u64 {
	mut dev := unsafe { &Device(context) }
	if !wrote_one(data, length) {
		return errno.einval
	}
	return if request_reset(mut dev) { u64(0) } else { u64(errno.ebusy) }
}

// The removal runs on the worker: it takes this very file away, and
// sysfs_remove() waits for the store that asked for it to return.
fn store_remove(context voidptr, data &u8, length u64) u64 {
	mut dev := unsafe { &Device(context) }
	if !wrote_one(data, length) {
		return errno.einval
	}
	return if request_remove(mut dev) { u64(0) } else { u64(errno.ebusy) }
}

fn store_rescan_pci(_ voidptr, data &u8, length u64) u64 {
	if !wrote_one(data, length) {
		return errno.einval
	}
	return if request_rescan(.pci) { u64(0) } else { u64(errno.enodev) }
}

fn store_bind(context voidptr, data &u8, length u64) u64 {
	driver := unsafe { &Driver(context) }
	name := fs.sysfs_word(data, length)
	// Under the gate, so that the device found is still there when it is used.
	gate_enter()
	defer {
		gate_leave()
	}
	mut dev := find(driver.bus, name)
	if dev == unsafe { nil } {
		return errno.enodev
	}
	if dev.state == .bound {
		return errno.ebusy
	}
	return if bind(mut dev, driver.name) { u64(0) } else { u64(errno.enodev) }
}

fn store_unbind(context voidptr, data &u8, length u64) u64 {
	driver := unsafe { &Driver(context) }
	name := fs.sysfs_word(data, length)
	gate_enter()
	defer {
		gate_leave()
	}
	mut dev := find(driver.bus, name)
	if dev == unsafe { nil } || voidptr(dev.driver) != voidptr(driver) {
		return errno.enodev
	}
	return if unbind(mut dev) { u64(0) } else { u64(errno.ebusy) }
}
