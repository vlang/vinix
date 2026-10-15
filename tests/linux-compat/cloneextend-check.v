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
	for row in log.split_into_lines().filter(it.starts_with('LINUX CLONEEXTEND SLAB:') || it.starts_with('LINUX CLONEEXTEND STORAGE:')) {
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
		'wrapper_source':    state + '/source/cloneextendreferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/cloneextend-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/cloneextendreferenceinit/core.v')
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
	assert log.contains('LINUX CLONEEXTEND DETAIL:'), 'cloneextend baseline failure markers required'
	semantics(log, 'before', arch, false)
}

fn semantics(log string, phase string, arch string, reference bool) {
	assert phase in ['before', 'after'] && arch in ['aarch64', 'x86_64']
	mut seen := map[string]bool{}
	for label in ['CASES:', 'FINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX CLONEEXTEND ' + label))
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
			calls := [45, 90, 36, 75, 36, 45]![class]
			bad := if phase == 'after' {
				0
			} else if class == 0 || class == 5 {
				45
			} else if class == 2 {
				27
			} else if class == 4 {
				24
			} else {
				0
			}
			assert f[6] == 'calls=' + calls.str() && f[7] == 'failures=' + bad.str()
			total += calls
			failures += bad
		}
		assert total == 1308 && failures == if phase == 'after' { 0 } else { 564 }
	}
	cohorts := log.split_into_lines().filter(it.starts_with('LINUX CLONEEXTEND COHORT:'))
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
		assert f[8..] == ['raw=327', 'classes=6', 'layouts=3']
	}
	for label in ['CHILDREN:', 'CHILDRENFINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX CLONEEXTEND ' + label))
		assert rows.len == 4
		seen.clear()
		for row in rows {
			f := row.fields()
			assert f.len == 7 && f[3] in ['ordinary=0', 'ordinary=1'] && f[4] in [
				'namespace=0',
				'namespace=1',
			]
			key := f[3] + f[4]
			assert key !in seen
			seen[key] = true
			assert f[5] == 'valid=' + if phase == 'before' { '0' } else { '45' }
			assert f[6] == 'unexpected=0'
		}
	}

	if phase == 'before' {
		assert log.contains('LINUX CLONEEXTEND DETAIL:') && log.contains('LINUX CLONEEXTEND FAIL:') && !log.contains('LINUX CLONEEXTEND: PASS')
	} else {
		assert !log.contains('LINUX CLONEEXTEND DETAIL:') && !log.contains('LINUX CLONEEXTEND FAIL:')
	}
	if reference {
		assert log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX CLONEEXTEND REFERENCE: PASS') && !log.contains('LINUX CLONEEXTEND STORAGE:')
	} else if phase == 'after' {
		assert log.count('LINUX CLONEEXTEND: PASS') == 1
	}
	assert !log.contains('Kernel panic') && !log.contains('setup stage=')
}

