// Compile without -prod: both deliberately failing controls must execute.
import crypto.sha256
import json2
import os

$if macos {
	#include <CommonCrypto/CommonDigest.h>
}

@[typedef]
struct C.CC_SHA256_CTX {}

fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

struct Evidence {
	architecture  string
	context       string
	base_commit   string
	artifacts     map[string]string
	source_inputs map[string]string
}

fn digest(path string) string {
	mut input := os.open(path) or { panic(err) }
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	$if macos {
		mut state := C.CC_SHA256_CTX{}
		assert C.CC_SHA256_Init(unsafe { &state }) == 1
		for {
			n := input.read(mut buffer) or {
				if err is os.Eof { break }
				panic(err)
			}
			if n == 0 { break }
			assert C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) == 1
		}
		mut result := [32]u8{}
		assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) == 1
		return result[..].hex()
	} $else {
		mut state := sha256.new()
		for {
			n := input.read(mut buffer) or {
				if err is os.Eof { break }
				panic(err)
			}
			if n == 0 { break }
			assert state.write(buffer[..n]) or { panic(err) } == n
		}
		mut result := []u8{len: 32}
		state.checksum_into(mut result)
		return result.hex()
	}
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[json2.Any](os.read_file(path)!)!.as_map()
}

fn publish(input string, output string) ! {
	data := os.read_bytes(input)!
	if os.exists(output) {
		assert os.read_bytes(output)! == data
	} else {
		os.write_file_array(output, data)!
	}
}

fn git(tree string, args []string) !string {
	mut p := os.new_process('git')
	p.set_args(['-C', tree, ...args])
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	assert code == 0, output
	return output.trim_space()
}

fn control(args []string, marker string) string {
	mut p := os.new_process(os.executable())
	p.set_args(args)
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }
	return output
}

fn storage(log string, arch string, _phase string) {
	mut slabs := [4]int{}
	mut pages := [4]int{}
	mut seen := map[string]bool{}
	for row in log.split_into_lines().filter(it.starts_with('LINUX CLONESTACK SLAB:') || it.starts_with('LINUX CLONESTACK STORAGE:')) {
		fields := row.fields()
		assert fields.len == 8 && fields[3].starts_with('ordinary=') && fields[4].starts_with('namespace=')
		ordinary := fields[3].all_after('=').int()
		namespace := fields[4].all_after('=').int()
		assert ordinary in [0, 1] && namespace in [0, 1]
		cohort := ordinary + 2 * namespace
		pair := fields[6].all_after('=').split('/')
		assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' {
			assert fields[5].starts_with('size=') && fields[7] == 'cycles=200'
			key := fields[3] + fields[4] + fields[5]
			assert key !in seen
			seen[key] = true
			slabs[cohort]++
		} else {
			assert fields[5] == 'cycles=200' && fields[7] == 'PASS' && pair[0].u64() > 0
			pages[cohort]++
		}
	}
	for cohort in 0 .. 4 {
		assert slabs[cohort] == if arch == 'aarch64' {
			18
		} else {
			14
		}
		assert pages[cohort] == 1
	}
}

fn receipt(state string, arch string, kernel string, names []string, failing bool) !map[string]string {
	value := object(state + '/receipt.json')!
	assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel && digest(state + '/kernel/bin/vinix') == kernel
	rows := value['results']!.as_array()
	assert rows.len == names.len
	mut artifacts := {
		'receipt': digest(state + '/receipt.json')
	}
	artifacts['aggregate'] = digest(state + '.log')
	for index, row in rows {
		entry := row.as_map()
		name := entry['name']!.str()
		assert name == names[index] && entry['exit_code']!.int() == if failing && index == 0 {
			1
		} else {
			0
		} && entry['detail']!.str() == ''
		for label, path in {
			'source': state + '/sources/' + name + 'fixture/core.v'
			'init':   state + '/' + name + '/init'
			'iso':    state + '/' + name + '/test.iso'
		} {
			hash := digest(path)
			key := if label == 'source' {
				'source_sha256'
			} else if label == 'init' {
				'init_sha256'
			} else {
				'iso_sha256'
			}
			assert hash == entry[key]!.str()
			artifacts[name + '_' + label] = hash
		}
		assert artifacts[name + '_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/' + name + 'fixture/core.v')
		artifacts[name + '_c'] = digest(state + '/' + name + '/fixture.c')
		artifacts[name + '_serial'] = digest(state + '/' + name + '/serial.log')
		if !failing || index > 0 {
			assert os.read_file(state + '/' + name + '/serial.log')!.contains('LINUX ' + name.to_upper() + ': PASS')
		}
	}
	return artifacts
}

