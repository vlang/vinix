// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import errno
import memory

const map_shared = 1
const node_ifchr = u32(0o020000)

struct NodeBox {
	minor u64
	node &DrmNode
}

struct NodeHandle {
	flags int
}

struct RegistryLock {
mut:
	held bool
}

struct NamespaceLock {
mut:
	held bool
}

struct VFSNode {
	directory bool
mut:
	name string
	parent &VFSNode = unsafe { nil }
	children &map[string]&VFSNode = unsafe { nil }
}

fn (mut lock_state RegistryLock) acquire() {
	assert !lock_state.held
	lock_state.held = true
}

fn (mut lock_state RegistryLock) release() {
	assert lock_state.held
	lock_state.held = false
}

fn (mut lock_state NamespaceLock) acquire() {
	assert !lock_state.held && vfs_lock.held
	lock_state.held = true
}

fn (mut lock_state NamespaceLock) release() {
	assert lock_state.held
	lock_state.held = false
	observe_dri_publication()
}

__global drm_devices_lock RegistryLock
__global vfs_lock RegistryLock
__global children_lock NamespaceLock
__global devtmpfs_root = unsafe { &VFSNode(nil) }
__global registered_devices [64]&DrmDevice
__global node_names [192]&DrmNode
__global published_nodes = 0
__global staged_nodes [2]&VFSNode
__global staged_devices [2]&NodeBox

fn shared_timeline_stub() {}

fn expect_unavailable(mut node DrmNode) {
	errno.set(0)
	assert node.open(0) == none && errno.get() == errno.enodev
	assert (node.open(o_path) or { panic('metadata-only open rejected') }) == node.box
	request := (u64(`d`) << 8) | 0x00
	expect_error(mut node, request, unsafe { nil }, errno.enodev)
}

fn devtmpfs_remove_device(name string, expected &NodeBox) bool {
	assert drm_devices_lock.held
	prefix := if expected.minor >= 128 { 'renderD' } else { 'card' }
	leaf := '${prefix}${expected.minor}'
	assert name == 'dri/${leaf}'
	mut node := unsafe { node_names[expected.minor] }
	if node == unsafe { nil } || node.box != expected { return false }
	expect_unavailable(mut node)
	mut parent := unsafe { devtmpfs_root.children['dri'] }
	namespace_node := unsafe { parent.children[leaf] }
	parent.children.delete(leaf)
	memory.free_registration(namespace_node.name.str)
	memory.free_registration(namespace_node)
	node_names[expected.minor] = unsafe { nil }
	node.unref(unsafe { nil }) or { panic('namespace reference release failed') }
	return true
}

fn ensure_devtmpfs_dir(parent &VFSNode, name string) &VFSNode {
	if name in parent.children { return unsafe { parent.children[name] } }
	mut root := unsafe { parent }
	dir := &VFSNode{directory: true, children: &map[string]&VFSNode{}}
	unsafe { root.children[name] = dir }
	return dir
}

fn init_devtmpfs_node(mut namespace_node VFSNode, device &NodeBox, seat bool) {
	assert drm_devices_lock.held && vfs_lock.held && !children_lock.held && seat
	prefix := if device.minor >= 128 { 'renderD' } else { 'card' }
	leaf := namespace_node.name
	assert leaf == '${prefix}${device.minor}'
	assert unsafe { leaf.str[leaf.len] } == 0
	assert leaf !in namespace_node.parent.children
	slot := if device.minor >= 128 { 1 } else { 0 }
	assert staged_nodes[slot] == unsafe { nil }
	staged_nodes[slot] = unsafe { namespace_node }
	staged_devices[slot] = unsafe { device }
}

