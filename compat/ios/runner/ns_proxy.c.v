// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Independent Foundation root metadata. Proxy storage and forwarding are not implemented.
fn ns_proxy_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSProxy' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic NSProxy superclass chain')
}

fn ns_proxy_types(selector string) ?string {
	return match selector {
		'class', 'superclass' { '#16@0:8' }
		'self' { '@16@0:8' }
		'isKindOfClass:' { 'B24@0:8#16' }
		'respondsToSelector:' { 'B24@0:8:16' }
		'conformsToProtocol:' { 'B24@0:8@16' }
		else { return none }
	}
}

fn ns_proxy_unsupported(selector string) bool {
	if _ := ns_proxy_types(selector) { return false }
	return true
}

fn ns_proxy_require_forwarding(cls u64) {
	if ns_proxy_family(cls) {
		panic('iOS: NSProxy construction and forwarding are not implemented')
	}
}

fn ns_proxy_publish() {
	mut info := ios_runtime.classes[ios_runtime.names['NSProxy']] or { panic('iOS: missing NSProxy') }
	info.ivars['isa'] = &ObjIvar{name: 'isa'.clone(), types: '#'.clone(), offset: 0, size: 8}
	info.protocols << ios_runtime.protocol_names['NSObject']
}
