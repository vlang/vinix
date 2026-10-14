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
	architecture string
	context string
	base_commit string
	artifacts map[string]string
	source_inputs map[string]string
}
fn digest(path string) string {
	mut input := os.open(path) or { panic(err) }; defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}; defer { unsafe { buffer.free() } }
	$if macos {
		mut state := C.CC_SHA256_CTX{}
		assert C.CC_SHA256_Init(unsafe { &state }) == 1
		for {
			n := input.read(mut buffer) or { if err is os.Eof { break }; panic(err) }
			if n == 0 { break }; assert C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) == 1
		}
		mut result := [32]u8{}; assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) == 1
		return result[..].hex()
	} $else {
		mut state := sha256.new()
		for {
			n := input.read(mut buffer) or { if err is os.Eof { break }; panic(err) }
			if n == 0 { break }; assert state.write(buffer[..n]) or { panic(err) } == n
		}
		mut result := []u8{len: 32}; state.checksum_into(mut result); return result.hex()
	}
}
fn object(path string) !map[string]json2.Any { return json2.decode[json2.Any](os.read_file(path)!)!.as_map() }
fn publish(input string, output string) ! {
	data := os.read_bytes(input)!
	if os.exists(output) { assert os.read_bytes(output)! == data } else { os.write_file_array(output, data)! }
}
fn git(tree string, args []string) !string {
	mut p := os.new_process('git'); p.set_args(['-C',tree,...args]); p.set_redirect_stdio_merged(); p.run(); output := p.stdout_slurp(); p.wait(); code := p.code; p.close(); assert code == 0,output; return output.trim_space()
}
fn control(args []string, marker string) string {
	mut p := os.new_process(os.executable()); p.set_args(args); p.set_redirect_stdio_merged(); p.run()
	output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }; return output
}
fn erase(source string, names []string, units int) string {
 mut kept := []string{}; mut inside := false; mut separator := false; mut removed := 0
 for line in source.split_into_lines() {
 if inside { if line == '}' { inside = false; separator = true }; continue }
 if separator { assert line == ''; separator = false; continue }
 if line != '' && line[0] != `\t` && names.any(line.contains(' ' + it + '(')) { assert line.ends_with(';') || line.ends_with('{'); inside = line.ends_with('{'); removed++; continue }
 kept << line
 }; assert !inside && removed == units; return kept.join('\n')
}
fn body(source string, name string) string {
	mut lines := []string{}; mut inside := false
	for line in source.split_into_lines() {
		if !inside && line != '' && line[0] != `\t` && line.contains(' ' + name + '(') && line.ends_with('{') { inside = true }
		if inside { lines << line; if line == '}' { return lines.join('\n') } }
	}
	panic('missing generated body: ' + name)
}
fn semantics(log string, phase string, arch string, reference bool) {
	assert phase in ['before', 'middle', 'after'] && arch in ['aarch64', 'x86_64']
	mut cases := map[string]string{}
	for label in ['CASES:', 'FINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX SCHEDABI ' + label)); assert rows.len == 8
		mut seen := map[string]bool{}; mut total := 0; mut failures := 0
		for row in rows {
			fields := row.fields(); assert fields.len == 7
			for index, prefix in {3: 'ordinary=', 4: 'kind=', 5: 'calls=', 6: 'failures='} { assert fields[index].starts_with(prefix) }
			ordinary := fields[3].all_after('=').int(); kind := fields[4].all_after('=').int(); assert ordinary in [0,1] && kind in [0,1,2,3]
			key := fields[3] + fields[4]; assert key !in seen; seen[key] = true
			n := fields[5].all_after('=').int(); f := fields[6].all_after('=').int()
			assert n == [876,1824,36,2]![kind]
			expected := if phase == 'after' { 0 } else if phase == 'middle' { [0, 654, 0, 0]![kind] } else { [124, 1106, 0, 0]![kind] }
			assert f == expected, row
			if label == 'CASES:' { cases[key] = fields[5] + fields[6] } else { assert cases[key] == fields[5] + fields[6] }
			total += n; failures += f
		}; assert total == 5476; if phase == 'after' { assert failures == 0 } else { assert failures > 0 }
	}
	assert !log.contains('Kernel panic') && !log.contains('LINUX SCHEDABI FAIL: setup')
	if phase == 'after' { assert !log.contains('LINUX SCHEDABI DETAIL:') && !log.contains('LINUX SCHEDABI FAIL:') }
	else { assert log.contains('LINUX SCHEDABI DETAIL:'), 'schedabi baseline failure markers required'; assert log.contains('LINUX SCHEDABI FAIL:') && !log.contains('LINUX SCHEDABI: PASS') }
	if reference { assert phase == 'after' && log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX SCHEDABI REFERENCE: PASS') && !log.contains('LINUX SCHEDABI STORAGE:') }
	else if phase == 'after' { assert log.count('LINUX SCHEDABI: PASS') == 1 }
}
fn storage(log string, arch string, phase string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines().filter(it.starts_with('LINUX SCHEDABI SLAB:') || it.starts_with('LINUX SCHEDABI STORAGE:')) {
		fields := row.fields(); assert fields.len == 7 && fields[3].starts_with('ordinary=')
		ordinary := fields[3].all_after('=').int(); assert ordinary in [0,1]
		pair := fields[5].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' { assert fields[4].starts_with('size=') && fields[6] == 'cycles=200'; key := fields[3] + fields[4]; assert key !in seen; seen[key] = true; slabs[ordinary]++ }
		else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS' && pair[0].u64() > 0; pages[ordinary]++ }
	}
	for ordinary in 0 .. 2 { assert slabs[ordinary] == if phase == 'before' { 0 } else if arch == 'aarch64' { 18 } else { 14 }; assert pages[ordinary] == if phase == 'before' { 0 } else { 1 } }
}
fn failure(log string, arch string) { assert log.contains('LINUX SCHEDABI DETAIL:'), 'schedabi baseline failure markers required'; semantics(log, 'before', arch, false) }
fn receipt(state string, arch string, kernel string, names []string, failing bool) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel && digest(state + '/kernel/bin/vinix') == kernel
	rows := value['results']!.as_array(); assert rows.len == names.len
	mut artifacts := {'receipt': digest(state + '/receipt.json'), 'aggregate': digest(state + '.log')}
	for index, row in rows {
		entry := row.as_map(); name := entry['name']!.str(); assert name == names[index] && entry['exit_code']!.int() == if failing && index == 0 { 1 } else { 0 } && entry['detail']!.str() == ''
		for label, path in {'source': state + '/sources/' + name + 'fixture/core.v', 'init': state + '/' + name + '/init', 'iso': state + '/' + name + '/test.iso'} { hash := digest(path); key := if label == 'source' { 'source_sha256' } else if label == 'init' { 'init_sha256' } else { 'iso_sha256' }; assert hash == entry[key]!.str(); artifacts[name + '_' + label] = hash }
		assert artifacts[name + '_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/' + name + 'fixture/core.v')
		artifacts[name + '_c'] = digest(state + '/' + name + '/fixture.c'); artifacts[name + '_serial'] = digest(state + '/' + name + '/serial.log')
		if !failing || index > 0 { assert os.read_file(state + '/' + name + '/serial.log')!.contains('LINUX ' + name.to_upper() + ': PASS') }
	}; return artifacts
}
fn reference_receipt(state string, arch string, init string) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['passed']!.bool() && value['finished']!.bool() && value['forced']!.bool() && value['status']!.int() == 0
	artifacts := value['artifacts']!.as_map_of_strings(); command := value['command']!.as_array().map(it.str()); assert command.contains('-kernel') && command.contains('-initrd') && command.contains('-no-reboot')
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/schedabireferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/schedabi-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/schedabireferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, 'after', arch, true); return artifacts
}
fn scope(area string, final bool) {
	changed := ['table__syscall_linux_sched_setscheduler', 'table__syscall_linux_sched_getparam', 'table__syscall_linux_sched_setparam']
	all := [...changed, 'table__syscall_linux_sched_getscheduler', 'table__syscall_linux_sched_get_priority_min', 'table__syscall_linux_sched_get_priority_max']
	mut verdict := ''
	for suffix in ['arm', 'x86'] {
		before := os.read_file(area + 'before-' + suffix + '.c') or { panic(err) }; middle := os.read_file(area + 'middle-' + suffix + '.c') or { panic(err) }
		assert before != middle && erase(before, changed, 6) == erase(middle, changed, 6)
		for name in changed {
			text := body(middle, name); assert text.contains('param == 0') && text.contains('errno__einval')
			if name != 'table__syscall_linux_sched_getparam' {
				copy_at := text.index('usercopy__copy_from_user') or { panic('missing input copy') }; target_at := text.index('table__sched_target_tid') or { panic('missing target lookup') }
				assert text.contains('i32 priority32 = (i32)(0);') && copy_at < target_at
			}
		}
		if final {
			after := os.read_file(area + 'after-' + suffix + '.c') or { panic(err) }
			assert middle != after && erase(before, all, 12) == erase(after, all, 12)
			for name in all {
				text := body(after, name)
				if name.contains('priority_') { assert text.contains('(i64)((i32)((u32)(raw_policy)))') }
				else { assert text.contains('(i64)((i32)((u32)(raw_pid)))') }
				if name.ends_with('setscheduler') { assert text.contains('(i64)((i32)((u32)(raw_policy)))') }
			}
		}
		verdict += suffix + ': full generated C unchanged outside three error-handling bodies/prototypes' + if final { ' and six legacy scheduler argument-decoding bodies/prototypes\n' } else { '\n' }
	}
	os.write_file(area + if final { 'scope-check.log' } else { 'middle-scope-check.log' }, verdict) or { panic(err) }
}
fn preparation(area string, out string, arch string, suffix string) !map[string]string {
	mut artifacts := map[string]string{}
	for phase in ['before', 'reference'] {
		state := area + 'states/p1-' + phase + '-' + suffix
		serial := state + if phase == 'before' { '/schedabi/serial.log' } else { '/serial.log' }
		text := os.read_file(serial)!; assert text.contains('LINUX SCHEDABI FAIL: setup or child protocol') && !text.contains('LINUX SCHEDABI CASES:') && !text.contains('LINUX SCHEDABI FINAL:')
		if phase == 'before' { assert object(state + '/receipt.json')!['results']!.as_array()[0].as_map()['exit_code']!.int() == 1 }
		else { assert !object(state + '/receipt.json')!['passed']!.bool() }
		for label, path in {'receipt': state + '/receipt.json', 'aggregate': state + '.log', 'serial': serial} { artifacts['diagnostic_p1_' + phase + '_' + label] = digest(path); publish(path, out + 'schedabi-diagnostic-p1-' + phase + '-' + arch + '-' + label + if label == 'receipt' { '.json' } else { '.log' })! }
	}
	for version in ['1', '2', '3', '4'] {
		state := area + 'states/preflight' + version + '-schedabi-' + suffix
		for label, path in {'c': state + '/fixture.c', 'elf': state + '/init'} { artifacts['diagnostic_preflight' + version + '_' + label] = digest(path) }
	}
	for phase in ['before', 'middle', 'after', 'reference'] {
		state := area + 'states/p2-' + phase + '-' + suffix
		serial := state + if phase == 'reference' { '/serial.log' } else { '/schedabi/serial.log' }
		text := os.read_file(serial)!; rows := text.split_into_lines().filter(it.starts_with('LINUX SCHEDABI FINAL:')); assert rows.len == 8
		if phase == 'reference' {
			assert !object(state + '/receipt.json')!['passed']!.bool()
			for row in rows { fields := row.fields(); kind := fields[4].all_after('=').int(); assert fields[6] == 'failures=' + [0,8,4,0]![kind].str() }
		}
		for label, path in {'receipt': state + '/receipt.json', 'aggregate': state + '.log', 'serial': serial} { artifacts['diagnostic_p2_' + phase + '_' + label] = digest(path); publish(path, out + 'schedabi-diagnostic-p2-' + phase + '-' + arch + '-' + label + if label == 'receipt' { '.json' } else { '.log' })! }
	}
	return artifacts
}
fn qos(area string, out string, arch string, suffix string, final_kernel string) !map[string]string {
	mut artifacts := map[string]string{}
	mut init := ''; phases := if suffix == 'arm' { ['before','after'] } else { ['after'] }
	for phase in phases {
		state := area + 'states/qos-' + phase + '-' + suffix; inputs := object(state + '/inputs.json')!
		assert inputs['family']!.str() == 'scheduler-qos' && inputs['arch']!.str() == arch && inputs['compile_command']!.as_array().any(it.str() == '-DSCHED_QOS_SMALL=1')
		kernel := digest(state + '/kernel/bin/vinix'); assert kernel == inputs['kernel_sha256']!.str() && kernel == if phase == 'after' { final_kernel } else { digest(area + 'baseline-' + suffix + '/kernel/bin/vinix') }
		assert digest('/Users/alex/code/vinix/tests/scheduler-qos/guest.c') == inputs['source_sha256']!.str()
		assert digest(state + '/init') == inputs['init_sha256']!.str(); if init != '' { assert init == inputs['init_sha256']!.str() }; init = inputs['init_sha256']!.str()
		assert digest(state + '/initramfs.tar') == inputs['archive_sha256']!.str()
		command := inputs['command']!.as_array().map(it.str()); assert command[command.index('-smp') + 1] == '4'
		text := os.read_file(state + '/serial.log')!
		if suffix == 'arm' { assert text.contains('skipping SMP (no device tree)') && text.contains('SCHED-QOS hints-legacy-ABI-timer-slack PASS') && text.contains('SCHED-QOS FAIL line=33 errno=22') && !text.contains('SCHED-QOS PASS') }
		else { assert text.contains('SCHED-QOS PASS') && !text.contains('SCHED-QOS FAIL') }
		for label, path in {'inputs': state + '/inputs.json', 'serial': state + '/serial.log', 'aggregate': state + '.log'} { publish(path, out + 'schedabi-qos-' + phase + '-' + arch + '-' + label + if label == 'inputs' { '.json' } else { '.log' })!; artifacts['qos_' + phase + '_' + label] = digest(path) }
		artifacts['qos_' + phase + '_kernel'] = kernel; artifacts['qos_' + phase + '_init'] = init
		for label, path in {'archive': state + '/initramfs.tar', 'iso': state + '/test.iso', 'serial_c': state + '/serial.c', 'qemu': command[0]} { artifacts['qos_' + phase + '_' + label] = digest(path) }
	}
	return artifacts
}
fn main() {
	if '--negative-control' in os.args { assert false, 'schedabi assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!, os.args[3]); return }
	assert os.args.len >= 2, 'Usage: schedabi-check.v EVIDENCE-AREA [--middle-only]'
	area := os.args[1].trim_right('/') + '/'; states := area + 'states/'; root := '/Users/alex/code/vinix/'; out := root + 'tests/linux-compat/results/2026-10-14/'
	middle_only := '--middle-only' in os.args
	scope(area, !middle_only)
	control_prefix := if middle_only { 'middle-' } else { '' }
	os.write_file(area + control_prefix + 'assertion-control.log', control(['--negative-control'], 'schedabi assertions must execute'))!
	os.write_file(area + control_prefix + 'passing-log-control.log', control(['--negative-pass-control', states + 'p3-reference-arm/serial.log', 'aarch64'], 'schedabi baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '108082c1e0513e87559e47fde420471ccc2f15f7'
	compiler_root := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/'; compiler := compiler_root + 'compiler/v'
	assert digest(compiler) == '9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b'
	mut pins := map[string]string{}; for path, value in object(compiler_root + 'compiler-inputs.json')! { pins[path] = value.str() }; assert pins.len == 15146 && pins['v'] == digest(compiler)
	for path, hash in pins { assert digest(compiler_root + 'compiler/' + path) == hash, path }
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.count('Linux dispatch coverage: PASS') == 4
	for arch, count in {'aarch64': '398', 'x86_64': '290'} { for name in ['allocs-before.log','allocs-after.log'] { assert os.read_file(area + name)!.split_into_lines().filter(it.starts_with(arch + ':')).len == 1 && os.read_file(area + name)!.contains(count + ' allocation sites (V exit 0)') && os.read_file(area + name)!.contains('NEW:') } }
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		mut artifacts := {'compiler': digest(compiler), 'compiler_inputs': digest(compiler_root + 'compiler-inputs.json'), 'fixture_source': digest(root + 'tests/linux-compat/schedabifixture/core.v'), 'audit_source': digest(@FILE)}
		mut identity := map[string]string{}
		phases := if middle_only { ['before', 'middle'] } else { ['before', 'middle', 'after'] }
		for phase in phases {
			state := states + 'p3-' + phase + '-' + suffix; kernel := area + if phase == 'after' { 'kernel-' } else if phase == 'before' { 'baseline-' } else { 'middle-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'after' { ['schedabi', 'runtime', 'capabi', 'open', 'fcntlabi'] } else { ['schedabi'] }
			captured := receipt(state, arch, digest(kernel), names, phase != 'after')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['schedabi_source', 'schedabi_init', 'schedabi_c'] { if phase == 'before' { identity[key] = captured[key] } else { assert identity[key] == captured[key], 'probe changed between phases' } }
			text := os.read_file(state + '/schedabi/serial.log')!; semantics(text, phase, arch, false); storage(text, arch, phase)
			build := area + 'build-' + phase + '-' + suffix + '.log'; text_build := os.read_file(build)!; assert text_build.contains('-o bin/vinix') && !text_build.contains('Nothing to be done') && !text_build.contains('Error ')
			artifacts[phase + '_kernel'] = digest(kernel); artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
			if !middle_only { for label, path in {'receipt': state + '/receipt.json', 'aggregate': state + '.log', 'native': state + '/schedabi/serial.log', 'build': build} { publish(path, out + 'schedabi-' + phase + '-' + arch + '-' + label + if label == 'receipt' { '.json' } else { '.log' })! } }
		}
		preflight := states + 'preflight5-schedabi-' + suffix
		assert digest(area + 'preview-' + suffix + '.c') == identity['schedabi_c'] && digest(preflight + '/fixture.c') == identity['schedabi_c'] && digest(preflight + '/init') == identity['schedabi_init']
		probe_c := os.read_file(preflight + '/fixture.c')!; assert probe_c.count('alloca(') == 7
		for token in ['malloc(', 'memdup(', 'array_push(', 'array_get(', 'array_set('] { assert !probe_c.contains(token) }
		artifacts['preflight_c'] = digest(preflight + '/fixture.c'); artifacts['preflight_init'] = digest(preflight + '/init'); artifacts['preview_c'] = digest(area + 'preview-' + suffix + '.c')
		linux := reference_receipt(states + 'p3-reference-' + suffix, arch, identity['schedabi_init'])!
		if !middle_only {
			for key, value in qos(area, out, arch, suffix, artifacts['after_kernel'])! { artifacts[key] = value }
			for key, value in linux { artifacts['reference_' + key] = value }
			for label, path in {'receipt': states + 'p3-reference-' + suffix + '/receipt.json', 'aggregate': states + 'p3-reference-' + suffix + '.log', 'native': states + 'p3-reference-' + suffix + '/serial.log'} { publish(path, out + 'schedabi-reference-' + arch + '-' + label + if label == 'receipt' { '.json' } else { '.log' })!; artifacts['reference_' + label] = digest(path) }
			for key, value in preparation(area, out, arch, suffix)! { artifacts[key] = value }
			inputs := object(area + 'kernel-' + suffix + '/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 64
			assert git(area + 'kernel-' + suffix, ['rev-parse','HEAD'])! == base && git(area + 'kernel-' + suffix, ['diff','--name-only','HEAD','--','kernel'])! == 'kernel/syscall/table/gaps.v'
			for path, hash in inputs { assert digest(area + 'kernel-' + suffix + '/' + path) == hash }
			// The dispatch inventory pins selected dispatch inputs, not every
			// implementation file. Bind this handler file separately as well.
			assert digest(area + 'kernel-' + suffix + '/kernel/syscall/table/gaps.v') == digest(root + 'kernel/syscall/table/gaps.v')
			review := os.read_file(out + 'schedabi-lifetime-review.md')!; assert review.starts_with('Independent schedabi lifetime review: PASS') && review.contains(digest(root + 'kernel/syscall/table/gaps.v')) && review.contains(digest(root + 'tests/linux-compat/schedabifixture/core.v'))
			for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'middle-assertion-control.log', 'middle-passing-log-control.log', 'middle-check.log', 'middle-scope-check.log', 'error-commit.txt'] { artifacts[name] = digest(area + name) }
			artifacts['review'] = digest(out + 'schedabi-lifetime-review.md'); artifacts['kernel_source'] = digest(root + 'kernel/syscall/table/gaps.v')
			assert os.read_file(area + 'allocs-before.log')! == os.read_file(area + 'allocs-after.log')!
			artifacts['middle_audit_source'] = digest(area + 'middle-audit-source.v')
			os.write_file(out + 'schedabi-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: 'Six native legacy scheduling syscalls; 5476 checks per architecture: 4600 kernel-facing/state checks and 876 exact pinned musl legacy process-wrapper ENOSYS refusals. Raw low/high words, priority-bound libc calls, guarded buffers and observed policy/priority after errors. Original2460 failures, error-only1308, decoded/reference0; identical native ELF/C on all phases and Linux6.12.51. Two credential cohorts200 cycles retain all slabs/large pages flat. Six isolated production builds, full generated C scope, unchanged allocation allowance failures, compiler/source/ELF pins, five-case final native profile and independent lifetime review. Small scheduler QoS passes x86; original/decoded ARM both fail CPU1 affinity in boots without a device tree. Setup and policy7/SCHED_EXT oracle assumptions remain separate diagnostics. Realtime/deadline, reset/capability/limit rules, SCHED_EXT, target races, namespace/pledge, RR/attribute/affinity argument ABIs, glibc, translation/ELF32 and broad gates remain open.', base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
		}
	}
	if middle_only { os.write_file(area + 'middle-check.log', 'Scheduler error precedence qualification: PASS\n')!; println('Scheduler error precedence qualification: PASS'); return }
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'middle-assertion-control.log', 'middle-passing-log-control.log', 'middle-check.log', 'middle-scope-check.log', 'error-commit.txt'] { publish(area + name, out + 'schedabi-' + name)! }
	os.write_file(area + 'audit.log', 'Native schedabi conformance audit: PASS\n')!; publish(area + 'audit.log', out + 'schedabi-audit.log')!; println('Native schedabi conformance audit: PASS')
}