fn observe_dri_publication() {
	assert drm_devices_lock.held && vfs_lock.held && !children_lock.held
	primary := staged_devices[0]
	assert primary != unsafe { nil }
	count := if primary.node.dev.render_node == unsafe { nil } { 1 } else { 2 }
	for slot in 0 .. count {
		entry := staged_nodes[slot]
		device := staged_devices[slot]
		assert entry != unsafe { nil } && device != unsafe { nil }
		assert unsafe { entry.parent.children[entry.name] } == entry, 'directory reader saw partial DRM publication'
		mut node := unsafe { device.node }
		assert registered_devices[node.dev.dev_id] == unsafe { nil }
		assert node.stat.rdev == u64(226 << 8) | device.minor
		assert node.stat.mode == node_ifchr | 0o666
		assert node.refcount == 1 && node.box == device
		expect_unavailable(mut node)
		node_names[device.minor] = unsafe { node }
		staged_nodes[slot] = unsafe { nil }
		staged_devices[slot] = unsafe { nil }
		published_nodes++
	}
}

fn check_registration_collisions() {
	driver := DrmDriver{features: driver_render}
	assert register_driver_with_data(&driver, unsafe { nil }) == none && errno.get() == errno.enodev
	assert memory.registration_outstanding() == 0
	devtmpfs_root = &VFSNode{directory: true, children: &map[string]&VFSNode{}}
	blocker := &VFSNode{}
	unsafe { devtmpfs_root.children['dri'] = blocker }
	assert register_driver_with_data(&driver, unsafe { nil }) == none && errno.get() == errno.enotdir
	assert memory.registration_outstanding() == 0
	assert unsafe { devtmpfs_root.children['dri'] == blocker }
	devtmpfs_root.children.delete('dri')
	mut dir := ensure_devtmpfs_dir(devtmpfs_root, 'dri')
	for leaf in ['card0', 'renderD128']! {
		unsafe { dir.children[leaf] = blocker }
		assert register_driver_with_data(&driver, unsafe { nil }) == none && errno.get() == errno.eexist
		assert published_nodes == 0 && dir.children.len == 1 && unsafe { dir.children[leaf] == blocker }
		assert get_device(0) == none && node_names[0] == unsafe { nil } && node_names[128] == unsafe { nil }
		assert memory.registration_outstanding() == 0
		if leaf == 'card0' {
			assert register_driver_with_data(&DrmDriver{}, unsafe { nil }) == none && errno.get() == errno.eexist
		}
		dir.children.delete(leaf)
	}
	unsafe { dir.children['renderD128'] = blocker }
	card_only := register_driver_with_data(&DrmDriver{}, unsafe { nil }) or { panic('unrelated render name blocked a card') }
	assert card_only.dev_id == 0 && card_only.render_node == unsafe { nil }
	unregister_device(card_only)
	assert dir.children.len == 1 && unsafe { dir.children['renderD128'] == blocker }
	dir.children.delete('renderD128')
	assert !drm_devices_lock.held && !vfs_lock.held
}

fn check_registration_allocation_failure() {
	dir := unsafe { devtmpfs_root.children['dri'] }
	for render in [false, true]! {
		driver := DrmDriver{features: if render { driver_render } else { u32(0) }}
		allocations := if render { 9 } else { 5 }
		for _ in 0 .. 8 {
			for successful in 0 .. allocations {
				live := memory.registration_outstanding()
				prior_publications := published_nodes
				memory.fail_registration_after(successful)
				errno.set(0)
				assert register_driver_with_data(&driver, unsafe { nil }) == none && errno.get() == errno.enomem
				memory.fail_registration_after(-1)
				assert memory.registration_outstanding() == live, 'failed registration retained metadata'
				assert published_nodes == prior_publications && dir.children.len == 0
				assert get_device(0) == none && node_names[0] == unsafe { nil } && node_names[128] == unsafe { nil }
				assert !drm_devices_lock.held && !vfs_lock.held
				retry := register_driver_with_data(&driver, unsafe { nil }) or { panic('registration retry failed') }
				assert retry.dev_id == 0 && retry.is_registered()
				assert memory.registration_outstanding() == live + allocations
				unregister_device(retry)
			}
		}
	}
	println('DRM registration: 112 injected failures across DRM metadata and leaf storage allow retry')
}

