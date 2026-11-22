// SPDX-License-Identifier: GPL-2.0-or-later
module drm

// Linux's sysfs entries for DRM minors: the directory each card and render
// node has under its parent device, and the /sys/class/drm and /sys/dev/char
// links to it. libdrm's drmGetDevices2() finds devices through these: it
// follows /sys/dev/char/226:<minor>/device, requires a drm directory there,
// reads the bus from its subsystem link and the device from its uevent.
//
// A driver whose device has a place in /sys names it in
// DrmDriver.sysfs_parent and publishes the parent's own files. Without one,
// the minors go under devices/virtual/drm, as Linux puts devices with no
// parent; libdrm does not enumerate those, as it found nothing before.

import fs
import lib

const drm_major = 226

struct DrmMinorSysfs {
	directory bool
	class_link bool
	char_link bool
}

// Called with the slot reserved and data opens still gated. Sysfs calls may sleep.
fn publish_drm_sysfs(mut dev DrmDevice) {
	parent := if dev.driver != unsafe { nil } && dev.driver.sysfs_parent.len != 0 {
		dev.driver.sysfs_parent.clone()
	} else {
		// Owned like a driver's path: removal frees it.
		'devices/virtual'.clone()
	}
	dev.sysfs_parent = parent
	fs.sysfs_directory('class/drm')
	fs.sysfs_directory('dev/char')
	dev.primary_sysfs = publish_minor_sysfs(parent, 'card', dev.dev_id)
	if dev.render_node != unsafe { nil } {
		dev.render_sysfs = publish_minor_sysfs(parent, 'renderD', 128 + dev.dev_id)
	}
	if parent != 'devices/virtual' {
		publish_drm_debugfs(mut dev, parent)
	}
}

fn remove_drm_sysfs(mut dev DrmDevice) {
	if dev.sysfs_parent.len == 0 { return }
	remove_drm_debugfs(mut dev)
	remove_minor_sysfs(dev.sysfs_parent, 'card', dev.dev_id, dev.primary_sysfs)
	remove_minor_sysfs(dev.sysfs_parent, 'renderD', 128 + dev.dev_id, dev.render_sysfs)
	dev.primary_sysfs = DrmMinorSysfs{}
	dev.render_sysfs = DrmMinorSysfs{}
	unsafe { dev.sysfs_parent.free() }
	dev.sysfs_parent = ''
}

fn publish_minor_sysfs(parent string, prefix string, minor u32) DrmMinorSysfs {
	name := minor_name(prefix, minor)
	directory := sysfs_join3(parent, '/drm/', name)
	defer {
		unsafe {
			directory.free()
			name.free()
		}
	}
	if !fs.sysfs_create_directory(directory) { return DrmMinorSysfs{} }
	dev_text := minor_dev_text(minor)
	uevent := minor_uevent_text(name, minor)
	publish_text(directory, 'dev', dev_text)
	publish_text(directory, 'uevent', uevent)
	subsystem := relative_link(directory, 'class/drm')
	publish_link(directory, 'subsystem', subsystem)
	if parent != 'devices/virtual' {
		// card0/device -> ../../../206400000.gpu, as Linux writes it.
		device := parent_link(parent)
		publish_link(directory, 'device', device)
		unsafe { device.free() }
	}
	unsafe {
		dev_text.free()
		uevent.free()
		subsystem.free()
	}
	class_link := relative_link('class/drm', directory)
	class_added := publish_link('class/drm', name, class_link)
	char_name := minor_dev_name(minor)
	char_link := relative_link('dev/char', directory)
	char_added := publish_link('dev/char', char_name, char_link)
	unsafe {
		class_link.free()
		char_name.free()
		char_link.free()
	}
	return DrmMinorSysfs{directory: true, class_link: class_added, char_link: char_added}
}

// sysfs copies what it is given; the path made here is freed here.
fn publish_text(directory string, name string, text string) {
	path := sysfs_join3(directory, '/', name)
	fs.sysfs_text(path, text)
	unsafe { path.free() }
}

fn publish_link(directory string, name string, target string) bool {
	path := sysfs_join3(directory, '/', name)
	added := fs.sysfs_link(path, target)
	unsafe { path.free() }
	return added
}

fn remove_minor_sysfs(parent string, prefix string, minor u32, entries DrmMinorSysfs) {
	if !entries.directory { return }
	name := minor_name(prefix, minor)
	if entries.class_link {
		remove_sysfs_entry('class/drm', name)
	}
	if entries.char_link {
		char_name := minor_dev_name(minor)
		remove_sysfs_entry('dev/char', char_name)
		unsafe { char_name.free() }
	}
	directory := sysfs_join3(parent, '/drm/', name)
	fs.sysfs_remove(directory)
	unsafe {
		directory.free()
		name.free()
	}
}

fn remove_sysfs_entry(directory string, name string) {
	path := sysfs_join3(directory, '/', name)
	fs.sysfs_remove(path)
	unsafe { path.free() }
}

// Linux's DRM debugfs: a directory per device named after its parent device
// (dev->unique), dri/206400000.gpu on M1, and a link to it per minor, dri/0
// and dri/128. Linux mounts debugfs at /sys/kernel/debug. Vinix has no
// debugfs, so the DRM part of it is published in /sys at that path, for the
// files drivers add with debugfs_add_file(). A device with no parent gets
// none: Linux names the directory after the parent. Unlike debugfs, whose
// root only root may enter, these directories can be listed by anyone; the
// files in them are root-only.
const debugfs_dri = 'kernel/debug/dri'

