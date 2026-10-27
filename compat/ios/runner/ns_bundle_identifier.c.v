// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import plist

fn ns_bundle_identifier_value() u64 {
	path := os.join_path(ios_runtime.bundle, 'Info.plist')
	defer { unsafe { path.free() } }
	bytes := os.read_bytes(path) or { return 0 }
	defer { unsafe { bytes.free() } }
	info := plist.parse(bytes) or { return 0 }
	defer { info.free() }
	if info.kind != .dictionary { return 0 }
	value := info.fields['CFBundleIdentifier'] or { return 0 }
	// Foundation returns the stored plist value, even when it is not a string.
	return plist_owned_object(value)
}

fn ns_bundle_identifier(object u64) u64 {
	C.ios_objc_initialize_lock()
	ns_bundle_resource_bundle(object)
	header := obj_header(object)
	loaded := header.valid // NSBundle owns its cached value in fields[0], including nil.
	current := header.fields[0]
	C.ios_objc_initialize_unlock()
	if loaded { return current }
	// Allocating a plist object can run application constructors. Do not hold
	// the runtime lock while constructing; release any losing candidate.
	candidate := ns_bundle_identifier_value()
	C.ios_objc_initialize_lock()
	ns_bundle_resource_bundle(object)
	mut published := obj_header(object)
	mut adopted := false
	if !published.valid {
		published.fields[0] = candidate
		published.valid = true
		adopted = true
	}
	winner := published.fields[0]
	C.ios_objc_initialize_unlock()
	if !adopted { objc_release(candidate) }
	return winner
}