fn reference_receipt(state string, arch string, init string) !map[string]string {
	value := object(state + '/receipt.json')!
	assert value['architecture']!.str() == arch && value['passed']!.bool() && value['finished']!.bool() && value['forced']!.bool() && value['status']!.int() == 0
	artifacts := value['artifacts']!.as_map_of_strings()
	command := value['command']!.as_array().map(it.str())
	assert command.contains('-kernel') && command.contains('-initrd') && command.contains('-no-reboot')
	for label, path in {
		'kernel':            state + '/linux'
		'probe':             state + '/probe'
		'wrapper_source':    state + '/source/clonestackreferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/clonestack-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/clonestackreferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, 'after', arch, true)
	return artifacts
}

fn definition(source string, marker string) string {
	start := source.index(marker) or { panic('missing complete definition: ' + marker) }
	mut depth := 0
	mut entered := false
	for position in start .. source.len {
		if source[position] == `{` {
			depth++
			entered = true
		} else if source[position] == `}` {
			depth--
			if entered && depth == 0 { return source[start..position + 1] }
		}
	}
	panic('unclosed function definition')
}

fn failure(log string, arch string) {
	assert log.contains('LINUX CLONESTACK DETAIL:'), 'clonestack baseline failure markers required'
	semantics(log, 'before', arch, false)
}

fn semantics(log string, phase string, arch string, reference bool) {
	assert phase in ['before', 'after'] && arch in ['aarch64', 'x86_64']
	mut seen := map[string]bool{}
	for label in ['CASES:', 'FINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX CLONESTACK ' + label))
		assert rows.len == 24
		seen.clear()
		mut total := 0
		mut failures := 0
		for row in rows {
			f := row.fields()
			assert f.len == 8 && f[3] in ['ordinary=0', 'ordinary=1'] && f[4] in [
				'namespace=0',
				'namespace=1',
			] && f[5] in ['kind=0', 'kind=1', 'kind=2', 'kind=3', 'kind=4', 'kind=5']
			key := label + f[3] + f[4] + f[5]
			assert key !in seen
			seen[key] = true
			class := f[5].all_after('=').int()
			calls := [36, 36, 48, 24, 36, 12]![class]
			bad := if phase == 'before' && class in [0, 1] { calls } else { 0 }
			assert f[6] == 'calls=' + calls.str() && f[7] == 'failures=' + bad.str()
			total += calls
			failures += bad
		}
		assert total == 768 && failures == if phase == 'after' { 0 } else { 288 }
	}
	cohorts := log.split_into_lines().filter(it.starts_with('LINUX CLONESTACK COHORT:'))
	assert cohorts.len == 4
	seen.clear()
	for row in cohorts {
		f := row.fields()
		assert f.len == 11 && f[3] in ['ordinary=0', 'ordinary=1'] && f[4] in [
			'namespace=0',
			'namespace=1',
		]
		key := f[3] + f[4]
		assert key !in seen
		seen[key] = true
		assert f[5].starts_with('self=') && f[5].all_after('=').int() > 1
		if f[4] == 'namespace=1' {
			assert f[5] == 'self=2'
		}
		assert f[6] == 'uid=' + if f[3] == 'ordinary=1' { '1000' } else { '0' }
		assert f[7] == 'page=' + if arch == 'aarch64' && !reference { '16384' } else { '4096' }
		assert f[8..] == ['raw=192', 'classes=6', 'layouts=3']
	}
	if phase == 'before' {
		assert log.contains('LINUX CLONESTACK DETAIL:') && log.contains('LINUX CLONESTACK FAIL:') && !log.contains('LINUX CLONESTACK: PASS')
	} else {
		assert !log.contains('LINUX CLONESTACK DETAIL:') && !log.contains('LINUX CLONESTACK FAIL:')
	}
	if reference {
		assert log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX CLONESTACK REFERENCE: PASS') && !log.contains('LINUX CLONESTACK STORAGE:')
	} else if phase == 'after' {
		assert log.count('LINUX CLONESTACK: PASS') == 1
	}
	assert !log.contains('Kernel panic') && !log.contains('setup stage=')
}

