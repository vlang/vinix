// SPDX-License-Identifier: GPL-2.0-or-later
module linuxcheck

import os

fn cxx_dynamic_fixture() string {
	return 'Dynamic section at offset 0x100 contains 4 entries:\n' +
		'  Tag Type Name/Value\n' +
		' 0x0000000000000001 (NEEDED) Shared library: [libc.so.6]\n' +
		' 0x0000000000000005 (STRTAB) 0x200\n' +
		' 0x0000000000000006 (SYMTAB) 0x300\n' +
		' 0x0000000000000000 (NULL) 0x0\n'
}

fn cxx_symbols_fixture() string {
	return "Symbol table '.dynsym' contains 3 entries:\n" +
		'   Num: Value Size Type Bind Vis Ndx Name\n' +
		' 0: 0000000000000000 0 NOTYPE LOCAL DEFAULT UND\n' +
		' 1: 0000000000000000 0 FUNC GLOBAL DEFAULT UND __cxa_finalize@GLIBC_2.17\n' +
		' 2: 0000000000400100 16 FUNC GLOBAL DEFAULT 12 ordinary_c_function\n'
}

fn test_cxx_dynamic_reader_requires_complete_populated_gnu_tables() {
	valid := cxx_dynamic_fixture()
	cxx_validate_dynamic_output(valid) or { panic(err) }
	for invalid in ['', 'There is no dynamic section in this file.\n', valid.all_before(' 0x'),
		valid.replace('4 entries:', '5 entries:'), valid.replace('0x0000000000000005', 'invalid-tag'),
		valid.replace('(STRTAB)', 'STRTAB'), valid.replace('(STRTAB)', '(UNKNOWN)'),
		valid.replace('[libc.so.6]', '[]'), valid.replace('[libc.so.6]', '[libc.so.6'),
		valid.replace('libc.so.6', 'libm.so.6'), valid + 'reader warning\n'] {
		mut rejected := false
		cxx_validate_dynamic_output(invalid) or { rejected = true }
		assert rejected
	}
	for forbidden in ['libubsan.so.1', 'libstdc++.so.6'] {
		mut rejected := false
		cxx_validate_dynamic_output(valid.replace('libc.so.6', forbidden)) or {
			rejected = err.msg().contains('incompatible shared GNU C++ or UBSan runtime')
		}
		assert rejected
	}
}

fn test_cxx_symbol_reader_requires_complete_rows_and_preserves_namespace_checks() {
	valid := cxx_symbols_fixture()
	cxx_validate_symbol_output(valid) or { panic(err) }
	for invalid in ['', "Symbol table '.dynsym' contains 0 entries:\n", valid.all_before(' 0:'),
		valid.replace('3 entries:', '4 entries:'), valid.replace("'.dynsym'", "'.symtab'"),
		valid.replace(' 2:', ' 1:'), valid.replace('0000000000400100', 'not-hex'),
		valid.replace('16 FUNC', 'bad FUNC'), valid.replace('GLOBAL DEFAULT 12', 'GLOBAL DEFAULT'),
		valid + 'reader warning\n'] {
		mut rejected := false
		cxx_validate_symbol_output(invalid) or { rejected = true }
		assert rejected
	}
	for forbidden in ['_ZNSt3__16localeD1Ev', '__cxa_throw', '_Unwind_RaiseException'] {
		mut rejected := false
		cxx_validate_symbol_output(valid.replace('ordinary_c_function', forbidden)) or {
			rejected = err.msg().contains('exported into the native DSO namespace')
		}
		assert rejected
	}
}

fn test_cxx_linkage_accepts_real_elf_metadata_and_rejects_a_zero_output_reader() {
	base := os.join_path(os.temp_dir(), 'vinix-cxx-linkage-reader-${os.getpid()}')
	os.mkdir(base) or { panic(err) }
	defer { os.rmdir_all(base) or {} }
	variable := 'VINIX_IOS_LINUX_READELF'
	had_previous := variable in os.environ()
	previous := os.getenv(variable)
	defer {
		if had_previous {
			os.setenv(variable, previous, true)
		} else {
			os.unsetenv(variable)
		}
	}
	reader := os.find_abs_path_of_executable('readelf') or { panic(err) }
	benign_elf := os.find_abs_path_of_executable('true') or { panic(err) }
	os.setenv(variable, reader, true)
	env := isolated_build_environment()
	cxx_verify_linkage(base, 'actual-elf', benign_elf, env) or { panic(err) }
	assert (os.read_file(base + '/actual-elf-needed.log') or { panic(err) }).contains('[libc.so.6]')
	assert (os.read_file(base + '/actual-elf-dynamic-symbols.log') or { panic(err) }).contains("'.dynsym'")
	os.setenv(variable, benign_elf, true)
	mut rejected := false
	cxx_verify_linkage(base, 'zero-output', benign_elf, env) or {
		rejected = err.msg().contains('populated dynamic section')
	}
	assert rejected
	assert (os.read_file(base + '/zero-output-needed.status.txt') or { panic(err) }) == '0\n'
	assert !os.exists(base + '/zero-output-dynamic-symbols.log')
}
