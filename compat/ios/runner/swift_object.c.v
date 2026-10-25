// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Objective-C root metadata only. Swift heap storage and reference counts have
// a separate ABI and must never be replaced by the shim's NSObject storage.
fn swift_object_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == '_TtCs12_SwiftObject' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic SwiftObject superclass chain')
}

fn swift_object_types(selector string) ?string {
	return match selector {
		'class', 'superclass' { '#16@0:8' }
		'self' { '@16@0:8' }
		'isKindOfClass:' { 'B24@0:8#16' }
		'respondsToSelector:' { 'B24@0:8:16' }
		'conformsToProtocol:' { 'B24@0:8@16' }
		else { return none }
	}
}

fn swift_object_unsupported(selector string) bool {
	if _ := swift_object_types(selector) { return false }
	return true
}

fn swift_object_require_storage(cls u64) {
	if swift_object_family(cls) {
		panic('iOS: SwiftObject construction and Objective-C instance operations are not implemented')
	}
}

fn swift_object_publish() {
	mut info := ios_runtime.classes[ios_runtime.names['_TtCs12_SwiftObject']] or { panic('iOS: missing SwiftObject') }
	info.ivars['isa'] = &ObjIvar{name: 'isa'.clone(), types: '#'.clone(), offset: 0, size: 8}
	info.protocols << ios_runtime.protocol_names['NSObject']
}
