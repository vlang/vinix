// SPDX-License-Identifier: GPL-2.0-or-later
module wineheaders

import os
import json2

fn test_complete_resource_tree_and_input_pins() {
	root := os.real_path(os.temp_dir()) + '/vinix-wine-headers-' + os.getpid().str()
	os.mkdir_all(root + '/include/nested')!
	defer { os.rmdir_all(root) or {} }
	file := root + '/include/nested/stddef.h'
	os.write_file(file, '#define HEADER 1\n')!
	mut inputs := map[string]string{}
	expected := capture(root + '/include', mut inputs)!
	assert selection(root + '\n')! == root
	admit(expected, inputs)!
	mut refused := false
	admit(expected, map[string]string{}) or { refused = true }
	assert refused
	mut changed := inputs.clone()
	changed[file] = 'bad'
	refused = false
	admit(expected, changed) or { refused = true }
	assert refused
	os.write_file(file, '#define HEADER 2\n')!
	refused = false
	admit(expected, inputs) or { refused = true }
	assert refused
	os.write_file(file, '#define HEADER 1\n')!
	os.write_file(root + '/include/extra.h', '')!
	refused = false
	admit(expected, inputs) or { refused = true }
	assert refused
	os.rm(root + '/include/extra.h')!
	os.mkdir(root + '/include/extra')!
	refused = false
	admit(expected, inputs) or { refused = true }
	assert refused
	os.rmdir(root + '/include/extra')!
	os.rm(file)!
	refused = false
	admit(expected, inputs) or { refused = true }
	assert refused
	os.write_file(file, '#define HEADER 1\n')!
	admit(expected, inputs)!
}

fn test_linked_resource_entries_and_ambiguous_selection_refuse() {
	root := os.real_path(os.temp_dir()) + '/vinix-wine-header-links-' + os.getpid().str()
	os.mkdir_all(root + '/include')!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/include/stddef.h', '')!
	for text in ['', root, root + '\r\n', root + '\n\n', root + '\x00\n', 'relative\n', root + '/.\n'] {
		mut refused := false
		selection(text) or { refused = true }
		assert refused
	}
	mut inputs := map[string]string{}
	os.symlink(root + '/include/stddef.h', root + '/include/alias.h')!
	mut refused := false
	capture(root + '/include', mut inputs) or { refused = true }
	assert refused
	os.rm(root + '/include/alias.h')!
	os.symlink(root + '/include', root + '/include/linked-directory')!
	refused = false
	capture(root + '/include', mut inputs) or { refused = true }
	assert refused
}

fn test_resource_receipt_binds_discovery_and_actual_compile_selection() {
	root := os.real_path(os.temp_dir()) + '/vinix-wine-header-receipt-' + os.getpid().str()
	os.mkdir_all(root + '/resource/include')!
	os.mkdir_all(root + '/logs')!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/resource/include/stddef.h', '')!
	mut inputs := map[string]string{}
	expected := capture(root + '/resource/include', mut inputs)!
	manifest := json2.encode(expected)
	query := json2.encode(['/opt/homebrew/opt/llvm/bin/clang', '-print-resource-dir'])
	cc := json2.encode(['/opt/homebrew/opt/llvm/bin/clang', '-resource-dir=' + root + '/resource'])
	os.write_file(root + '/clang-headers.json', manifest)!
	os.write_file(root + '/logs/clang-resource.log.argv.json', query)!
	os.write_file(root + '/logs/clang-resource.log', root + '/resource\n')!
	os.write_file(root + '/logs/cc.log.argv.json', cc)!
	admit_producer(root, inputs)!
	for contents in ['[]', json2.encode(['/opt/homebrew/opt/llvm/bin/clang']),
		json2.encode(['/opt/homebrew/opt/llvm/bin/clang', '-resource-dir=' + root + '/resource', '-resource-dir=/other']),
		json2.encode(['/other/clang', '-resource-dir=' + root + '/resource'])] {
		os.write_file(root + '/logs/cc.log.argv.json', contents)!
		mut refused := false
		admit_producer(root, inputs) or { refused = true }
		assert refused
	}
	os.write_file(root + '/logs/cc.log.argv.json', cc)!
	os.write_file(root + '/logs/clang-resource.log.argv.json', '["clang","-print-resource-dir"]')!
	mut refused := false
	admit_producer(root, inputs) or { refused = true }
	assert refused
	os.write_file(root + '/logs/clang-resource.log.argv.json', query)!
	os.rename(root + '/clang-headers.json', root + '/manifest')!
	os.symlink(root + '/manifest', root + '/clang-headers.json')!
	refused = false
	admit_producer(root, inputs) or { refused = true }
	assert refused
}
