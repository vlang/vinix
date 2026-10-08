// SPDX-License-Identifier: GPL-2.0-or-later
module hosttest

import os

fn test_module_scalar_unicode_and_typedef_boundaries() {
	work := work_dir('', 'vinix-module-test-') or { panic(err) }
	defer { module_remove_tree(work) or { panic(err) } }
	os.write_file(os.join_path(work, 'core.v'), '// ABI native-scalar: Té const_unsigned_long_64\n@[typedef]\u00a0struct C.Té\u00a0{\u00a0}\n') or { panic(err) }
	output := scalar_metadata(work, 'typedef int XTé;') or { panic(err) }
	assert output.starts_with('typedef const unsigned long Té;\n')
	assert output.ends_with('typedef int XTé;')
	scalar_metadata(work, 'typedef int Té\u00a0;') or {
		assert err.msg() == 'Native scalar alias conflicts with compiler declaration: Té'
		return
	}
	assert false
}

fn test_module_readonly_header_multiple_prototypes_and_uppercase() {
	work := work_dir('', 'vinix-module-test-') or { panic(err) }
	defer { module_remove_tree(work) or { panic(err) } }
	os.write_file(os.join_path(work, 'core.v'), '// ABI readonly-pointer: first.data\n') or { panic(err) }
	output := os.join_path(work, 'compiler.c')
	header := os.join_path(work, 'ß-api.h')
	os.write_file(output, '__attribute__((visibility("default"))) void first(char** data); __attribute__((visibility("default"))) i32 second(i32\tvalue);\n') or { panic(err) }
	emit_module_header(work, output, header) or { panic(err) }
	text := os.read_file(header) or { panic(err) }
	assert text.contains('#ifndef VINIX_GENERATED_SS_API_H\n')
	assert text.contains('void first(char* const* data);\nint32_t second(int32_t\tvalue);\n')
}

fn test_module_readonly_metadata_requires_exact_leading_spacing() {
	work := work_dir('', 'vinix-module-test-') or { panic(err) }
	defer { module_remove_tree(work) or { panic(err) } }
	os.write_file(os.join_path(work, 'core.v'), '// ABI readonly:  missing.data\n') or { panic(err) }
	output := os.join_path(work, 'compiler.c')
	header := os.join_path(work, 'api.h')
	os.write_file(output, '__attribute__((visibility("default"))) void first(void);\n') or { panic(err) }
	emit_module_header(work, output, header) or { panic(err) }
	assert os.read_file(header) or { panic(err) }.contains('void first(void);')
}

fn test_module_path_resolution_deep_acyclic_links_and_cycles() {
	work := work_dir('', 'vinix-module-test-') or { panic(err) }
	defer { module_remove_tree(work) or { panic(err) } }
	os.mkdir(os.join_path(work, 'target')) or { panic(err) }
	for index in 0 .. 64 {
		os.symlink(if index == 63 { 'target' } else { 'link-' + (index + 1).str() }, os.join_path(work, 'link-' + index.str())) or { panic(err) }
	}
	assert module_resolve(os.join_path(work, 'link-0/new.h')) or { panic(err) } == os.join_path(os.real_path(work), 'target/new.h')
	assert module_resolve(os.join_path(work, 'link-0/../link-0/new.h')) or { panic(err) } == os.join_path(os.real_path(work), 'target/new.h')
	os.symlink('cycle-b', os.join_path(work, 'cycle-a')) or { panic(err) }
	os.symlink('cycle-a', os.join_path(work, 'cycle-b')) or { panic(err) }
	module_resolve(os.join_path(work, 'cycle-a')) or {
		assert err.msg().starts_with('Symlink loop from ')
		return
	}
	assert false
}

fn test_module_unix_literal_backslash_names() {
	work := work_dir('', 'vinix-module-test-') or { panic(err) }
	defer { module_remove_tree(work) or { panic(err) } }
	source := work + '/literal\\source'
	os.mkdir(source) or { panic(err) }
	os.write_file(source + '/core\\name.v', '// ABI native-scalar: T const_unsigned_long_64\n@[typedef]\nstruct C.T {}\n') or { panic(err) }
	assert scalar_metadata(source, 'body') or { panic(err) }.starts_with('typedef const unsigned long T;')
	output := work + '/module.c'
	os.write_file(output, '__attribute__((visibility("default"))) void f(void);\n') or { panic(err) }
	header := 'literal\\header.h'
	emit_module_header(source, output, work + '/' + header) or { panic(err) }
	assert os.read_file(work + '/' + header) or { panic(err) }.contains('VINIX_GENERATED_LITERAL_HEADER_H')
	copy := work + '/copied'
	module_copy(source, copy) or { panic(err) }
	assert os.read_file(copy + '/core\\name.v') or { panic(err) } == os.read_file(source + '/core\\name.v') or { panic(err) }
}
