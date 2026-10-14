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
	rows_topology := log.split_into_lines().filter(it.starts_with('LINUX AFFABI TOPOLOGY:'))
	assert rows_topology.len == 2
	mut seen_topology := map[string]bool{}
	for row in rows_topology {
		fields := row.fields()
		assert fields.len == 9
		for index, prefix in {
			3: 'ordinary='
			4: 'mask='
			5: 'worker='
			6: 'peer='
			7: 'page='
			8: 'mask_bytes='
		} {
			assert fields[index].starts_with(prefix)
		}
		assert fields[3] in ['ordinary=0', 'ordinary=1'] && fields[3] !in seen_topology
		seen_topology[fields[3]] = true
		assert fields[4] == if !reference && arch == 'aarch64' { 'mask=1' } else { 'mask=3' }
		assert fields[5].all_after('=').int() > 0 && fields[6].all_after('=').int() > 0 && fields[5].all_after('=') != fields[6].all_after('=')
		assert fields[7].all_after('=').int() == if reference || arch == 'x86_64' {
			4096
		} else {
			16384
		}
		assert fields[8].all_after('=').int() == if reference && arch == 'x86_64' { 32 } else { 8 }
	}
	mut cases := map[string]string{}
	for label in ['CASES:', 'FINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX AFFABI ' + label))
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
			assert n == [6080, 12160, 6080, 388]![kind]
			expected := if phase == 'after' { 0 } else { [3098, 8336, 2302, 198]![kind] }
			assert f == expected, row
			if label == 'CASES:' {
				cases[key] = fields[5] + fields[6]
			} else {
				assert cases[key] == fields[5] + fields[6]
			}
			total += n
			failures += f
		}
		assert total == 49416
		if phase == 'after' {
			assert failures == 0
		} else {
			assert failures > 0
		}
	}
	assert !log.contains('Kernel panic') && !log.contains('LINUX AFFABI FAIL: setup')
	if phase == 'after' {
		assert !log.contains('LINUX AFFABI DETAIL:') && !log.contains('LINUX AFFABI FAIL:')
	} else {
		assert log.contains('LINUX AFFABI DETAIL:'), 'affabi baseline failure markers required'
		assert log.contains('LINUX AFFABI FAIL:') && !log.contains('LINUX AFFABI: PASS')
	}
	if reference {
		assert phase == 'after' && log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX AFFABI REFERENCE: PASS') && !log.contains('LINUX AFFABI STORAGE:')
	} else if phase == 'after' {
		assert log.count('LINUX AFFABI: PASS') == 1
	}
}

