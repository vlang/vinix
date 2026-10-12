// SPDX-License-Identifier: GPL-2.0-or-later
module kpihost

import auditfixture
import gamehost
import hosttest
import json2
import os

struct AuditObservation {
	caller string
	root   string
mut:
	generations []string
	bounds      int
	compilers   int
	generated   []string
}

fn fixture_source(_ string, _ string, pointer voidptr) ![]string {
	context := unsafe { &AuditObservation(pointer) }
	return [context.caller]
}

fn fixture_observe(argv []string, pointer voidptr) ! {
	mut context := unsafe { &AuditObservation(pointer) }
	if argv[0].ends_with('/generate-abi') {
		context.generations << gamehost.parent(gamehost.parent(argv.last()))
		return
	}
	if '-S' in argv {
		context.bounds++
		return
	}
	if context.caller in argv {
		include := argv[argv.index('-I') + 1]
		for name in ['vinix/spinlock_adapters.h', 'vinix/atomic_exchange.h', 'vinix/integer_policy.h',
			'generated/bounds.h', 'generated/bounds.h.d', 'generated/bounds.h.json'] {
			assert os.is_file(include + '/' + name), name
		}
		assert !argv.any('obj' in it.split('/'))
		context.compilers++
		context.generated << include
	}
}

pub fn controlled_audit_compiler(argv []string) !int {
	if '-S' in argv {
		if path := os.getenv_opt('VINIX_AUDIT_MOCK_REJECTION') {
			os.write_file(path, 'bounds compiler rejected -S\n')!
		}
		eprintln('injected bounds compiler failure')
		return 1
	}
	compiler := hosttest.shell_split(gamehost.env('CC', 'clang'))!
	result := os.exec([...compiler, ...argv])
	print(result.output)
	return result.exit_code
}

pub fn audit_generation_cli(tools Tools, argv []string) !int {
	args, work, temporary := private_work(argv, 'Exercise native audit header generation, bounds failure and malformed metadata.\nUsage: audit_generation_test [--work DIR]')!
	_ = args
	defer { if temporary { gamehost.remove(work) or {} } }
	audit_generation_cases(tools, work)!
	return 0
}

pub fn audit_generation_cases(tools Tools, work string) ! {
	gamehost.mkdir(work)!
	pin := hosttest.upstream_pin()!
	source := gamehost.env('LINUXKPI_SOURCE_DIR', tools.root + '/third_party/linux-i915/linux-' + pin['version']!.str())
	archive := gamehost.parent(source) + '/linux-' + pin['version']!.str() + '.tar.xz'
	caller := work + '/adapter_caller.c'
	os.write_file(caller, auditfixture.native_caller_source())!
	mut context := AuditObservation{ caller: caller, root: tools.root }
	real_compiler := gamehost.env('CC', 'clang')
	hooks := AuditHooks{ sources: fixture_source, observe: fixture_observe, context: &context }
	for invocation in ['first', 'second'] {
		output := work + '/' + invocation + '.json'
		assert execute_audit(tools, AuditOptions{ source: source, archive: archive, compiler: real_compiler, output: output }, hooks)! == 0
		report := json2.decode[json2.Any](os.read_file(output)!)!.as_map()
		assert report['compiled']!.int() == 1 && report['total']!.int() == 1
		bounds := report['bounds']!.as_map()
		assert bounds['configuration']!.as_map()['CONFIG_MMU']!.str() == '1'
		assert bounds['archive_sha256']!.str() == pin['sha256']!.str()
	}
	assert context.compilers == 2 && context.bounds == 2 && context.generated.len == 2 && context.generated[0] != context.generated[1]
	for path in context.generated {
		assert !os.exists(gamehost.parent(path))
	}
	println('test_each_invocation_generates_and_removes_its_own_headers: PASS')
	compiler := work + '/reject-bounds'
	os.write_file(compiler, '#!/bin/sh\nexec ' + hosttest.shell_quote(os.executable()) + ' --audit-mock-compiler "$@"\n')!
	os.chmod(compiler, 0o755)!
	context = AuditObservation{ caller: caller, root: tools.root }
	marker := work + '/bounds-rejected'
	previous := os.getenv_opt('VINIX_AUDIT_MOCK_REJECTION')
	os.setenv('VINIX_AUDIT_MOCK_REJECTION', marker, true)
	defer {
		if value := previous {
			os.setenv('VINIX_AUDIT_MOCK_REJECTION', value, true)
		} else {
			os.unsetenv('VINIX_AUDIT_MOCK_REJECTION')
		}
	}
	mut failed := false
	execute_audit(tools, AuditOptions{ source: source, archive: archive, compiler: compiler, output: work + '/bounds-failure.json' }, hooks) or {
		assert err.msg().contains('compiler failed with exit status 1'), err.msg()
		failed = true
	}
	assert os.read_file(marker)! == 'bounds compiler rejected -S\n'
	assert failed && context.compilers == 0 && context.bounds == 1 && !os.exists(work + '/bounds-failure.json')
	for path in context.generations {
		assert !os.exists(gamehost.parent(path))
	}
	println('test_bounds_compiler_failure_stops_before_driver_compilation: PASS')
	for overflow in [false, true] {
		context = AuditObservation{ caller: caller, root: tools.root }
		here := work + if overflow { '/invalid-integer-metadata' } else { '/invalid-metadata' }
		gamehost.mkdir(here + '/abi')!
		for schema in ['spinlock', 'atomic-exchange', 'overflow'] {
			if schema == if overflow { 'overflow' } else { 'spinlock' } {
				os.write_file(here + '/abi/' + schema + '.json', '{ malformed metadata')!
			} else {
				gamehost.copy_file(tools.root + '/kernel/linuxkpi/abi/' + schema + '.json', here + '/abi/' + schema + '.json')!
			}
		}
		output := here + '/failure.json'
		failed = false
		execute_audit(tools, AuditOptions{ source: source, archive: archive, compiler: real_compiler, output: output, schema_directory: here }, hooks) or { failed = true }
		assert failed && !os.exists(output) && context.compilers == 0 && context.bounds == 0
		assert context.generations.len == if overflow { 3 } else { 1 }
		for path in context.generations {
			assert !os.exists(gamehost.parent(path))
		}
		println(if overflow {
			'test_invalid_optional_integer_metadata_stops_before_the_compiler: PASS'
		} else {
			'test_invalid_metadata_stops_before_the_compiler: PASS'
		})
	}
	os.write_file(work + '/passed', 'PASS 4\n')!
}
