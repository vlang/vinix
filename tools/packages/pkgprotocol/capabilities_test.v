// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

const capabilities_fixture = '{"format":1,"package_formats":[1],"application_sdks":[1],"native_window_protocols":[1,2],"deployment_formats":[1,2]}'

fn test_capabilities_exact_membership_owns_arrays_and_allows_future_interface_versions() {
	mut source := capabilities_fixture.clone()
	mut value := decode_capabilities(source)!
	unsafe { source.free() }
	assert value.format == 1 && value.package_formats == [1] && value.application_sdks == [1]
	assert value.native_window_protocols == [1, 2] && value.deployment_formats == [1, 2]
	for protocol in 0 .. 3 { assert value.supports_package(1, 1, protocol) }
	for request in [[2, 1, 0]!, [1, 2, 0]!, [1, 1, 3]!, [0, 1, 0]!, [1, 0, 0]!, [1, 1, -1]!] {
		assert !value.supports_package(request[0], request[1], request[2])
	}
	value.close(); value.close()
	assert !value.supports_package(1, 1, 0)
	mut future := decode_capabilities('{"deployment_formats":[1,65535],"native_window_protocols":[1,7],"application_sdks":[1,9],"package_\\u0066ormats":[1,3],"format":1}')!
	defer { future.close() }
	assert future.supports_package(3, 9, 7)
	assert !future.supports_package(2, 1, 0) && !future.supports_package(1, 1, 2)
}

fn capabilities_refused(text string) {
	mut value := decode_capabilities(text) or {
		message := err.msg()
		unsafe { message.free(); err.free() }
		return
	}
	value.close()
	assert false, 'accepted invalid capabilities: ${text}'
}

fn capabilities_consume(text string, expected bool) {
	if mut value := decode_capabilities(text) {
		value.close(); value.close()
		assert expected
	} else {
		message := err.msg()
		unsafe { message.free(); err.free() }
		assert !expected
	}
}

fn test_capabilities_retires_owned_arrays_and_every_partial_decode() {
	$if track_heap ? {
		// Every prefix exercises failure after different spread assignments and
		// partially constructed arrays; all fixture storage predates tracking.
		mut invalid := []string{cap: capabilities_fixture.len + 4}
		for i in 0 .. capabilities_fixture.len { invalid << capabilities_fixture[..i] }
		invalid << capabilities_fixture.replace('"deployment_formats":[1,2]', '"deployment_formats":[1,2,2]')
		invalid << capabilities_fixture.replace('"deployment_formats":[1,2]', '"deployment_formats":[1,65536]')
		invalid << capabilities_fixture + ' false'
		invalid << capabilities_fixture.replace('"format":1', '"format":0')
		reordered := '{"deployment_formats":[1,2],"native_window_protocols":[1,2],"application_sdks":[1],"package_formats":[1],"format":1}'
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			capabilities_consume(capabilities_fixture, true)
			capabilities_consume(reordered, true)
			for text in invalid { capabilities_consume(text, false) }
		}
		kept := C.vinix_heap_end()
		assert kept == 0 && C.vinix_heap_count() == 0, 'capabilities reader retained ${kept} bytes'
		println('PACKAGE CAPABILITIES 1000 decode/refusal/double-close cycles with every truncated prefix retain zero tracked bytes PASS')
	}
}

fn test_capabilities_refuses_ambiguous_unbounded_or_incomplete_wire_input() {
	for field in ['"format":1,', '"package_formats":[1],', '"application_sdks":[1],',
		'"native_window_protocols":[1,2],', ',"deployment_formats":[1,2]'] {
		capabilities_refused(capabilities_fixture.replace(field, ''))
	}
	for fragment in ['"format":1,"format":1', '"format":1,"forma\\u0074":1', '"format":0',
		'"format":2', '"format":01', '"format":1.0', '"format":true', '"format":"1"', '"other":0,"format":1'] {
		capabilities_refused(capabilities_fixture.replace('"format":1', fragment))
	}
	for versions in ['[]', 'null', '{}', '[0]', '[-1]', '[1,1]', '[2,1]', '[1,65536]',
		'[01]', '[1.0]', '[1e0]', '[true]', '["1"]', '[1,]', '[[1]]', '[999999999999999999999]'] {
		capabilities_refused(capabilities_fixture.replace('"package_formats":[1]', '"package_formats":' + versions))
	}
	for text in ['', '{}', 'null', capabilities_fixture + ' false', capabilities_fixture[..capabilities_fixture.len - 1],
		capabilities_fixture.replace('"format"', '"form\\u0000at"'), ' '.repeat(4097)] { capabilities_refused(text) }
	for i in 0 .. capabilities_fixture.len { capabilities_refused(capabilities_fixture[..i]) }
	mut versions := ''
	for i in 1 .. 34 { versions += if i == 1 { '1' } else { ',' + i.str() } }
	capabilities_refused(capabilities_fixture.replace('"package_formats":[1]', '"package_formats":[' + versions + ']'))
}

fn test_capabilities_validates_constructed_values_and_every_list_at_its_bound() {
	mut values := []int{len: 32, init: index + 1}
	mut value := Capabilities{
		package_formats: values.clone(), application_sdks: values.clone()
		native_window_protocols: values.clone(), deployment_formats: values.clone()
	}
	value.validate()!
	value.close()
	unsafe { values.free() }
	for field in ['package_formats', 'application_sdks', 'native_window_protocols', 'deployment_formats'] {
		for versions in ['[]', '[1,1]', '[2,1]', '[0]', '[65536]'] {
			old := if field in ['package_formats', 'application_sdks'] { '[1]' } else { '[1,2]' }
			capabilities_refused(capabilities_fixture.replace('"' + field + '":' + old, '"' + field + '":' + versions))
		}
	}
}
