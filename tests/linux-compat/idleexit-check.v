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
	rows_topology := log.split_into_lines().filter(it.starts_with('LINUX IDLEEXIT TOPOLOGY:'))
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
		rows := log.split_into_lines().filter(it.starts_with('LINUX IDLEEXIT ' + label))
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
			assert n == [3780, 896, 3584, 4244]![kind]
			expected := if phase == 'after' {
				0
			} else if ordinary == 0 {
				[76, 32, 64, 144]![kind]
			} else {
				[76, 32, 64, 144]![kind]
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
		assert total == 25008
		if phase == 'after' {
			assert failures == 0
		} else {
			assert failures > 0
		}
	}
	assert !log.contains('Kernel panic') && !log.contains('LINUX IDLEEXIT FAIL: setup')
	if phase == 'after' {
		assert !log.contains('LINUX IDLEEXIT DETAIL:') && !log.contains('LINUX IDLEEXIT FAIL:')
	} else {
		assert log.contains('LINUX IDLEEXIT DETAIL:'), 'idleexit baseline failure markers required'
		assert log.contains('LINUX IDLEEXIT FAIL:') && !log.contains('LINUX IDLEEXIT: PASS')
	}
	if reference {
		assert phase == 'after' && log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX IDLEEXIT REFERENCE: PASS') && !log.contains('LINUX IDLEEXIT STORAGE:')
	} else if phase == 'after' {
		assert log.count('LINUX IDLEEXIT: PASS') == 1
	}
}