fn scope(area string, root string) ! {
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == 'fd7ebcc0aca956cf0eea2757e993b8fb2fb7c01c'
	added := '// Import older prefixes and zero-filled future extensions, as Linux does.\n// Check the extension first, one aligned word at a time: a nonzero word must\n// win over an inaccessible later page or an inaccessible known prefix.\nfn import_clone3_args(mut args CloneArgs, address u64, size u64) u64 {\n	if size > page_size { return errno.e2big }\n	if size < clone_args_size_ver0 { return errno.einval }\n	args = CloneArgs{}\n	mut copy_size := size\n	if size > sizeof(CloneArgs) {\n		if address > ~u64(0) - sizeof(CloneArgs)\n			|| !usercopy.user_range(address + sizeof(CloneArgs), size - sizeof(CloneArgs)) {\n			return errno.efault\n		}\n		mut offset := u64(sizeof(CloneArgs))\n		mut word := [8]u8{}\n		for offset < size {\n			current := address + offset\n			mut length := u64(8) - (current & 7)\n			if length > size - offset { length = size - offset }\n			if !usercopy.copy_from_user(unsafe { voidptr(&word[0]) }, current, length) {\n				return errno.efault\n			}\n			for index in 0 .. int(length) {\n				if word[index] != 0 { return errno.e2big }\n			}\n			offset += length\n		}\n		copy_size = sizeof(CloneArgs)\n	}\n	if !usercopy.copy_from_user(voidptr(&args), address, copy_size) { return errno.efault }\n	return 0\n}\n\n'
	old_import := '\tif size < clone_args_size_ver0 {\n\t\treturn errno.err, errno.einval\n\t}\n\tif size > sizeof(CloneArgs) {\n\t\treturn errno.err, errno.e2big\n\t}\n\n\tmut args := CloneArgs{}\n\tif !usercopy.copy_from_user(voidptr(&args), uargs, size) {\n\t\treturn errno.err, errno.efault\n\t}'
	new_import := '\tmut args := CloneArgs{}\n\tfailure := import_clone3_args(mut args, uargs, size)\n\tif failure != 0 {\n\t\treturn errno.err, failure\n\t}'
	for path in ['linux_task.v', 'clone_arm64.v', 'clone_amd64.v'] {
		before := os.read_file(area + 'before-' + path)!
		after := os.read_file(area + 'after-' + path)!
		mut expected := before
		if path == 'linux_task.v' {
			at := "// CLONE_CLEAR_SIGHAND resets the child's private copy before it can run."
			assert before.count(at) == 1
			expected = before.replace(at, added + at)
		} else {
			assert before.count(old_import) == 1
			expected = before.replace(old_import, new_import)
		}
		assert expected == after && digest(root + 'kernel/userland/' + path) == digest(area + 'after-' + path)
		for suffix in ['arm', 'x86'] {
			tree := area + 'kernel-' + suffix
			assert git(tree, ['show', base + ':kernel/userland/' + path])!.trim_space() == before.trim_space()
			assert digest(tree + '/kernel/userland/' + path) == digest(area + 'after-' + path)
		}
	}
	for suffix in ['arm', 'x86'] {
		tree := area + 'kernel-' + suffix
		assert git(tree, ['rev-parse', 'HEAD'])! == base
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/userland/clone_amd64.v\nkernel/userland/clone_arm64.v\nkernel/userland/linux_task.v'
		before := os.read_file(area + 'before-' + suffix + '.c')!
		after := os.read_file(area + 'after-' + suffix + '.c')!
		marker := '\nmulti_return_u64_u64 userland__syscall_clone3(void* ' + if suffix == 'arm' {
			'_gpr_state'
		} else {
			'gpr_state'
		} + ', u64 uargs, u64 size) {'
		old_body := definition(before, marker)
		new_body := definition(after, marker)
		start := old_body.index('\n\tif (size < userland__clone_args_size_ver0)') or { panic('C import') }
		end := old_body.index('\n\tif (!userland__valid_clone3_flags') or { panic('C flags') }
		replacement := '\n\tuserland__CloneArgs args = (userland__CloneArgs){0};\n\tu64 failure = userland__import_clone3_args(&args, uargs, size);\n\tif (failure != 0) {\n\t\treturn (multi_return_u64_u64){errno__err, failure};\n\t}'
		assert old_body[..start] + replacement + old_body[end..] == new_body
		proto := 'u64 userland__import_clone3_args(userland__CloneArgs* args, u64 address, u64 size);\n'
		helper := definition(after, '\nu64 userland__import_clone3_args(userland__CloneArgs* args, u64 address, u64 size) {')
		assert helper == '\nu64 userland__import_clone3_args(userland__CloneArgs* args, u64 address, u64 size) {\n	if (size > memory__page_size) {\n		return errno__e2big;\n	}\n	if (size < userland__clone_args_size_ver0) {\n		return errno__einval;\n	}\n	*args = (userland__CloneArgs){0};\n	u64 copy_size = size;\n	if (size > sizeof(userland__CloneArgs)) {\n		if ((address > (~(u64)(0) - sizeof(userland__CloneArgs))) || !usercopy__user_range(address + sizeof(userland__CloneArgs), size - sizeof(userland__CloneArgs))) {\n			return errno__efault;\n		}\n		u64 offset = (u64)(sizeof(userland__CloneArgs));\n		u8 word[8];\n		memmove(word, (u8[8]){0}, sizeof(word));\n		while (offset < size) {\n			u64 current = address + offset;\n			u64 length = (u64)(8) - (current & 7);\n			if (length > (size - offset)) {\n				length = size - offset;\n			}\n			if (!usercopy__copy_from_user((void*)(&word[0]), current, length)) {\n				return errno__efault;\n			}\n			{\n				i64 v_index = 0;\n				for (; v_index < (i64)(length); v_index++) {\n					if (word[v_fixed_index(v_index, 8)] != 0) {\n						return errno__e2big;\n					}\n				}\n			}\n			offset += length;\n		}\n		copy_size = sizeof(userland__CloneArgs);\n	}\n	if (!usercopy__copy_from_user((void*)(args), address, copy_size)) {\n		return errno__efault;\n	}\n	return 0;\n}' && after.count(proto) == 1
		equal := before.replace(old_body, new_body) == after.replace(proto, '').replace(helper + '\n', '')
		assert equal, 'Exact whole C must differ only in clone3 argument import'
		for body in [new_body, helper] {
			for prohibited in ['memdup(', 'malloc(', 'calloc(', 'new_array', '__builtin_alloca('] {
				assert !body.contains(prohibited)
			}
		}
	}
}

