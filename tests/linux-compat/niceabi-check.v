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

fn before_vector(ordinary int, kind int) int {
	return if ordinary == 0 { [480, 984, 0, 0]![kind] } else { [480, 954, 0, 0]![kind] }
}

fn semantics(log string, phase string, arch string, reference bool) {
	assert phase in ['before', 'after'] && arch in ['aarch64', 'x86_64']
	rows_topology := log.split_into_lines().filter(it.starts_with('LINUX NICEABI TOPOLOGY:'))
	assert rows_topology.len == 2
	mut seen_topology := map[string]bool{}
	for row in rows_topology {
		fields := row.fields()
		assert fields.len == 10
		for index, prefix in {
			3: 'ordinary='
			4: 'uid='
			5: 'self='
			6: 'same='
			7: 'cross='
			8: 'reaped='
			9: 'cap_sys_nice='
		} {
			assert fields[index].starts_with(prefix)
		}
		assert fields[3] in ['ordinary=0', 'ordinary=1'] && fields[3] !in seen_topology
		seen_topology[fields[3]] = true
		assert fields[4] == if fields[3] == 'ordinary=0' { 'uid=0' } else { 'uid=1000' }
		assert fields[9] == if fields[3] == 'ordinary=0' {
			'cap_sys_nice=1'
		} else {
			'cap_sys_nice=0'
		}
		mut pids := map[string]bool{}
		for index in 5 .. 9 {
			id := fields[index].all_after('=')
			assert id.int() > 0 && id !in pids
			pids[id] = true
		}
	}
	mut cases := map[string]string{}
	for label in ['CASES:', 'FINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX NICEABI ' + label))
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
			assert n == [840, 1512, 4032, 223]![kind]
			expected := if phase == 'after' {
				0
			} else if ordinary == 0 {
				before_vector(ordinary, kind)
			} else {
				before_vector(ordinary, kind)
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
		assert total == 13214
		if phase == 'after' {
			assert failures == 0
		} else {
			assert failures > 0
		}
	}
	assert !log.contains('Kernel panic') && !log.contains('LINUX NICEABI FAIL: setup')
	if phase == 'after' {
		assert !log.contains('LINUX NICEABI DETAIL:') && !log.contains('LINUX NICEABI FAIL:')
	} else {
		assert log.contains('LINUX NICEABI DETAIL:'), 'niceabi baseline failure markers required'
		assert log.contains('LINUX NICEABI FAIL:') && !log.contains('LINUX NICEABI: PASS')
	}
	if reference {
		assert phase == 'after' && log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX NICEABI REFERENCE: PASS') && !log.contains('LINUX NICEABI STORAGE:')
	} else if phase == 'after' {
		assert log.count('LINUX NICEABI: PASS') == 1
	}
}

