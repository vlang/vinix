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
	primary_sysfs DrmMinorSysfs
	render_sysfs DrmMinorSysfs
	debugfs_dir  string
	debugfs_primary_link bool
	debugfs_render_link bool
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

// drmParseSubsystemType(): a virtio device's bus is its parent's.
fn libdrm_bus(minor u32) string {
	bus := subsystem_type(minor)
	if bus != 'virtio' { return bus }
	link := readlink('dev/char/226:${minor}/device/../subsystem') or { return 'virtio' }
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

// Read an attribute through its show function, as a read(2) of it does.
fn read_attribute(path string) ?string {
	real := resolve(path)?
	entry := fs.entry(real) or { return none }
	if entry.kind != .attribute { return none }
	mut text := lib.new_text(64)
	entry.show(entry.context, mut text)
	return lib.finish_text(text)
}

fn check_minor_sysfs_collisions() {
	parent := 'devices/platform/occupied.gpu'
	mut driver := DrmDriver{sysfs_parent: parent}
	mut node := DrmNode{}
	mut dev := DrmDevice{driver: &driver, dev_id: 5, render_node: &node}
	minors := [
		['${parent}/drm/card5', 'class/drm/card5', 'dev/char/226:5']!,
		['${parent}/drm/renderD133', 'class/drm/renderD133', 'dev/char/226:133']!,
	]!
	for minor_index, paths in minors {
		sibling := minors[1 - minor_index]
		for blocked_index, blocked in paths {
			assert fs.sysfs_text('${blocked}/owner', 'existing directory')
			publish_drm_sysfs(mut dev)
			if blocked_index == 0 {
				assert !fs.published('${blocked}/dev'), 'registration populated the occupied minor directory'
				assert !fs.published(paths[1]) && !fs.published(paths[2])
			}
			for path in sibling {
				assert fs.published(path)
			}
			remove_drm_sysfs(mut dev)
			assert text_of('${blocked}/owner') == 'existing directory', 'teardown removed the occupied sysfs path'
			for index, path in paths {
				assert fs.published(path) == (index == blocked_index)
			}
			for path in sibling {
				assert !fs.published(path)
			}
			assert fs.sysfs_remove(blocked)
		}
	}
	println('DRM sysfs: six card and render collisions preserve occupied paths through unregister')
}

fn show_marker(context voidptr, mut text lib.Text) {
	text.add('stats of ')
	text.add_unsigned(u64(context))
	text.add_byte(`\n`)
}

pub fn run_checks() {
	check_minor_sysfs_collisions()
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

	// Linux's DRM debugfs at /sys/kernel/debug: dri/<unique>, named after the
	// parent device, and a link to it per minor, written as debugfs writes it.
	unique := '${oracle_unit}.${oracle_node}'
	debugfs := 'kernel/debug/dri/${unique}'
	assert gpu_device.debugfs_dir == debugfs, gpu_device.debugfs_dir
	assert fs.published(debugfs)
	for minor in [u32(1), 129] {
		assert (readlink('kernel/debug/dri/${minor}') or { '' }) == unique, 'dri/${minor}'
		assert (resolve('kernel/debug/dri/${minor}') or { '' }) == debugfs
	}
	// A driver's file in it: root-only, read through its show function, and
	// reachable through either minor's link.
	assert debugfs_add_file(&gpu_device, 'asahi_stats', show_marker, voidptr(u64(42)))
	assert !debugfs_add_file(&gpu_device, 'asahi_stats', show_marker, voidptr(u64(42)))
	stats := fs.entry('${debugfs}/asahi_stats') or { panic('asahi_stats missing') }
	assert stats.kind == .attribute && stats.mode == 0o400
	assert (read_attribute('kernel/debug/dri/1/asahi_stats') or { '' }) == 'stats of 42\n'
	assert (read_attribute('kernel/debug/dri/129/asahi_stats') or { '' }) == 'stats of 42\n'
	// A second device whose parent has the same name gets no directory, as
	// Linux's debugfs_create_dir() refuses a taken name, and its removal
	// leaves the first device's directory alone.
	mut twin_driver := DrmDriver{sysfs_parent: parent}
	mut twin := DrmDevice{driver: &twin_driver, dev_id: 2, render_node: &node}
	publish_drm_sysfs(mut twin)
	assert twin.debugfs_dir == '' && !fs.published('kernel/debug/dri/2')
	assert !fs.published('kernel/debug/dri/130')
	assert !debugfs_add_file(&twin, 'asahi_stats', show_marker, unsafe { nil })
	remove_drm_sysfs(mut twin)
	assert (read_attribute('kernel/debug/dri/1/asahi_stats') or { '' }) == 'stats of 42\n'

	competed_name := 'competing.gpu'
	competed_directory := 'kernel/debug/dri/${competed_name}'
	mut competing_driver := DrmDriver{sysfs_parent: 'devices/platform/${competed_name}'}
	mut losing_device := DrmDevice{driver: &competing_driver, dev_id: 3, render_node: &node}
	fs.compete_for_directory(competed_directory)
	publish_drm_sysfs(mut losing_device)
	assert losing_device.debugfs_dir == '', 'a losing claim acquired the competing debugfs directory'
	assert !fs.published('kernel/debug/dri/3') && !fs.published('kernel/debug/dri/131')
	remove_drm_sysfs(mut losing_device)
	assert text_of('${competed_directory}/owner') == 'competing device'

	mut partial_driver := DrmDriver{sysfs_parent: 'devices/platform/partial.gpu'}
	mut partial_device := DrmDevice{driver: &partial_driver, dev_id: 4, render_node: &node}
	partial_dir := 'kernel/debug/dri/partial.gpu'
	minor_paths := ['kernel/debug/dri/4', 'kernel/debug/dri/132']!
	for blocked_index in 0 .. minor_paths.len {
		blocked := minor_paths[blocked_index]
		added := minor_paths[1 - blocked_index]
		assert fs.sysfs_text('${blocked}/owner', 'existing directory')
		publish_drm_sysfs(mut partial_device)
		assert (resolve(added) or { '' }) == partial_dir
		assert debugfs_add_file(&partial_device, 'stats', show_marker, voidptr(u64(42)))
		remove_drm_sysfs(mut partial_device)
		assert text_of('${blocked}/owner') == 'existing directory', 'teardown removed the occupied minor path'
		assert !fs.published(added) && !fs.published(partial_dir)
		assert fs.sysfs_remove(blocked)
	}
	println('DRM debugfs: unregister preserves occupied card and render paths and removes the links it created')

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
	// It has no debugfs directory to add files to.
	assert framebuffer.debugfs_dir == '' && !fs.published('kernel/debug/dri/0')
	assert !debugfs_add_file(&framebuffer, 'asahi_stats', show_marker, unsafe { nil })

	// QEMU's VirGL GPU on the VirtIO-MMIO transport, at slot 31 of the virt
	// machine: its DRM parent is the virtio device, in the platform device of
	// the virtio_mmio@a003e00 node, with QEMU's vendor ID.
	virtio_parent := virtio_device_path(0x0a003e00, 31)
	assert virtio_parent == 'devices/platform/a003e00.virtio_mmio/virtio31', virtio_parent
	mut virtio_driver := DrmDriver{sysfs_parent: virtio_parent}
	mut virtio := DrmDevice{driver: &virtio_driver, dev_id: 2, render_node: &node}
	publish_drm_sysfs(mut virtio)
	publish_virtio_sysfs(0x0a003e00, 31, 16, 0x554d4551)
	for minor in [u32(2), 130] {
		// libdrm lists it, on the platform bus through the virtio parent.
		assert node_is_drm(minor), 'libdrm rejects 226:${minor}'
		assert subsystem_type(minor) == 'virtio'
		assert libdrm_bus(minor) == 'platform', libdrm_bus(minor)
		// libdrm reads only the links' last names; Linux's lead to the buses.
		assert (resolve('dev/char/226:${minor}/device/subsystem') or { '' }) == 'bus/virtio'
		assert (resolve('dev/char/226:${minor}/device/../subsystem') or { '' }) == 'bus/platform'
		// drmParseOFBusInfo() and drmParseOFDeviceInfo(): the virtio device
		// has no OF data, so both use its MODALIAS after the last colon.
		device := 'dev/char/226:${minor}/device'
		assert uevent_get(device, 'OF_FULLNAME') == none
		assert (uevent_get(device, 'MODALIAS') or { '' }) == 'virtio:d00000010v554D4551'
		// The platform device above it carries the node's identity.
		assert (uevent_get(device + '/..', 'OF_FULLNAME') or { '' }) == '/virtio_mmio@a003e00'
		assert (uevent_get(device + '/..', 'OF_COMPATIBLE_0') or { '' }) == 'virtio,mmio'
	}
	assert (device_name(130) or { '' }) == '/dev/dri/renderD130'
	assert (resolve('class/drm/renderD130/device') or { '' }) == virtio_parent
	assert virtio.debugfs_dir == 'kernel/debug/dri/virtio31'
	remove_drm_sysfs(mut virtio)
	assert !fs.published('dev/char/226:130') && !fs.published('class/drm/card2')

	// Unregistering removes the class and dev/char links and the minors; the
	// parent directory and its own files stay with their driver.
	remove_drm_sysfs(mut gpu_device)
	remove_drm_sysfs(mut framebuffer)
	for path in ['class/drm/card1', 'class/drm/renderD129', 'dev/char/226:1', 'dev/char/226:129',
		'${parent}/drm/card1', '${parent}/drm/renderD129', 'class/drm/card0', 'dev/char/226:0',
		'devices/virtual/drm/card0', 'kernel/debug/dri/1', 'kernel/debug/dri/129', debugfs,
		'${debugfs}/asahi_stats'] {
		assert !fs.published(path), '${path} survived unregister'
	}
	assert fs.published('${parent}/uevent')
	assert gpu_device.sysfs_parent == '' && framebuffer.sysfs_parent == ''
	assert gpu_device.debugfs_dir == ''
	// A second registration can publish the same names again.
	publish_drm_sysfs(mut framebuffer)
	assert node_is_drm(0) == false && exists('class/drm/card0')
	remove_drm_sysfs(mut framebuffer)
	_ = lib.new_text(0)
	println('DRM sysfs: libdrm finds the M1 GPU as a platform device named from the pinned device tree, its debugfs directory holds root-only driver files, virtual devices stay unlisted, and unregister removes its own links; a VirtIO-MMIO GPU is listed as a platform device through its virtio parent')
}
