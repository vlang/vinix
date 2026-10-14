// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn configuration_fixture() RepositoryConfiguration {
	mut repositories := []Repository{cap: 32}
	for index in 0 .. 32 {
		repositories << Repository{ id: 'publisher-' + index.str(), url: 'file:///media/repository é🚀', public_key: '00'.repeat(32) }
	}
	return RepositoryConfiguration{ format: 1, scope: 'configuration', architecture: 'aarch64', repositories: repositories }
}

fn configuration_consume(text string, expected bool) {
	if value := decode_repository_configuration(text) {
		mut owned := value
		owned.close()
		assert expected
	} else {
		message := err.msg()
		unsafe { message.free(); err.free() }
		assert !expected
	}
}

fn test_configuration_reader_requires_explicit_scope_complete_fields_and_valid_identities() {
	fixture := configuration_fixture()
	text := json2.encode(fixture)
	configuration_consume(text, true)
	configuration_consume(text.replace('"scope":', '"sc\\u006fpe":'), true)
	for bad in [text.replace('"scope":"configuration",', ''), text.replace('"scope":"configuration"', '"scope":"history"'),
		text.replace('"scope":"configuration"', '"scope":null'), text.replace('"format":1', '"format":2'),
		text.replace('"architecture":"aarch64"', '"architecture":"i386"'), text.replace('"repositories":[', '"repositories":null,"ignored":['),
		text.replace('"scope":', '"sc\\u006fpe":"configuration","scope":'),
		text.replace('"id":"publisher-31"', '"id":"publisher-0"'), text.replace('"id":"publisher-31",', ''),
		text.replace('"url":"file:///media/repository é🚀"', '"url":"file:///media/../secret"'),
		text.replace('"public_key":"' + '00'.repeat(32) + '"', '"public_key":null'),
		text[..text.len - 1], text + 'true', text[..text.len - 1] + ',"history":[]}', '{}', 'null',
		json2.encode(RepositoryStatus{ format: 1, architecture: 'aarch64', repositories: fixture.repositories })] {
		assert bad != text
		configuration_consume(bad, false)
	}
	if _ := decode_repositories(text) { assert false }
	configuration_consume(' '.repeat(8 * 1024 * 1024 + 1), false)
	mut decoded := decode_repository_configuration(text)!
	decoded.close()
	assert decoded.scope == '' && decoded.repositories.len == 0 && decoded.architecture == ''
	println('REPOSITORY CONFIG protocol explicit scope, complete bounded metadata, legacy separation and owned close PASS')
}

fn test_configuration_reader_retires_valid_and_partial_invalid_metadata() {
	$if track_heap ? {
		text := json2.encode(configuration_fixture())
		invalid := [text.replace('"id":"publisher-31",', ''), text.replace('"scope":"configuration"', '"scope":null'),
			text.replace('"id":"publisher-31"', '"id":"publisher-0"'), text[..text.len - 1]]
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			configuration_consume(text, true)
			for bad in invalid { configuration_consume(bad, false) }
		}
		kept := C.vinix_heap_end()
		assert kept == 0 && C.vinix_heap_count() == 0, 'configuration reader retained ${kept} bytes'
		println('REPOSITORY CONFIG protocol 1000 valid/partial-invalid decode and retirement cycles retain zero tracked bytes PASS')
	}
}
