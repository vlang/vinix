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
	rows_topology := log.split_into_lines().filter(it.starts_with('LINUX NICEADMIT TOPOLOGY:'))
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
		rows := log.split_into_lines().filter(it.starts_with('LINUX NICEADMIT ' + label))
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
			assert n == [6480, 6480, 6480, 658]![kind]
			expected := if phase == 'after' {
				0
			} else if ordinary == 0 {
				[1377, 1377, 1377, 0]![kind]
			} else {
				[2187, 2187, 2187, 0]![kind]
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
		assert total == 40196
		if phase == 'after' {
			assert failures == 0
		} else {
			assert failures > 0
		}
	}
	assert !log.contains('Kernel panic') && !log.contains('LINUX NICEADMIT FAIL: setup')
	if phase == 'after' {
		assert !log.contains('LINUX NICEADMIT DETAIL:') && !log.contains('LINUX NICEADMIT FAIL:')
	} else {
		assert log.contains('LINUX NICEADMIT DETAIL:'), 'niceadmit baseline failure markers required'
		assert log.contains('LINUX NICEADMIT FAIL:') && !log.contains('LINUX NICEADMIT: PASS')
	}
	if reference {
		assert phase == 'after' && log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX NICEADMIT REFERENCE: PASS') && !log.contains('LINUX NICEADMIT STORAGE:')
	} else if phase == 'after' {
		assert log.count('LINUX NICEADMIT: PASS') == 1
	}
}

fn storage(log string, arch string, phase string) {
	mut slabs := [2]int{}
	mut pages := [2]int{}
	mut seen := map[string]bool{}
	for row in log.split_into_lines().filter(it.starts_with('LINUX NICEADMIT SLAB:') || it.starts_with('LINUX NICEADMIT STORAGE:')) {
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
	assert log.contains('LINUX NICEADMIT DETAIL:'), 'niceadmit baseline failure markers required'
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
		'wrapper_source':    state + '/source/niceadmitreferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/niceadmit-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/niceadmitreferenceinit/core.v')
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
	marker := 'fn syscall_linux_setpriority(_ voidptr, raw_which int, raw_local_who int, raw_prio int)'
	old := definition(before, marker)
	new := definition(after, marker)
	unchanged := before.replace(old, '') == after.replace(new, '')
	assert unchanged, 'Only setpriority definition may change'
	old_owner := '\tif caller.euid != 0 && caller.euid != target.euid && caller.euid != target.uid {'
	new_owner := '\tprivileged := proc.has_capability(caller, proc.cap_sys_nice)\n\tif !privileged && caller.euid != target.euid && caller.euid != target.uid {'
	old_nice := '\tif wanted < target.nice && caller.euid != 0 {'
	new_nice := '\tif wanted < target.nice && !privileged\n\t\t&& !proc.limit_allows(target, proc.rlimit_nice, u64(20 - wanted)) {'
	assert old.count(old_owner) == 1 && old.count(old_nice) == 1
	exact := old.replace(old_owner, new_owner).replace(old_nice, new_nice) == new
	assert exact, 'Only exact capability/target-limit scalar admission may change'
	assert new.count('proc.lock_table()') == 1 && new.count('proc.unlock_table()') == 1
	assert new.contains('defer { proc.unlock_table() }') && new.contains('proc.mac_peer_allowed(caller, target)') && new.contains('target.nice = wanted')
	assert digest(root + 'kernel/syscall/table/linux_common.v') == digest(area + 'after-linux_common.v')
}

