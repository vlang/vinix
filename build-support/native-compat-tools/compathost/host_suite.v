// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module compathost

import fixturehost
import hosttest
import json2
import os
import policyhost

const hypervisor_original = '9f47270ee3c6754312bc09fc74d8f77e2cfe2229'

#include <signal.h>
fn C.signal(i32, voidptr) voidptr
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
__global host_suite_interrupted i32

fn host_suite_signal(_signal i32) { unsafe { C.__atomic_store_n(&host_suite_interrupted, i32(1), C.__ATOMIC_RELAXED) } }
fn host_suite_cancelled() bool { return unsafe { C.__atomic_load_n(&host_suite_interrupted, C.__ATOMIC_RELAXED) } != 0 }

struct HostSuite {
	work string
mut:
	commands []json2.Any
	sources map[string]string
}

fn (mut suite HostSuite) record(argv []string) ! {
	suite.commands << json2.Any(hosttest.strings(argv))
	hosttest.write_json(suite.work + '/inputs.json', {
		'host_arch': json2.Any(policyhost.caller_arch()),
		'commands': json2.Any(suite.commands),
		'sources': json2.Any(hosttest.string_map(suite.sources))
	})!
}

fn (mut suite HostSuite) invoke(argv []string) ! {
	result := suite.capture(argv, -1, policyhost.environment(), '')!
	print(result.stdout); eprint(result.stderr)
	if result.code != 0 { return error('Command failed: ' + argv[0]) }
}

fn (mut suite HostSuite) capture(argv []string, timeout int, env map[string]string, directory string) !hosttest.Result {
	suite.record(argv)!
	result := fixturehost.capture_bounded(argv, env, policyhost.caller_arch(), directory, timeout, host_suite_cancelled) or {
		if err.code() == 130 { return err }
		// Exec errors are runtime failures; ENOENT is not argparse's status 2.
		return error(err.msg())
	}
	write(suite.work + '/command-' + suite.commands.len.str() + '.log', json2.encode(argv) + '\n' + result.stdout + result.stderr)!
	return hosttest.Result{stdout: result.stdout, stderr: result.stderr, code: result.status}
}

fn (mut suite HostSuite) source(path string) !string {
	text := read(root() + '/' + path)!
	suite.sources[path] = hosttest.text_sha(text)
	return text
}

fn (mut suite HostSuite) copy(path string, destination string) ! {
	hosttest.module_copy_file_preserving_stat(root() + '/' + path, destination)!
	suite.sources[path] = hosttest.sha(destination)!
}

fn host_assertion_lines(original_c string, port string) ![]int {
	c_lines := original_c.split_into_lines()
	mut original_lines := []int{}
	for i, line in c_lines {
		if line.contains('CHECK(') && !line.starts_with('#define') { original_lines << i + 1 }
	}
	mut native_lines := []int{}
	// Preserve the original whole-line greedy match and identifier boundary.
	for line in port.split('\n') {
		mut cursor := 0
		for cursor < line.len {
			first := cursor + (line[cursor..].index('check(') or { break })
			cursor = first + 6
			if first > 0 && hosttest.module_word_rune(line[..first].runes().last()) { continue }
			mut found := -1
			mut end := cursor
			for pos in cursor + 1 .. line.len {
				if line[pos] != `,` || pos + 2 >= line.len || line[pos + 1] != ` ` { continue }
				mut stop := pos + 2
				for stop < line.len && line[stop].is_digit() { stop++ }
				if stop > pos + 2 && stop < line.len && line[stop] == `)` { found = pos + 2; end = stop }
			}
			if found >= 0 { native_lines << line[found..end].int(); cursor = end + 1 }
		}
	}
	if original_lines != native_lines {
		return error('Original assertion diagnostics changed: ' + original_lines.str() + ' != ' + native_lines.str())
	}
	return original_lines
}

