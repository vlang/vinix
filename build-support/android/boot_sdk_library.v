// SPDX-License-Identifier: GPL-2.0-or-later
module main

import cpythonhost

@[export: 'vinix_android_boot_sdk']
fn entry(operation &char, namespace voidptr, arguments voidptr, pins voidptr) voidptr {
	return cpythonhost.boot_entry(operation, namespace, arguments, pins)
}