fn check_c(area string, suffix string) ! {
	before := os.read_file(area + 'before-' + suffix + '.c')!
	after := os.read_file(area + 'after-' + suffix + '.c')!
	marker := '\nmulti_return_u64_u64 table__syscall_linux_setpriority(void* _0, i64 raw_which, i64 raw_local_who, i64 raw_prio) {'
	old := definition(before, marker)
	new := definition(after, marker)
	unchanged := before.replace(old, '') == after.replace(new, '')
	assert unchanged, 'Whole production C differs outside setpriority'
	assert old.count('proc__lock_table();') == 1 && new.count('proc__lock_table();') == 1
	assert old.count('proc__unlock_table();') == new.count('proc__unlock_table();')
	assert new.contains('bool privileged = proc__has_capability(caller, proc__cap_sys_nice);')
	assert new.contains('!proc__limit_allows(target, proc__rlimit_nice, (u64)(20 - wanted))')
	assert new.contains('proc__mac_peer_allowed(caller, target)') && new.contains('target->nice = wanted;')
	for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array__', 'free(', 'alloca('] {
		assert !new.contains(token), suffix + token
	}
	assert digest(area + 'kernel-' + suffix + '/kernel/syscall/table/linux_common.v') == digest(area + 'after-linux_common.v')
}

fn main() {
	if '--negative-control' in os.args {
		assert false, 'niceadmit assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: niceadmit-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-15/'
	os.mkdir_all(out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'niceadmit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p1-reference-arm/serial.log', 'aarch64'], 'niceadmit baseline failure markers required'))!
	check_source(area, root)!
	for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
	os.write_file(area + 'scope-check.log', 'arm/x86: whole generated production C differs only in table__syscall_linux_setpriority; no compiler identifier normalization, allocation/free or pointer escape; existing locked target lookup, MAC check, error returns and nice mutation retained\n')!
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == '9969135689c8ca354631d3ce46257d20b1bd3b20'
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
	first_preflight := os.read_file(area + 'preflight1-arm.log')!
	assert first_preflight.contains('failed to create C build directory') && first_preflight.contains('No space left on device')
	assert os.read_file(area + 'preflight1-helper.log')!.contains(first_preflight.trim_space())
	assert !os.exists(states + 'preflight1-niceadmit-arm/fixture.c') && !os.exists(states + 'preflight1-niceadmit-arm/init')
	assert !os.exists(states + 'preflight1-niceadmit-x86')
	assert os.read_file(area + 'helper-preflight-jobs.log')!.trim_space() == 'arm fixture C heap-free preflight: PASS; explicit allocas=5\nx86 fixture C heap-free preflight: PASS; explicit allocas=5'
	assert os.read_file(area + 'initial-build-before-arm-detached.log')! == ''
	assert digest(area + 'initial-before-arm.c') == digest(area + 'before-arm.c')
	assert digest(area + 'initial-before-arm.elf') == 'f78c4fae503fe2b9035f8331dbb24af8e982eba023e8acf42452ec7cd378b8a4'
	assert digest(area + 'initial-before-arm.elf') != digest(area + 'baseline-arm/kernel/bin/vinix')
	initial_attribution := os.read_file(area + 'initial-arm-attribution.log')!
	assert initial_attribution.contains('initial-before-arm.c bytes=10842748 sha256=' + digest(area + 'before-arm.c'))
	assert initial_attribution.contains('initial-before-arm.elf bytes=17776640 sha256=' + digest(area + 'initial-before-arm.elf'))
	assert initial_attribution.contains('baseline-arm/kernel/bin/vinix bytes=33207632 sha256=' + digest(area + 'baseline-arm/kernel/bin/vinix'))
	assert initial_attribution.contains('common_prefix_bytes=24 equal=false initial_is_complete_prefix=false')
	initial_boundary := os.read_file(area + 'independent-initial.log')!
	assert initial_boundary.contains(digest(area + 'initial-before-arm.elf')) && initial_boundary.contains(digest(area + 'baseline-arm/kernel/bin/vinix'))
	assert initial_boundary.contains('initial-before-arm.elf bytes=17776640 machine=183 entry=ffffffff8013d624 phoff=64 phnum=3 shoff=33206288 shnum=21 header_tables_complete=false')
	assert initial_boundary.contains('program 2 type=1 offset=3244032 filesz=16244552 memsz=16244552 complete=false')
	assert initial_boundary.contains('vinix bytes=33207632 machine=183 entry=ffffffff801c696c phoff=64 phnum=3 shoff=33206288 shnum=21 header_tables_complete=true')
	assert initial_boundary.contains('all segment payloads complete=true all non-NOBITS sections complete=true')
	initial_incomplete := os.read_file(area + 'independent-initial-incomplete.log')!
	assert initial_incomplete.contains('header_tables_complete=false') && initial_incomplete.contains('FAIL: fn main.elf: assert table_complete')
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
	assert os.read_file(area + 'linux-sched-source.sha256')!.trim_space() == digest(area + 'linux-sched-v6.12.c') + ' https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/sched/syscalls.c'
	linux_sys := os.read_file(area + 'linux-sys-v6.12.c')!
	assert linux_sys.contains('ns_capable(pcred->user_ns, CAP_SYS_NICE)') && linux_sys.contains('niceval < task_nice(p) && !can_nice(p, niceval)') && linux_sys.contains('error = -EACCES;')
	linux_sched := os.read_file(area + 'linux-sched-v6.12.c')!
	assert linux_sched.contains('nice_rlim <= task_rlimit(p, RLIMIT_NICE)') && linux_sched.contains('is_nice_reduction(p, nice) || capable(CAP_SYS_NICE)')
	assert os.read_file(area + 'watch.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 10
	retained := object(area + 'watch-retained-inputs.json')!
	assert retained.len == 90
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
				['niceadmit']
			} else {
				['niceadmit', 'runtime', 'niceabi', 'attrnice']
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
	assert walked.len == retained.len && completed.len == 10
	for row in os.read_file(area + 'watch.log')!.split_into_lines() {
		assert row in completed
		completed.delete(row)
	}
	assert completed.len == 0
	review_path := out + 'niceadmit-lifetime-review.md'
	review := os.read_file(review_path)!
	assert review.starts_with('Independent niceadmit lifetime review: PASS') && review.contains(digest(root + 'kernel/syscall/table/linux_common.v')) && review.contains(digest(root + 'tests/linux-compat/niceadmitfixture/core.v'))
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
			'compiler':                   digest(compiler_root + 'compiler/v')
			'compiler_inputs':            digest(compiler_root + 'compiler-inputs.json')
			'kernel_source':              digest(root + 'kernel/syscall/table/linux_common.v')
			'kernel_source_before':       digest(area + 'before-linux_common.v')
			'fixture_source':             digest(root + 'tests/linux-compat/niceadmitfixture/core.v')
			'audit_source':               digest(@FILE)
			'review':                     digest(review_path)
			'linux_primary_source':       digest(area + 'linux-sys-v6.12.c')
			'linux_sched_primary_source': digest(area + 'linux-sched-v6.12.c')
			'linux_sched_primary_pin':    digest(area + 'linux-sched-source.sha256')
			'linux_primary_pin':          digest(area + 'linux-source.sha256')
			'native_controller':          digest(area + 'run')
			'native_controller_source':   digest(root + 'tests/linux-compat/run.v')
			'reference_controller':       digest(area + 'reference')
			'watch_pins':                 digest(area + 'watch-retained-inputs.json')
			'watch_log':                  digest(area + 'watch.log')
		}
		for name in ['preflight1-arm.log', 'preflight1-helper.log', 'preflight-detached.log',
			'initial-preflight.v', 'initial-preflight-jobs.v', 'preflight.v', 'preflight-jobs.v',
			'preflight2-arm.log', 'preflight2-x86.log', 'helper-preflight-jobs.log',
			'initial-build-before-arm-detached.log', 'initial-build-before-arm.log',
			'initial-before-arm.c', 'initial-before-arm.elf', 'initial-artifacts.v',
			'initial-arm-attribution.log', 'independent-initial.log', 'independent-initial.v',
			'independent-initial-incomplete.log', 'independent-initial-incomplete.v',
			'coverage-before-check.log', 'coverage-before-arm.json', 'coverage-before-x86.json',
			'watch.v', 'watch', 'manage.v', 'manage', 'resume.v', 'resume', 'linux-sys-v6.12.c',
			'linux-sched-v6.12.c'] {
			artifacts[name] = digest(area + name)
		}
		mut identity := map[string]string{}
		for phase in ['before', 'after'] {
			state := states + 'p1-' + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['niceadmit']
			} else {
				['niceadmit', 'runtime', 'niceabi', 'attrnice']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['niceadmit_source', 'niceadmit_init', 'niceadmit_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/niceadmit/serial.log')!
			semantics(text, phase, arch, false)
			storage(text, arch, phase)
			build := area + 'build-' + phase + '-' + suffix + '.log'
			text_build := os.read_file(build)!
			assert text_build.contains('-o bin/vinix') && !text_build.contains('Nothing to be done') && !text_build.contains('Error ')
			producer := area + if phase == 'before' && suffix == 'x86' {
				'build-before-x86-detached.log'
			} else {
				'fresh-build-' + phase + '-' + suffix + '.log'
			}
			assert os.read_file(producer)!.trim_space() == suffix + ' ' + phase + ' production build: PASS'
			artifacts[phase + '_build_producer'] = digest(producer)
			artifacts[phase + '_kernel'] = digest(kernel)
			artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
			artifacts[phase + '_build'] = digest(build)
			for label, path in {
				'receipt':   state + '/receipt.json'
				'aggregate': state + '.log'
				'native':    state + '/niceadmit/serial.log'
				'build':     build
			} {
				publish(path, out + 'niceadmit-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			if phase == 'after' {
				for name in names {
					if name == 'niceadmit' { continue }
					publish(state + '/' + name + '/serial.log', out + 'niceadmit-regression-' + arch + '-' + name + '.log')!
				}
			}
		}
		preflight := states + 'preflight2-niceadmit-' + suffix
		raw := os.read_file(preflight + '/fixture.c')!
		assert digest(preflight + '/fixture.c') == identity['niceadmit_c'] && digest(preflight + '/init') == identity['niceadmit_init']
		assert raw.count('alloca(') == 5
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array_push(', 'array_get(',
			'v_fixed_index('] {
			assert !raw.contains(token)
		}
		artifacts['preflight_c'] = digest(preflight + '/fixture.c')
		artifacts['preflight_init'] = digest(preflight + '/init')
		reference := states + 'p1-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['niceadmit_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'niceadmit-reference-' + arch + '-' + label + if label == 'receipt' {
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
		os.write_file(out + 'niceadmit-evidence-' + arch + '.json', json2.encode(Evidence{
			architecture:  arch
			context:       'Native stable process-leader setpriority capability/target RLIMIT_NICE admission: 40196 root/UID1000 controls per architecture. Both effective CAP_SYS_NICE states, OTHER/BATCH/IDLE, PID0/explicit self/same-owner/cross-owner peers, current nice -20/-1/0/1/19, nine requested/clamped boundaries and target soft limits 0/1/20/21/40/infinity, hard infinity. Canonical raw, simultaneous upper words and real musl calls; independently observed target limits, opposite caller limits, policies/priority/raw+musl nice and exact capset restoration. Root without capability is constrained; non-root effective capability permits lowering/cross-owner updates; errors preserve state. 10692 original failures; corrected and identical-ELF Linux6.12.51 zero. Five explicit allocas and two flat warmed200-cycle cohorts. Four fresh production builds differ only in existing setpriority scalar admission; four native cases per architecture, retained allocation diagnostics, compiler/inventory pins, executing audit negatives and independent lifetime review. Disposable PR_SET_KEEPCAPS and raised hard limit are setup state, not full process restoration. Process-group/user selectors, worker-thread nice, namespace/credential/limit races, GNU/foreign/ELF32 and broad roadmap gates remain unqualified.'
			base_commit:   base
			artifacts:     artifacts
			source_inputs: inputs
		}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log',
		'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'watch.log',
		'preflight1-arm.log', 'preflight1-helper.log', 'helper-preflight-jobs.log',
		'initial-build-before-arm-detached.log', 'initial-arm-attribution.log',
		'independent-initial.log', 'independent-initial-incomplete.log', 'coverage-before-check.log'] {
		publish(area + name, out + 'niceadmit-' + name)!
	}
	publish(area + 'watch-retained-inputs.json', out + 'niceadmit-watch-retained-inputs.json')!
	os.write_file(area + 'audit.log', 'Native niceadmit conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'niceadmit-audit.log')!
	println('Native niceadmit conformance audit: PASS')
}