fn hypervisor_host(mut suite HostSuite, compiler string) ! {
	original_c := fixturehost.capture_in_preferred(['git', 'show', hypervisor_original + ':tests/hypervisor/guest.c'],
		'', policyhost.environment(), false, root(), true, policyhost.caller_arch())!
	write(suite.work + '/original.c', original_c)!
	lines := host_assertion_lines(original_c, suite.source('tests/hypervisor/guestfixture/core.v')!)!
	for pair in [['modelcore', 'model.c'], ['guestfixture', 'ported.c']] {
		source := root() + '/tests/hypervisor/' + pair[0]
		// Both original host profiles generated the portable ARM64 ABI subset.
		argv := [root() + '/build-support/compile-v-module', source, suite.work + '/' + pair[1], '--arch', 'arm64']
		suite.invoke(argv)!
		suite.sources[pair[1]] = hosttest.sha(suite.work + '/' + pair[1])!
	}
	mut cc := [compiler]
	$if macos { cc << ['-arch', if policyhost.caller_arch() == 'arm64' { 'arm64' } else { 'x86_64' }] }
	flags := [...cc, '-g', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-strict-aliasing',
		'-fsanitize=address,undefined', '-I', root() + '/tests/hypervisor', '-I', root() + '/tests/hypervisor/guestfixture']
	generated := ['-Wno-unused-function', '-Wno-unused-parameter']
	suite.invoke([...flags, ...generated, '-c', suite.work + '/model.c', '-o', suite.work + '/model.o'])!
	suite.invoke([...cc, '-c', root() + '/tests/hypervisor/model-ioctl.S', '-o', suite.work + '/ioctl.o'])!
	bindings := ['open', 'pwrite', 'ioctl', 'read', 'close', 'pause'].map('-D' + it + '=hv_model_' + it)
	for name in ['original', 'ported'] {
		mut argv := flags.clone()
		if name == 'ported' { argv << generated }
		argv << [...bindings, suite.work + '/' + name + '.c', suite.work + '/model.o', suite.work + '/ioctl.o', '-o', suite.work + '/' + name]
		suite.invoke(argv)!
	}
	mut results := []json2.Any{}
	for value in -3 .. 16 {
		mut env := policyhost.environment()
		env['HV_MODEL_CASE'] = value.str()
		env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1'
		original_run := suite.capture([suite.work + '/original'], 30, env, '')!
		ported_run := suite.capture([suite.work + '/ported'], 30, env, '')!
		expected := if value in [-2, -1, 0] { 0 } else { 1 }
		if original_run.code != expected || ported_run.code != expected || original_run.stderr != '' || ported_run.stderr != '' {
			return error('Case ' + value.str() + ': unexpected status/sanitizer output: ' + original_run.str() + ' / ' + ported_run.str())
		}
		if original_run.stdout != ported_run.stdout { return error('Case ' + value.str() + ': original/V output differs') }
		hosttest.module_decode_utf8(original_run.stdout)!
		results << json2.Any({'case': json2.Any(value), 'exit': json2.Any(expected), 'stdout': json2.Any(original_run.stdout)})
	}
	hosttest.write_json(suite.work + '/result.json', {
		'status': json2.Any('PASS'), 'original_revision': json2.Any(hypervisor_original),
		'original_sha256': json2.Any(hosttest.text_sha(original_c)),
		'assertion_lines': json2.Any(lines.map(json2.Any(it))), 'cases': json2.Any(results),
		'scope': json2.Any('host ABI model; actual VMX entry requires nested VT-x')
	})!
	println('Hypervisor frozen-C/V: PASS (' + results.len.str() + ' sanitizer cases, all ' + lines.len.str() + ' original assertions)')
}

fn host_v() !string {
	if 'V' in policyhost.environment() && os.getenv('V') == '' { return error('Compiler override is empty') }
	return output(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root()])!
}

