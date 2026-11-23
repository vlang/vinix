// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import memory
import resource

__global (
	retain_executable_node fn (voidptr)
	release_executable_node fn (voidptr)
)

pub fn on_executable_node(retain fn (voidptr), release fn (voidptr)) {
	retain_executable_node = retain
	release_executable_node = release
}

// Install on a private new map. A caller opening an executable already has a
// temporary claim and a reference, and fork has the parent's claim as well.
pub fn retain_executable(mut pagemap memory.Pagemap, res &resource.Resource, node voidptr) ? {
	pagemap.executable_access.acquire(res, true)?
	mut executable := unsafe { res }
	resource.retain_resource(mut executable)
	pagemap.executable = executable
	retain_executable_node(node)
	pagemap.executable_node = node
}

fn release_executable(mut pagemap memory.Pagemap) {
	if pagemap.executable == unsafe { nil } { return }
	pagemap.executable_access.release()
	mut executable := pagemap.executable
	pagemap.executable = unsafe { nil }
	resource.release_resource(mut executable)
	release_executable_node(pagemap.executable_node)
}