fn storage(log string, arch string, phase string) {
	mut slabs := [2]int{}
	mut pages := [2]int{}
	mut seen := map[string]bool{}
	for row in log.split_into_lines().filter(it.starts_with('LINUX IDLEEXIT SLAB:') || it.starts_with('LINUX IDLEEXIT STORAGE:')) {
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
	assert log.contains('LINUX IDLEEXIT DETAIL:'), 'idleexit baseline failure markers required'
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
		'wrapper_source':    state + '/source/idleexitreferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/idleexit-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/idleexitreferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, 'after', arch, true)
	return artifacts
}

// Initial native setup failures and their passing Linux oracles have distinct
// identities. They never supply the final baseline failure vector.
fn setup_receipt(state string, arch string, kernel string, preflight string) !map[string]string {
	value := object(state + '/receipt.json')!
	assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel
	assert digest(state + '/kernel/bin/vinix') == kernel
	rows := value['results']!.as_array()
	assert rows.len == 1
	row := rows[0].as_map()
	assert row['name']!.str() == 'idleexit' && row['exit_code']!.int() == 1 && row['detail']!.str() == ''
	mut pins := map[string]string{}
	for label, path in {
		'source': state + '/sources/idleexitfixture/core.v'
		'init':   state + '/idleexit/init'
		'iso':    state + '/idleexit/test.iso'
	} {
		pins[label] = digest(path)
		assert pins[label] == row[if label == 'source' {
			'source_sha256'
		} else if label == 'init' {
			'init_sha256'
		} else {
			'iso_sha256'
		}]!.str()
	}
	for label, path in {
		'receipt':   state + '/receipt.json'
		'aggregate': state + '.log'
		'serial':    state + '/idleexit/serial.log'
		'c':         state + '/idleexit/fixture.c'
	} {
		pins[label] = digest(path)
	}
	assert pins['init'] == digest(preflight + '/init') && pins['c'] == digest(preflight + '/fixture.c')
	text := os.read_file(state + '/idleexit/serial.log')!
	assert text.contains('LINUX IDLEEXIT FAIL: setup or parent/child protocol stage=19 errno=0')
	assert !text.contains('LINUX IDLEEXIT CASES:') && !text.contains('LINUX IDLEEXIT FINAL:') && !text.contains('LINUX IDLEEXIT: PASS')
	return pins
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
	before := os.read_file(area + 'before-gaps.v')!
	after := os.read_file(area + 'after-gaps.v')!
	marker := 'fn may_set_sched_params(target_tid int, policy int, priority int)'
	old := definition(before, marker)
	new := definition(after, marker)
	source_matches := before.replace(old, '') == after.replace(new, '')
	assert source_matches, 'Only IDLE exit helper may change'
	addition := "\t// Leaving IDLE needs the target's current nice to fit its nice limit,\n\t// even when the request would otherwise retain or lower priority.\n\tif target.sched.policy == proc.sched_idle && policy != proc.sched_idle\n\t\t&& !proc.limit_allows(owner, proc.rlimit_nice, u64(20 - owner.nice)) {\n\t\treturn false\n\t}\n"
	assert new.count(addition) == 1
	normalized := new.replace(addition, '').replace('// Deadline needs privilege; IDLE exits need explicit nice admission.', '// Deadline needs privilege; ordinary classes retain their prior admission.')
	helper_matches := normalized == old
	assert helper_matches, 'Only exact six-line IDLE guard and internal comment may change'
	assert new.contains('proc.lock_table()\n\tdefer { proc.unlock_table() }')
	assert new.contains('target == unsafe { nil }') && new.contains('owner := target.process') && new.contains('owner == unsafe { nil }')
	assert new.contains('proc.has_capability(caller, proc.cap_sys_nice)')
	assert digest(root + 'kernel/syscall/table/gaps.v') == digest(area + 'after-gaps.v')
}

fn check_c(area string, suffix string) ! {
	before := os.read_file(area + 'before-' + suffix + '.c')!
	after := os.read_file(area + 'after-' + suffix + '.c')!
	marker := '\nbool table__may_set_sched_params(i64 target_tid, i64 policy, i64 priority) {'
	old := definition(before, marker)
	new := definition(after, marker)
	c_matches := before.replace(old, '') == after.replace(new, '')
	assert c_matches, 'Whole production C differs outside RT permission helper'
	assert old.count('proc__lock_table();') == 1 && new.count('proc__lock_table();') == 1
	assert old.count('proc__unlock_table();') == 10 && new.count('proc__unlock_table();') == 11
	assert new.contains('proc__Process* owner = target->process;')
	assert new.contains('proc__limit_allows(owner, proc__rlimit_nice, (u64)(20 - owner->nice))')
	assert new.contains('target->sched.policy') && new.contains('target->sched.priority')
	for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array__', 'free(', 'alloca('] {
		assert !new.contains(token), suffix + token
	}
	assert digest(area + 'kernel-' + suffix + '/kernel/syscall/table/gaps.v') == digest(area + 'after-gaps.v')
}

fn main() {
	if '--negative-control' in os.args {
		assert false, 'idleexit assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: idleexit-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-15/'
	os.mkdir_all(out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'idleexit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p2-reference-arm/serial.log', 'aarch64'], 'idleexit baseline failure markers required'))!
	check_source(area, root)!
	for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
	os.write_file(area + 'scope-check.log', 'arm/x86: whole generated production C differs only in table__may_set_sched_params; no compiler identifier normalization, new allocation/free or pointer escape; one PID-table lock and exact existing unlock paths plus one new guarded return\n')!
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == '410d7c5e499acbb3c274be54161f84b59514d505'
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
	assert os.read_file(area + 'linux-source.sha256')!.trim_space() == digest(area + 'linux-sched-v6.12.c') + ' https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/sched/syscalls.c'
	linux_source := os.read_file(area + 'linux-sched-v6.12.c')!
	assert linux_source.contains('task_has_idle_policy(p) && !idle_policy(policy)') && linux_source.contains('is_nice_reduction(p, task_nice(p))')
	assert os.read_file(area + 'watch.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 18
	retained := object(area + 'watch-retained-inputs.json')!
	assert retained.len >= 72
	for path, hash in retained {
		assert path.starts_with(states + 'p2-before-') || path.starts_with(states + 'p2-after-')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert os.inode(path).typ == .regular && digest(path) == hash.str(), path
	}
	primary_watch := os.read_file(area + 'watch-primary.log')!
	assert primary_watch.split_into_lines().filter(it.starts_with('Completed ')).len == 10
	assert os.read_file(area + 'watch.log')!.starts_with(primary_watch)
	assert os.read_file(area + 'watch-primary-detached.log')!.contains('completed-boot cleanup watchdog timed out')
	assert os.read_file(area + 'watch-resume-context.log')!.contains('native passing cases are not rerun')
	assert os.read_file(area + 'resume-watch-detached.log')!.contains('Resumed retained-capture watchdog completed')
	primary_pins := object(area + 'watch-primary-retained-inputs.json')!
	for path, hash in primary_pins {
		assert path in retained && retained[path]!.str() == hash.str() && digest(path) == hash.str()
	}
	preparations := object(area + 'preparation-inputs.json')!
	assert preparations.len > 0
	for path, hash in preparations {
		assert path.starts_with(area + 'preparations/') && os.inode(path).typ == .regular && digest(path) == hash.str(), path
	}
	assert os.read_file(area + 'preparations/first-generation/context.log')!.contains('No matching probe ELF or guest was produced')
	assert os.read_file(area + 'preparations/second-generation/context.log')!.contains('before CASES rows')
	early_retained := object(area + 'preparations/second-generation/watch-retained-inputs.json')!
	assert os.read_file(area + 'preparations/second-generation/watch.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 2
	for path, hash in early_retained {
		assert path.starts_with(states + 'p1-before-') && os.inode(path).typ == .regular && digest(path) == hash.str()
	}

	review_path := out + 'idleexit-lifetime-review.md'
	review := os.read_file(review_path)!
	assert review.starts_with('Independent idleexit lifetime review: PASS') && review.contains(digest(root + 'kernel/syscall/table/gaps.v')) && review.contains(digest(root + 'tests/linux-compat/idleexitfixture/core.v'))
	for arch, suffix in {
		'aarch64': 'arm'
		'x86_64':  'x86'
	} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == base
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/syscall/table/gaps.v'
		inputs := object(tree + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
		assert inputs.len == 64
		for path, hash in inputs {
			assert digest(tree + path) == hash, path
		}
		mut artifacts := {
			'compiler':                 digest(compiler_root + 'compiler/v')
			'compiler_inputs':          digest(compiler_root + 'compiler-inputs.json')
			'kernel_source':            digest(root + 'kernel/syscall/table/gaps.v')
			'kernel_source_before':     digest(area + 'before-gaps.v')
			'fixture_source':           digest(root + 'tests/linux-compat/idleexitfixture/core.v')
			'audit_source':             digest(@FILE)
			'review':                   digest(review_path)
			'linux_primary_source':     digest(area + 'linux-sched-v6.12.c')
			'linux_primary_pin':        digest(area + 'linux-source.sha256')
			'native_controller':        digest(area + 'run')
			'native_controller_source': digest(root + 'tests/linux-compat/run.v')
			'reference_controller':     digest(area + 'reference')
			'watch_pins':               digest(area + 'watch-retained-inputs.json')
			'watch_log':                digest(area + 'watch.log')
			'preparation_pins':         digest(area + 'preparation-inputs.json')
			'watch_primary_log':        digest(area + 'watch-primary.log')
			'watch_primary_pins':       digest(area + 'watch-primary-retained-inputs.json')
			'watch_primary_timeout':    digest(area + 'watch-primary-detached.log')
			'watch_resume_context':     digest(area + 'watch-resume-context.log')
			'watch_completion_output':  digest(area + 'watch-completion-detached.log')
			'watch_resume_output':      digest(area + 'resume-watch-detached.log')
		}
		mut identity := map[string]string{}
		early := states + 'p1-before-' + suffix
		early_probe := states + 'preflight2-idleexit-' + suffix
		early_native := setup_receipt(early, arch, digest(area + 'baseline-' + suffix + '/kernel/bin/vinix'), early_probe)!
		for key, value in early_native { artifacts['setup_' + key] = value }
		early_linux := reference_receipt(states + 'p1-reference-' + suffix, arch, early_native['init'])!
		for key, value in early_linux { artifacts['setup_reference_' + key] = value }
		for label, path in {
			'receipt':             early + '/receipt.json'
			'aggregate':           early + '.log'
			'native':              early + '/idleexit/serial.log'
			'reference_receipt':   states + 'p1-reference-' + suffix + '/receipt.json'
			'reference_aggregate': states + 'p1-reference-' + suffix + '.log'
			'reference_native':    states + 'p1-reference-' + suffix + '/serial.log'
		} {
			publish(path, out + 'idleexit-setup-' + arch + '-' + label + if label.ends_with('receipt') {
				'.json'
			} else {
				'.log'
			})!
		}
		for phase in ['before', 'after'] {
			state := states + 'p2-' + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['idleexit']
			} else {
				['idleexit', 'runtime', 'schedabi', 'rrabi', 'rtadmit', 'attrimport', 'attrnice',
					'fcntlabi']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['idleexit_source', 'idleexit_init', 'idleexit_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/idleexit/serial.log')!
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
				'native':    state + '/idleexit/serial.log'
				'build':     build
			} {
				publish(path, out + 'idleexit-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			if phase == 'after' {
				for name in names {
					if name == 'idleexit' { continue }
					publish(state + '/' + name + '/serial.log', out + 'idleexit-regression-' + arch + '-' + name + '.log')!
				}
			}
		}
		preflight := states + 'preflight3-idleexit-' + suffix
		raw := os.read_file(preflight + '/fixture.c')!
		assert digest(preflight + '/fixture.c') == identity['idleexit_c'] && digest(preflight + '/init') == identity['idleexit_init']
		assert digest(area + 'preview-' + suffix + '.c') == identity['idleexit_c'] && raw.count('alloca(') == 26
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array_push(', 'array_get(',
			'v_fixed_index('] {
			assert !raw.contains(token)
		}
		artifacts['preflight_c'] = digest(preflight + '/fixture.c')
		artifacts['preflight_init'] = digest(preflight + '/init')
		reference := states + 'p2-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['idleexit_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'idleexit-reference-' + arch + '-' + label + if label == 'receipt' {
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
		os.write_file(out + 'idleexit-evidence-' + arch + '.json', json2.encode(Evidence{
			architecture:  arch
			context:       'Native stable single-thread process-leader IDLE exit admission: 25008 root/UID1000 controls per architecture. Target current nice and RLIMIT_NICE before leaving IDLE, effective CAP_SYS_NICE and owner checks; legacy/setparam/attribute APIs, peer limit distinctions, independent RT limits, imported nice/clamping, guarded inputs and real errors/state/restoration. Same-ELF Linux 6.12.51 references, 26 explicit allocas and two flat warmed 200-cycle cohorts. Four production builds and whole-C changes limited to one existing scalar helper; eight regressions per architecture, byte-identical allocation diagnostics, host/inventory/compiler pins, executing auditor negatives and independent lifetime review. First v_fixed_index compile failures, actual stage19 native setup failures and matching initial Linux passes remain separate from final p2 identities. Broker setup uses canonical signed64 setpriority words. RT getattr nice field, setpriority signed32 words/permissions/group behavior, worker/identity/credential/limit races, reset/deadline/timing/security/GNU/foreign/ELF32 and broad roadmap gates remain unqualified.'
			base_commit:   base
			artifacts:     artifacts
			source_inputs: inputs
		}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log',
		'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'watch.log'] {
		publish(area + name, out + 'idleexit-' + name)!
	}
	for name in ['first-generation/context.log', 'second-generation/context.log'] {
		publish(area + 'preparations/' + name, out + 'idleexit-preparation-' + name.replace('/', '-'))!
	}
	for name in ['watch-primary.log', 'watch-primary-detached.log', 'watch-resume-context.log',
		'watch-completion-detached.log', 'resume-watch-detached.log'] {
		publish(area + name, out + 'idleexit-' + name)!
	}
	os.write_file(area + 'audit.log', 'Native idleexit conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'idleexit-audit.log')!
	println('Native idleexit conformance audit: PASS')
}