fn mounted_disk_host(mut suite HostSuite) ! {
	mut generator := os.getenv('VINIX_BLOCK_POLICY_GENERATOR')
	if generator == '' {
		generator = suite.work + '/generator'
		suite.invoke([root() + '/build-support/run-v-tool.sh', root() + '/tests/mounted-disk-policy/host_generator.v', '--install', generator])!
	}
	suite.invoke([generator, '--stubs', suite.work])!
	suite.copy('kernel/resource/block_identity.v', suite.work + '/resource/block_identity.v')!
	suite.copy('kernel/security/device_policy.v', suite.work + '/security/device_policy.v')!
	write(suite.work + '/host.h', suite.source('tests/mounted-disk-policy/hosttemplates/host.h')!)!
	suite.invoke([generator, '--finish', suite.work])!
	compiler := host_v()!
	suite.invoke([compiler, '-enable-globals', '-gc', 'none', '-cc', 'clang', '-arch', policyhost.caller_arch(),
		'-cflags', '-fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined', '-o', suite.work + '/test', suite.work])!
	mut env := policyhost.environment()
	env['ASAN_OPTIONS'] = 'detect_leaks=0'
	result := suite.capture([suite.work + '/test'], 30, env, '')!
	print(result.stdout); eprint(result.stderr)
	if result.code != 0 { return error('Mounted disk policy host tests failed') }
}

fn original_function_slice(text string, signature string) !string {
	first := text.index(signature) or { return error('Missing production function ' + signature) }
	last := first + 4 + (text[first + 4..].index('\nfn ') or { return error('Missing production function boundary ' + signature) })
	return text[first..last]
}

fn append_dispatch_body(generated string) !string {
	mut offset := 0
	for line in generated.split('\n') {
		mut signature := -1
		for name in [' append_write(', ' main__append_write('] {
			if pos := line.index(name) {
				if pos > 0 { signature = pos + name.len; break }
			}
		}
		stop := line.last_index(') {') or { -1 }
		if signature >= 0 && stop > signature {
			first := offset + stop + 2
			mut last := first + 1
			mut depth := 1
			for depth > 0 && last < generated.len {
				if generated[last] == `{` { depth++ }
				if generated[last] == `}` { depth-- }
				last++
			}
			if depth != 0 { return error('Generated append dispatch definition is unterminated') }
			return generated[first..last]
		}
		offset += line.len + 1
	}
	return error('Generated append dispatch definition is missing')
}

fn append_dispatch_check(generated string) ! {
	body := append_dispatch_body(generated)!
	if ['memdup', 'malloc', 'new_array', 'string__substr'].any(body.contains(it)) {
		return error('Generated append dispatch allocates on its repeated path')
	}
}

