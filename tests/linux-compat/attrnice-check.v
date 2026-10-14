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
	rows_topology := log.split_into_lines().filter(it.starts_with('LINUX ATTRNICE TOPOLOGY:'))
	assert rows_topology.len == 2
	mut seen_topology := map[string]bool{}
	for row in rows_topology {
		fields := row.fields()
		assert fields.len == 8
		for index, prefix in {
			3: 'ordinary='
			4: 'uid='
			5: 'same='
			6: 'cross='
			7: 'page='
		} {
			assert fields[index].starts_with(prefix)
		}
		assert fields[3] in ['ordinary=0', 'ordinary=1'] && fields[3] !in seen_topology
		seen_topology[fields[3]] = true
		assert fields[4] == if fields[3] == 'ordinary=0' { 'uid=0' } else { 'uid=1000' }
		assert fields[5].all_after('=').int() > 0 && fields[6].all_after('=').int() > 0 && fields[5].all_after('=') != fields[6].all_after('=')
		assert fields[7].all_after('=').int() == if reference || arch == 'x86_64' {
			4096
		} else {
			16384
		}
	}
	mut cases := map[string]string{}
	for label in ['CASES:', 'FINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX ATTRNICE ' + label))
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
			assert n == [3456, 6912, 3456, 831]![kind]
			expected := if phase == 'after' {
				0
			} else if ordinary == 0 {
				[1056, 2112, 1056, 435]![kind]
			} else {
				[1080, 2160, 1080, 387]![kind]
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
		assert total == 29310
		if phase == 'after' {
			assert failures == 0
		} else {
			assert failures > 0
		}
	}
	assert !log.contains('Kernel panic') && !log.contains('LINUX ATTRNICE FAIL: setup')
	if phase == 'after' {
		assert !log.contains('LINUX ATTRNICE DETAIL:') && !log.contains('LINUX ATTRNICE FAIL:')
	} else {
		assert log.contains('LINUX ATTRNICE DETAIL:'), 'attrnice baseline failure markers required'
		assert log.contains('LINUX ATTRNICE FAIL:') && !log.contains('LINUX ATTRNICE: PASS')
	}
	if reference {
		assert phase == 'after' && log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX ATTRNICE REFERENCE: PASS') && !log.contains('LINUX ATTRNICE STORAGE:')
	} else if phase == 'after' {
		assert log.count('LINUX ATTRNICE: PASS') == 1
	}
}

