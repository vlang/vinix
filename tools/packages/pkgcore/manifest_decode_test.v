// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import strings
import time

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn manifest_selected(selection string) bool {
	return os.args.len != 3 || os.args[1] != '--manifest-case' || os.args[2] == selection
}

fn manifest_sample(architecture string) Package {
	return Package{ id: 'data', name: 'Data é🚀', version: '1.0.0', architecture: architecture,
		description: 'Quotes "firmware":false and brackets [] {}', homepage: 'https://example.invalid',
		kind: 'data', license: 'MIT', arguments: ['--title="Data"'], permissions: ['files'], associations: ['text/plain'],
		dependencies: [Dependency{ id: 'base', minimum: '1.0.0', before: '2.0.0' }],
		files: [Payload{ path: 'share/data', sha256: 'a'.repeat(64), bytes: 1 }] }
}

// Stream large fixture inventories from one canonical package, keeping generic
// encoder scratch outside the decoder measurement and the guest's live budget.
fn manifest_document(count int, architecture string) string {
	p := manifest_sample(architecture); defer { close_decoded_package(p) }
	text := json2.encode(p); defer { unsafe { text.free() } }
	start := text.index('"files":[') or { panic('fixture files missing') } + '"files":['.len
	end := text.index('],"sdk":') or { panic('fixture sdk missing') }
	mut out := strings.new_builder(count * 160 + 1024); defer { unsafe { out.free() } }
	out.write_string(unsafe { tos(text.str, start) })
	for i in 0 .. count {
		if i > 0 { out.write_u8(`,`) }
		out.write_string('{"path":"share/')
		digits := i.str(); out.write_string(digits); unsafe { digits.free() }
		out.write_string('","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bytes":1,"executable":false}')
	}
	out.write_string(unsafe { tos(text.str + end, text.len - end) })
	return out.str()
}

fn manifest_refusal(text string, inventory bool) {
	if value := decode_manifest(text, inventory) { close_decoded_package(value); assert false }
	else {
		message := err.msg(); assert message != ''
		if text.contains('"audio","display","files","network","process","files"') { assert message.contains('distinct SDK 1 grants') }
		unsafe { message.free(); err.free() }
	}
}

fn test_manifest_decode_owns_complete_and_growing_template_and_inventory_fields() {
	if os.args.len == 3 && os.args[1] == '--manifest-case' && !os.args[2].starts_with('owned-') { return }
	cycles := $if track_heap ? { 1000 } $else { 64 }
	for architecture in ['aarch64', 'x86_64']! {
		for mode in ['template', 'inventory']! {
			inventory := mode == 'inventory'
			for count in [1, 64, max_files]! {
				if !manifest_selected('owned-' + architecture + '-' + mode + '-' + count.str()) { continue }
				text := manifest_document(count, architecture); defer { unsafe { text.free() } }
				last_path := 'share/' + (count - 1).str()
				tracked := count != max_files
				$if track_heap ? { if tracked { C.vinix_heap_begin() } }
				for _ in 0 .. if tracked { cycles } else { 1 } {
					value := decode_manifest(text, inventory)!
					assert value.architecture == architecture && value.files.len == count && value.files[count - 1].path == last_path
					assert value.name == 'Data é🚀' && value.sdk == 1 && value.window_protocol == 0
					assert value.arguments[0] == '--title="Data"' && value.dependencies[0].before == '2.0.0' && value.files[0].bytes == 1
					close_decoded_package(value)
				}
				$if track_heap ? { if tracked {
					kept := C.vinix_heap_end(); assert kept == 0
					println('MANIFEST DECODE ' + architecture + ' ' + mode + ' ' + count.str() + ' payloads: 1000 cycles retained ' + kept.str() + ' bytes')
				} }
				if !tracked { continue }
				source := text.clone()
				first := decode_manifest(source, inventory)!; second := decode_manifest(source, inventory)!
				assert first == second && first.name.str != second.name.str && first.files.data != second.files.data
				close_decoded_package(first); unsafe { source.free() }
				assert second.files[count - 1].path == last_path && json2.encode(second) == text
				close_decoded_package(second)
			}
		}
	}
	println('MANIFEST DECODE both architectures, owned template/inventory fields, independent results, exact canonical bytes and full 16384 payload bounds PASS')
}

