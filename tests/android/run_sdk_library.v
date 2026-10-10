// SPDX-License-Identifier: GPL-2.0-or-later
module main

import cpythonhost

@[export: 'vinix_android_run_sdk']
fn entry(operation &char, namespace voidptr, arguments voidptr, pins voidptr) voidptr {
	return cpythonhost.run_entry(operation, namespace, arguments, pins)
}

@[export: 'vinix_android_run_take']
fn take(capsule voidptr, index i32) voidptr {
	return cpythonhost.run_take(capsule, index)
}
