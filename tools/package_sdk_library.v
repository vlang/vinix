// SPDX-License-Identifier: GPL-2.0-or-later
module main

import cpythonhost

@[export: 'vinix_package_store_sdk']
fn entry(operation &char, key u64, first voidptr, second voidptr) voidptr {
	return cpythonhost.package_entry(operation, key, first, second)
}
