// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn test_deployment_decoder_retires_locked_records_on_success_and_refusal() {
	pin := DeploymentPin{ id: 'app', version: '1.0.0', architecture: 'aarch64', repository: 'fixture',
		public_key: 'a'.repeat(64), minimum_sequence: 1, metadata_sha256: 'b'.repeat(64) }
	other := DeploymentPin{ ...pin, id: 'runtime', minimum_sequence: 2 }
	text := json2.encode(DeploymentDocument{ format: 2, architecture: 'aarch64', packages: ['app'], locked: [pin, other] })
	roots := '{"format":1,"architecture":"aarch64","packages":["app"]}'
	invalid := [text.replace('"minimum_sequence":2', '"minimum_sequence":false'),
		text.replace('"format":2', '"format":1'), text + ' trailing']!
	for input in invalid { assert input != text }
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 64 {
		for input in [roots, text]! {
			mut document := decode_deployment_document(input)!
			document.close()
		}
		for input in invalid {
			if mut value := decode_deployment_document(input) { value.close(); assert false } else { unsafe { err.free() } }
		}
	}
	$if track_heap ? {
		kept := C.vinix_heap_end()
		count := C.vinix_heap_count()
		println('DEPLOYMENT DECODER retained ${kept} bytes / ${count} allocations across 320 attempts')
		assert kept == 0 && count == 0
	}
}

fn test_deployment_wire_documents_own_fields_and_require_the_exact_versioned_shape() {
	mut source := '{"locked":[{"id":"app","version":"1.0.0","architecture":"all","repository":"publisher","public_key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","minimum_sequence":18446744073709551615,"metadata_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}],"packages":["app"],"architecture":"x86_64","format":2}'.clone()
	mut document := decode_deployment_document(source)!
	unsafe { source.free() }
	assert document.format == 2 && document.architecture == 'x86_64' && document.packages == ['app']
	assert document.locked[0].repository == 'publisher' && document.locked[0].minimum_sequence == ~u64(0)
	document.close(); document.close()
	assert document.packages.len == 0 && document.locked.len == 0 && document.architecture == ''
	mut roots := decode_deployment_document('{"format":1,"architecture":"aarch64","packages":[]}')!
	assert roots.format == 1 && roots.locked.len == 0; roots.close()
	for text in ['{"format":1,"architecture":"aarch64","packages":[],"locked":[]}',
		'{"format":2,"architecture":"x86_64","packages":[]}',
		'{"format":2,"architecture":"x86_64","packages":[],"locked":null}',
		'{"format":2,"architecture":"x86_64","packages":[],"locked":[] ,"forma\\u0074":2}',
		'{"format":2,"architecture":"x86_64","packages":[],"locked":[{"id":"app"}]}'] {
		if mut value := decode_deployment_document(text) { value.close(); assert false } else { unsafe { err.free() } }
	}
	println('Deployment document protocol: owned strings, repeatable close, full-width sequence, formats 1/2 and exact required schema PASS')
}
