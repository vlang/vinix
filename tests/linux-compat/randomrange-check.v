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

fn semantics(log string, phase string, arch string, reference bool) {
	assert phase in ['before', 'after'] && arch in ['aarch64', 'x86_64']
	rows_topology := log.split_into_lines().filter(it.starts_with('LINUX RANDOMRANGE TOPOLOGY:'))
	assert rows_topology.len == 2
	mut seen_topology := map[string]bool{}
	for row in rows_topology {
		fields := row.fields()
		assert fields.len == 9 && fields[3] in ['ordinary=0', 'ordinary=1'] && fields[3] !in seen_topology
		seen_topology[fields[3]] = true
		assert fields[4] == if fields[3] == 'ordinary=0' { 'uid=0' } else { 'uid=1000' }
		assert fields[5] == if reference || arch == 'x86_64' { 'page=4096' } else { 'page=16384' }
		assert fields[6] == 'readiness=seeded'
		assert fields[8] == if fields[5] == 'page=16384' { 'cap=7fffc000' } else { 'cap=7ffff000' }
		if arch == 'aarch64' {
			assert fields[7] == if reference {
				'ceiling=1000000000000'
			} else {
				'ceiling=800000000000'
			}
		} else {
			assert fields[7] == if reference {
				'ceiling=800000000000'
			} else {
				'ceiling=100000000000000'
			}
		}
	}
	mut cases := map[string]string{}
	for label in ['CASES:', 'FINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX RANDOMRANGE ' + label))
		assert rows.len == 8
		mut seen := map[string]bool{}
		mut total := 0
		mut failures := 0
		for row in rows {
			fields := row.fields()
			assert fields.len == 7
			for index, prefix in {
				3: 'ordinary='
				4: 'kind='
				5: 'calls='
				6: 'failures='
			} {
				assert fields[index].starts_with(prefix)
			}
			ordinary := fields[3].all_after('=').int()
			kind := fields[4].all_after('=').int()
			assert ordinary in [0, 1] && kind in [0, 1, 2, 3]
			key := fields[3] + fields[4]
			assert key !in seen
			seen[key] = true
			n := fields[5].all_after('=').int()
			f := fields[6].all_after('=').int()
			assert n == [888, 1800, 1440, 1464]![kind]
			expected := if phase == 'after' {
				0
			} else if ordinary == 0 {
				[504, 0, 0, 0]![kind]
			} else {
				[504, 0, 0, 0]![kind]
			}
			assert f == expected, row
			if label == 'CASES:' {
				cases[key] = fields[5] + fields[6]
			} else {
				assert cases[key] == fields[5] + fields[6]
			}
			total += n
			failures += f
		}
		assert total == 11184
		if phase == 'after' {
			assert failures == 0
		} else {
			assert failures > 0
		}
	}
	assert !log.contains('Kernel panic') && !log.contains('LINUX RANDOMRANGE FAIL: setup')
	if phase == 'after' {
		assert !log.contains('LINUX RANDOMRANGE DETAIL:') && !log.contains('LINUX RANDOMRANGE FAIL:')
	} else {
		assert log.contains('LINUX RANDOMRANGE DETAIL:'), 'randomrange baseline failure markers required'
		assert log.contains('LINUX RANDOMRANGE FAIL:') && !log.contains('LINUX RANDOMRANGE: PASS')
	}
	if reference {
		assert phase == 'after' && log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX RANDOMRANGE REFERENCE: PASS') && !log.contains('LINUX RANDOMRANGE STORAGE:')
	} else if phase == 'after' {
		assert log.count('LINUX RANDOMRANGE: PASS') == 1
	}
}

fn storage(log string, arch string, phase string) {
	mut slabs := [2]int{}
	mut pages := [2]int{}
	mut seen := map[string]bool{}
	for row in log.split_into_lines().filter(it.starts_with('LINUX RANDOMRANGE SLAB:') || it.starts_with('LINUX RANDOMRANGE STORAGE:')) {
		fields := row.fields()
		assert fields.len == 7 && fields[3].starts_with('ordinary=')
		ordinary := fields[3].all_after('=').int()
		assert ordinary in [0, 1]
		pair := fields[5].all_after('=').split('/')
		assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' {
			assert fields[4].starts_with('size=') && fields[6] == 'cycles=200'
			key := fields[3] + fields[4]
			assert key !in seen
			seen[key] = true
			slabs[ordinary]++
		} else {
			assert fields[4] == 'cycles=200' && fields[6] == 'PASS' && pair[0].u64() > 0
			pages[ordinary]++
		}
	}
	for ordinary in 0 .. 2 {
		assert slabs[ordinary] == if phase == 'before' {
			0
		} else if arch == 'aarch64' {
			18
		} else {
			14
		}
		assert pages[ordinary] == if phase == 'before' { 0 } else { 1 }
	}
}