fn publish_drm_debugfs(mut dev DrmDevice, parent string) {
	unique := parent_name(parent)
	directory := sysfs_join3(debugfs_dri, '/', unique)
	// A name another device already has stays that device's, as Linux's
	// debugfs_create_dir() refuses it; this device then gets no directory.
	if fs.sysfs_create_directory(directory) {
		dev.debugfs_primary_link = publish_debugfs_link(dev.dev_id, unique)
		if dev.render_node != unsafe { nil } {
			dev.debugfs_render_link = publish_debugfs_link(128 + dev.dev_id, unique)
		}
		dev.debugfs_dir = directory
	} else {
		unsafe { directory.free() }
	}
	unsafe { unique.free() }
}

fn publish_debugfs_link(minor u32, unique string) bool {
	name := minor_name('', minor)
	added := publish_link(debugfs_dri, name, unique)
	unsafe { name.free() }
	return added
}

// Removing the directory waits for every read of a file in it to return.
fn remove_drm_debugfs(mut dev DrmDevice) {
	if dev.debugfs_dir.len == 0 { return }
	if dev.debugfs_primary_link {
		remove_debugfs_link(dev.dev_id)
		dev.debugfs_primary_link = false
	}
	if dev.debugfs_render_link {
		remove_debugfs_link(128 + dev.dev_id)
		dev.debugfs_render_link = false
	}
	fs.sysfs_remove(dev.debugfs_dir)
	unsafe { dev.debugfs_dir.free() }
	dev.debugfs_dir = ''
}

fn remove_debugfs_link(minor u32) {
	name := minor_name('', minor)
	remove_sysfs_entry(debugfs_dri, name)
	unsafe { name.free() }
}

// Add the read-only file `name` to the device's debugfs directory, read
// through `show`: Linux's drm_debugfs_add_file(). Only root may read it, as
// only root may enter debugfs on Linux. The file goes when the device
// unregisters, once no read of it is running, so `context` must last until
// then. It does not synchronize with unregister_device(): call it before
// anything can unregister the device, as the AGX driver does during its own
// registration. False for a device with no directory.
pub fn debugfs_add_file(dev &DrmDevice, name string, show fs.SysfsShow, context voidptr) bool {
	if dev.debugfs_dir.len == 0 { return false }
	path := sysfs_join3(dev.debugfs_dir, '/', name)
	added := fs.sysfs_attribute(path, 0o400, show, unsafe { nil }, context)
	unsafe { path.free() }
	return added
}

// The last component of `parent`, a copy: 206400000.gpu.
fn parent_name(parent string) string {
	mut start := 0
	for index, c in parent {
		if c == `/` { start = index + 1 }
	}
	mut text := lib.new_text(parent.len - start)
	for index := start; index < parent.len; index++ {
		text.add_byte(parent[index])
	}
	return lib.finish_text(text)
}

fn minor_name(prefix string, minor u32) string {
	mut text := lib.new_text(16)
	text.add(prefix)
	text.add_unsigned(minor)
	return lib.finish_text(text)
}

// "../../../<parent's own name>", from <parent>/drm/<minor>.
fn parent_link(parent string) string {
	mut start := 0
	for index, c in parent {
		if c == `/` { start = index + 1 }
	}
	mut text := lib.new_text(parent.len - start + 9)
	text.add('../../../')
	for index := start; index < parent.len; index++ {
		text.add_byte(parent[index])
	}
	return lib.finish_text(text)
}

// "226:128"
fn minor_dev_name(minor u32) string {
	mut text := lib.new_text(16)
	text.add_unsigned(drm_major)
	text.add_byte(`:`)
	text.add_unsigned(minor)
	return lib.finish_text(text)
}

fn minor_dev_text(minor u32) string {
	mut text := lib.new_text(16)
	text.add_unsigned(drm_major)
	text.add_byte(`:`)
	text.add_unsigned(minor)
	text.add_byte(`\n`)
	return lib.finish_text(text)
}

// What Linux's drm_minor class device puts in its uevent.
pub fn minor_uevent_text(name string, minor u32) string {
	mut text := lib.new_text(80)
	text.add('MAJOR=')
	text.add_unsigned(drm_major)
	text.add('\nMINOR=')
	text.add_unsigned(minor)
	text.add('\nDEVNAME=dri/')
	text.add(name)
	text.add('\nDEVTYPE=drm_minor\n')
	return lib.finish_text(text)
}

// A link in directory `from` to `target`, both relative to /sys: up to /sys,
// then down, as Linux writes class and dev/char links.
pub fn relative_link(from string, target string) string {
	mut text := lib.new_text(from.len * 2 + target.len + 4)
	text.add('../')
	for c in from {
		if c == `/` { text.add('../') }
	}
	text.add(target)
	return lib.finish_text(text)
}

fn sysfs_join3(a string, b string, c string) string {
	mut text := lib.new_text(a.len + b.len + c.len)
	text.add(a)
	text.add(b)
	text.add(c)
	return lib.finish_text(text)
}
