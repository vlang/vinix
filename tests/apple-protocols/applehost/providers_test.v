// SPDX-License-Identifier: GPL-2.0-only
module applehost

import fixturehost
import hosttest
import os

fn synthetic_provider(names []string) string {
	mut text := 'module provider\n'
	for name in names { text += "@[export: '" + name + "']\npub fn " + name + '() { if true { } }\n' }
	return text
}

fn test_whole_definition_ranges_and_retained_text() {
	original := synthetic_provider(spi_hardware) + '\u2000// kernel_read32\n'
	copied, omitted, parts := remove_hardware(original, spi_hardware, 'spi')!
	assert copied == 'module provider\n\u2000// kernel_read32\n'
	assert parts.join('') == copied
	assert omitted.len == 5
	first := omitted[0].as_map()
	assert first['first_line']!.int() == 2 && first['last_line']!.int() == 3
	ref := first['original_references']!.as_array()[0].as_map()
	assert ref['kind']!.str() == 'comment'
	assert ref['line']!.int() == 12
}

fn test_original_definition_and_reference_errors() {
	for original in ['', "@[export: 'kernel_read32']\npub fn kernel_read32()",
		"@[export: 'kernel_read32']\npub fn kernel_read32() {", synthetic_provider(spi_hardware) + 'kernel_read32()'] {
		if _, _, _ := remove_hardware(original, spi_hardware, 'spi') { assert false } else {
			assert err is ProviderError
			assert err.kind in ['RuntimeError', 'ValueError', 'IndexError']
		}
	}
	assert word_hits('漢kernel_read32字', 'kernel_read32').len == 0
	assert word_hits('\xf0\x9e\x8a\x90kernel_read32\xf0\x91\xbc\x82', 'kernel_read32').len == 1
}

fn test_provider_read_errors_retire_all_descriptors() {
	work := hosttest.work_dir('', 'vinix-apple-provider-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	os.mkdir_all(work + '/kernel/apple/spi_keyboard/spicore')!
	fixturehost.write(work + '/kernel/apple/spi_keyboard/spicore/core.v', '\xff')!
	mut before := os.ls('/dev/fd')!
	before.sort()
	for index in 0 .. 100 {
		out := work + '/out-' + index.str()
		if _ := copy_provider(work, out, 'spi', false, true) { assert false } else {
			assert err is hosttest.ModuleDecodeError && err.data.hex() == 'ff'
		}
		assert os.is_dir(out)
		assert os.ls(out)!.len == 0
		os.rmdir(out)!
	}
	mut after := os.ls('/dev/fd')!
	after.sort()
	assert before == after
}

fn test_ext2_bytes_and_single_import_insertion() {
	work := hosttest.work_dir('', 'vinix-apple-storage-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	os.mkdir_all(work + '/kernel/apple/ans/ext2core')!
	os.mkdir_all(work + '/kernel/apple/ans/anscore')!
	fixturehost.write(work + '/kernel/apple/ans/ext2core/core.v', 'module ext2core\nmodule ext2core\n\x00\xff')!
	fixturehost.write(work + '/kernel/apple/ans/anscore/core.v', synthetic_provider(ans_hardware))!
	result := copy_provider(work, work + '/out', 'ans', true, false)!
	assert result['excluded_functions']!.as_array().len == 8
	assert fixturehost.read(work + '/out/core.v')! == 'module ext2core\nimport ext2core.anscore as _\nmodule ext2core\n\x00\xff'
	assert fixturehost.read(work + '/out/anscore/core.v')! == 'module provider\n'
}
