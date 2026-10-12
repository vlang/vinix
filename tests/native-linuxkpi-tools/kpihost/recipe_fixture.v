// SPDX-License-Identifier: GPL-2.0-or-later
module kpihost

import gamehost
import os
import sourcecommand

struct RecipeFixture {
	root           string
	work           string
	arch           string
	expected_flags []string
mut:
	commands [][]string
	modules  []string
	headers  int
	suites   int
	fail     bool
}

fn recipe_command(argv []string, environment map[string]string, pointer voidptr) !sourcecommand.Output {
	mut fixture := unsafe { &RecipeFixture(pointer) }
	fixture.commands << argv.clone()
	if argv[0] == fixture.root + '/tests/linuxkpi/compile-v-core' {
		assert argv[1] == fixture.work + '/compat.c' && argv[2] == '--arch' && argv[3] == if fixture.arch == 'aarch64' {
			'arm64'
		} else {
			'amd64'
		}
		os.write_file(argv[1], 'native generated-source fixture')!
		return sourcecommand.Output{}
	}
	assert environment.len > 0 && '-o' in argv
	output := argv[argv.index('-o') + 1]
	if output.ends_with('/compat.o') {
		for flag in fixture.expected_flags {
			assert flag in argv, flag
		}
		if fixture.arch == 'aarch64' {
			assert '--target=aarch64-linux-musl' in argv && '-mno-outline-atomics' in argv
		} else {
			for flag in ['-Wno-attributes', '-Wno-array-parameter', '-Wno-type-limits',
				'-Wno-misleading-indentation'] {
				assert flag in argv
			}
		}
		if fixture.fail {
			return sourcecommand.Output{ status: 7, stderr: 'controlled native compiler failure' }
		}
	}
	if output.ends_with('/linuxkpi-host') {
		assert '-static' in argv && '@' + fixture.work + '/host-fixtures.rsp' in argv
		for name in ['policyhost', 'i915policyfixture', 'runtimefixture', 'syncfixture',
			'fixture_storage', 'compat', 'headercore', 'exchangecore', 'linuxkpi_varargs',
			'linuxkpi_storage', 'linuxkpi_workqueue_abi', 'hostguest', 'serial'] {
			assert fixture.work + '/' + name + '.o' in argv
		}
		for name in ['lib/list_sort.c', 'lib/sort.c', 'lib/rbtree.c', 'lib/find_bit.c', 'lib/hweight.c',
			'lib/ctype.c', 'lib/siphash.c', 'drivers/gpu/drm/i915/i915_config.c',
			'drivers/gpu/drm/i915/display/intel_qp_tables.c'] {
			assert argv.any(it.ends_with('/' + name)), name
		}
	}
	os.write_file(output, 'controlled object or ELF fixture: ' + output)!
	return sourcecommand.Output{}
}

fn recipe_module(source string, output string, arch string, defines []string, pointer voidptr) ! {
	mut fixture := unsafe { &RecipeFixture(pointer) }
	assert arch == if fixture.arch == 'aarch64' { 'arm64' } else { 'amd64' }
	assert 'nofloat' in defines
	if source.ends_with('/runtimefixture') || source.ends_with('/syncfixture') || source.ends_with('/i915policyfixture') {
		assert 'linuxkpi_host_test' in defines
	}
	fixture.modules << source.all_after_last('/')
	os.write_file(output, 'native module source fixture')!
}

fn recipe_header(output string, arch string, host bool, implementations_only bool, pointer voidptr) ! {
	mut fixture := unsafe { &RecipeFixture(pointer) }
	assert arch == if fixture.arch == 'aarch64' { 'arm64' } else { 'amd64' }
	assert host && !implementations_only
	fixture.headers++
	os.write_file(output, 'native header source fixture')!
}

fn recipe_suite(work string, arch string, sanitize bool, environment map[string]string, pointer voidptr) ! {
	mut fixture := unsafe { &RecipeFixture(pointer) }
	assert work == fixture.work && arch == if fixture.arch == 'aarch64' { 'arm64' } else { 'amd64' }
	assert !sanitize && environment['NM'] != ''
	if fixture.arch == 'aarch64' {
		assert environment['CC'].contains('--target=aarch64-linux-musl')
	} else {
		assert environment['CC'].contains('-Wno-missing-braces')
	}
	fixture.suites++
	os.write_file(work + '/host-fixtures.rsp', 'controlled independent model object list\n')!
}

fn frozen_native_flags(root string) ![]string {
	original := os.exec(['git', '-C', root, 'show', '3678edd5:tests/linuxkpi/compile-native-host.py'])
	if original.exit_code != 0 { return error(original.output) }
	text := original.output.all_after('flags = [').all_before(']\n')
	parsed := literals(text)!
	mut flags := []string{}
	for field in fields(parsed) {
		if field.len != 1 || !field[0].string_value {
			return error('original flag table is not literal data')
		}
		flags << field[0].token
	}
	return flags
}

pub fn native_recipe_cases(root string, work string) ! {
	gamehost.mkdir(work)!
	expected := frozen_native_flags(root)!
	assert expected.len == 17
	for arch in ['aarch64', 'x86_64'] {
		path := work + '/' + arch
		mut fixture := RecipeFixture{ root: root, work: path, arch: arch, expected_flags: expected }
		tools := Tools{ root: root, command_hook: recipe_command, module_hook: recipe_module, header_hook: recipe_header, suite_hook: recipe_suite, context: &fixture }
		native_host(tools, path, arch)!
		assert fixture.headers == 1 && fixture.suites == 1
		assert fixture.modules == ['exchangecore', 'runtimefixture', 'syncfixture', 'i915policyfixture',
			'policyhost', 'hostguest', 'serialcore']
		assert os.is_file(path + '/native-inputs.json') && os.is_file(path + '/linuxkpi-host')
		fixture.fail = true
		fixture.commands.clear()
		fixture.modules.clear()
		fixture.headers = 0
		fixture.suites = 0
		os.write_file(path + '/linuxkpi-host', 'preserve previous executable')!
		mut failed := false
		native_host(tools, path, arch) or {
			assert err.msg().contains('controlled native compiler failure')
			failed = true
		}
		assert failed && fixture.modules.len == 0 && fixture.headers == 0 && fixture.suites == 0
		assert os.read_file(path + '/linuxkpi-host')! == 'preserve previous executable'
		println('NATIVE MUSL RECIPE / frozen original flags, architecture and object order, independent models, compiler failure stops publication: PASS ' + arch)
	}
	os.write_file(work + '/passed', 'PASS\n')!
}
