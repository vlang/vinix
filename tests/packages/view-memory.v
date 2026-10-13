// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import tools.packages.pkgprotocol

#include "@VMODROOT/../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn consume_view(text string, expected bool) {
	mut accepted := true
	mut view := pkgprotocol.decode_software_view(text) or { accepted = false; unsafe { err.free() }; pkgprotocol.SoftwareView{} }
	view.close()
	assert accepted == expected
}

fn main() {
	mut rows := []pkgprotocol.SoftwareRow{cap: 32}
	for index in 0 .. 32 {
		rows << pkgprotocol.SoftwareRow{ id: 'app-' + index.str(), name: 'Application é🚀', description: 'Complete description é🚀 '.repeat(16),
			version: '2.0.0', installed_version: '1.0.0', installed_name: 'Installed application', installed_kind: 'native',
			installed_permissions: ['display'], installed_window_protocol: 2, architecture: 'aarch64', kind: 'linux', runtime: 'runtime',
			repository: 'publisher', public_key: 'a'.repeat(64), license: 'Vendor-EULA', proprietary: true, firmware: true,
			permissions: ['files', 'network'], requested: true, updatable: true, update_action: 'update' }
	}
	text := json2.encode(pkgprotocol.SoftwareView{format: 1, generation: 7, architecture: 'aarch64', rows: rows})
	legacy := text.replace('"installed_name":"Installed application",', '').replace('"installed_kind":"native",', '')
		.replace('"installed_permissions":["display"],', '').replace('"installed_window_protocol":2,', '')
	additive := text[..text.len - 1] + ',"' + 'long-future-key-'.repeat(16) + '":{"unicode":"' + 'é🚀'.repeat(1024) + '","numbers":[null,true,false,-1.5e+2,1e9999]}}'
	invalid := [text.replace('"id":"app-31"', '"id":"app-31","firm\\u0077are":false'),
		text[..text.len - 1] + ',"extra":{"incomplete":}}', text.replace('"generation":7', '"generation":18446744073709551616'),
		additive.replace('"numbers":', '"broken":"\\ud800","numbers":'), text.replace('"installed_permissions":["display"],', '')]
	for warmup in 0 .. 2 {
		if warmup == 1 { C.vinix_heap_begin() }
		for _ in 0 .. 1000 {
			for valid in [text, legacy, additive]! { consume_view(valid, true) }
			for bad in invalid { consume_view(bad, false) }
		}
	}
	kept := C.vinix_heap_end()
	assert kept == 0, 'Software view readers retained ${kept} bytes'
	println('Software view reader: 1000 wide/current/legacy/additive/partial-invalid decode/close cycles retain zero tracked bytes')
}
