// Compile without -prod: both deliberately failing controls must execute.
import crypto.sha256
import json2
import os
import strings

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
	mut command := ['-C', tree]; command << args
	mut p := os.new_process('git'); p.set_args(command); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	assert code == 0, output; return output.trim_space()
}
fn definition(source string, name string) string {
	lines := source.split_into_lines().filter(!it.starts_with(' ') && !it.starts_with('	') && it.contains(' ' + name + '(') && it.ends_with(' {'))
	assert lines.len == 1; return source.all_after(lines[0]).all_before('\n}\n')
}
fn control(args []string, marker string) string {
	mut p := os.new_process(os.executable()); p.set_args(args); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }; return output
}
fn canonical_discard(source string) string {
	mut output := strings.new_builder(source.len); mut names := map[string]string{}; mut position := 0
	for position < source.len {
		start := position
		if source[position].is_letter() || source[position] == `_` {
			position++
			for position < source.len && (source[position].is_alnum() || source[position] == `_`) { position++ }
			token := source[start..position]
			if token.starts_with('__discard_') && token.len > 10 && token[10..].bytes().all(it.is_digit() || it == `_`) {
				if token !in names { names[token] = '_return' + names.len.str() }
				output.write_string(names[token])
			} else { output.write_string(token) }
		} else { output.write_u8(source[position]); position++ }
	}
	return output.str()
}
fn receipt(state string, arch string, kernel_hash string, names []string, failing bool) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel_hash
	assert digest(state + '/kernel/bin/vinix') == kernel_hash
	rows := value['results']!.as_array(); assert rows.len == names.len
	mut artifacts := {'receipt': digest(state + '/receipt.json'), 'aggregate': digest(state + '.log')}
	for index, row in rows {
		entry := row.as_map(); name := entry['name']!.str(); assert name == names[index]
		assert entry['exit_code']!.int() == if failing { 1 } else { 0 } && entry['detail']!.str() == ''
		for label, path in {'source': state + '/sources/' + name + 'fixture/core.v', 'init': state + '/' + name + '/init', 'iso': state + '/' + name + '/test.iso'} {
			hash := digest(path); assert hash == entry[if label == 'source' { 'source_sha256' } else if label == 'init' { 'init_sha256' } else { 'iso_sha256' }]!.str()
			artifacts[name + '_' + label] = hash
		}
		artifacts[name + '_c'] = digest(state + '/' + name + '/fixture.c')
		artifacts[name + '_serial'] = digest(state + '/' + name + '/serial.log')
		if !failing {
			assert artifacts[name + '_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/' + name + 'fixture/core.v')
			assert os.read_file(state + '/' + name + '/serial.log')!.contains('LINUX ' + name.to_upper() + ': PASS')
		}
	}
	return artifacts
}
fn success(log string, arch string) {
	rows := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF OUTCOMES:'))
	assert rows.len == 6 && rows.all(it.contains('cases=270 failures=0 status=1'))
	ids := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF TASKIDS:')); assert ids.len == 4 && ids.all(it.trim_space().ends_with('PASS'))
	mut seen := map[string]bool{}
	for row in ids {
		fields := row.fields(); assert fields.len == 11
		local := fields[3].all_after('='); leader := fields[4].all_after('='); key := local + '-' + leader
		assert local in ['0', '1'] && leader in ['0', '1'] && key !in seen; seen[key] = true
		pid := fields[5].all_after('=').split('/'); tgid := fields[6].all_after('=').split('/'); ns := fields[7].all_after('=').split(':')
		assert pid.len == 2 && tgid.len == 2 && ns.len == 2 && pid[0] == pid[1] && tgid[0] == tgid[1] && ns[0] == pid[0]
		assert (pid[0] == tgid[0]) == (leader == '1')
		assert fields[8].all_after('=') == if local == '1' { '1' } else { '2' }
		assert fields[9].all_after('=') == fields[8].all_after('=')
		if local == '1' { assert tgid[0] == '1' && ns[1] == '-1' } else { assert tgid[0].int() > 1 && ns[1].int() == if leader == '1' { 1 } else { 2 } }
	}
	assert log.contains('LINUX PROCSELF PIDVIEW: outer-and-own leader/worker Pid/Tgid/NSpid PASS')
	mut slab_keys := map[string]bool{}; mut counts := [2]int{}; mut pages := [2]int{}
	for line in log.split_into_lines() {
		if !line.starts_with('LINUX PROCSELF SLAB:') && !line.starts_with('LINUX PROCSELF STORAGE:') { continue }
		fields := line.fields(); assert fields.len == 7; group := fields[3].all_after('=').int(); assert group in [0, 1]
		pair := fields[5].all_after('=').split('/'); assert pair.len == 2 && pair.all(it != '' && it.bytes().all(it.is_digit())) && pair[0] == pair[1]
		if fields[2] == 'SLAB:' { key := fields[3] + '-' + fields[4]; assert key !in slab_keys && fields[6] == 'cycles=200'; slab_keys[key] = true; counts[group]++ }
		else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS'; assert pair[0] == if arch == 'aarch64' { '63' } else { '160' }; pages[group]++ }
	}
	for group in 0 .. 2 { assert counts[group] == if arch == 'aarch64' { 18 } else { 14 }; assert pages[group] == 1 }
	assert log.contains('LINUX PROCSELF CHROOT: no-/proc relative-self/thread-self-status PASS') && log.split_into_lines().filter(it.trim_space() == 'LINUX PROCSELF: PASS').len == 1
}
fn restore_generated(generated string, baseline string) {
	current := definition(generated, 'proc__process_stat_line'); previous := definition(baseline, 'proc__process_stat_line')
	assert current.contains('proc__tid_in(target, viewer)') && current.contains('proc__Thread__sched_or_default(target)') && current.contains('proc__lock_table') && current.contains('proc__unlock_table')
	assert generated.count(current) == 1
	mut restored := generated.replace(current, previous)
	old_signature := 'proc__process_stat_line(i64 pid, proc__Namespace* viewer)'
	new_signature := 'proc__process_stat_line(i64 pid, i64 tid, proc__Namespace* viewer)'
	assert restored.count(new_signature) == 2 && baseline.count(old_signature) == 2
	restored = restored.replace(new_signature, old_signature)
	new_call := 'proc__process_stat_line(this->pid, this->tid, (proc__Namespace*)(this->view))'
	old_call := 'proc__process_stat_line(this->pid, (proc__Namespace*)(this->view))'
	assert restored.count(new_call) == 1 && baseline.count(old_call) == 1
	restored = restored.replace(new_call, old_call)
	matched := canonical_discard(restored) == canonical_discard(baseline)
	assert matched, 'only selected stat formatter, callback/signature and unused-loop source offsets may change whole kernel C'
}
fn failure(log string) {
	assert log.contains('LINUX PROCSELF STAT DETAIL:'), 'task-stat baseline failure markers required'
	assert log.contains('LINUX PROCSELF MUSL SCHED: process wrappers refuse ENOSYS') && log.contains('LINUX PROCSELF SETUP: setrlimit=0 errno=0')
	rows := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF OUTCOMES:'))
	assert rows.len == 6 && rows.all(it.contains('cases=270 failures=0')) && rows.filter(it.contains('slot=0') && it.contains('status=1')).len == 2 && rows.filter(!it.contains('slot=0') && it.contains('status=0')).len == 4
	details := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF STAT DETAIL:')); assert details.len == 28
	mut counts := map[string]int{}
	for row in details {
		fields := row.fields(); assert fields.len == 9
		pid := fields[5].all_after('=').split('/'); priority := fields[6].all_after('=').split('/'); rt := fields[7].all_after('=').split('/'); policy := fields[8].all_after('=').split('/')
		assert pid.len == 2 && priority.len == 2 && rt.len == 2 && policy.len == 2 && pid[0] != pid[1]
		assert priority[0] == '20' && rt[0] == '0' && policy[0] == '0'
		assert rt[1] in ['17', '33', '23'] && priority[1].int() == -1 - rt[1].int() && policy[1] == if rt[1] == '33' { '2' } else { '1' }
		counts[rt[1]]++
	}
	assert counts['17'] == 12 && counts['33'] == 12 && counts['23'] == 4
	ids := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF TASKIDS:'))
	assert ids.len == 4 && ids.filter(it.contains('leader=1') && it.trim_space().ends_with('PASS')).len == 2 && ids.filter(it.contains('leader=0') && it.trim_space().ends_with('FAIL')).len == 2
	// Status identities already pass; only the newly appended stat controls fail.
	for row in ids { fields := row.fields(); assert fields.len == 11; pair := fields[5].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] }
	assert log.contains('LINUX PROCSELF CHROOT: no-/proc relative-self/thread-self-status PASS') && log.contains('LINUX PROCSELF PIDVIEW: outer-and-own leader/worker Pid/Tgid/NSpid FAIL')
	assert log.contains('LINUX PROCSELF FAIL:') && !log.split_into_lines().any(it.trim_space() == 'LINUX PROCSELF: PASS')
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/procstat-20261013/'; compiler := '/Users/alex/.cache/vinix-linux-compat/compiler-f6358ec/'
	out := root + 'tests/linux-compat/results/2026-10-13/'
	if '--kernel-control' in os.args { for suffix in ['arm', 'x86'] { restore_generated(os.read_file(area + 'kernel-' + suffix + '/kernel/obj/blob.c')!, os.read_file(area + 'before-' + suffix + '.c')!) }; println('Selected task-stat kernel scope: PASS'); return }
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'after-arm/procself/serial.log'], 'task-stat baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '21f57bbae976c4165a8b9dca7c431a049f7d9416'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	for path in ['kernel/proc/proc.v', 'kernel/fs/procfs.v'] { assert inputs[path] == digest(root + path) }
	assert git(compiler, ['rev-parse', 'HEAD'])! == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c' && git(compiler, ['diff', '--name-only', 'HEAD'])! == ''
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	for arch, row in {'aarch64': '657 source files, 406 allocation sites', 'x86_64': '653 source files, 295 allocation sites'} { assert before_allocs.contains(arch + ': ' + row + ' (V exit 0)') && after_allocs.contains(arch + ': ' + row + ' (V exit 0)') }
	review := root + 'tests/linux-compat/results/2026-10-13/procstat-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent selected task-stat lifetime review: PASS')
	for path in [root + 'kernel/proc/proc.v', root + 'kernel/fs/procfs.v', root + 'tests/linux-compat/procselffixture/core.v', area + 'preview-arm.c', area + 'preview-x86.c'] { assert review_text.contains(digest(path)) }
	original_v := git(root, ['show', base + ':tests/linux-compat/procselffixture/core.v'])! + '\n'; final_v := os.read_file(root + 'tests/linux-compat/procselffixture/core.v')!
	for name in ['probe', 'prepare', 'cleanup', 'storage', 'snapshot', 'namespace_child', 'namespace_test', 'qualify'] { assert definition(original_v, name) == definition(final_v, name) }
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/fs/procfs.v\nkernel/proc/proc.v'
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		restore_generated(os.read_file(tree + 'kernel/obj/blob.c')!, os.read_file(area + 'before-' + suffix + '.c')!)
		assert review_text.contains(digest(tree + 'kernel/obj/blob.c')) && review_text.contains(digest(area + 'after-' + suffix + '/procself/serial.log'))
		mut artifacts := {'compiler': digest(compiler + 'v'), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'audit': digest(@FILE),
			'host_tests': digest(area + 'host-tests.log'), 'allocs_before': digest(area + 'allocs-before.log'), 'allocs_after': digest(area + 'allocs-after.log'), 'assertion_control': digest(area + 'assertion-control.log'), 'passing_log_control': digest(area + 'passing-log-control.log'),
			'coverage_check': digest(area + 'coverage-check.log'), 'lifetime_review': digest(review), 'kernel_c': digest(tree + 'kernel/obj/blob.c'), 'kernel_before_c': digest(area + 'before-' + suffix + '.c'), 'preview_c': digest(area + 'preview-' + suffix + '.c')}
		for phase in ['before', 'after'] {
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_log := os.read_file(build)!
			assert build_log.contains('-o bin/vinix') && !build_log.contains('Error ') && !build_log.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
			state := area + phase + '-' + suffix; kernel_hash := digest(if phase == 'before' { area + 'before-' + suffix + '.kernel' } else { tree + 'kernel/bin/vinix' }); artifacts[phase + '_kernel'] = kernel_hash
			data := receipt(state, arch, kernel_hash, if phase == 'before' { ['procself'] } else { ['procself', 'nnpthread', 'seccompthread', 'namespace', 'open', 'runtime'] }, phase == 'before')!
			for key, value in data { artifacts[phase + '_' + key] = value }
			assert data['procself_source'] == digest(root + 'tests/linux-compat/procselffixture/core.v') && data['procself_c'] == digest(area + 'preview-' + suffix + '.c')
			log := os.read_file(state + '/procself/serial.log')!
			if phase == 'before' { failure(log) } else { success(log, arch); assert !log.contains('LINUX PROCSELF STAT DETAIL:') && log.contains('LINUX PROCSELF MUSL SCHED: process wrappers refuse ENOSYS') && log.contains('LINUX PROCSELF SETUP: setrlimit=0 errno=0'); assert os.read_file(state + '.log')!.contains('Linux compatibility guest suite: PASS') }
			publish(state + '.log', out + 'procstat-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'procstat-' + phase + '-' + arch + '.json')!
		}
		for draft in ['initial-before', 'diagnostic'] {
			state := area + draft + '-' + suffix; expected := artifacts[if draft == 'initial-before' { 'before_kernel' } else { 'after_kernel' }]
			data := receipt(state, arch, expected, ['procself'], true)!
			for key, value in data { artifacts[draft + '_' + key] = value }
			log := os.read_file(state + '/procself/serial.log')!; assert !log.contains('LINUX PROCSELF OUTCOMES:')
			if draft == 'diagnostic' { assert log.contains('LINUX PROCSELF SETUP: setrlimit=0 errno=0') && log.contains('LINUX PROCSELF FAIL: ordinary policy errno=38') }
			publish(state + '/sources/procselffixture/core.v', out + 'procstat-' + draft + '-fixture.v.txt')!
			publish(state + '.log', out + 'procstat-' + draft + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'procstat-' + draft + '-' + arch + '.json')!
		}
		context := 'Native musl ELF64 selected task stat fields1/18/40/41: validated table-locked Thread supplies namespace TID, own scheduler policy and real-time priority; process paths retain leader identity/policy. Existing formatter ownership/other fields unchanged. Extended procself retains1620 link probes and selected Pid/NSpid controls, plus84 initial named/numeric stat records across root/UID1000 main/fork/pthread readers,3 proc aliases, chroot and inherited-root/own-PID views. Musl pthread scheduling verifies FIFO17/RR33 workers and FIFO23 namespace worker, explicit RLIMIT_RTPRIO99, raw targeted getparam/getscheduler oracle and normal-policy restoration. Baselines fail28 records:12FIFO17+12RR33+4FIFO23, all show leader PID and20/0/0 in priority/rtprio/policy; status/link identities remain correct. Candidates pass named/numeric fields, both namespace columns and200 cycles with120 link probes,6 status checks and12 stat reads per cycle, all live slabs/pages exact. Main reading leader and workers reading leader remain normal. All six compatibility guests and eight host tests pass; existing406ARM/295x86 allocation allowance failures/NEW rows unchanged. Whole C restores baseline by replacing one formatter body, its prototype/definition parameter, one procfs callback and only unused-loop source offsets. Independent source/C/final capture lifetime review approves. Bare previews match actual before/after C; all63 isolated inputs/compiler/controller/build/kernel/C/source/ELF/ISO/log/receipt hashes bound and both negative controls execute. First test incorrectly used stock musl process sched_* wrappers, which return ENOSYS: two silent setup controls were terminated after fixture exit with missing verdicts; diagnostic candidates prove errno38 before any matrix. Draft sources/C/logs/failed receipts retained; final uses real pthread APIs/raw queries and requires unchanged ENOSYS process-wrapper refusal. CPU/fault/state/nice/start/command accounting beyond selected fields, repeated namespace creation/reclamation, scheduler timing, concurrent retirement/unmount/overmount, full mount retention and glibc/translated/ELF32/install/sandbox/portal acceptance remain separate.'
		os.write_file(out + 'procstat-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log'] { publish(area + name, out + 'procstat-' + name)! }
	println('Selected task-stat qualification audit: PASS')
}
