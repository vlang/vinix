// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_saved_deployment_receipts_require_complete_typed_bounded_coherent_fields_and_own_strings() {
	text := json2.encode(DeploymentSnapshotSaved{ generation: 7, architecture: 'aarch64', destination: '/部署/file with spaces; $literal.json', sha256: 'a'.repeat(64), roots: 1, packages: 3 })
	mut value := decode_deployment_saved(text)!; assert value.roots == 1 && value.packages == 3; value.close(); value.close()
	mut empty := decode_deployment_saved(json2.encode(DeploymentSnapshotSaved{ architecture: 'x86_64', destination: 'relative.json', sha256: 'b'.repeat(64) }))!; empty.close()
	for bad in [text + '{}', text[..text.len - 1], text.replace('"format":1', '"format":2'),
		text.replace('"format":1', '"format":true'), text.replace('"format":1', '"format":1,"forma\\u0074":1'),
		text.replace('"generation":7', '"generation":-1'), text.replace('"generation":7', '"generation":07'),
		text.replace('"generation":7', '"generation":18446744073709551616'), text.replace('"generation":7', '"generation":0'),
		text.replace('"roots":1', '"roots":4'), text.replace('"roots":1', '"roots":0'), text.replace('"roots":1', '"roots":null'),
		text.replace('"packages":3', '"packages":4097'), text.replace('"architecture":"aarch64"', '"architecture":"all"'),
		text.replace('"format":1', '"format":1,"extra":{}'), text.replace(',"roots":1', ''),
		text.replace('/部署/file with spaces; $literal.json', ''), text.replace('/部署/file with spaces; $literal.json', 'x'.repeat(4097)),
		text.replace('/部署/file with spaces; $literal.json', 'bad\\npath'), text.replace('/部署/file with spaces; $literal.json', '\xff'),
		text.replace('a'.repeat(64), 'A'.repeat(64)), ' '.repeat(32 * 1024 + 1)] {
		mut refused := false; decode_deployment_saved(bad) or { refused = true; message := err.msg(); unsafe { message.free(); err.free() } }; assert refused
	}
	println('DEPLOYMENT SAVED PROTOCOL complete typed fields, duplicate/unknown keys, numeric/path/count/digest bounds and independent closeable strings PASS')
	$if track_heap ? {
		bad := text[..text.len - 1] + ',"extra":{}}'
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			mut saved := decode_deployment_saved(text)!; saved.close()
			decode_deployment_saved(bad) or { message := err.msg(); unsafe { message.free(); err.free() } }
		}
		kept := C.vinix_heap_end(); assert kept == 0, 'saved receipt reader retained ${kept} bytes'
		println('DEPLOYMENT SAVED PROTOCOL 1000 valid/partial-invalid decode/close cycles retain zero tracked bytes PASS')
	}
}
