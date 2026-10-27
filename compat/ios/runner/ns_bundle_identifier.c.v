// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import plist

fn ns_bundle_info_value() u64 {
	path := os.join_path(ios_runtime.bundle, 'Info.plist')
	defer { unsafe { path.free() } }
	bytes := os.read_bytes(path) or { return objc_allocate(ios_runtime.names['NSMutableDictionary']) }
	defer { unsafe { bytes.free() } }
	info := plist.parse(bytes) or { return objc_allocate(ios_runtime.names['NSMutableDictionary']) }
	defer { info.free() }
	if info.kind != .dictionary { return objc_allocate(ios_runtime.names['NSMutableDictionary']) }
	return plist_owned_object_mode(info, .mutable_containers)
}

fn ns_bundle_info_dictionary(object u64) u64 {
	C.ios_objc_initialize_lock()
	ns_bundle_resource_bundle(object)
	header := obj_header(object)
	loaded := header.valid // NSBundle owns one complete cached plist tree in fields[0].
	current := header.fields[0]
	C.ios_objc_initialize_unlock()
	if loaded { return current }
	// Allocating a plist object can run application constructors. Do not hold
	// the runtime lock while constructing; release any losing candidate.
	candidate := ns_bundle_info_value()
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

fn ns_bundle_identifier(object u64) u64 {
	header := obj_header(ns_bundle_info_dictionary(object))
	for i, key in header.keys {
		if string_text(key) == 'CFBundleIdentifier' { return header.items[i] }
	}
	// Foundation returns the stored value, including non-strings and mutations.
	return 0
}
