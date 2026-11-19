// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import fs
import lib

// The DRM core types the publisher reads.
pub struct DrmDriver {
pub mut:
	sysfs_parent string
}

pub struct DrmNode {}

pub struct DrmDevice {
pub mut:
	driver       &DrmDriver = unsafe { nil }
	dev_id       u32
	render_node  &DrmNode = unsafe { nil }
	sysfs_parent string
}

// Follow every link in `path`, relative links from the link's own directory,
// as the kernel's path walk does. None if anything along it is missing.
fn resolve(path string) ?string {
	mut current := []string{}
	mut pending := path.split('/')
	mut hops := 0
	for pending.len > 0 {
		part := pending[0]
		pending.delete(0)
		if part == '' || part == '.' { continue }
		if part == '..' {
			if current.len > 0 { current.delete_last() }
			continue
		}
		mut candidate_parts := current.clone()
		candidate_parts << part
		candidate := candidate_parts.join('/')
		entry := fs.entry(candidate) or { return none }
		if entry.kind == .link {
			hops++
			if hops > 40 { return none }
			mut expanded := entry.value.split('/')
			expanded << pending
			pending = expanded.clone()
			continue
		}
		current << part
	}
	return current.join('/')
}

fn exists(path string) bool {
	resolve(path) or { return false }
	return true
}

fn readlink(path string) ?string {
	directory := resolve(path.all_before_last('/'))?
	entry := fs.entry(directory + '/' + path.all_after_last('/')) or { return none }
	if entry.kind != .link { return none }
	return entry.value
}

// libdrm's sysfs_uevent_get(): KEY=value lines of <dir>/uevent.
fn uevent_get(directory string, key string) ?string {
	real := resolve(directory + '/uevent')?
	entry := fs.entry(real) or { return none }
	for line in entry.value.split_into_lines() {
		if line.starts_with(key + '=') { return line.all_after('=') }
	}
	return none
}

// libdrm's drmNodeIsDRM(), drmParseSubsystemType() and the lookups of
// drmGetDeviceNameFromFd2(), drmParseOFBusInfo() and drmParseOFDeviceInfo().
fn node_is_drm(minor u32) bool { return exists('dev/char/226:${minor}/device/drm') }

fn subsystem_type(minor u32) string {
	link := readlink('dev/char/226:${minor}/device/subsystem') or { return '' }
	return link.all_after_last('/')
}

fn device_name(minor u32) ?string {
	if !node_is_drm(minor) { return none }
	name := uevent_get('dev/char/226:${minor}', 'DEVNAME')?
	return '/dev/' + name
}

fn text_of(path string) string {
	real := resolve(path) or { return '' }
	return (fs.entry(real) or { return '' }).value
}

pub fn run_checks() {
	// The base M1 GPU as the AGX driver registers it: card1 and renderD129,
	// under the directory named after the device-tree node.
	parent := gpu_sysfs_path(0x206400000)
	assert parent == 'devices/platform/soc/${oracle_unit}.${oracle_node}', parent
	mut driver := DrmDriver{sysfs_parent: parent}
	mut node := DrmNode{}
	mut gpu_device := DrmDevice{driver: &driver, dev_id: 1, render_node: &node}
	publish_drm_sysfs(mut gpu_device)
	// The AGX driver's own files in that directory.
	modalias := gpu_modalias()
	assert fs.sysfs_text(parent + '/uevent', gpu_uevent(0x206400000, modalias))
	assert fs.sysfs_link(parent + '/subsystem', agx_subsystem_link)

	for minor, name in {
		u32(1):   'card1'
		u32(129): 'renderD129'
	} {
		assert node_is_drm(minor), 'libdrm rejects 226:${minor}'
		assert subsystem_type(minor) == 'platform', 'bus of 226:${minor}'
		assert (device_name(minor) or { '' }) == '/dev/dri/${name}'
		assert text_of('dev/char/226:${minor}/dev') == '226:${minor}\n'
		assert (uevent_get('dev/char/226:${minor}', 'DEVTYPE') or { '' }) == 'drm_minor'
		assert (uevent_get('dev/char/226:${minor}', 'MAJOR') or { '' }) == '226'
		assert (uevent_get('dev/char/226:${minor}', 'MINOR') or { '' }) == '${minor}'
		// The class entry and the dev/char entry are the same directory, and
		// its device and subsystem lead where Linux's do.
		real := resolve('dev/char/226:${minor}') or { '' }
		assert real == '${parent}/drm/${name}', real
		assert (resolve('class/drm/${name}') or { '' }) == real
		assert (resolve('class/drm/${name}/device') or { '' }) == parent
		assert (resolve('class/drm/${name}/subsystem') or { '' }) == 'class/drm'
		assert (readlink('class/drm/${name}') or { '' }) == '../../${real}'
		assert (readlink('${real}/device') or { '' }) == '../../../${oracle_unit}.${oracle_node}'
		// drmParseOFBusInfo() and drmParseOFDeviceInfo().
		device := 'dev/char/226:${minor}/device'
		assert (uevent_get(device, 'OF_FULLNAME') or { '' }) == '/soc/${oracle_node}@${oracle_unit}'
		count := (uevent_get(device, 'OF_COMPATIBLE_N') or { '0' }).int()
		assert count == oracle_compatible.len
		for index in 0 .. count {
			assert (uevent_get(device, 'OF_COMPATIBLE_${index}') or { '' }) == oracle_compatible[index]
		}
		mut expected_alias := 'of:N${oracle_node}T(null)'
		for compatible in oracle_compatible { expected_alias += 'C' + compatible }
		assert (uevent_get(device, 'MODALIAS') or { '' }) == expected_alias
		assert (uevent_get(device, 'DRIVER') or { '' }) == 'asahi'
	}

	// A device with no parent, such as the QEMU framebuffer: Linux's
	// devices/virtual entries, which libdrm does not enumerate.
	mut plain := DrmDriver{}
	mut framebuffer := DrmDevice{driver: &plain, dev_id: 0}
	publish_drm_sysfs(mut framebuffer)
	assert (resolve('class/drm/card0') or { '' }) == 'devices/virtual/drm/card0'
	assert text_of('dev/char/226:0/dev') == '226:0\n'
	assert (resolve('class/drm/card0/subsystem') or { '' }) == 'class/drm'
	assert !exists('class/drm/card0/device') && !node_is_drm(0)
	assert !exists('dev/char/226:128')

	// Unregistering removes the class and dev/char links and the minors; the
	// parent directory and its own files stay with their driver.
	remove_drm_sysfs(mut gpu_device)
	remove_drm_sysfs(mut framebuffer)
	for path in ['class/drm/card1', 'class/drm/renderD129', 'dev/char/226:1', 'dev/char/226:129',
		'${parent}/drm/card1', '${parent}/drm/renderD129', 'class/drm/card0', 'dev/char/226:0',
		'devices/virtual/drm/card0'] {
		assert !fs.published(path), '${path} survived unregister'
	}
	assert fs.published('${parent}/uevent')
	assert gpu_device.sysfs_parent == '' && framebuffer.sysfs_parent == ''
	// A second registration can publish the same names again.
	publish_drm_sysfs(mut framebuffer)
	assert node_is_drm(0) == false && exists('class/drm/card0')
	remove_drm_sysfs(mut framebuffer)
	_ = lib.new_text(0)
	println('DRM sysfs: libdrm finds the M1 GPU as a platform device named from the pinned device tree, virtual devices stay unlisted, and unregister removes every link')
}
