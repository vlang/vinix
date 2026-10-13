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
	for needle in ['proc__thread_cpu_times(target, 0)', 'proc__process_cpu_times(process, 0)', 'target->usage.minor_faults', 'target->usage.major_faults', 'proc__lock_table', 'proc__unlock_table'] { assert current.contains(needle), needle }
	assert generated.count(current) == 1
	assert canonical_discard(generated.replace(current, previous)) == canonical_discard(baseline), 'only stat accounting body and unused-loop source offsets may change whole kernel C'
}
fn samples(log string) {
	rows := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF ACCOUNT SAMPLE:')); assert rows.len == 6
	mut seen := map[string]bool{}
	for row in rows {
		fields := row.fields(); assert fields.len == 8
		ordinary := fields[4].all_after('='); slot := fields[5].all_after('=').int(); key := ordinary + '-' + slot.str()
		assert ordinary in ['0', '1'] && slot in [0, 1, 2] && key !in seen; seen[key] = true
		faults := fields[6].all_after('=').split('/'); ticks := fields[7].all_after('=').split('/'); assert faults.len == 2 && ticks.len == 2
		assert faults[0].int() >= if slot == 0 { 256 } else { slot * 32 }
		if slot != 0 { assert faults[1].int() > faults[0].int() && ticks[1].int() - ticks[0].int() >= 10 }
	}
	work := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF WORK:')); assert work.len == 6
	mut counts := [3]int{}
	for row in work {
		fields := row.fields(); assert fields.len == 8; slot := fields[3].all_after('=').int(); assert slot in [0, 1, 2]; counts[slot]++
		pages := fields[4].all_after('=').int(); assert pages == if slot == 0 { 256 } else { slot * 32 }
		assert fields[5].all_after('=').int() >= pages && fields[6].all_after('=').i64() >= if slot == 0 { i64(200000000) } else { i64(slot * 50000000) }
		assert fields[7].all_after('=').u64() != 0
	}
	assert counts == [2, 2, 2]!
}
fn failure(log string) {
	assert log.contains('LINUX PROCSELF ACCOUNT DETAIL:'), 'task-account baseline failure markers required'
	samples(log)
	assert !log.contains('LINUX PROCSELF STAT DETAIL:')
	rows := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF OUTCOMES:'))
	assert rows.len == 6 && rows.all(it.contains('cases=270 failures=0')) && rows.filter(it.contains('slot=0') && it.contains('status=1')).len == 2 && rows.filter(!it.contains('slot=0') && it.contains('status=0')).len == 4
	details := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF ACCOUNT DETAIL:')); assert details.len == 28
	mut counts := map[string]int{}
	for row in details {
		fields := row.fields(); assert fields.len == 10 && fields[5] == 'task=1'
		minor := fields[6].all_after('=').replace(':', '/').split('/'); major := fields[7].all_after('=').replace(':', '/').split('/'); user := fields[8].all_after('=').replace(':', '/').split('/')
		assert minor.len == 3 && major == ['0', '0', '0'] && user.len == 3
		assert minor[1] in ['0', '32', '64'] && minor[2] == minor[1] && minor[0].int() > minor[2].int()
		if minor[1] != '0' { assert user[0].int() > user[2].int() }
		counts[minor[1]]++
	}
	assert counts['32'] == 12 && counts['64'] == 12 && counts['0'] == 4
	ids := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF TASKIDS:'))
	assert ids.len == 4 && ids.filter(it.contains('leader=1') && it.trim_space().ends_with('PASS')).len == 2 && ids.filter(it.contains('leader=0') && it.trim_space().ends_with('FAIL')).len == 2
	for row in ids { fields := row.fields(); assert fields.len == 11; pair := fields[5].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] }
	assert log.contains('LINUX PROCSELF CHROOT: no-/proc relative-self/thread-self-status PASS') && log.contains('LINUX PROCSELF PIDVIEW: outer-and-own leader/worker Pid/Tgid/NSpid FAIL')
	assert log.contains('LINUX PROCSELF FAIL:') && !log.split_into_lines().any(it.trim_space() == 'LINUX PROCSELF: PASS')
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/procaccount-20261013/'; compiler := '/Users/alex/.cache/vinix-linux-compat/compiler-f6358ec/'
	out := root + 'tests/linux-compat/results/2026-10-13/'
	if '--kernel-control' in os.args { for suffix in ['arm', 'x86'] { restore_generated(os.read_file(area + 'kernel-' + suffix + '/kernel/obj/blob.c')!, os.read_file(area + 'before-' + suffix + '.c')!) }; println('Selected task-account kernel scope: PASS'); return }
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'after-arm/procself/serial.log'], 'task-account baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '9880153c2832ad17b0b82c162441cdbc45b1b9d9'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	assert inputs['kernel/proc/proc.v'] == digest(root + 'kernel/proc/proc.v')
	assert git(compiler, ['rev-parse', 'HEAD'])! == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c' && git(compiler, ['diff', '--name-only', 'HEAD'])! == ''
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	for arch, row in {'aarch64': '657 source files, 406 allocation sites', 'x86_64': '653 source files, 295 allocation sites'} { assert before_allocs.contains(arch + ': ' + row + ' (V exit 0)') && after_allocs.contains(arch + ': ' + row + ' (V exit 0)') }
	review := root + 'tests/linux-compat/results/2026-10-13/procaccount-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent selected task-account lifetime review: PASS')
	for path in [root + 'kernel/proc/proc.v', root + 'tests/linux-compat/procselffixture/core.v', area + 'preview-arm.c', area + 'preview-x86.c'] { assert review_text.contains(digest(path)) }
	original_v := git(root, ['show', base + ':tests/linux-compat/procselffixture/core.v'])! + '\n'; final_v := os.read_file(root + 'tests/linux-compat/procselffixture/core.v')!
	for name in ['probe', 'prepare', 'cleanup', 'storage', 'snapshot', 'namespace_child', 'namespace_test', 'namespace_worker', 'scheduling', 'cycle', 'chroot_test', 'run'] { assert definition(original_v, name) == definition(final_v, name), name }
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/proc/proc.v'
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		restore_generated(os.read_file(tree + 'kernel/obj/blob.c')!, os.read_file(area + 'before-' + suffix + '.c')!)
		assert review_text.contains(digest(tree + 'kernel/obj/blob.c')) && review_text.contains(digest(area + 'after-' + suffix + '/procself/serial.log'))
		mut artifacts := {'compiler': digest(compiler + 'v'), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'audit': digest(@FILE),
			'host_tests': digest(area + 'host-tests.log'), 'allocs_before': digest(area + 'allocs-before.log'), 'allocs_after': digest(area + 'allocs-after.log'),
			'coverage_check': digest(area + 'coverage-check.log'), 'review': digest(review), 'baseline_c': digest(area + 'before-' + suffix + '.c'), 'candidate_c': digest(tree + 'kernel/obj/blob.c'), 'preview_c': digest(area + 'preview-' + suffix + '.c')}
		for phase in ['before', 'after'] {
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_log := os.read_file(build)!
			assert build_log.contains('-o bin/vinix') && !build_log.contains('Error ') && !build_log.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
			state := area + phase + '-' + suffix; kernel_hash := digest(if phase == 'before' { area + 'before-' + suffix + '.kernel' } else { tree + 'kernel/bin/vinix' }); artifacts[phase + '_kernel'] = kernel_hash
			data := receipt(state, arch, kernel_hash, if phase == 'before' { ['procself'] } else { ['procself', 'nnpthread', 'seccompthread', 'namespace', 'open', 'runtime'] }, phase == 'before')!
			for key, value in data { artifacts[phase + '_' + key] = value }
			assert data['procself_source'] == digest(root + 'tests/linux-compat/procselffixture/core.v') && data['procself_c'] == digest(area + 'preview-' + suffix + '.c')
			log := os.read_file(state + '/procself/serial.log')!
			if phase == 'before' { failure(log) } else { success(log, arch); samples(log); assert !log.contains('LINUX PROCSELF ACCOUNT DETAIL:') && !log.contains('LINUX PROCSELF STAT DETAIL:'); assert os.read_file(state + '.log')!.contains('Linux compatibility guest suite: PASS') }
			publish(state + '.log', out + 'procaccount-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'procaccount-' + phase + '-' + arch + '.json')!
		}
		state := area + 'eager-before-' + suffix; data := receipt(state, arch, artifacts['before_kernel'], ['procself'], true)!
		for key, value in data { artifacts['eager_before_' + key] = value }
		assert data['procself_c'] == digest(area + 'eager-preview-' + suffix + '.c')
		draft_log := os.read_file(state + '/procself/serial.log')!; assert draft_log.contains('LINUX PROCSELF ACCOUNT DETAIL:') && !draft_log.contains('pages=32 faults=')
		if arch == 'aarch64' { assert draft_log.contains('slot=1 faults=0/') && draft_log.contains('slot=2 faults=0/') }
		publish(state + '/sources/procselffixture/core.v', out + 'procaccount-eager-fixture.v.txt')!
		publish(state + '.log', out + 'procaccount-eager-before-' + arch + '.log')!; publish(state + '/receipt.json', out + 'procaccount-eager-before-' + arch + '.json')!
		context := 'Native musl selected task stat fields10/12/14/15: task fault counters and existing table-retained CPU snapshots; process paths preserve lifetime sibling totals and include unfinished turns. Four selected fields only; child counters, identities/scheduling/Text ownership unchanged. Extended procself brackets84 named/numeric stat records with RUSAGE_THREAD/SELF at100Hz, preserves1620 link probes,3 aliases, root/UID1000 main/fork/pthreads, chroot, inherited-root/own-PID views and FIFO17/RR33/FIFO23 controls. Each leader/worker64MiB demand reservation touches256/32/64 sysconf-sized pages and requires positive minor delta>=touches with unchanged majors; CPU work lasts200/50/100ms by thread clock and nonzero retained checksum. Samples require workers own fault counts and >=10 fewer CPU ticks than process. Both baselines fail28 task accounting records:12own32+12own64+4namespace-own0, each wrong minor>oracle,24normal worker user ticks exceed bracket; all major values0 and identities/scheduling/link/status fields remain correct. Candidates pass source-bound before/read/after fault+tick ranges;200 cycles repeat120links+6status+12stat reads with exact live slabs and63ARM/160x86pages. Six guest cases and eight host test files pass. Known406ARM/295x86 allocation allowance refusals/NEW rows unchanged. One formatter body plus only unused-loop source offsets restores whole generated C. Independent review verifies pid->threads->CPU and pid->CPU lock order, scalar snapshots, stack rusage/clock outputs, unmapping before clock failures, FD close/error paths and worker joins. All63 isolated inputs/compiler/controller/build/kernel/C/source/ELF/ISO/capture/receipt hashes bound and negative controls execute. Original eager-size draft baseline failures retained with original source/C/log/receipts: ARM touches produced no demand faults; final uses64MiB on both to prove positive faults. Major disk-fault production, child-time accounting, clock wrap/overflow, timer/scheduler timing, state/nice/start/name, repeated namespace creation/reclamation, concurrent retirement/unmount and glibc/translated/ELF32/install/sandbox/portal acceptance remain separate.'
		os.write_file(out + 'procaccount-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log'] { publish(area + name, out + 'procaccount-' + name)! }
	println('Selected task-account qualification audit: PASS')
}