fn storage(log string, arch string, phase string) {
	mut slabs := [2]int{}
	mut pages := [2]int{}
	mut seen := map[string]bool{}
	for row in log.split_into_lines().filter(it.starts_with('LINUX AFFABI SLAB:') || it.starts_with('LINUX AFFABI STORAGE:')) {
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
			assert pair[0].u64() == if arch == 'aarch64' { u64(71) } else { u64(175) }
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
	assert log.contains('LINUX AFFABI DETAIL:'), 'affabi baseline failure markers required'
	semantics(log, 'before', arch, false)
}

fn receipt(state string, arch string, kernel string, names []string, failing bool) !map[string]string {
	value := object(state + '/receipt.json')!
	assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel && digest(state + '/kernel/bin/vinix') == kernel
	rows := value['results']!.as_array()
	assert rows.len == names.len
	mut artifacts := {
		'receipt':   digest(state + '/receipt.json')
		'aggregate': digest(state + '.log')
	}
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
		'wrapper_source':    state + '/source/affabireferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/affabi-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/affabireferenceinit/core.v')
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
	before := os.read_file(area + '/before-gaps.v')!
	after := os.read_file(area + '/after-gaps.v')!
	old_get := definition(before, 'fn syscall_linux_sched_getaffinity(_ voidptr, local_pid int, size u64, mask u64)')
	old_set := definition(before, 'fn syscall_linux_sched_setaffinity(_ voidptr, local_pid int, size u64, mask u64)')
	new_get := definition(after, 'fn syscall_linux_sched_getaffinity(_ voidptr, raw_pid int, size u32, mask u64)')
	new_set := definition(after, 'fn syscall_linux_sched_setaffinity(_ voidptr, raw_pid int, size u32, mask u64)')
	permission := definition(after, 'fn sched_affinity_permission(tid int) u64')
	comment := "// Keep borrowed target/owner pointers within the PID-table lock. Linux allows\n// the same real/effective owner or an effective CAP_SYS_NICE, independently of\n// a caller's UID being zero. MAC checks still apply to every later lookup.\n"
	old_remainder := before.replace(old_get, '').replace(old_set, '')
	new_remainder := after.replace(new_get, '').replace(new_set, '').replace(comment + permission + '\n\n', '')
	matching_scope := old_remainder == new_remainder
	assert matching_scope, 'Source changes outside affinity functions and scalar helper'
	assert digest(root + '/kernel/syscall/table/gaps.v') == digest(area + '/after-gaps.v')
	before_container := os.read_file(area + '/before-container.v')!
	after_container := os.read_file(area + '/after-container.v')!
	matching_container := before_container == after_container.replace('pub const cap_sys_nice = 23\n', '')
	assert matching_container, 'Container change exceeds scalar CAP_SYS_NICE constant'
	assert digest(root + '/kernel/proc/container.v') == digest(area + '/after-container.v')
	assert new_get.contains('if u32(size * u32(8)) < u32(cpus) || size % sizeof(u64) != 0')
	get_validation := new_get.index('if u32(size * u32(8))') or { panic('missing order marker') }
	get_lookup := new_get.index('pid := proc.kernel_id') or { panic('missing order marker') }
	assert get_validation < get_lookup
	assert new_get.contains('proc.kernel_id(int(i32(u32(raw_pid))))') && new_set.contains('proc.kernel_id(int(i32(u32(raw_pid))))')
	set_copy := new_set.index('copy_from_user') or { panic('missing order marker') }
	set_lookup := new_set.index('pid := proc.kernel_id') or { panic('missing order marker') }
	assert set_copy < set_lookup
	set_permission := new_set.index('permission :=') or { panic('missing order marker') }
	set_empty := new_set.index('if bits & present == 0') or { panic('missing order marker') }
	assert set_permission < set_empty
	assert permission.contains('proc.lock_table()\n\tdefer { proc.unlock_table() }')
	assert permission.contains('target == unsafe { nil } || target.process == unsafe { nil }')
	assert permission.contains('caller.euid != owner.euid && caller.euid != owner.uid')
	assert permission.contains('!proc.has_capability(caller, proc.cap_sys_nice)')
	old_mutation := old_set.all_after('\tmut cpus :=').replace('\ttid := if pid == 0 { proc.current_thread().tid } else { pid }\n\tif !proc.mac_thread_peer_allowed(tid) { return errno.err, errno.get() }\n', '')
	new_mutation := new_set.all_after('\tmut cpus :=')
	mutation_matches := old_mutation == new_mutation
	assert mutation_matches, 'CPU filtering or final mutation changes beyond prior permission placement'
}