__global owned_driver = unsafe { &DrmDriver(nil) }
__global owned_ioctl_storage = voidptr(0)

fn new_owned_test_driver() &DrmDriver {
	assert owned_driver == unsafe { nil } && owned_ioctl_storage == unsafe { nil }
	driver := &DrmDriver{features: driver_render, ioctls: [DrmIoctl{cmd: 0x40}]}
	owned_driver = unsafe { driver }
	owned_ioctl_storage = driver.ioctls.data
	return driver
}

fn release_test_driver_ioctls(ioctls []DrmIoctl) {
	if ioctls.flags.has(.nofree) {
		unsafe { ioctls.free() }
		return
	}
	assert owned_driver != unsafe { nil }
	assert owned_ioctl_storage != unsafe { nil } && owned_ioctl_storage == ioctls.data
	unsafe { ioctls.free() }
	owned_ioctl_storage = unsafe { nil }
}

fn release_test_driver(driver &DrmDriver) {
	if driver.ioctls.flags.has(.nofree) {
		memory.free_registration(voidptr(driver))
		return
	}
	assert driver == owned_driver && owned_ioctl_storage == unsafe { nil }
	unsafe { free(driver) }
	owned_driver = unsafe { nil }
}

fn check_owned_driver_registration() {
	mut directory := unsafe { devtmpfs_root.children['dri'] }
	context := u64(0xa551)
	for _ in 0 .. 16 {
		live := memory.registration_outstanding()
		for allocation in 0 .. 9 {
			driver := new_owned_test_driver()
			memory.fail_registration_after(allocation)
			assert register_owned_driver(driver, voidptr(&context)) == none && errno.get() == errno.enomem
			memory.fail_registration_after(-1)
			assert owned_driver == unsafe { nil } && owned_ioctl_storage == unsafe { nil }
			assert memory.registration_outstanding() == live && directory.children.len == 0
		}
		blocker := &VFSNode{}
		unsafe { directory.children['renderD128'] = blocker }
		driver := new_owned_test_driver()
		assert register_owned_driver(driver, voidptr(&context)) == none && errno.get() == errno.eexist
		assert owned_driver == unsafe { nil } && owned_ioctl_storage == unsafe { nil }
		assert memory.registration_outstanding() == live && directory.children.len == 1
		assert unsafe { directory.children['renderD128'] == blocker }
		directory.children.delete('renderD128')
	}
	driver := new_owned_test_driver()
	device := register_owned_driver(driver, voidptr(&context)) or { panic('owned registration retry failed') }
	assert device.driver == driver && device.driver_data == voidptr(&context)
	assert owned_driver == driver && owned_ioctl_storage == device.driver.ioctls.data
	unregister_device(device)
	assert device.driver.ioctls[0].cmd == 0x40 && device.driver_data == voidptr(&context)
	assert context == 0xa551
	owned_driver = unsafe { nil }
	owned_ioctl_storage = unsafe { nil }
	println('DRM owned registration: 160 failed attempts release the driver and ioctl table, and a published device keeps both')
}

const published_ioctl_table = [DrmIoctl{cmd: 0x40}, DrmIoctl{cmd: 0x41}]!

fn check_driver_definition_registration() {
	directory := unsafe { devtmpfs_root.children['dri'] }
	ioctls := unsafe { static_ioctl_table(&published_ioctl_table[0], published_ioctl_table.len) }
	definition := DrmDriver{name: 'static-table', features: driver_render, ioctls: ioctls}
	assert ioctls.data == unsafe { voidptr(&published_ioctl_table[0]) }
	assert ioctls.len == published_ioctl_table.len && ioctls.flags.has(.nofree)
	for _ in 0 .. 8 {
		live := memory.registration_outstanding()
		prior_publications := published_nodes
		for allocation in 0 .. 10 {
			memory.fail_registration_after(allocation)
			errno.set(0)
			assert register_driver_definition(definition, unsafe { nil }) == none && errno.get() == errno.enomem
			memory.fail_registration_after(-1)
			assert memory.registration_outstanding() == live && published_nodes == prior_publications
			assert get_device(0) == none && directory.children.len == 0
			assert ioctls[0].cmd == 0x40 && ioctls[1].cmd == 0x41
		}
	}
	device := register_driver_definition(definition, unsafe { nil }) or { panic('definition retry failed') }
	assert device.dev_id == 0 && device.driver.ioctls.data == ioctls.data
	unregister_device(device)
	assert device.driver.ioctls[1].cmd == 0x41
	println('DRM driver definition: 80 allocation failures release storage and preserve the static ioctl table')
}

