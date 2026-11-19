// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import errno

const map_shared = 1

struct NodeBox {
	minor u64
}

struct NodeHandle {
	flags int
}

struct RegistryLock {
mut:
	held bool
}

fn (mut lock_state RegistryLock) acquire() {
	assert !lock_state.held
	lock_state.held = true
}

fn (mut lock_state RegistryLock) release() {
	assert lock_state.held
	lock_state.held = false
}

__global drm_devices_lock RegistryLock
__global registered_devices [64]&DrmDevice
__global node_names [192]&DrmNode
__global staged_card = unsafe { &DrmNode(nil) }
__global fail_render = false

fn shared_timeline_stub() {}

fn expect_unavailable(mut node DrmNode) {
	errno.set(0)
	assert node.open(0) == none && errno.get() == errno.enodev
	assert (node.open(o_path) or { panic('metadata-only open rejected') }) == node.box
	request := (u64(`d`) << 8) | 0x00
	expect_error(mut node, request, unsafe { nil }, errno.enodev)
}

fn drm_node_name(prefix string, number u64) string { return 'dri/${prefix}${number}' }

fn devtmpfs_remove_device(name string, expected &NodeBox) bool {
	assert drm_devices_lock.held
	assert name == drm_node_name(if expected.minor >= 128 { 'renderD' } else { 'card' }, expected.minor)
	mut node := unsafe { node_names[expected.minor] }
	if node == unsafe { nil } || node.box != expected { return false }
	expect_unavailable(mut node)
	node_names[expected.minor] = unsafe { nil }
	node.unref(unsafe { nil }) or { panic('namespace reference release failed') }
	return true
}

fn create_device_node(dev &DrmDevice, prefix string, number u64, render bool) ?&DrmNode {
	assert drm_devices_lock.held && registered_devices[dev.dev_id] == unsafe { nil }
	assert prefix == if render { 'renderD' } else { 'card' }
	assert number == u64(dev.dev_id) + if render { u64(128) } else { u64(0) }
	assert node_names[number] == unsafe { nil }, 'reused device slots must have no visible old name'
	mut node := &DrmNode{dev: unsafe { dev }, box: &NodeBox{minor: number}, refcount: 1}
	// Opening a visible primary node can race creation of the render node.
	expect_unavailable(mut node)
	if render {
		expect_unavailable(mut node_names[dev.dev_id])
		if fail_render { return none }
	} else {
		staged_card = unsafe { node }
	}
	node_names[number] = unsafe { node }
	return node
}

fn check_registration() {
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
	fail_render = true
	assert register_driver_with_data(&DrmDriver{features: driver_render}, unsafe { nil }) == none
	assert get_device(0) == none && node_names[0] == unsafe { nil } && node_names[128] == unsafe { nil }
	expect_unavailable(mut staged_card)
	fail_render = false
	assert !drm_devices_lock.held
	check_slot_reuse()
	check_unregistered_mapping_admission()
	check_file_close_after_unregister()
	println('DRM registration: publication, namespace rollback, 64 active slots and safe ID reuse passed')
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
