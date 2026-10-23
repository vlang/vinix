// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn deployment_writer_require(ok bool) {
	// Explicit checks remain active when this consumer is compiled with -prod.
	if !ok { panic('deployment writer check failed') }
}

fn deployment_writer_refused(document &DeploymentDocument) {
	text := document.encode() or {
		message := err.msg()
		unsafe { message.free(); err.free() }
		return
	}
	unsafe { text.free() }
	panic('deployment writer accepted invalid wire fields')
}

fn deployment_writer_roundtrip(document &DeploymentDocument) {
	text := document.encode() or { panic(err) }
	mut decoded := decode_deployment_document(text) or { panic(err) }
	unsafe { text.free() }
	deployment_writer_require(decoded.format == document.format && decoded.architecture == document.architecture
		&& decoded.packages == document.packages && decoded.locked == document.locked)
	decoded.close(); decoded.close()
	deployment_writer_require(decoded.architecture == '' && decoded.packages.len == 0 && decoded.locked.len == 0)
}

fn test_deployment_writer_preserves_exact_versioned_schema_order_and_borrowed_input() {
	mut roots := ['org.example.z'.clone(), 'org.example.a'.clone()]
	defer { unsafe { for id in roots { id.free() }; (&array(&roots)).free() } }
	document := DeploymentDocument{ format: 1, architecture: 'aarch64', packages: roots }
	text := document.encode()!
	defer { unsafe { text.free() } }
	deployment_writer_require(text == '{"format":1,"architecture":"aarch64","packages":["org.example.z","org.example.a"]}')
	deployment_writer_roundtrip(&document)
	deployment_writer_require(roots[0] == 'org.example.z' && roots[1] == 'org.example.a')
	for format in [1, 2]! {
		empty := DeploymentDocument{ format: format, architecture: 'x86_64' }
		encoded := empty.encode()!
		deployment_writer_require(encoded == if format == 1 {
			'{"format":1,"architecture":"x86_64","packages":[]}'
		} else { '{"format":2,"architecture":"x86_64","packages":[],"locked":[]}' })
		unsafe { encoded.free() }
		deployment_writer_roundtrip(&empty)
	}
	// Wire encoding deliberately preserves semantically invalid identities,
	// duplicates and zero sequences for the service to refuse independently.
	mut pins := [DeploymentPin{ id: 'quote"\\\n\x00é', version: '', architecture: '',
		repository: '', public_key: '', minimum_sequence: ~u64(0), metadata_sha256: '' },
		DeploymentPin{ id: '', minimum_sequence: 0 }]
	defer { unsafe { (&array(&pins)).free() } }
	locked := DeploymentDocument{ format: 2, architecture: '', packages: roots, locked: pins }
	deployment_writer_roundtrip(&locked)
	deployment_writer_require(pins[0].id == 'quote"\\\n\x00é' && pins[0].minimum_sequence == ~u64(0))
	println('DEPLOYMENT WRITER exact format-1/2 schemas, escaping, full u64, caller ownership PASS')
}