fn check_drm_names() {
	mut buffer := [32]u8{}
	name := drm_node_name(unsafe { &buffer[0] }, 'renderD', ~u64(0), true)
	assert name == 'dri/renderD18446744073709551615' && name.len == 31
	assert buffer[31] == 0 && name.str == unsafe { &buffer[0] }
}

fn check_registration() {
	check_drm_names()
	check_registration_collisions()
	check_registration_allocation_failure()
	check_owned_driver_registration()
	check_driver_definition_registration()
	for render in [false, true]! {
		driver := DrmDriver{features: if render { driver_render } else { u32(0) }}
		dev := register_driver_with_data(&driver, voidptr(0x1234)) or { panic('registration failed') }
		assert dev.is_registered() && dev.driver_data == voidptr(0x1234)
		assert dev.dev_id == 0
		assert (get_device(dev.dev_id) or { panic('registry entry missing') }) == dev
		mut card := unsafe { dev.node }
		assert (card.open(0) or { panic('primary node failed to open') }) == card.box
		if render {
			mut render_node := unsafe { dev.render_node }
			assert (render_node.open(0) or { panic('render node failed to open') }) == render_node.box
		} else {
			assert dev.render_node == unsafe { nil }
		}
		unregister_device(dev)
		assert get_device(dev.dev_id) == none
		assert node_names[0] == unsafe { nil } && node_names[128] == unsafe { nil }
		expect_unavailable(mut card)
		if render {
			mut render_node := unsafe { dev.render_node }
			expect_unavailable(mut render_node)
		}
	}
	assert !drm_devices_lock.held
	check_slot_reuse()
	check_unregistered_mapping_admission()
	check_file_close_after_unregister()
	println('DRM registration: name collisions, paired publication, 64 active slots and safe ID reuse passed')
}

__global close_device = unsafe { &DrmDevice(nil) }
__global closed_handle = voidptr(0)
__global destroyed_owner = u64(0)

fn close_test_file(dev &DrmDevice, handle voidptr) {
	assert dev == close_device
	assert closed_handle == unsafe { nil }
	closed_handle = handle
}

fn destroy_owner(owner u64) {
	assert destroyed_owner == 0
	destroyed_owner = owner
}

fn check_file_close_after_unregister() {
	driver := DrmDriver{file_close: close_test_file}
	old := register_driver_with_data(&driver, unsafe { nil }) or { panic('initial registration failed') }
	defer { close_device = unsafe { nil } }
	close_device = unsafe { old }
	mut node := unsafe { old.node }
	data := NodeHandle{}
	path := NodeHandle{flags: o_path}
	assert (node.open(0) or { panic('data open failed') }) == node.box
	node.refcount++
	unregister_device(old)
	replacement := register_driver_with_data(&driver, unsafe { nil }) or { panic('replacement registration failed') }
	defer { unregister_device(replacement) }
	assert replacement.dev_id == old.dev_id
	assert (node.open(o_path) or { panic('metadata-only open failed') }) == node.box
	node.refcount++
	node.unref(voidptr(&path)) or { panic('metadata-only close failed') }
	assert node.refcount == 1 && closed_handle == unsafe { nil } && destroyed_owner == 0
	node.unref(voidptr(&data)) or { panic('data close failed') }
	assert node.refcount == 0 && closed_handle == voidptr(&data) && destroyed_owner == u64(&data)
	closed_handle = unsafe { nil }
	destroyed_owner = 0
	println('DRM close: metadata handles skip driver cleanup and old data handles close on their original device')
}