fn scope(area string, root string) ! {
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == '9c6bc0f8e2b06e1988c5144fd3d28b4c50d7b626'
	for path in ['linux_task.v', 'clone_arm64.v', 'clone_amd64.v'] {
		before := os.read_file(area + 'before-' + path)!
		after := os.read_file(area + 'after-' + path)!
		old := '\t\tif args.stack_size == 0 {'
		new := '\t\t// Check the range before adding; Linux does not require mapped pages here.\n\t\tif args.stack_size == 0 || !usercopy.user_range(args.stack, args.stack_size) {'
		if path == 'linux_task.v' {
			assert before == after
		} else {
			assert before.count(old) == 1 && before.replace(old, new) == after
		}
		assert digest(root + 'kernel/userland/' + path) == digest(area + 'after-' + path)
		for suffix in ['arm', 'x86'] {
			tree := area + 'kernel-' + suffix
			assert git(tree, ['show', base + ':kernel/userland/' + path])!.trim_space() == before.trim_space()
			assert digest(tree + '/kernel/userland/' + path) == digest(area + 'after-' + path)
		}
	}
	for suffix in ['arm', 'x86'] {
		tree := area + 'kernel-' + suffix
		assert git(tree, ['rev-parse', 'HEAD'])! == base
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/userland/clone_amd64.v\nkernel/userland/clone_arm64.v'
		before := os.read_file(area + 'before-' + suffix + '.c')!
		after := os.read_file(area + 'after-' + suffix + '.c')!
		marker := '\nmulti_return_u64_u64 userland__syscall_clone3(void* ' + if suffix == 'arm' {
			'_gpr_state'
		} else {
			'gpr_state'
		} + ', u64 uargs, u64 size) {'
		old_body := definition(before, marker)
		new_body := definition(after, marker)
		old := '\t\tif (args.stack_size == 0) {'
		new := '\t\tif ((args.stack_size == 0) || !usercopy__user_range(args.stack, args.stack_size)) {'
		assert old_body.count(old) == 1 && old_body.replace(old, new) == new_body
		equal := before.replace(old_body, new_body) == after
		assert equal, 'Exact whole C must differ only in clone3 stack range validation'
		for prohibited in ['memdup(', 'malloc(', 'calloc(', 'new_array', '__builtin_alloca('] {
			assert !new_body.contains(prohibited)
		}
	}
}

