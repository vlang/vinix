// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import errno

struct NodeBox {}

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
__global next_dev_id = u32(0)
__global registered_devices [64]&DrmDevice
__global staged_card = unsafe { &DrmNode(nil) }
__global fail_render = false

fn shared_timeline_stub() {}

fn expect_unavailable(mut node DrmNode) {
	errno.set(0)
	assert node.open(0) == none && errno.get() == errno.enodev
	request := (u64(`d`) << 8) | 0x00
	expect_error(mut node, request, unsafe { nil }, errno.enodev)
}

fn create_device_node(dev &DrmDevice, _ string, _ u64, render bool) ?&DrmNode {
	assert drm_devices_lock.held && registered_devices[dev.dev_id] == unsafe { nil }
	mut node := &DrmNode{dev: unsafe { dev }, box: &NodeBox{}}
	// Opening a visible primary node can race creation of the render node.
	expect_unavailable(mut node)
	if render {
		expect_unavailable(mut staged_card)
		if fail_render { return none }
	} else {
		staged_card = unsafe { node }
	}
	return node
}

fn check_registration() {
	for render in [false, true]! {
		driver := DrmDriver{features: if render { driver_render } else { u32(0) }}
		dev := register_driver_with_data(&driver, voidptr(0x1234)) or { panic('registration failed') }
		assert dev.is_registered() && dev.driver_data == voidptr(0x1234)
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
		expect_unavailable(mut card)
		if render {
			mut render_node := unsafe { dev.render_node }
			expect_unavailable(mut render_node)
		}
	}
	fail_render = true
	failed_id := next_dev_id
	assert register_driver_with_data(&DrmDriver{features: driver_render}, unsafe { nil }) == none
	assert get_device(failed_id) == none
	expect_unavailable(mut staged_card)
	assert !drm_devices_lock.held
	println('DRM registration: node opens follow publication and stop on failure or unregister')
}