__global mapping_device = unsafe { &DrmDevice(nil) }
__global mapping_refs = 0

fn retain_test_mapping(dev &DrmDevice, _ voidptr, _ u64, _ u64) bool {
	assert dev == mapping_device
	mapping_refs++
	return true
}

fn admit_test_mapping(dev &DrmDevice, handle voidptr, offset u64, len u64, shared_mapping bool) int {
	assert shared_mapping && retain_test_mapping(dev, handle, offset, len)
	return 0
}

fn release_test_mapping(dev &DrmDevice, _ voidptr, _ u64, _ u64) {
	assert dev == mapping_device && mapping_refs > 0
	mapping_refs--
}

fn check_unregistered_mapping_admission() {
	handle := voidptr(1)
	for driver in [DrmDriver{},
		DrmDriver{mmap_retain: retain_test_mapping, mmap_release: release_test_mapping},
		DrmDriver{mmap_admit: admit_test_mapping, mmap_retain: retain_test_mapping, mmap_release: release_test_mapping}]! {
		old := register_driver_with_data(&driver, voidptr(1)) or { panic('initial registration failed') }
		mapping_device = unsafe { old }
		mut old_node := unsafe { old.node }
		assert old_node.admit_mapping_range(handle, 0, 4096, map_shared) && old_node.mapping_can_grow()
		unregister_device(old)
		replacement := register_driver_with_data(&DrmDriver{}, voidptr(2)) or { panic('replacement registration failed') }
		assert replacement.dev_id == old.dev_id
		mut new_node := unsafe { replacement.node }
		assert new_node.admit_mapping_range(handle, 0, 4096, map_shared) && new_node.mapping_can_grow()
		errno.set(0)
		assert !old_node.admit_mapping_range(handle, 0, 4096, map_shared) && errno.get() == errno.enodev
		assert !old_node.mapping_can_grow()
		assert old_node.retain_mapping_range(handle, 0, 4096, map_shared)
		assert mapping_refs == if driver.mmap_retain != unsafe { nil } { 2 } else { 0 }
		old_node.release_mapping_range(handle, 0, 4096, map_shared)
		old_node.release_mapping_range(handle, 0, 4096, map_shared)
		assert mapping_refs == 0
		new_node.release_mapping_range(handle, 0, 4096, map_shared)
		unregister_device(replacement)
	}
	mapping_device = unsafe { nil }
	println('DRM mmap: unregister blocks new mappings and growth while old mappings retain their device')
}

fn check_slot_reuse() {
	driver := DrmDriver{features: driver_render}
	mut devices := [64]&DrmDevice{}
	for index in 0 .. devices.len {
		dev := register_driver_with_data(&driver, voidptr(u64(index) + 1)) or { panic('active slot missing') }
		assert dev.dev_id == u32(index)
		devices[index] = unsafe { dev }
	}
	assert register_driver_with_data(&driver, unsafe { nil }) == none
	assert register_owned_driver(new_owned_test_driver(), unsafe { nil }) == none
	assert owned_driver == unsafe { nil } && owned_ioctl_storage == unsafe { nil }
	old := devices[13]
	mut old_card := unsafe { old.node }
	mut old_render := unsafe { old.render_node }
	unregister_device(old)
	for _ in 0 .. 70 {
		replacement := register_driver_with_data(&driver, voidptr(0xffff)) or { panic('cannot reuse minor number') }
		assert replacement != old && replacement.dev_id == old.dev_id
		unregister_device(old)
		assert (get_device(13) or { panic('stale unregister removed the replacement') }) == replacement
		assert node_names[13] == replacement.node && node_names[141] == replacement.render_node
		assert old.driver_data == voidptr(14)
		expect_unavailable(mut old_card)
		expect_unavailable(mut old_render)
		unregister_device(replacement)
	}
	for dev in devices { unregister_device(dev) }
	for node in node_names { assert node == unsafe { nil } }
}