fn preliminary(area string, root string, out string) !map[string]string {
	old_source := os.read_file(area + 'p0/core.v')!
	assert old_source.replace('Range{(u64(1)<<47)-16,16},Range{(u64(1)<<47)-1,1}',
		'Range{(u64(1)<<47)-65552,16},Range{(u64(1)<<47)-65537,1}') == os.read_file(root + 'tests/linux-compat/clonestackfixture/core.v')!
	for arch, suffix in {
		'aarch64': 'arm'
		'x86_64':  'x86'
	} {
		before := area + 'p0/states/before-' + suffix
		log := os.read_file(before + '/clonestack/serial.log')!
		semantics(log, 'before', arch, false)
		storage(log, arch, 'before')
		value := object(before + '/receipt.json')!
		assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == digest(before + '/kernel/bin/vinix')
		rows := value['results']!.as_array()
		assert rows.len == 1
		entry := rows[0].as_map()
		assert entry['name']!.str() == 'clonestack' && entry['exit_code']!.int() == 1
		assert entry['source_sha256']!.str() == digest(area + 'p0/core.v') && entry['source_sha256']!.str() == digest(before + '/sources/clonestackfixture/core.v')
		assert entry['init_sha256']!.str() == digest(before + '/clonestack/init') && entry['iso_sha256']!.str() == digest(before + '/clonestack/test.iso')
		refstate := area + 'p0/states/reference-' + suffix
		reference := object(refstate + '/receipt.json')!
		artifacts := reference['artifacts']!.as_map_of_strings()
		assert reference['architecture']!.str() == arch
		command := reference['command']!.as_array().map(it.str())
		for key, path in {
			'wrapper_source':    refstate + '/source/clonestackreferenceinit/core.v'
			'wrapper_c':         refstate + '/fixture.c'
			'wrapper_elf':       refstate + '/init'
			'initramfs':         refstate + '/initramfs.cpio'
			'serial_adapter_c':  refstate + '/serial.c'
			'controller_source': root + 'tests/linux-compat/clonestack-reference.v'
			'qemu':              command[0]
		} {
			assert artifacts[key] == digest(path)
		}
		assert artifacts['probe'] == digest(before + '/clonestack/init') && artifacts['probe'] == digest(refstate + '/probe')
		assert artifacts['serial'] == digest(refstate + '/serial.log') && artifacts['kernel'] == digest(refstate + '/linux')
		ref_log := os.read_file(refstate + '/serial.log')!
		if suffix == 'arm' {
			assert reference['passed']!.bool()
			semantics(ref_log, 'after', arch, true)
		} else {
			assert !reference['passed']!.bool() && reference['finished']!.bool()
			assert os.read_file(area + 'p0/states/reference-x86.log.status')!.trim_space() == '1'
			for label in ['CASES:', 'FINAL:'] {
				cases := ref_log.split_into_lines().filter(it.starts_with('LINUX CLONESTACK ' + label))
				assert cases.len == 24
				mut seen := map[string]bool{}
				mut failures := 0
				for row in cases {
					f := row.fields()
					assert f.len == 8 && f[3] in ['ordinary=0', 'ordinary=1'] && f[4] in [
						'namespace=0',
						'namespace=1',
					]
					kind := f[5].all_after('=').int()
					assert kind >= 0 && kind < 6 && f[5] == 'kind=' + kind.str()
					key := f[3] + f[4] + f[5]
					assert key !in seen
					seen[key] = true
					bad := if kind == 2 { 6 } else { 0 }
					assert f[6] == 'calls=' + [36, 36, 48, 24, 36, 12]![kind].str() && f[7] == 'failures=' + bad.str()
					failures += bad
				}
				assert failures == 24
			}
			assert ref_log.contains('LINUX CLONESTACK FAIL:') && !ref_log.contains('LINUX CLONESTACK REFERENCE: PASS')
		}
		for phase in ['before', 'reference'] {
			state := area + 'p0/states/' + phase + '-' + suffix
			publish(state + if phase == 'before' { '/clonestack/serial.log' } else { '/serial.log' }, out + 'clonestack-p0-' + phase + '-' + suffix + '.log')!
			publish(state + '/receipt.json', out + 'clonestack-p0-' + phase + '-' + suffix + '-receipt.json')!
		}
	}
	mut pins := map[string]string{}
	for path in os.walk_ext(area + 'p0', '') {
		if os.inode(path).typ == .regular { pins[path] = digest(path) }
	}
	return pins
}