fn test_deployment_writer_bounds_every_string_count_and_escaped_wire_size() {
	for format in [-1, 0, 3, 65535]! { deployment_writer_refused(&DeploymentDocument{ format: format }) }
	mut one_pin := [DeploymentPin{}]
	defer { unsafe { (&array(&one_pin)).free() } }
	deployment_writer_refused(&DeploymentDocument{ format: 1, locked: one_pin })
	for bad in ['a'.repeat(17), '\xff'] { deployment_writer_refused(&DeploymentDocument{ format: 1, architecture: bad }) }
	mut roots := ['a'.repeat(128)]
	defer { unsafe { roots[0].free(); (&array(&roots)).free() } }
	mut pins := [DeploymentPin{ id: 'a'.repeat(128), version: 'v'.repeat(29),
		architecture: 'a'.repeat(16), repository: 'r'.repeat(128), public_key: 'k'.repeat(64),
		metadata_sha256: 'd'.repeat(64) }]
	defer { unsafe { close_deployment_pin(pins[0]); (&array(&pins)).free() } }
	deployment_writer_roundtrip(&DeploymentDocument{ format: 2, architecture: 'a'.repeat(16), packages: roots, locked: pins })
	for bad in ['a'.repeat(129), '\xff'] {
		mut bad_roots := [bad]
		deployment_writer_refused(&DeploymentDocument{ format: 1, packages: bad_roots })
		unsafe { (&array(&bad_roots)).free() }
	}
	base := pins[0]
	for field in 0 .. 6 {
		limit := [128, 29, 16, 128, 64, 64]![field]
		for bad in ['a'.repeat(limit + 1), '\xff'] {
			pin := match field {
				0 { DeploymentPin{ ...base, id: bad } }
				1 { DeploymentPin{ ...base, version: bad } }
				2 { DeploymentPin{ ...base, architecture: bad } }
				3 { DeploymentPin{ ...base, repository: bad } }
				4 { DeploymentPin{ ...base, public_key: bad } }
				else { DeploymentPin{ ...base, metadata_sha256: bad } }
			}
			mut bad_pins := [pin]
			deployment_writer_refused(&DeploymentDocument{ format: 2, locked: bad_pins })
			unsafe { (&array(&bad_pins)).free() }
		}
	}
	mut many_roots := []string{len: 4096, init: 'root'}
	mut many_pins := []DeploymentPin{len: 4096, init: DeploymentPin{}}
	unsafe { many_roots.flags |= .noslices; many_pins.flags |= .noslices }
	defer { unsafe { (&array(&many_roots)).free(); (&array(&many_pins)).free() } }
	deployment_writer_roundtrip(&DeploymentDocument{ format: 2, packages: many_roots, locked: many_pins })
	many_roots << 'overflow'
	deployment_writer_refused(&DeploymentDocument{ format: 1, packages: many_roots })
	many_pins << DeploymentPin{}
	deployment_writer_refused(&DeploymentDocument{ format: 2, locked: many_pins })
	control128 := '\x00'.repeat(128)
	control64 := '\x00'.repeat(64)
	control29 := '\x00'.repeat(29)
	control16 := '\x00'.repeat(16)
	defer { unsafe { control128.free(); control64.free(); control29.free(); control16.free() } }
	mut escaped := []DeploymentPin{len: 4096, init: DeploymentPin{ id: control128, version: control29,
		architecture: control16, repository: control128, public_key: control64, metadata_sha256: control64 }}
	defer { unsafe { (&array(&escaped)).free() } }
	oversized := DeploymentDocument{ format: 2, locked: escaped }
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 8 { deployment_writer_refused(&oversized) }
	$if track_heap ? { deployment_writer_require(C.vinix_heap_end() == 0 && C.vinix_heap_count() == 0) }
	println('DEPLOYMENT WRITER UTF-8, per-field/count boundaries and escaped 8 MiB refusal PASS')
}

fn test_deployment_writer_repeated_success_refusal_and_double_close_retire_allocations() {
	$if track_heap ? {
		mut roots := ['z', 'a', 'z']
		key := 'a'.repeat(64)
		digest := 'b'.repeat(64)
		mut pins := []DeploymentPin{len: 256, init: DeploymentPin{ id: 'org.example.app',
			version: '1.0.0', architecture: 'aarch64', repository: 'local', public_key: key,
			minimum_sequence: ~u64(0), metadata_sha256: digest }}
		// Repeated fields share their borrowed storage; only decoded values own it.
		defer { unsafe { key.free(); digest.free(); (&array(&roots)).free(); (&array(&pins)).free() } }
		one := DeploymentDocument{ format: 1, architecture: 'aarch64', packages: roots }
		two := DeploymentDocument{ format: 2, architecture: 'aarch64', packages: roots, locked: pins }
		bad := DeploymentDocument{ format: 1, locked: pins }
		bad_utf8 := DeploymentDocument{ format: 2, architecture: '\xff' }
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			deployment_writer_roundtrip(&one); deployment_writer_roundtrip(&two)
			deployment_writer_refused(&bad); deployment_writer_refused(&bad_utf8)
		}
		kept := C.vinix_heap_end()
		deployment_writer_require(kept == 0 && C.vinix_heap_count() == 0)
		println('DEPLOYMENT WRITER 1000 encode/decode/refusal/double-close cycles with 256 pins retain zero tracked bytes PASS')
	}
}