fn storage(log string, arch string, phase string) {
	mut slabs := [2]int{}
	mut pages := [2]int{}
	mut seen := map[string]bool{}
	for row in log.split_into_lines().filter(it.starts_with('LINUX NICEABI SLAB:') || it.starts_with('LINUX NICEABI STORAGE:')) {
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
	assert log.contains('LINUX NICEABI DETAIL:'), 'niceabi baseline failure markers required'
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
		preparation := state.ends_with('/p1-after-arm') && name == 'runtime'
		assert name == names[index] && entry['exit_code']!.int() == if preparation || (failing && index == 0) {
			1
		} else {
			0
		} && entry['detail']!.str() == if preparation { 'Command failed' } else { '' }
		if preparation {
			assert os.read_file(state + '.log')!.contains('No space left on device')
			assert !os.exists(state + '/runtime/test.iso') && !os.exists(state + '/runtime/serial.log')
		}
		for label, path in {
			'source': state + '/sources/' + name + 'fixture/core.v'
			'init':   state + '/' + name + '/init'
			'iso':    state + '/' + name + '/test.iso'
		} {
			hash := if preparation && label == 'iso' { '' } else { digest(path) }
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
		artifacts[name + '_serial'] = if preparation {
			''
		} else {
			digest(state + '/' + name + '/serial.log')
		}
		if !preparation && (!failing || index > 0) {
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
		'wrapper_source':    state + '/source/niceabireferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/niceabi-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/niceabireferenceinit/core.v')
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
	mut expected := before
	for method in ['setpriority', 'getpriority'] {
		setter := method == 'setpriority'
		old_header := 'fn syscall_linux_' + method + '(_ voidptr, which int, local_who int' + if setter {
			', prio int'
		} else {
			''
		} + ') (u64, u64) {'
		new_header := 'fn syscall_linux_' + method + '(_ voidptr, raw_which int, raw_local_who int' + if setter {
			', raw_prio int'
		} else {
			''
		} + ') (u64, u64) {'
		old := definition(before, old_header)
		new := definition(after, new_header)
		decoded := new_header + '\n\twhich := int(i32(raw_which))\n\tlocal_who := int(i32(raw_local_who))' + if setter {
			'\n\tprio := int(i32(raw_prio))'
		} else {
			''
		}
		wanted := old.replace(old_header, decoded).replace('which != prio_process || who < 0', 'which != prio_process')
		assert wanted == new, 'only signed32 arguments and negative target error may change'
		assert new.count('proc.lock_table()') == 1 && new.count('proc.unlock_table()') == 1
		assert new.contains('proc.process_at(target_pid)') && new.contains('proc.mac_peer_allowed(')
		if setter {
			assert new.contains('target.nice = wanted')
		} else {
			assert new.contains('return u64(20 - target.nice), 0')
		}
		expected = expected.replace(old, new)
	}
	assert expected == after && digest(root + 'kernel/syscall/table/linux_common.v') == digest(area + 'after-linux_common.v')
}

fn check_c(area string, suffix string) ! {
	before := os.read_file(area + 'before-' + suffix + '.c')!
	after := os.read_file(area + 'after-' + suffix + '.c')!
	mut old_outside := before
	mut new_outside := after
	for method in ['setpriority', 'getpriority'] {
		setter := method == 'setpriority'
		old_parameters := 'i64 which, i64 local_who' + if setter { ', i64 prio' } else { '' }
		new_parameters := 'i64 raw_which, i64 raw_local_who' + if setter {
			', i64 raw_prio'
		} else {
			''
		}
		prefix := '\nmulti_return_u64_u64 table__syscall_linux_' + method + '(void* _0, '
		old := definition(before, prefix + old_parameters + ') {')
		new := definition(after, prefix + new_parameters + ') {')
		old_outside = old_outside.replace(old, '').replace(prefix + old_parameters + ');', prefix + new_parameters + ');')
		new_outside = new_outside.replace(new, '')
		assert old.count('proc__lock_table();') == new.count('proc__lock_table();') && new.count('proc__lock_table();') == 1
		assert old.count('proc__unlock_table();') == new.count('proc__unlock_table();') && new.count('proc__unlock_table();') > 0
		assert new.contains('((i32)(raw_which))') && new.contains('((i32)(raw_local_who))')
		if setter {
			assert new.contains('((i32)(raw_prio))') && new.contains('target->nice = wanted;')
		}
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array__', 'free(', 'alloca('] {
			assert !new.contains(token), suffix + token
		}
	}
	whole_equal := old_outside == new_outside
	assert whole_equal, 'whole production C differs outside the two definitions/prototype parameter names'
	assert digest(area + 'kernel-' + suffix + '/kernel/syscall/table/linux_common.v') == digest(area + 'after-linux_common.v')
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--scope-only' {
		area := os.args[2].trim_right('/') + '/'
		check_source(area, '/Users/alex/code/vinix/')!
		for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
		println('Native niceabi complete source/C scope: PASS')
		return
	}
	if '--negative-control' in os.args {
		assert false, 'niceabi assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: niceabi-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-15/'
	os.mkdir_all(out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'niceabi assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p1-reference-arm/serial.log', 'aarch64'], 'niceabi baseline failure markers required'))!
	check_source(area, root)!
	for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
	os.write_file(area + 'scope-check.log', 'arm/x86: complete production C differs only in setpriority/getpriority definitions and their prototype parameter names; no identifier normalization or allocation/free/escape; existing table locks, borrowed targets and nice mutation remain unchanged\n')!
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == 'e72783a88349ac10cd1d3ec405237c9438b94eca'
	compiler_root := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/'
	pins := object(compiler_root + 'compiler-inputs.json')!
	assert pins.len == 15146
	assert pins['v']!.str() == '9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b'
	for path, hash in pins {
		assert digest(compiler_root + 'compiler/' + path) == hash.str(), path
	}
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'coverage-check.log')!.count('Linux dispatch coverage: PASS') == 4
	assert os.read_file(area + 'coverage-before-check.log')!.count('Linux dispatch coverage: PASS') == 4
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
	assert os.read_file(area + 'linux-source.sha256')!.trim_space() == digest(area + 'linux-sys-v6.12.c') + ' https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/sys.c'
	assert os.read_file(area + 'preflight-arm.log')!.contains("call to undeclared function 'memdup'")
	assert os.read_file(states + 'preflight1-niceabi-arm/fixture.c')!.count('memdup(') == 4
	assert !os.exists(states + 'preflight1-niceabi-arm/init'), 'failed preparation must not supply a probe ELF'
	linux_source := os.read_file(area + 'linux-sys-v6.12.c')!
	assert linux_source.contains('SYSCALL_DEFINE3(setpriority, int, which, int, who, int, niceval)') && linux_source.contains('SYSCALL_DEFINE2(getpriority, int, which, int, who)') && linux_source.contains('retval = -ESRCH')
	assert os.read_file(area + 'watch.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 11
	assert os.read_file(area + 'watch.log')!.split_into_lines().filter(it.starts_with('Completed preparation failure ')).len == 1
	watch_output := os.read_file(area + 'helper-watch.log')!
	assert watch_output.split_into_lines().filter(it.starts_with('Retired completed boot staging:')).len == 7
	assert !watch_output.contains('timed out') && !watch_output.contains('panic')
	initial_watch := os.read_file(area + 'watch-initial-stdout.log')!
	assert initial_watch.split_into_lines().filter(it.starts_with('Retired completed boot staging:')).len == 4
	assert initial_watch.contains("assert code.int() == if phase == 'before' { 1 } else { 0 }")
	assert os.read_file(area + 'watch-initial.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 4
	initial_pins := object(area + 'watch-initial-retained-inputs.json')!
	assert initial_pins.len == 36
	for path, hash in initial_pins {
		assert digest(path) == hash.str(), path
	}
	retained := object(area + 'watch-retained-inputs.json')!
	assert retained.len == 97
	for path, hash in retained {
		assert path.starts_with(states + 'p1-before-') || path.starts_with(states + 'p1-after-') || path.starts_with(states + 'p2-after-arm/runtime/')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert os.inode(path).typ == .regular && digest(path) == hash.str(), path
	}
	mut actual_retained := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after'] {
			names := if phase == 'before' {
				['niceabi']
			} else {
				['niceabi', 'runtime', 'attrclass', 'attrnice']
			}
			for name in names {
				probe := states + 'p1-' + phase + '-' + suffix + '/' + name
				assert !os.exists(probe + '/iso-build') && !os.exists(probe + '/efivars.fd')
				for path in os.walk_ext(probe, '') {
					if os.inode(path).typ == .regular {
						assert path in retained
						actual_retained[path] = true
					}
				}
			}
		}
	}
	retry_probe := states + 'p2-after-arm/runtime'
	assert !os.exists(retry_probe + '/iso-build') && !os.exists(retry_probe + '/efivars.fd')
	for path in os.walk_ext(retry_probe, '') {
		if os.inode(path).typ == .regular {
			assert path in retained
			actual_retained[path] = true
		}
	}
	assert actual_retained.len == retained.len
	review_path := out + 'niceabi-lifetime-review.md'
	review := os.read_file(review_path)!
	assert review.starts_with('Independent niceabi lifetime review: PASS') && review.contains(digest(root + 'kernel/syscall/table/linux_common.v')) && review.contains(digest(root + 'tests/linux-compat/niceabifixture/core.v'))
	for arch, suffix in {
		'aarch64': 'arm'
		'x86_64':  'x86'
	} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == base
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/syscall/table/linux_common.v'
		inputs := object(tree + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
		assert inputs.len == 64
		for path, hash in inputs {
			assert digest(tree + path) == hash, path
		}
		before_inputs := object(area + 'coverage-before-' + suffix + '.json')!['inputs']!.as_map_of_strings()
		assert before_inputs.len == 64
		for path, hash in before_inputs {
			assert digest(if path == 'kernel/syscall/table/linux_common.v' {
				area + 'before-linux_common.v'
			} else {
				tree + path
			}) == hash, path
		}
		mut artifacts := {
			'compiler':                 digest(compiler_root + 'compiler/v')
			'compiler_inputs':          digest(compiler_root + 'compiler-inputs.json')
			'kernel_source':            digest(root + 'kernel/syscall/table/linux_common.v')
			'kernel_source_before':     digest(area + 'before-linux_common.v')
			'fixture_source':           digest(root + 'tests/linux-compat/niceabifixture/core.v')
			'failed_preflight_source':  digest(states + 'preflight1-niceabi-arm/fixture-source.v')
			'failed_preflight_c':       digest(states + 'preflight1-niceabi-arm/fixture.c')
			'failed_preflight_log':     digest(area + 'preflight-arm.log')
			'audit_source':             digest(@FILE)
			'review':                   digest(review_path)
			'linux_primary_source':     digest(area + 'linux-sys-v6.12.c')
			'linux_primary_pin':        digest(area + 'linux-source.sha256')
			'native_controller':        digest(area + 'run')
			'native_controller_source': digest(root + 'tests/linux-compat/run.v')
			'reference_controller':     digest(area + 'reference')
			'watch_pins':               digest(area + 'watch-retained-inputs.json')
			'watch_log':                digest(area + 'watch.log')
			'watch_initial_log':        digest(area + 'watch-initial.log')
			'watch_initial_stdout':     digest(area + 'watch-initial-stdout.log')
			'watch_initial_pins':       digest(area + 'watch-initial-retained-inputs.json')
			'watch_initial_source':     digest(area + 'watch-initial.v')
			'watch_resume_source':      digest(area + 'watch.v')
		}
		mut identity := map[string]string{}
		for phase in ['before', 'after'] {
			state := states + 'p1-' + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['niceabi']
			} else {
				['niceabi', 'runtime', 'attrclass', 'attrnice']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['niceabi_source', 'niceabi_init', 'niceabi_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/niceabi/serial.log')!
			semantics(text, phase, arch, false)
			storage(text, arch, phase)
			build := area + 'build-' + phase + '-' + suffix + '.log'
			text_build := os.read_file(build)!
			assert text_build.contains('-o bin/vinix') && !text_build.contains('Nothing to be done') && !text_build.contains('Error ')
			artifacts[phase + '_kernel'] = digest(kernel)
			artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
			artifacts[phase + '_build'] = digest(build)
			for label, path in {
				'receipt':   state + '/receipt.json'
				'aggregate': state + '.log'
				'native':    state + '/niceabi/serial.log'
				'build':     build
			} {
				publish(path, out + 'niceabi-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			if phase == 'after' {
				for name in names {
					if name == 'niceabi' || (arch == 'aarch64' && name == 'runtime') { continue }
					publish(state + '/' + name + '/serial.log', out + 'niceabi-regression-' + arch + '-' + name + '.log')!
				}
			}
		}
		if arch == 'aarch64' {
			retry := states + 'p2-after-arm'
			captured := receipt(retry, arch, digest(tree + 'kernel/bin/vinix'), ['runtime'], false)!
			for key, value in captured { artifacts['runtime_retry_' + key] = value }
			for label in ['source', 'init', 'c'] {
				assert captured['runtime_' + label] == artifacts['after_runtime_' + label], 'unchanged retry probe identity'
			}
			assert os.read_file(retry + '.log')!.contains('Linux compatibility guest suite: PASS')
			for label, path in {
				'receipt':   retry + '/receipt.json'
				'aggregate': retry + '.log'
				'native':    retry + '/runtime/serial.log'
			} {
				publish(path, out + 'niceabi-runtime-retry-aarch64-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			publish(retry + '/runtime/serial.log', out + 'niceabi-regression-aarch64-runtime.log')!
		}
		preflight := states + 'preflight2-niceabi-' + suffix
		raw := os.read_file(preflight + '/fixture.c')!
		assert digest(preflight + '/fixture.c') == identity['niceabi_c'] && digest(preflight + '/init') == identity['niceabi_init']
		assert raw.count('alloca(') == 4
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array_push(', 'array_get(',
			'v_fixed_index('] {
			assert !raw.contains(token)
		}
		artifacts['preflight_c'] = digest(preflight + '/fixture.c')
		artifacts['preflight_init'] = digest(preflight + '/init')
		reference := states + 'p1-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['niceabi_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'niceabi-reference-' + arch + '-' + label + if label == 'receipt' {
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
		os.write_file(out + 'niceabi-evidence-' + arch + '.json', json2.encode(Evidence{
			architecture:  arch
			context:       'Native PRIO_PROCESS signed32 which/who/nice words and missing-target ESRCH, preserving leader nice and OTHER/BATCH/IDLE policy. 13214 root/CAP_SYS_NICE and UID1000/no-capability zero-limit controls per architecture; seven raw word forms, genuine musl calls, live/absent/reaped/negative targets, clamped boundaries, exact errors and actual retained state. Same-ELF Linux6.12.51 references; four fresh production builds and four completed native cases per architecture across truthful split receipts, flat200-cycle storage, compiler/inventory/host/allocation diagnostics and independent review. Retain failed ARM memdup preparation separately from final four-alloca probes, ARM runtime ISO ENOSPC with no guest verdict, initial watcher assertion/partial inventory and fresh runtime-only completion with unchanged kernel/source/C/ELF. All97 regular files across11 captures are retained/rehashed. Full admission/group/worker/namespace/security/race/GNU/translated/ELF32 semantics, probe failed-transfer abort cleanup and broad roadmap gates remain unqualified.'
			base_commit:   base
			artifacts:     artifacts
			source_inputs: inputs
		}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log',
		'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'watch.log'] {
		publish(area + name, out + 'niceabi-' + name)!
	}
	publish(area + 'preflight-arm.log', out + 'niceabi-preflight-failure.log')!
	publish(area + 'watch-initial.log', out + 'niceabi-watch-initial.log')!
	publish(area + 'watch-initial-stdout.log', out + 'niceabi-watch-initial-stdout.log')!
	os.write_file(area + 'audit.log', 'Native niceabi conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'niceabi-audit.log')!
	println('Native niceabi conformance audit: PASS')
}