fn main() {
	if '--scope-only' in os.args {
		scope(os.args[2].trim_right('/') + '/', '/Users/alex/code/vinix/')!
		println('Native clonestack exact source/C scope: PASS')
		return
	}
	if '--negative-control' in os.args {
		assert false, 'clonestack assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len in [2, 3] && (os.args.len == 2 || os.args[2] == '--verify-only'), 'Usage: clonestack-check.v EVIDENCE-AREA [--verify-only] (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	root := '/Users/alex/code/vinix/'
	out := if os.args.len == 3 {
		area + 'preview/'
	} else {
		root + 'tests/linux-compat/results/2026-10-16/'
	}
	os.mkdir_all(out)!
	scope(area, root)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'clonestack assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		area + 'states/reference-arm/serial.log', 'aarch64'], 'clonestack baseline failure markers required'))!
	for arch, suffix in {
		'aarch64': 'arm'
		'x86_64':  'x86'
	} {
		before := area + 'states/before-' + suffix
		after := area + 'states/after-' + suffix
		mut artifacts := map[string]string{}
		for phase, state in {
			'before': before
			'after':  after
		} {
			names := if phase == 'before' {
				['clonestack']
			} else {
				['clonestack', 'runtime', 'clonecgroup']
			}
			kernel := digest(state + '/kernel/bin/vinix')
			assert kernel == digest(area + '/' + if phase == 'before' {
				'baseline-' + suffix
			} else {
				'kernel-' + suffix
			} + '/kernel/bin/vinix')
			got := receipt(state, arch, kernel, names, phase == 'before')!
			for key, hash in got { artifacts[phase + '_' + key] = hash }
			log := os.read_file(state + '/clonestack/serial.log')!
			if phase == 'before' {
				failure(log, arch)
			} else {
				semantics(log, 'after', arch, false)
			}
			storage(log, arch, phase)
			probe_c := os.read_file(state + '/clonestack/fixture.c')!
			for forbidden in ['memdup(', 'malloc(', 'calloc(', 'realloc(', 'new_array', 'v_fixed_index'] {
				assert !probe_c.contains(forbidden), forbidden
			}
			assert probe_c.count('alloca(') == 8
			assert digest(state + '/clonestack/fixture.c') == digest(before + '/clonestack/fixture.c') && digest(state + '/clonestack/init') == digest(before + '/clonestack/init')
			for name in names {
				publish(state + '/' + name + '/serial.log', out + 'clonestack-' + phase + '-' + suffix + '-' + name + '.log')!
			}
			for path in ['receipt.json'] {
				publish(state + '/' + path, out + 'clonestack-' + phase + '-' + suffix + '-' + path)!
			}
			publish(state + '.log', out + 'clonestack-' + phase + '-' + suffix + '-producer.log')!
			publish(area + 'build-' + phase + '-' + suffix + '.log', out + 'clonestack-build-' + phase + '-' + suffix + '.log')!
			artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
			artifacts[phase + '_build_log'] = digest(area + 'build-' + phase + '-' + suffix + '.log')
		}
		refstate := area + 'states/reference-' + suffix
		reference := reference_receipt(refstate, arch, digest(before + '/clonestack/init'))!
		for key, hash in reference { artifacts['reference_' + key] = hash }
		publish(refstate + '/receipt.json', out + 'clonestack-reference-' + suffix + '-receipt.json')!
		publish(refstate + '/serial.log', out + 'clonestack-reference-' + suffix + '.log')!
		mut sources := {
			'auditor':              digest(@FILE)
			'controller':           digest(root + 'tests/linux-compat/run.v')
			'reference_controller': digest(root + 'tests/linux-compat/clonestack-reference.v')
			'probe':                digest(root + 'tests/linux-compat/clonestackfixture/core.v')
		}
		for path in ['linux_task.v', 'clone_arm64.v', 'clone_amd64.v'] {
			sources['kernel/userland/' + path] = digest(root + 'kernel/userland/' + path)
		}
		value := Evidence{ architecture: arch, context: '768 native musl clone3 stack range/wrap/admission/import controls; Linux identical ELF; inherited-stack SIGCHLD fork/reap; identical original/corrected retention inputs; targeted kernel heap retention only', base_commit: os.read_file(area + 'base.txt')!.trim_space(), artifacts: artifacts, source_inputs: sources }
		os.write_file(area + 'evidence-' + arch + '.json', json2.encode(value, prettify: true) + '\n')!
		publish(area + 'evidence-' + arch + '.json', out + 'clonestack-evidence-' + arch + '.json')!
	}
	assert digest(area + 'states/preflight-arm/fixture.c') == digest(area + 'states/before-arm/clonestack/fixture.c')
	assert os.read_file(area + 'preflight.log')!.contains('Probe compiler preflight: PASS')
	pins := object('/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler-inputs.json')!
	assert pins.len == 15146
	for path, hash in pins {
		assert digest('/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/' + path) == hash.str(), path
	}
	sdk := object('/Users/alex/.cache/vinix-linux-compat/tidfault-20261015/sdk-inputs.json')!
	assert sdk.len == 2014
	for path, hash in sdk {
		assert digest(area + 'sdk/' + path) == hash.str(), path
	}
	for suffix in ['arm', 'x86'] {
		view := area + 'kernel-' + suffix + '/'
		inventory := object(view + 'docs/linux-syscall-coverage.json')!
		inputs := inventory['inputs']!.as_map()
		assert inputs.len == 67
		for path, hash in inputs {
			assert digest(view + path) == hash.str(), path
		}
		assert digest(view + 'docs/linux-syscall-coverage.json') == digest(area + 'kernel-arm/docs/linux-syscall-coverage.json')
	}
	retained := object(area + 'watch-final-retained-inputs.json')!
	assert retained.len == 84
	for path, hash in retained {
		assert path.starts_with(area + 'states/') && os.inode(path).typ == .regular && digest(path) == hash.str()
		if path.ends_with('.compiler.json') {
			command := object(path)!
			assert command['status']!.str() == '0' && command['arguments']!.str().contains('--target=aarch64-linux-musl') && command['arguments']!.str().contains('--sysroot=' + area + 'sdk')
		}
	}
	mut walked := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after'] {
			names := if phase == 'before' {
				['clonestack']
			} else {
				['clonestack', 'runtime', 'clonecgroup']
			}
			for name in names {
				probe := area + 'states/' + phase + '-' + suffix + '/' + name
				assert !os.exists(probe + '/iso-build') && !os.exists(probe + '/efivars.fd')
				mut count := 0
				for path in os.walk_ext(probe, '') {
					if os.inode(path).typ != .regular { continue }
					assert path in retained && path !in walked
					walked[path] = true
					count++
				}
				assert count == if suffix == 'arm' { 12 } else { 9 }
			}
		}
	}
	assert walked.len == retained.len && os.read_file(area + 'watch-final.log')!.split_into_lines().len == 8
	assert os.read_file(area + 'coverage-check.log')!.count('Linux dispatch coverage: PASS') == 4
	mut diagnostics := preliminary(area, root, out)!
	for path in ['manage.v', 'manage', 'arm-cc.v', 'arm-cc', 'preflight.v', 'preflight', 'preflight.log',
		'archive-p0.v', 'archive-p0', 'archive-p0-producer.log', 'states/preflight-arm/fixture.c',
		'states/preflight-arm/init', 'assertion-control.log', 'passing-log-control.log',
		'before-linux_task.v', 'after-linux_task.v', 'before-clone_arm64.v', 'after-clone_arm64.v',
		'before-clone_amd64.v', 'after-clone_amd64.v', 'watch.v', 'watch-final-retained-inputs.json',
		'coverage-check.log'] {
		diagnostics[path] = digest(area + path)
	}
	os.write_file(area + 'diagnostic-pins.json', json2.encode(diagnostics, prettify: true) + '\n')!
	publish(area + 'diagnostic-pins.json', out + 'clonestack-diagnostic-pins.json')!
	for path in ['assertion-control.log', 'passing-log-control.log', 'watch-final.log', 'preflight.log'] {
		publish(area + path, out + 'clonestack-' + path)!
	}
	println('Native clonestack conformance audit: PASS')
}