fn storage(log string, arch string, phase string) {
	mut slabs := [2]int{}
	mut pages := [2]int{}
	mut seen := map[string]bool{}
	for row in log.split_into_lines().filter(it.starts_with('LINUX ATTRNICE SLAB:') || it.starts_with('LINUX ATTRNICE STORAGE:')) {
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
			assert pair[0].u64() == if arch == 'aarch64' { u64(85) } else { u64(216) }
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
	assert log.contains('LINUX ATTRNICE DETAIL:'), 'attrnice baseline failure markers required'
	semantics(log, 'before', arch, false)
}

fn receipt(state string, arch string, kernel string, names []string, failing bool, aggregate bool, build_failure bool) !map[string]string {
	value := object(state + '/receipt.json')!
	assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel && digest(state + '/kernel/bin/vinix') == kernel
	rows := value['results']!.as_array()
	assert rows.len == names.len
	mut artifacts := {
		'receipt': digest(state + '/receipt.json')
	}
	assert os.exists(state + '.log') == aggregate
	if aggregate { artifacts['aggregate'] = digest(state + '.log') }
	for index, row in rows {
		entry := row.as_map()
		name := entry['name']!.str()
		if build_failure && index == names.len - 1 {
			assert arch == 'x86_64' && name == 'fcntlabi' && names[index] == name
			assert entry['exit_code']!.int() == 1 && entry['detail']!.str() == 'Command failed' && entry['iso_sha256']!.str() == ''
			assert !os.exists(state + '/' + name + '/test.iso') && !os.exists(state + '/' + name + '/serial.log')
			for label, path in {
				'source': state + '/sources/' + name + 'fixture/core.v'
				'init':   state + '/' + name + '/init'
				'c':      state + '/' + name + '/fixture.c'
			} {
				artifacts[name + '_' + label] = digest(path)
			}
			assert artifacts[name + '_source'] == entry['source_sha256']!.str() && artifacts[name + '_init'] == entry['init_sha256']!.str()
			assert artifacts[name + '_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/' + name + 'fixture/core.v')
			assert os.read_file(state + '.log')!.contains('No space left on device')
			continue
		}
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
		'wrapper_source':    state + '/source/attrnicereferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/attrnice-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/attrnicereferenceinit/core.v')
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
	old_set := definition(before, 'fn syscall_linux_sched_setattr(_ voidptr, raw_pid int, attr_ptr u64, flags u32)')
	new_set := definition(after, 'fn syscall_linux_sched_setattr(_ voidptr, raw_pid int, attr_ptr u64, flags u32)')
	old_may := definition(before, 'fn may_set_sched_params(target_tid int, policy int, priority int)')
	new_may := definition(after, 'fn may_set_sched_params(target_tid int, policy int, priority int)')
	helper := definition(after, 'fn sched_nice_permission(tid int, wanted int) u64')
	comment := "// The target's nice limit authorizes fair-class priority increases. Keep\n// borrowed task/process pointers under the PID-table lock and return errno.\n"
	old_rest := before.replace(old_set, '').replace(old_may, '').replace('// May the caller give this thread that priority? Root may do anything;', '// May the caller give this thread that priority? CAP_SYS_NICE grants it;')
	new_rest := after.replace(new_set, '').replace(new_may, '').replace(comment + helper + '\n\n', '')
	scope_matches := old_rest == new_rest
	assert scope_matches, 'Source exceeds nice helper, scheduler permission and attribute setter'
	permission_matches := old_may.replace('if caller.euid == 0 { return true }', 'if proc.has_capability(caller, proc.cap_sys_nice) { return true }') == new_may
	assert permission_matches, 'Existing scheduler permission body exceeds effective capability check'
	assert digest(root + '/kernel/syscall/table/gaps.v') == digest(area + '/after-gaps.v')
	before_proc := os.read_file(area + '/before-proc.v')!
	after_proc := os.read_file(area + '/after-proc.v')!
	old_limits := definition(before_proc, 'pub fn default_rlimits() [rlimit_nlimits]RLimit')
	new_limits := definition(after_proc, 'pub fn default_rlimits() [rlimit_nlimits]RLimit')
	proc_scope := before_proc.replace(old_limits, '') == after_proc.replace(new_limits, '')
	assert proc_scope, 'Process source exceeds default limit initializer'
	assert new_limits.contains('limits[rlimit_nice] = RLimit{}')
	normalized_limits := new_limits.replace('\t// Nice increases require explicit resource admission or CAP_SYS_NICE.\n\tlimits[rlimit_nice] = RLimit{}\n', '').replace('CAP_SYS_NICE authorizes privileged callers (may_set_sched_params).', 'Root is not asked (may_set_sched_params).')
	assert normalized_limits == old_limits
	assert digest(root + '/kernel/proc/proc.v') == digest(area + '/after-proc.v')
	assert helper.contains('proc.lock_table()\n\tdefer { proc.unlock_table() }')
	assert helper.contains('target == unsafe { nil } || target.process == unsafe { nil }')
	assert helper.contains('proc.has_capability(caller, proc.cap_sys_nice)')
	assert helper.contains('proc.limit_allows(owner, proc.rlimit_nice, u64(20 - wanted))')
	assert new_set.contains('if attr.sched_nice < -20 { attr.sched_nice = -20 }') && new_set.contains('if attr.sched_nice > 19 { attr.sched_nice = 19 }')
	import_position := new_set.index('copy_from_user(voidptr(&attr)') or { panic('missing attribute import') }
	clamp := new_set.index('if attr.sched_nice < -20') or { panic('missing clamp') }
	permission := new_set.index('nice_error := sched_nice_permission') or { panic('missing permission') }
	mutation := new_set.index('proc.set_thread_sched_params_with_util') or { panic('missing mutation') }
	assert import_position < clamp && clamp < permission && permission < mutation
	assert new_set.count('if policy == proc.sched_other || policy == proc.sched_batch {') == 2
}

fn check_c(area string, suffix string) ! {
	before := os.read_file(area + '/before-' + suffix + '.c')!
	after := os.read_file(area + '/after-' + suffix + '.c')!
	mut old_rest := before
	mut new_rest := after
	for marker in [
		'\nmulti_return_u64_u64 table__syscall_linux_sched_setattr(void* _0, i64 raw_pid, u64 attr_ptr, u32 flags) {',
		'\nbool table__may_set_sched_params(i64 target_tid, i64 policy, i64 priority) {',
		'\n_v_ret_Array_fixed_proc__RLimit_16 proc__default_rlimits(void) {',
	] {
		old := definition(before, marker)
		new := definition(after, marker)
		old_rest = old_rest.replace(old, '')
		new_rest = new_rest.replace(new, '')
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array__', 'free(', 'alloca('] {
			assert !new.contains(token), suffix + ' changed body: ' + token
		}
	}
	helper := definition(after, '\nu64 table__sched_nice_permission(i64 tid, i64 wanted) {')
	assert after.count('u64 table__sched_nice_permission(i64 tid, i64 wanted);\n') == 1
	new_rest = new_rest.replace(helper + '\n', '').replace('u64 table__sched_nice_permission(i64 tid, i64 wanted);\n', '')
	stem := if suffix == 'arm' { '__discard_174_' } else { '__discard_179_' }
	old_name := stem + '21692_21693'
	new_name := stem + '21821_21822'
	assert old_rest.count(old_name) == 3 && old_rest.count(new_name) == 0 && new_rest.count(new_name) == 3 && new_rest.count(old_name) == 0
	old_loop := definition(before, '\n__v_option_i64 proc__find_free_id(void) {')
	new_loop := definition(after, '\n__v_option_i64 proc__find_free_id(void) {')
	loop_matches := old_loop == new_loop.replace(new_name, old_name)
	assert loop_matches
	new_rest = new_rest.replace(new_name, old_name)
	c_scope := old_rest == new_rest
	assert c_scope, suffix + ' whole C differs outside nice/default-limit/permission bodies, new helper prototype and exact3-token loop temporary rename'
	assert helper.count('proc__lock_table();') == 1 && helper.count('proc__unlock_table();') == 6
	assert helper.contains('proc__Thread* target = proc__threads_by_tid[v_fixed_index(tid, 65536)];')
	assert helper.contains('proc__Process* owner = target->process;')
	assert helper.contains('proc__limit_allows(owner, proc__rlimit_nice, (u64)(20 - wanted))')
	for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array__', 'free(', 'alloca('] {
		assert !helper.contains(token), suffix + ' scalar nice helper: ' + token
	}
	assert digest(area + '/kernel-' + suffix + '/kernel/syscall/table/gaps.v') == digest(area + '/after-gaps.v')
	assert digest(area + '/kernel-' + suffix + '/kernel/proc/proc.v') == digest(area + '/after-proc.v')
}

fn scope(area string) {
	clean := area.trim_right('/')
	check_source(clean, '/Users/alex/code/vinix') or { panic(err) }
	for suffix in ['arm', 'x86'] { check_c(clean, suffix) or { panic(err) } }
	os.write_file(area + 'scope-check.log', 'arm/x86: complete generated C differs only in sched_setattr, may_set_sched_params, default_rlimits, scalar locked nice helper/prototype and exactly three existing proc loop identifier uses per architecture; other code unchanged\n') or { panic(err) }
}

fn main() {
	if '--negative-control' in os.args {
		assert false, 'attrnice assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: attrnice-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-14/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'attrnice assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p1-reference-arm/serial.log', 'aarch64'], 'attrnice baseline failure markers required'))!
	scope(area)
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == '4fd5c605d87b05208b73cf725ba93b59699b4f1c'
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
	mut normalized_alloc := alloc_after
	for old_position, new_position in {
		'1117:9':  '1119:9'
		'1239:21': '1241:21'
		'1244:21': '1246:21'
		'1259:6':  '1261:6'
	} {
		old_marker := 'proc/proc.v:' + old_position + ' '
		new_marker := 'proc/proc.v:' + new_position + ' '
		assert alloc_before.count(old_marker) == 1 && alloc_after.count(new_marker) == 1
		normalized_alloc = normalized_alloc.replace(new_marker, old_marker)
	}
	// Exact source scope already proves the only two added lines precede these sites.
	assert alloc_before == normalized_alloc
	assert os.read_file(area + 'linux-source.sha256')!.trim_space() == digest(area + 'linux-sched-v6.12.c') + ' https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/sched/syscalls.c'
	assert os.read_file(area + 'watch-final.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 18
	retained := object(area + 'watch-final-retained-inputs.json')!
	assert retained.len >= 72
	for path, hash in retained {
		assert path.starts_with(states + 'p1-before-') || path.starts_with(states + 'p1-after-') || path.starts_with(states + 'p3-after-') || path.starts_with(states + 'p4-after-x86/')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert digest(path) == hash.str(), path
	}
	interrupted := object(area + 'preparation-retained-inputs.json')!
	assert interrupted.len == 117
	for path, hash in interrupted {
		assert path.starts_with(states + 'p1-after-') || path.starts_with(area + 'watch')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert digest(path) == hash.str(), path
	}
	assert os.read_file(area + 'watch.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 11
	assert os.read_file(area + 'preparation-retire.log')!.contains('five passing cases each and no aggregate')
	stopped := object(area + 'p2-retained-inputs.json')!
	assert stopped.len == 30
	for path, hash in stopped {
		assert path.starts_with(states + 'p2-after-') || path.starts_with(area + 'p2-interrupted-watch-final')
		assert os.inode(path).typ == .regular && digest(path) == hash.str(), path
	}
	for suffix in ['arm', 'x86'] {
		assert !os.exists(states + 'p2-after-' + suffix + '/receipt.json') && !os.exists(states + 'p2-after-' + suffix + '.log')
	}
	assert os.read_file(area + 'p2-interruption.log')!.contains('no completed case receipt or aggregate')
	retry := object(area + 'p3-retained-inputs.json')!
	assert retry.len == 67
	for path, hash in retry {
		assert path.starts_with(states + 'p3-after-') || path.starts_with(area + 'p3-interrupted-')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd') && digest(path) == hash.str(), path
	}
	assert os.read_file(area + 'p3-interrupted-watch-final.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 16
	assert os.read_file(area + 'p3-retire.log')!.contains('No space left on device')
	for arch, count in {
		'aarch64': '398'
		'x86_64':  '290'
	} {
		for name in ['allocs-before.log', 'allocs-after.log'] {
			text := os.read_file(area + name)!
			assert text.split_into_lines().filter(it.starts_with(arch + ':')).len == 1 && text.contains(count + ' allocation sites (V exit 0)') && text.contains('NEW:')
		}
	}
	review := os.read_file(out + 'attrnice-lifetime-review.md')!
	assert review.starts_with('Independent attrnice lifetime review: PASS') && review.contains(digest(root + 'kernel/syscall/table/gaps.v')) && review.contains(digest(root + 'kernel/proc/proc.v')) && review.contains(digest(root + 'tests/linux-compat/attrnicefixture/core.v'))
	for arch, suffix in {
		'aarch64': 'arm'
		'x86_64':  'x86'
	} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD',
			'--', 'kernel'])! == 'kernel/proc/proc.v\nkernel/syscall/table/gaps.v'
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
			'default_limit_source':     digest(root + 'kernel/proc/proc.v')
			'default_limit_before':     digest(area + 'before-proc.v')
			'linux_primary_source':     digest(area + 'linux-sched-v6.12.c')
			'linux_primary_pin':        digest(area + 'linux-source.sha256')
			'fixture_source':           digest(root + 'tests/linux-compat/attrnicefixture/core.v')
			'audit_source':             digest(@FILE)
			'review':                   digest(out + 'attrnice-lifetime-review.md')
			'native_controller':        digest(area + 'run')
			'native_controller_source': digest(root + 'tests/linux-compat/run.v')
			'reference_controller':     digest(area + 'reference')
			'watch_pins':               digest(area + 'watch-final-retained-inputs.json')
			'watch_log':                digest(area + 'watch-final.log')
			'interrupted_watch_log':    digest(area + 'watch.log')
			'interrupted_pins':         digest(area + 'preparation-retained-inputs.json')
			'interrupted_retire_log':   digest(area + 'preparation-retire.log')
			'stopped_preparation_pins': digest(area + 'p2-retained-inputs.json')
			'stopped_preparation_log':  digest(area + 'p2-interruption.log')
			'retry_retained_pins':      digest(area + 'p3-retained-inputs.json')
			'retry_retire_log':         digest(area + 'p3-retire.log')
		}
		mut identity := map[string]string{}
		for phase in ['before', 'after'] {
			state := states + 'p1-' + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['attrnice']
			} else {
				['attrnice', 'runtime', 'schedabi', 'rrabi', 'attrquery']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before', phase == 'before', false)!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['attrnice_source', 'attrnice_init', 'attrnice_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/attrnice/serial.log')!
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
				'native':    state + '/attrnice/serial.log'
				'build':     build
			} {
				if label == 'aggregate' && phase == 'after' { continue }
				publish(path, out + 'attrnice-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
		}
		completion := states + 'p3-after-' + suffix
		completed := receipt(completion, arch, digest(area + 'kernel-' + suffix + '/kernel/bin/vinix'), [
			'attrimport',
			'affabi',
			'fcntlabi',
		], false, true, arch == 'x86_64')!
		for key, value in completed { artifacts['completion_' + key] = value }
		publish(completion + '/receipt.json', out + 'attrnice-completion-' + arch + '-receipt.json')!
		publish(completion + '.log', out + 'attrnice-completion-' + arch + '-aggregate.log')!
		for name in ['attrimport', 'affabi', 'fcntlabi'] {
			if arch == 'x86_64' && name == 'fcntlabi' { continue }
			publish(completion + '/' + name + '/serial.log', out + 'attrnice-completion-' + arch + '-' + name + '-serial.log')!
		}
		if arch == 'x86_64' {
			recovery := states + 'p4-after-x86'
			recovered := receipt(recovery, arch, digest(area + 'kernel-x86/kernel/bin/vinix'), ['fcntlabi'], false, true, false)!
			for key in ['fcntlabi_source', 'fcntlabi_init', 'fcntlabi_c'] {
				assert recovered[key] == completed[key]
			}
			for key, value in recovered { artifacts['recovery_' + key] = value }
			for label, path in {
				'receipt':   recovery + '/receipt.json'
				'aggregate': recovery + '.log'
				'serial':    recovery + '/fcntlabi/serial.log'
			} {
				publish(path, out + 'attrnice-recovery-x86_64-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
		}
		preflight := states + 'preflight1-attrnice-' + suffix
		raw := os.read_file(preflight + '/fixture.c')!
		assert digest(preflight + '/fixture.c') == identity['attrnice_c'] && digest(preflight + '/init') == identity['attrnice_init'] && digest(area + 'preview-' + suffix + '.c') == identity['attrnice_c']
		assert raw.count('alloca(') == 25
		for token in ['malloc(', 'memdup(', 'array_push(', 'array_get(', 'v_fixed_index('] {
			assert !raw.contains(token)
		}
		artifacts['preflight_c'] = digest(preflight + '/fixture.c')
		artifacts['preflight_init'] = digest(preflight + '/init')
		reference := states + 'p1-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['attrnice_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'attrnice-reference-' + arch + '-' + label + if label == 'receipt' {
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
		os.write_file(out + 'attrnice-evidence-' + arch + '.json', json2.encode(Evidence{ architecture: arch, context: 'Native single-thread process-leader sched_attr nice contract: 29310 root/UID1000 checks per architecture; signed32 normalization, target RLIMIT_NICE, effective CAP_SYS_NICE independently of UID0, fair-class state application and nonfair nice preservation. Six target classes, guarded read-only/unaligned/inaccessible inputs, upper PID/flag words, layouts and real musl getpriority observations; privileged synchronous broker restores peer state. Separate original cohort failure vectors, identical-ELF Linux 6.12.51 references, 25 probe allocas and two warmed 200-cycle storage cohorts. Four production builds, exact complete C scope with only three uses of one compiler loop identifier per architecture renamed, eight cases with identical corrected kernels: ARM five primary plus three completion passes; x86 five primary plus two completion and one recovery pass, retaining the explicit p3 fcntlabi ENOSPC build failure with absent ISO/serial and matching recovery source/C/ELF. Missing initial aggregates, 117 interrupted files, 30 stopped-retry regular files and 67 p3 retained files remain explicit, executing audit negatives and independent lifetime review. Native nice remains process-wide; worker-thread nice, target/credential/limit races, complete realtime/deadline/reset/clamp behavior, GNU/foreign/ELF32 and broad roadmap gates remain open', base_commit: base, artifacts: artifacts, source_inputs: inputs },
			prettify: true
		) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log',
		'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] {
		publish(area + name, out + 'attrnice-' + name)!
	}
	publish(area + 'watch-final.log', out + 'attrnice-watch.log')!
	publish(area + 'watch.log', out + 'attrnice-interrupted-watch.log')!
	publish(area + 'preparation-retire.log', out + 'attrnice-preparation-retire.log')!
	publish(area + 'p2-interruption.log', out + 'attrnice-p2-interruption.log')!
	publish(area + 'p3-retire.log', out + 'attrnice-p3-retire.log')!
	publish(area + 'p3-interrupted-watch-final.log', out + 'attrnice-p3-interrupted-watch.log')!
	os.write_file(area + 'audit.log', 'Native attrnice conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'attrnice-audit.log')!
	println('Native attrnice conformance audit: PASS')
}