fn test_manifest_decode_preserves_source_defaults_and_requires_complete_inventory() {
	if !manifest_selected('defaults') { return }
	cycles := $if track_heap ? { 1000 } $else { 64 }
	inputs := ['{}', '{"sdk":1,"window_protocol":0}',
		'{"dependencies":[{}, {"id":"base"}],"files":[{}, {"path":"ignored"}]}',
		'{"id":"data","name":"Data","version":"1.0.0","architecture":"all","kind":"data","license":"MIT"}']
	for text in inputs {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. cycles {
			p := decode_manifest(text, false)!
			assert p.sdk == 1 && p.window_protocol == 0 && !p.proprietary && !p.firmware
			assert p.permissions.len == 0 && p.arguments.len == 0 && p.associations.len == 0
			if p.dependencies.len > 0 { assert p.dependencies[0] == Dependency{} && p.dependencies[1].minimum == '' && p.files[0] == Payload{} }
			close_decoded_package(p)
			manifest_refusal(text, true)
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
	}
	full := decode_manifest('{"files":[{"bytes":18446744073709551615}],"sdk":2147483647,"window_protocol":2147483647}', false)!
	assert full.files[0].bytes == ~u64(0) && full.sdk == max_i32 && full.window_protocol == max_i32
	close_decoded_package(full)
	println('MANIFEST DECODE omitted package/dependency/payload defaults, full integer ranges and complete-inventory refusals retire scratch PASS')
}

fn test_manifest_decode_retires_every_truncated_prefix_and_late_refusals() {
	if !manifest_selected('refusals') { return }
	cycles := $if track_heap ? { 1000 } $else { 64 }
	p := manifest_sample('aarch64'); text := json2.encode(p)
	invalid_utf8 := [u8(0xc0), 0xaf].bytestr()
	inputs := [text + 'true', text.replace('"files":', '"unknown":{},"files":'),
		text.replace('"firmware":false', '"firmware":false,"firm\\u0077are":false'),
		text.replace('"arguments":["--title=\\"Data\\""]', '"arguments":null'),
		text.replace('"permissions":["files"]', '"permissions":["files","files"]'),
		text.replace('"permissions":["files"]', '"permissions":[null]'), text.replace('"associations":["text/plain"]', '"associations":null'),
		text.replace('Data é🚀', invalid_utf8), text.replace('Data é🚀', '\\uD800'),
		text.replace('"bytes":1', '"bytes":18446744073709551616'), text.replace('"bytes":1', '"bytes":1.0'),
		text.replace('"bytes":1', '"bytes":01'), text.replace('"bytes":1', '"bytes":1e0'),
		text.replace('"sdk":1', '"sdk":"1"'), text.replace('"files":[', '"files":[null,'),
		text.replace('"minimum":"1.0.0"', '"minimum":null'), text.replace('"executable":false', '"executable":null'),
		text.replace('"permissions":["files"]', '"permissions":["audio","display","files","network","process","files"]')]
	for inventory in [false, true]! {
		$if track_heap ? { C.vinix_heap_begin() }
		for end in 0 .. text.len { manifest_refusal(unsafe { tos(text.str, end) }, inventory) }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
		for number, input in inputs {
			$if track_heap ? { C.vinix_heap_begin() }
			for _ in 0 .. cycles { manifest_refusal(input, inventory) }
			$if track_heap ? {
				kept := C.vinix_heap_end(); assert kept == 0
				println('MANIFEST DECODE refusal ' + number.str() + ' inventory=' + inventory.str() + ': 1000 cycles retained ' + kept.str() + ' bytes')
			}
		}
	}
	println('MANIFEST DECODE every truncated prefix and schema/UTF8/number/permission refusal cycles retire scratch PASS')
}

fn test_manifest_decode_enforces_metadata_and_nested_bounds_before_publication() {
	if !manifest_selected('bounds') { return }
	for inventory in [false, true]! {
		text := if inventory { manifest_document(1, 'x86_64') } else { '{}' }
		for size in [max_metadata - 1, max_metadata]! {
			padding := ' '.repeat(size - text.len); padded := text + padding
			p := decode_manifest(padded, inventory)!; close_decoded_package(p)
			unsafe { padded.free(); padding.free() }
		}
		padding := ' '.repeat(max_metadata + 1 - text.len); oversized := text + padding
		manifest_refusal(oversized, inventory); unsafe { oversized.free(); padding.free() }
		manifest_refusal(manifest_document(max_files + 1, 'x86_64'), inventory)
	}
	p := manifest_sample('aarch64')
	for inventory in [false, true]! {
		for pair in [json2.encode(Package{ ...p, arguments: []string{len: 65, init: 'argument'} }),
			json2.encode(Package{ ...p, dependencies: []Dependency{len: 129, init: Dependency{ id: 'base' }} }),
			json2.encode(Package{ ...p, associations: []string{len: 129, init: 'text/plain'} }),
			json2.encode(Package{ ...p, description: 'd'.repeat(4097) })] { manifest_refusal(pair, inventory) }
	}
	println('MANIFEST DECODE exact 8 MiB and limit-minus-one accepted; metadata/payload/argument/dependency/association/string overflows refused PASS')
}

fn test_manifest_decode_pack_refusal_leaves_destination_absent_and_retry_uses_source_files() {
	if !manifest_selected('pack') { return }
	root := os.temp_dir() + '/vinix-manifest-decode-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(root + '/source/share')!; defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/source/share/data', 'payload')!
	path := root + '/manifest.json'; destination := root + '/repository'
	minimal := '{"id":"data","name":"Data","version":"1.0.0","architecture":"all","kind":"data","license":"MIT","files":[{}]}'
	for invalid in [minimal[..minimal.len - 3], minimal.replace('"files":[{}]', '"files":null'),
		minimal.replace('"name":"Data"', '"name":"Data","na\\u006de":"Other"'),
		minimal.replace('"files":[{}]', '"permissions":["files","files"]')] {
		os.write_file(path, invalid)!
		if _ := pack(path, root + '/source', destination) { assert false } else { assert err.msg() != '' }
		assert !os.exists(destination) && os.read_file(path)! == invalid && os.read_file(root + '/source/share/data')! == 'payload'
	}
	os.write_file(path, minimal)!
	value := pack(path, root + '/source', destination)!
	assert value.files.len == 1 && value.files[0].path == 'share/data' && value.files[0].bytes == 7
	assert !value.files[0].executable && value.sdk == 1 && value.window_protocol == 0
	assert os.read_file(destination + '/manifests/data-all-1.0.0.json')! == json2.encode(value) + '\n'
	println('MANIFEST DECODE invalid pack input preserves source and absent destination; restored template defaults and captured inventory publish unchanged canonical bytes PASS')
}