fn failure(log string, arch string) {
	assert log.contains('LINUX RANDOMRANGE DETAIL:'), 'randomrange baseline failure markers required'
	semantics(log, 'before', arch, false)
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
		'wrapper_source':    state + '/source/randomrangereferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/randomrange-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/randomrangereferenceinit/core.v')
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

fn check_source(area string, root string) ! {
	before := os.read_file(area + 'before-linux_common.v')!
	after := os.read_file(area + 'after-linux_common.v')!
	marker := 'fn syscall_linux_getrandom(_ voidptr, buf u64, count u64, flags u32)'
	old := definition(before, marker)
	new := definition(after, marker)
	unchanged := before.replace(old, '') == after.replace(new, '')
	assert unchanged, 'Only getrandom definition may change'
	guard := '\t// Linux imports one bounded user buffer before generating any output.\n\tmax_count := u64(0x7fffffff) & ~(memory.page_size - 1)\n\tlength := if count > max_count { max_count } else { count }\n\tlimit := memory.user_address_limit()\n\tif buf > limit || length > limit - buf {\n\t\treturn errno.err, errno.efault\n\t}\n'
	assert new.count(guard) == 1
	removed := new.replace(guard, '').replace('if length == 0', 'if count == 0').replace('for written < length', 'for written < count').replace('mut chunk := length - written', 'mut chunk := count - written')
	exact := removed == old
	assert exact, 'Only request cap, whole range validation and bounded loop length may change'
	guard_index := new.index(guard) or { panic('guard missing') }
	zero_index := new.index('\tif length == 0') or { panic('zero check missing') }
	assert guard_index < zero_index
	assert digest(root + 'kernel/syscall/table/linux_common.v') == digest(area + 'after-linux_common.v')
}

