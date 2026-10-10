// SPDX-License-Identifier: GPL-2.0-or-later
module main

import cpythonhost

@[export: 'vinix_vulkan_sdk']
fn entry(operation &char, namespace voidptr, arguments voidptr, pins voidptr) voidptr {
	return cpythonhost.vulkan_entry(operation, namespace, arguments, pins)
}

@[export: 'vinix_vulkan_prepare_take']
fn take(capsule voidptr, index i32) voidptr {
    return cpythonhost.vulkan_prepare_take(capsule, index)
}

@[export: 'vinix_vulkan_prepare_dispose']
fn dispose(capsule voidptr) {
    cpythonhost.vulkan_prepare_dispose(capsule)
}