fn check_c(area string, suffix string) ! {
	before := os.read_file(area + '/before-' + suffix + '.c')!
	after := os.read_file(area + '/after-' + suffix + '.c')!
	mut old_remainder := before
	mut new_remainder := after
	for operation in ['get', 'set'] {
		old_proto := 'multi_return_u64_u64 table__syscall_linux_sched_' + operation + 'affinity(void* _0, i64 local_pid, u64 size, u64 mask);'
		new_proto := old_proto.replace('i64 local_pid, u64 size,', 'i64 raw_pid, u32 size,')
		old := definition(before, '\n' + old_proto.trim_right(';') + ' {')
		new := definition(after, '\n' + new_proto.trim_right(';') + ' {')
		assert before.count(old_proto) == 1 && after.count(new_proto) == 1
		old_remainder = old_remainder.replace(old, '').replace(old_proto, '')
		new_remainder = new_remainder.replace(new, '').replace(new_proto, '')
		assert new.contains('proc__kernel_id((i64)((i32)((u32)(raw_pid))))')
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array__', 'free(', 'v_fixed_index(',
			'alloca('] {
			assert !new.contains(token), suffix + ' ' + operation + ' lifetime: ' + token
		}
	}
	helper := definition(after, '\nu64 table__sched_affinity_permission(i64 tid) {')
	assert after.count('u64 table__sched_affinity_permission(i64 tid);\n') == 1
	new_remainder = new_remainder.replace(helper + '\n', '').replace('u64 table__sched_affinity_permission(i64 tid);\n', '').replace('#define proc__cap_sys_nice (23)\n', '')
	scope_matches := old_remainder == new_remainder
	assert scope_matches, suffix + ' entire C differs beyond two syscall bodies/prototypes, permission helper and capability define'
	assert helper.count('proc__lock_table();') == 1 && helper.count('proc__unlock_table();') == 5
	assert helper.contains('proc__Thread* target = proc__threads_by_tid[v_fixed_index(tid, 65536)];')
	assert helper.contains('proc__Process* owner = target->process;')
	assert helper.contains('proc__has_capability(caller, proc__cap_sys_nice)')
	for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array__', 'free(', 'alloca('] {
		assert !helper.contains(token), suffix + ' permission lifetime: ' + token
	}
	assert digest(area + '/kernel-' + suffix + '/kernel/syscall/table/gaps.v') == digest(area + '/after-gaps.v')
	assert digest(area + '/kernel-' + suffix + '/kernel/proc/container.v') == digest(area + '/after-container.v')
}

fn scope(area string) {
	clean := area.trim_right('/')
	check_source(clean, '/Users/alex/code/vinix') or { panic(err) }
	for suffix in ['arm', 'x86'] { check_c(clean, suffix) or { panic(err) } }
	os.write_file(area + 'scope-check.log', 'arm/x86: complete generated C differs only in two affinity bodies/prototypes, scalar locked permission helper/prototype and CAP_SYS_NICE define; other code unchanged\n') or { panic(err) }
}

fn preparations(area string, out string, arch string, suffix string) !map[string]string {
	mut artifacts := map[string]string{}
	old_c := digest(area + 'states/preflight2-affabi-' + suffix + '/fixture.c')
	old_init := digest(area + 'states/preflight2-affabi-' + suffix + '/init')
	artifacts['preparation_width_c'] = old_c
	artifacts['preparation_width_init'] = old_init
	for phase in ['before', 'after'] {
		state := area + 'states/p1-' + phase + '-' + suffix
		value := object(state + '/receipt.json')!
		assert value['architecture']!.str() == arch
		rows := value['results']!.as_array()
		assert rows.len == if phase == 'before' { 1 } else { 8 }
		for index, row in rows {
			entry := row.as_map()
			code := entry['exit_code']!.int()
			assert code in [0, 1]
			if phase == 'before' {
				assert code == 1
			}
			if index == 0 {
				assert code == if phase == 'before' { 1 } else { 0 }
				assert entry['name']!.str() == 'affabi' && entry['init_sha256']!.str() == old_init
				assert entry['source_sha256']!.str() == digest(state + '/sources/affabifixture/core.v')
			}
		}
		if phase == 'after' {
			assert os.read_file(state + '.log')!.contains('No space left on device')
		}
		assert digest(state + '/affabi/fixture.c') == old_c && digest(state + '/affabi/init') == old_init
		for label, path in {
			'receipt':   state + '/receipt.json'
			'source':    state + '/sources/affabifixture/core.v'
			'native':    state + '/affabi/serial.log'
			'aggregate': state + '.log'
			'iso':       state + '/affabi/test.iso'
		} {
			artifacts['preparation_' + phase + '_' + label] = digest(path)
			if label in ['receipt', 'native', 'aggregate'] {
				publish(path, out + 'affabi-preparation-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
		}
	}
	state := area + 'states/p1-reference-' + suffix
	value := object(state + '/receipt.json')!
	assert value['architecture']!.str() == arch && value['passed']!.bool() == (arch == 'aarch64')
	bound := value['artifacts']!.as_map_of_strings()
	assert bound['probe'] == old_init && digest(state + '/probe') == old_init && bound['controller_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/affabi-reference.v')
	text := os.read_file(state + '/serial.log')!
	rows := text.split_into_lines().filter(it.starts_with('LINUX AFFABI CASES:'))
	assert rows.len == 8
	mut seen := map[string]bool{}
	for row in rows {
		fields := row.fields()
		assert fields.len == 7
		group := fields[3].all_after('=').int()
		kind := fields[4].all_after('=').int()
		assert group in [0, 1] && kind in [0, 1, 2, 3]
		key := fields[3] + fields[4]
		assert key !in seen
		seen[key] = true
		assert fields[5].all_after('=').int() == [6080, 12160, 6080, 388]![kind]
		assert fields[6].all_after('=').int() == if arch == 'aarch64' {
			0
		} else {
			[288, 576, 288, 0]![kind]
		}
	}
	if arch == 'aarch64' {
		assert text.contains('LINUX AFFABI REFERENCE: PASS')
	} else {
		assert text.contains('LINUX AFFABI FAIL:') && !text.contains('LINUX AFFABI REFERENCE: PASS') && text.contains('ret=16')
	}
	for label, path in {
		'receipt':   state + '/receipt.json'
		'native':    state + '/serial.log'
		'aggregate': state + '.log'
	} {
		artifacts['preparation_reference_' + label] = digest(path)
		publish(path, out + 'affabi-preparation-reference-' + arch + '-' + label + if label == 'receipt' {
			'.json'
		} else {
			'.log'
		})!
	}
	for label, path in {
		'kernel':           state + '/linux'
		'probe':            state + '/probe'
		'wrapper_source':   state + '/source/affabireferenceinit/core.v'
		'wrapper_c':        state + '/fixture.c'
		'wrapper_elf':      state + '/init'
		'initramfs':        state + '/initramfs.cpio'
		'serial':           state + '/serial.log'
		'serial_adapter_c': state + '/serial.c'
	} {
		assert bound[label] == digest(path)
		artifacts['preparation_reference_' + label] = digest(path)
	}
	return artifacts
}

fn main() {
	if '--negative-control' in os.args {
		assert false, 'affabi assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: affabi-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-14/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'affabi assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p2-reference-arm/serial.log', 'aarch64'], 'affabi baseline failure markers required'))!
	scope(area)
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == '16be6d0a204b509c75d456930af478de0232c36b'
	compiler_root := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/'
	compiler := compiler_root + 'compiler/v'
	mut pins := map[string]string{}
	for path, value in object(compiler_root + 'compiler-inputs.json')! { pins[path] = value.str() }
	assert pins.len == 15146
	assert pins['v'] == '9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b'
	for path, hash in pins {
		assert digest(compiler_root + 'compiler/' + path) == hash, path
	}
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.count('Linux dispatch coverage: PASS') == 4
	alloc_before := os.read_file(area + 'allocs-before.log')!
	alloc_after := os.read_file(area + 'allocs-after.log')!
	for position in ['132:9', '237:14'] {
		assert alloc_before.count('proc/container.v:' + position + ' struct on the heap') == 1
	}
	for position in ['133:9', '238:14'] {
		assert alloc_after.count('proc/container.v:' + position + ' struct on the heap') == 1
	}
	// The sole capability constant shifts two existing diagnostic positions.
	// check_source has already proved that every other container byte is unchanged.
	assert alloc_before == alloc_after.replace('proc/container.v:133:9 struct on the heap', 'proc/container.v:132:9 struct on the heap').replace('proc/container.v:238:14 struct on the heap', 'proc/container.v:237:14 struct on the heap')
	assert os.read_file(area + 'linux-source.sha256')!.trim_space() == digest(area + 'linux-sched-v6.12.c') + ' https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/sched/syscalls.c'
	assert os.read_file(area + 'watch-p2.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 18
	retained := object(area + 'watch-p2-retained-inputs.json')!
	assert retained.len >= 72
	for path, hash in retained {
		assert path.starts_with(states + 'p2-before-') || path.starts_with(states + 'p2-after-')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert digest(path) == hash.str(), path
	}
	for arch, count in {
		'aarch64': '398'
		'x86_64':  '290'
	} {
		for name in ['allocs-before.log', 'allocs-after.log'] {
			text := os.read_file(area + name)!
			assert text.split_into_lines().filter(it.starts_with(arch + ':')).len == 1 && text.contains(count + ' allocation sites (V exit 0)') && text.contains('NEW:')
		}
	}
	review := os.read_file(out + 'affabi-lifetime-review.md')!
	assert review.starts_with('Independent affabi lifetime review: PASS') && review.contains(digest(root + 'kernel/syscall/table/gaps.v')) && review.contains(digest(root + 'kernel/proc/container.v')) && review.contains(digest(root + 'tests/linux-compat/affabifixture/core.v'))
	for arch, suffix in {
		'aarch64': 'arm'
		'x86_64':  'x86'
	} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD',
			'--', 'kernel'])! == 'kernel/proc/container.v\nkernel/syscall/table/gaps.v'
		assert digest(tree + 'kernel/syscall/table/gaps.v') == digest(root + 'kernel/syscall/table/gaps.v')
		inputs := object(tree + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
		assert inputs.len == 64
		for path, hash in inputs {
			assert digest(tree + path) == hash, path
		}
		mut artifacts := {
			'compiler':                 digest(compiler)
			'compiler_inputs':          digest(compiler_root + 'compiler-inputs.json')
			'kernel_source':            digest(root + 'kernel/syscall/table/gaps.v')
			'kernel_source_before':     digest(area + 'before-gaps.v')
			'capability_source':        digest(root + 'kernel/proc/container.v')
			'capability_source_before': digest(area + 'before-container.v')
			'linux_primary_source':     digest(area + 'linux-sched-v6.12.c')
			'linux_primary_pin':        digest(area + 'linux-source.sha256')
			'fixture_source':           digest(root + 'tests/linux-compat/affabifixture/core.v')
			'audit_source':             digest(@FILE)
			'review':                   digest(out + 'affabi-lifetime-review.md')
			'native_controller':        digest(area + 'run')
			'native_controller_source': digest(root + 'tests/linux-compat/run.v')
			'reference_controller':     digest(area + 'reference')
			'watch_pins':               digest(area + 'watch-p2-retained-inputs.json')
			'watch_log':                digest(area + 'watch-p2.log')
			'preparation_retire_pins':  digest(area + 'preparation-retained-inputs.json')
			'preparation_retire_log':   digest(area + 'preparation-retire.log')
		}
		for key, hash in preparations(area, out, arch, suffix)! { artifacts[key] = hash }
		failed_preflight := states + 'preflight1-affabi-' + suffix
		assert !os.exists(failed_preflight + '/init')
		failed_c := os.read_file(failed_preflight + '/fixture.c')!
		assert failed_c.contains('sched_setaffinity(source, (size_t)(length), data + 8)') && failed_c.contains('sched_getaffinity(source, (size_t)(length), data + 8)')
		artifacts['preparation_c_pointer_types'] = digest(failed_preflight + '/fixture.c')
		mut identity := map[string]string{}
		for phase in ['before', 'after'] {
			state := states + 'p2-' + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['affabi']
			} else {
				['affabi', 'runtime', 'schedabi', 'rrabi', 'attrquery', 'attrimport', 'open', 'fcntlabi']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['affabi_source', 'affabi_init', 'affabi_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/affabi/serial.log')!
			semantics(text, phase, arch, false)
			storage(text, arch, phase)
			build := area + 'build-' + phase + '-' + suffix + '.log'
			text_build := os.read_file(build)!
			assert text_build.contains('-o bin/vinix') && !text_build.contains('Nothing to be done') && !text_build.contains('Error ')
			artifacts[phase + '_kernel'] = digest(kernel)
			artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
			for label, path in {
				'receipt':   state + '/receipt.json'
				'aggregate': state + '.log'
				'native':    state + '/affabi/serial.log'
				'build':     build
			} {
				publish(path, out + 'affabi-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
		}
		preflight := states + 'preflight3-affabi-' + suffix
		raw := os.read_file(preflight + '/fixture.c')!
		assert digest(preflight + '/fixture.c') == identity['affabi_c'] && digest(preflight + '/init') == identity['affabi_init'] && digest(area + 'preview-' + suffix + '.c') == identity['affabi_c']
		assert raw.count('alloca(') == 20
		for token in ['malloc(', 'memdup(', 'array_push(', 'array_get(', 'v_fixed_index('] {
			assert !raw.contains(token)
		}
		artifacts['preflight_c'] = digest(preflight + '/fixture.c')
		artifacts['preflight_init'] = digest(preflight + '/init')
		reference := states + 'p2-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['affabi_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'affabi-reference-' + arch + '-' + label + if label == 'receipt' {
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
		os.write_file(out + 'affabi-evidence-' + arch + '.json', json2.encode(Evidence{ architecture: arch, context: 'Native affinity import/query and stable-peer permission contract: 49416 root/UID1000 checks per architecture, eight target classes, 19 unsigned32 lengths, ten guarded input/output forms, upper PID/length words and real musl affinity wrappers. Short zero-extended masks, unsigned32 getter bit-count overflow, error ordering, live worker TIDs and UID1001 target with CAP_SYS_NICE off/on. Exact masks/guards, ignored inaccessible tails, restoration, original failure vectors and identical-ELF Linux 6.12.51 references. Twenty probe allocas; two flat warmed 200-cycle cohorts. Four production builds, exact complete C scope, eight-case profiles, compiler/source/C/ELF/reference pins, executing auditor negative controls and independent lifetime review. Large masks/CPU hotplug, ARM CPU1 QoS, credential/TID races, namespaces/pledge, GNU/foreign/ELF32 and broad roadmap gates remain separate', base_commit: base, artifacts: artifacts, source_inputs: inputs },
			prettify: true
		) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log',
		'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] {
		publish(area + name, out + 'affabi-' + name)!
	}
	publish(area + 'watch-p2.log', out + 'affabi-watch.log')!
	publish(area + 'preparation-retire.log', out + 'affabi-preparation-retire.log')!
	os.write_file(area + 'audit.log', 'Native affabi conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'affabi-audit.log')!
	println('Native affabi conformance audit: PASS')
}