fn main() {
	if '--scope-only' in os.args {
		scope(os.args[2].trim_right('/') + '/', '/Users/alex/code/vinix/')!
		println('Native cloneextend exact source/C scope: PASS')
		return
	}
	if '--negative-control' in os.args {
		assert false, 'cloneextend assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len in [2, 3] && (os.args.len == 2 || os.args[2] == '--verify-only'), 'Usage: cloneextend-check.v EVIDENCE-AREA [--verify-only] (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	root := '/Users/alex/code/vinix/'
	out := if os.args.len == 3 {
		area + 'preview/'
	} else {
		root + 'tests/linux-compat/results/2026-10-16/'
	}
	os.mkdir_all(out)!
	scope(area, root)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'cloneextend assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		area + 'states/reference-arm/serial.log', 'aarch64'], 'cloneextend baseline failure markers required'))!
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
				['cloneextend']
			} else {
				['cloneextend', 'runtime', 'cloneclear']
			}
			kernel := digest(state + '/kernel/bin/vinix')
			assert kernel == digest(area + '/' + if phase == 'before' {
				'baseline-' + suffix
			} else {
				'kernel-' + suffix
			} + '/kernel/bin/vinix')
			got := receipt(state, arch, kernel, names, phase == 'before')!
			for key, hash in got { artifacts[phase + '_' + key] = hash }
			log := os.read_file(state + '/cloneextend/serial.log')!
			if phase == 'before' {
				failure(log, arch)
			} else {
				semantics(log, 'after', arch, false)
			}
			storage(log, arch, phase)
			probe_c := os.read_file(state + '/cloneextend/fixture.c')!
			for forbidden in ['memdup(', 'malloc(', 'calloc(', 'realloc(', 'new_array', 'v_fixed_index'] {
				assert !probe_c.contains(forbidden), forbidden
			}
			assert probe_c.count('alloca(') == 8
			assert digest(state + '/cloneextend/fixture.c') == digest(before + '/cloneextend/fixture.c') && digest(state + '/cloneextend/init') == digest(before + '/cloneextend/init')
			for name in names {
				publish(state + '/' + name + '/serial.log', out + 'cloneextend-' + phase + '-' + suffix + '-' + name + '.log')!
			}
			for path in ['receipt.json'] {
				publish(state + '/' + path, out + 'cloneextend-' + phase + '-' + suffix + '-' + path)!
			}
			publish(state + '.log', out + 'cloneextend-' + phase + '-' + suffix + '-producer.log')!
			publish(area + 'build-' + phase + '-' + suffix + '.log', out + 'cloneextend-build-' + phase + '-' + suffix + '.log')!
			artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
			artifacts[phase + '_build_log'] = digest(area + 'build-' + phase + '-' + suffix + '.log')
		}
		refstate := area + 'states/reference-' + suffix
		reference := reference_receipt(refstate, arch, digest(before + '/cloneextend/init'))!
		for key, hash in reference { artifacts['reference_' + key] = hash }
		publish(refstate + '/receipt.json', out + 'cloneextend-reference-' + suffix + '-receipt.json')!
		publish(refstate + '/serial.log', out + 'cloneextend-reference-' + suffix + '.log')!
		mut sources := {
			'auditor':              digest(@FILE)
			'controller':           digest(root + 'tests/linux-compat/run.v')
			'reference_controller': digest(root + 'tests/linux-compat/cloneextend-reference.v')
			'probe':                digest(root + 'tests/linux-compat/cloneextendfixture/core.v')
		}
		for path in ['linux_task.v', 'clone_arm64.v', 'clone_amd64.v'] {
			sources['kernel/userland/' + path] = digest(root + 'kernel/userland/' + path)
		}
		value := Evidence{ architecture: arch, context: '1308 native musl clone3 extensible import controls; zero/nonzero tails, word/page fault ordering, every prefix length 64-88, native page size limits, admission and real forks; Linux identical ELF; original/corrected identical targeted cleanup inputs', base_commit: os.read_file(area + 'base.txt')!.trim_space(), artifacts: artifacts, source_inputs: sources }
		os.write_file(area + 'evidence-' + arch + '.json', json2.encode(value, prettify: true) + '\n')!
		publish(area + 'evidence-' + arch + '.json', out + 'cloneextend-evidence-' + arch + '.json')!
	}
	assert digest(area + 'states/preflight-arm/fixture.c') == digest(area + 'states/before-arm/cloneextend/fixture.c')
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
				['cloneextend']
			} else {
				['cloneextend', 'runtime', 'cloneclear']
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
	mut diagnostics := map[string]string{}
	assert os.read_file(area + 'audit-scope-refused.log.status')!.trim_space() == '1' && os.read_file(area + 'audit-scope-refused.log')!.contains('userland__CloneArgs args = {0};')
	for path in ['audit-scope-refused.v', 'audit-scope-refused', 'audit-scope-refused.log',
		'audit-scope-refused.log.status'] {
		diagnostics[path] = digest(area + path)
	}
	assert os.read_file(area + 'preflight-refused-replay.log.status')!.trim_space() == '1' && os.read_file(area + 'preflight-refused-replay.log')!.contains('undefined ident: `prefix_fault`')
	assert digest(area + 'preflight-refused-core.v') == digest(area + 'refused-inputs/cloneextendfixture/core.v')
	for path in os.walk_ext(area + 'states/preflight-refused-arm', '') {
		if os.inode(path).typ == .regular { diagnostics[path] = digest(path) }
	}
	for path in ['linux-fork-v6.12.c', 'repair-fixture.v', 'preflight-refused-core.v',
		'preflight-refused-replay.log', 'preflight-refused-replay.log.status', 'manage.v', 'manage',
		'arm-cc.v', 'arm-cc', 'preflight.v', 'preflight', 'preflight.log',
		'states/preflight-arm/fixture.c', 'states/preflight-arm/init', 'assertion-control.log',
		'passing-log-control.log', 'before-linux_task.v', 'after-linux_task.v', 'before-clone_arm64.v',
		'after-clone_arm64.v', 'before-clone_amd64.v', 'after-clone_amd64.v', 'watch.v',
		'watch-final-retained-inputs.json', 'coverage-check.log'] {
		diagnostics[path] = digest(area + path)
	}
	os.write_file(area + 'diagnostic-pins.json', json2.encode(diagnostics, prettify: true) + '\n')!
	publish(area + 'diagnostic-pins.json', out + 'cloneextend-diagnostic-pins.json')!
	for path in ['assertion-control.log', 'passing-log-control.log', 'watch-final.log', 'preflight.log',
		'preflight-refused-replay.log', 'audit-scope-refused.log'] {
		publish(area + path, out + 'cloneextend-' + path)!
	}
	println('Native cloneextend conformance audit: PASS')
}