fn securelevel_host(mut suite HostSuite, family string) ! {
	compiler := host_v()!
	mut env := policyhost.environment()
	env['VEXE'] = compiler
	if family == 'securelevel-host' {
		source := suite.source('kernel/security/securelevel_parse.v')!
		write(suite.work + '/securelevel_parse.v', source.replace_once('module security', 'module main'))!
		suite.copy('tests/securelevel-boot/parse_test.v', suite.work + '/parse_test.v')!
		argv := [compiler, '-gc', 'none', '-arch', policyhost.caller_arch(), 'test', suite.work]
		result := suite.capture(argv, -1, env, '')!
		print(result.stdout); eprint(result.stderr)
		if result.code != 0 { return error('Securelevel parser tests failed') }
		println('SECURELEVEL PARSER PASS')
	} else if family == 'securelevel-dispatch' {
		source := suite.source('kernel/resource/cache.v')!
		first := source.index('pub struct AppendResult') or { return error('Missing production AppendResult') }
		last := first + (source[first..].index('// Optional capabilities') or { return error('Missing production append boundary') })
		os.mkdir(suite.work + '/errno')!
		write(suite.work + '/v.mod', "Module { name: 'vinix_append_dispatch' }\n")!
		write(suite.work + '/errno/errno.v', 'module errno\npub const efbig = 27\npub fn set(_value int) {}\n')!
		model := suite.source('tests/securelevel-boot/hosttemplates/dispatch/main.v')!
		write(suite.work + '/main.v', model + source[first..last])!
		argv := [compiler, '-gc', 'none', '-manualfree', '-arch', policyhost.caller_arch(), '-o', suite.work + '/out.c', suite.work + '/main.v']
		result := suite.capture(argv, -1, env, '')!
		print(result.stdout); eprint(result.stderr)
		if result.code != 0 { return error('Append dispatch C generation failed') }
		append_dispatch_check(read(suite.work + '/out.c')!)!
		println('APPEND DISPATCH STACK PASS')
	} else {
		for name in ['ext2', 'errno', 'katomic', 'resource'] { os.mkdir(suite.work + '/' + name)! }
		write(suite.work + '/v.mod', "Module { name: 'vinix_attributes' }\n")!
		source := suite.source('kernel/fs/ext2/ext2.v')!
		cache_source := suite.source('kernel/fs/ext2/pagecache.v')!
		write(suite.work + '/ext2/production.v', 'module ext2\nimport errno\nimport katomic\nimport resource as resource_mod\n'
			+ original_function_slice(source, 'fn (mut this EXT2Resource) set_attribute_bits(')! + '\n'
			+ original_function_slice(cache_source, 'fn (mut filesystem EXT2Filesystem) raw_device_write(')!
			+ '\nfn C.memset(voidptr, int, usize) voidptr\nfn C.__builtin_alloca(usize) voidptr\n')!
		write(suite.work + '/errno/errno.v', 'module errno\npub const ebusy = 16\npub const eio = 5\npub const erofs = 30\npub fn set(_ int) {}\n')!
		write(suite.work + '/katomic/katomic.v', 'module katomic\npub fn store[T](mut value T, wanted T) { value = wanted }\n')!
		write(suite.work + '/resource/resource.v', 'module resource\npub const attributes_kept = u32(0x30)\n')!
		write(suite.work + '/ext2/model.v', suite.source('tests/securelevel-boot/hosttemplates/ext2/model.v')!)!
		for name in ['compat.v', 'readonly_test.v'] {
			suite.copy('tests/securelevel-boot/hosttemplates/ext2/' + name, suite.work + '/ext2/' + name)!
		}
		suite.copy('tests/securelevel-boot/attribute_fault_test.v', suite.work + '/ext2/attribute_fault_test.v')!
		argv := [compiler, '-gc', 'none', '-arch', policyhost.caller_arch(), 'test', 'ext2']
		result := suite.capture(argv, -1, env, suite.work)!
		print(result.stdout); eprint(result.stderr)
		if result.code != 0 { return error('Attribute publication fault tests failed') }
		println('ATTRIBUTE PUBLICATION FAULTS PASS')
	}
}

fn host_suite_command(args []string, family string) !int {
	mut specs := [hosttest.Option{ name: '--state-dir', value: true }]
	if family == 'hypervisor-host' { specs << hosttest.Option{ name: '--cc', value: true } }
	parsed := hosttest.parse_arguments(args, specs, 0,
		'Usage: host [--state-dir FRESH-DIR]' + if family == 'hypervisor-host' { ' [--cc clang] (state directory required)' } else { '' },
		'Run the unchanged independent fixtures and production source checks directly through V.') or { return error_with_code(err.msg(), 2) }
	if family == 'hypervisor-host' { needed(parsed, ['--state-dir'])! }
	unsafe { C.__atomic_store_n(&host_suite_interrupted, i32(0), C.__ATOMIC_RELAXED) }
	previous := unsafe { C.signal(C.SIGINT, voidptr(host_suite_signal)) }
	defer { unsafe { C.signal(C.SIGINT, previous) } }
	keep := if '--state-dir' in parsed.options { resolve(parsed.options['--state-dir'])! } else { '' }
	work := hosttest.work_dir(keep, 'vinix-' + family + '-')!
	defer { if keep == '' { retire(work) } }
	mut suite := HostSuite{ work: work }
	if family == 'hypervisor-host' { hypervisor_host(mut suite, parsed.options['--cc'] or { 'clang' })! }
	else if family == 'mounted-disk-host' { mounted_disk_host(mut suite)! }
	else { securelevel_host(mut suite, family)! }
	return 0
}