fn check_c(area string, suffix string) ! {
	before := os.read_file(area + 'before-' + suffix + '.c')!
	after := os.read_file(area + 'after-' + suffix + '.c')!
	marker := '\nmulti_return_u64_u64 table__syscall_linux_getrandom(void* _0, u64 buf, u64 count, u32 flags) {'
	old := definition(before, marker)
	new := definition(after, marker)
	unchanged := before.replace(old, '') == after.replace(new, '')
	assert unchanged, 'Whole production C differs outside getrandom'
	assert new.contains('max_count') && new.contains('memory__user_address_limit') && new.contains('length - written')
	for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array__', 'free(', 'alloca('] {
		assert old.count(token) == new.count(token), suffix + token
	}
	assert digest(area + 'kernel-' + suffix + '/kernel/syscall/table/linux_common.v') == digest(area + 'after-linux_common.v')
}

fn primary_and_compilation(area string, out string) ! {
	pins := object(area + 'primary-inputs.json')!
	assert pins.len == 7
	for name, path in {
		'random':        'drivers/char/random.c'
		'iov_iter':      'lib/iov_iter.c'
		'access_ok':     'include/asm-generic/access_ok.h'
		'uaccess-x86':   'arch/x86/include/asm/uaccess.h'
		'uaccess64-x86': 'arch/x86/include/asm/uaccess_64.h'
		'page-x86':      'arch/x86/include/asm/page_64_types.h'
		'cpu-x86':       'arch/x86/kernel/cpu/common.c'
	} {
		file := 'linux-' + name + '-v6.12.c'
		assert pins[file]!.str() == digest(area + file) + ' https://raw.githubusercontent.com/torvalds/linux/v6.12/' + path
	}
	iterator := os.read_file(area + 'linux-iov_iter-v6.12.c')!
	start := iterator.index('int import_ubuf(') or { panic('Linux import missing') }
	imported := iterator[start..]
	cap := imported.index('if (len > MAX_RW_COUNT)') or { panic('Linux cap missing') }
	access := imported.index('access_ok(buf, len)') or { panic('Linux range check missing') }
	assert cap < access
	publish(area + 'primary-inputs.json', out + 'randomrange-primary-inputs.json')!
	failed := object(area + 'compilation-attempt1-inputs.json')!
	assert failed.len == 4
	for path, hash in failed {
		assert digest(area + path) == hash.str(), path
	}
	text := os.read_file(area + 'preflight1-arm.log')!
	assert text.contains("undeclared function 'v_fixed_index'") && text.contains('format specifies')
	assert !os.exists(area + 'states/preflight1-randomrange-arm/init')
	publish(area + 'preflight1-arm.log', out + 'randomrange-compilation-attempt1.log')!
	publish(area + 'compilation-attempt1-inputs.json', out + 'randomrange-compilation-attempt1-inputs.json')!
}

fn main() {
	if '--negative-control' in os.args {
		assert false, 'randomrange assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: randomrange-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-15/'
	os.mkdir_all(out)!
	primary_and_compilation(area, out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'randomrange assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p1-reference-arm/serial.log', 'aarch64'], 'randomrange baseline failure markers required'))!
	check_source(area, root)!
	for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
	os.write_file(area + 'scope-check.log', 'arm/x86: complete generated production C differs only in table__syscall_linux_getrandom; exact request cap and complete range guard before zero count with bounded copy loop; existing bounce lifetime, erasure and counted copies unchanged, with no compiler normalization or added allocation/free\n')!
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == 'c9495f033519d1313520d2b954620671e3db594f'
	compiler_root := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/'
	pins := object(compiler_root + 'compiler-inputs.json')!
	assert pins.len == 15146
	assert pins['v']!.str() == '9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b'
	for path, hash in pins {
		assert digest(compiler_root + 'compiler/' + path) == hash.str(), path
	}
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'coverage-check.log')!.count('Linux dispatch coverage: PASS') == 4
	before_alloc := os.read_file(area + 'allocs-before.log')!
	after_alloc := os.read_file(area + 'allocs-after.log')!
	assert before_alloc == after_alloc, 'Allocation diagnostics must remain byte-identical'
	for arch, count in {
		'aarch64': '398'
		'x86_64':  '290'
	} {
		assert before_alloc.split_into_lines().filter(it.starts_with(arch + ':')).len == 1
		assert before_alloc.contains(count + ' allocation sites (V exit 0)') && before_alloc.contains('NEW:')
	}
	assert os.read_file(area + 'coverage-before-check.log')!.count('Linux dispatch coverage: PASS') == 4
	assert os.read_file(area + 'linux-source.sha256')!.trim_space() == digest(area + 'linux-random-v6.12.c') + ' https://raw.githubusercontent.com/torvalds/linux/v6.12/drivers/char/random.c'
	linux_source := os.read_file(area + 'linux-random-v6.12.c')!
	assert linux_source.contains('if ((flags & (GRND_INSECURE | GRND_RANDOM)) == (GRND_INSECURE | GRND_RANDOM))') && linux_source.contains('SYSCALL_DEFINE3(getrandom, char __user *, ubuf, size_t, len, unsigned int, flags)')
	assert os.read_file(area + 'watch.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 8
	retained := object(area + 'watch-retained-inputs.json')!
	assert retained.len == 72
	for path, hash in retained {
		assert path.starts_with(states + 'p1-before-') || path.starts_with(states + 'p1-after-')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert os.inode(path).typ == .regular && digest(path) == hash.str(), path
	}
	mut walked := map[string]bool{}
	mut completed := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after'] {
			names := if phase == 'before' {
				['randomrange']
			} else {
				['randomrange', 'runtime', 'randomcopy']
			}
			for name in names {
				probe := states + 'p1-' + phase + '-' + suffix + '/' + name
				completed['Completed ' + probe + ': captured files byte-identical; disposable boot staging retired'] = true
				assert !os.exists(probe + '/iso-build') && !os.exists(probe + '/efivars.fd')
				mut count := 0
				for path in os.walk_ext(probe, '') {
					if os.inode(path).typ != .regular { continue }
					assert path in retained && path !in walked
					walked[path] = true
					count++
				}
				assert count == 9
			}
		}
	}
	assert walked.len == retained.len
	for row in os.read_file(area + 'watch.log')!.split_into_lines() {
		assert row in completed
		completed.delete(row)
	}
	assert completed.len == 0
	for arch, suffix in {
		'aarch64': 'arm'
		'x86_64':  'x86'
	} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == base
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/syscall/table/linux_common.v'
		inputs := object(tree + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
		assert inputs.len == 64
		before_inputs := object(area + 'coverage-before-' + suffix + '.json')!['inputs']!.as_map_of_strings()
		assert before_inputs.len == 64
		for path, hash in inputs {
			assert digest(tree + path) == hash, path
			assert before_inputs[path] == if path == 'kernel/syscall/table/linux_common.v' {
				digest(area + 'before-linux_common.v')
			} else {
				hash
			}
		}
		mut artifacts := {
			'compiler':                 digest(compiler_root + 'compiler/v')
			'compiler_inputs':          digest(compiler_root + 'compiler-inputs.json')
			'kernel_source':            digest(root + 'kernel/syscall/table/linux_common.v')
			'kernel_source_before':     digest(area + 'before-linux_common.v')
			'fixture_source':           digest(root + 'tests/linux-compat/randomrangefixture/core.v')
			'audit_source':             digest(@FILE)
			'linux_primary_source':     digest(area + 'linux-random-v6.12.c')
			'linux_primary_pin':        digest(area + 'linux-source.sha256')
			'linux_primary_inputs':     digest(area + 'primary-inputs.json')
			'probe_compile_refusal':    digest(area + 'compilation-attempt1-inputs.json')
			'native_controller':        digest(area + 'run')
			'native_controller_source': digest(root + 'tests/linux-compat/run.v')
			'reference_controller':     digest(area + 'reference')
			'watch_pins':               digest(area + 'watch-retained-inputs.json')
			'watch_log':                digest(area + 'watch.log')
		}
		for name in ['manage.v', 'manage', 'watch.v', 'watch', 'preflight3.v', 'preflight-jobs3.v',
			'run-preflight3.v', 'helper-preflight-jobs3.log', 'preflight3-arm.log', 'preflight3-x86.log',
			'coverage-before-check.log', 'coverage-before-arm.json', 'coverage-before-x86.json'] {
			artifacts[name] = digest(area + name)
		}
		mut identity := map[string]string{}
		for phase in ['before', 'after'] {
			state := states + 'p1-' + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['randomrange']
			} else {
				['randomrange', 'runtime', 'randomcopy']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['randomrange_source', 'randomrange_init', 'randomrange_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/randomrange/serial.log')!
			semantics(text, phase, arch, false)
			storage(text, arch, phase)
			build := area + 'build-' + phase + '-' + suffix + '.log'
			text_build := os.read_file(build)!
			assert text_build.contains('-o bin/vinix') && !text_build.contains('Nothing to be done') && !text_build.contains('Error ')
			producer := area + 'build-' + phase + '-' + suffix + '-detached.log'
			assert os.read_file(producer)!.trim_space() == suffix + ' ' + phase + ' production build: PASS'
			artifacts[phase + '_build_producer'] = digest(producer)
			artifacts[phase + '_kernel'] = digest(kernel)
			artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
			artifacts[phase + '_build'] = digest(build)
			for label, path in {
				'receipt':   state + '/receipt.json'
				'aggregate': state + '.log'
				'native':    state + '/randomrange/serial.log'
				'build':     build
			} {
				publish(path, out + 'randomrange-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			if phase == 'after' {
				for name in names {
					if name == 'randomrange' { continue }
					publish(state + '/' + name + '/serial.log', out + 'randomrange-regression-' + arch + '-' + name + '.log')!
				}
			}
		}
		preflight := states + 'preflight3-randomrange-' + suffix
		raw := os.read_file(preflight + '/fixture.c')!
		assert digest(preflight + '/fixture.c') == identity['randomrange_c'] && digest(preflight + '/init') == identity['randomrange_init']
		assert raw.count('alloca(') == 4
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array_push(', 'array_get(',
			'v_fixed_index('] {
			assert !raw.contains(token)
		}
		artifacts['preflight_c'] = digest(preflight + '/fixture.c')
		artifacts['preflight_init'] = digest(preflight + '/init')
		reference := states + 'p1-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['randomrange_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'randomrange-reference-' + arch + '-' + label + if label == 'receipt' {
				'.json'
			} else {
				'.log'
			})!
			artifacts['reference_' + label] = digest(path)
		}
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log',
			'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] {
			artifacts[name] = digest(area + name)
		}
		os.write_file(out + 'randomrange-evidence-' + arch + '.json', json2.encode(Evidence{
			architecture:  arch
			context:       'Native seeded getrandom request import,11184 root/UID1000 controls per architecture: cap counts at native-page-aligned MAX_RW_COUNT then reject complete ranges outside userspace before any output, including invalid zero-count addresses. Fixed4GiB guarded arena and separate guarded arena1GiB below a discovered mapping ceiling; six accepted flags, three raw upper-word forms and genuine musl calls. Original1008 failures each; corrected and identical-ELF Linux6.12.51 zero. Unknown/conflicting flag precedence, actual bounded success and first-byte EFAULT, positive bounded partial copies including large/SIZE_MAX requests at the lower arena, intact writable/readonly guards and zero controls. Four stack allocas, two flat warmed200-cycle range/zero paths, four production builds, runtime/randomcopy regressions, identical allocation diagnostics, compiler/64-input inventory pins and executing audit negatives. Only scalar request import and bounded loop length change; counted copies, bounce ownership and existing erasure remain unchanged. Initial probe compile refusal is retained. Entropy quality, unseeded readiness/blocking/interruption, tags, exact last-user-page policy, mapping/range races, full bulk2GiB transfers and GNU/translated/ELF32 paths remain unqualified.'
			base_commit:   base
			artifacts:     artifacts
			source_inputs: inputs
		},
			prettify: true
		) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log',
		'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'watch.log',
		'coverage-before-check.log', 'helper-preflight-jobs3.log'] {
		publish(area + name, out + 'randomrange-' + name)!
	}
	publish(area + 'watch-retained-inputs.json', out + 'randomrange-watch-retained-inputs.json')!
	os.write_file(area + 'audit.log', 'Native randomrange conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'randomrange-audit.log')!
	println('Native randomrange conformance audit: PASS')
}
