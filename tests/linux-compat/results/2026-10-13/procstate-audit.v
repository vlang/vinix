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
		else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS'; assert pair[0] == if arch == 'aarch64' { '75' } else { '198' }; pages[group]++ }
	}
	for group in 0 .. 2 { assert counts[group] == if arch == 'aarch64' { 18 } else { 14 }; assert pages[group] == 1 }
	assert log.contains('LINUX PROCSELF CHROOT: no-/proc relative-self/thread-self-status PASS') && log.split_into_lines().filter(it.trim_space() == 'LINUX PROCSELF: PASS').len == 1
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
fn full_definition(source string, name string) string {
	lines := source.split_into_lines().filter(!it.starts_with(' ') && !it.starts_with('\t') && it.contains(' ' + name + '(') && it.ends_with(' {'))
	assert lines.len == 1; return lines[0] + definition(source, name) + '\n}\n\n'
}
fn fixture_reproduction(original string, reproduced string) {
	old_prelude := r'static FILE* v3_eprint_begin(void) {
	fflush(stdout);
	fflush(stderr);
	return stderr;
}
static void v3_eprint_end(void) {
	fflush(stderr);
}
#define v3_eprintf(...) do { fprintf(v3_eprint_begin(), __VA_ARGS__); v3_eprint_end(); } while (0)
static void v3_eprint_lit(const char* s) {
	v3_eprintf("%s", s);
}
static void v3_eprintln_string(string s) {
	v3_eprintf("%.*s\n", s.len, (char*)s.str);
}

'
	new_prelude := r'static void v3_eprint_lit(const char* s) {
	fprintf(stderr, "%s", s);
}
static void v3_eprintln_string(string s) {
	fprintf(stderr, "%.*s\n", s.len, (char*)s.str);
}

'
	assert original.count(old_prelude) == 1 && reproduced.count(new_prelude) == 1
	for name in ['v3_eprint_lit(', 'v3_eprintln_string('] { assert original.count(name) == 1 && reproduced.count(name) == 1 }
	assert original == reproduced.replace(new_prelude, old_prelude), 'only exact unused stderr prelude may differ from private fixture reproduction'
}
fn restore_generated(generated string, baseline string) {
	mut restored := generated
	for name in ['proc__process_stat_line', 'proc__process_status_text'] {
		current := definition(generated, name); previous := definition(baseline, name)
		assert current.contains('proc__task_state(process, target)') && previous.contains('proc__process_state(process)')
		assert generated.count(current) == 1; restored = restored.replace(current, previous)
	}
	new_body := full_definition(generated, 'proc__task_state'); assert restored.count(new_body) == 1 && !new_body.contains('memdup') && !new_body.contains('malloc')
	for needle in ['process->exiting', 'task == NULL', 'task->is_dead', 'process->job_stop_complete', 'task->is_in_queue', 'task->running_on'] { assert new_body.contains(needle) }
	restored = restored.replace(new_body, '')
	new_proto := 'u8 proc__task_state(proc__Process* process, proc__Thread* task);\n'; assert restored.count(new_proto) == 1; restored = restored.replace(new_proto, '')
	old_proto := 'u8 proc__process_state(proc__Process* process);\n'; anchor_proto := 'u8 proc__process_state_unlocked(proc__Process* process);\n'
	assert restored.count(anchor_proto) == 1 && baseline.count(old_proto) == 1 && !restored.contains(old_proto)
	restored = restored.replace(anchor_proto, old_proto + anchor_proto)
	anchor_body := full_definition(restored, 'proc__process_state_unlocked'); assert restored.count(anchor_body) == 1
	restored = restored.replace(anchor_body, full_definition(baseline, 'proc__process_state') + anchor_body)
	assert canonical_discard(restored) == canonical_discard(baseline), 'only two formatter state calls, new helper/pruned aggregate helper and unused-loop source offsets may change whole kernel C'
}
fn states(log string, passing bool) {
	rows := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF STATES:')); assert rows.len == 4
	mut seen := map[string]bool{}
	for row in rows {
		fields := row.fields(); assert fields.len == 7; ordinary := fields[3].all_after('='); reader := fields[4].all_after('='); key := ordinary + '-' + reader
		assert ordinary in ['0', '1'] && reader in ['0', '1'] && key !in seen; seen[key] = true
		assert fields[5] == 'records=30' && fields[6].all_after('=').int() == if passing { 0 } else if reader == '0' { 6 } else { 18 }
	}
	child := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF CHILDSTATE:')); assert child.len == 4; mut children := map[string]bool{}
	for row in child {
		fields := row.fields(); assert fields.len == 7; ordinary := fields[3].all_after('='); code := fields[4].all_after('='); key := ordinary + '-' + code
		assert ordinary in ['0', '1'] && code in ['T', 'Z'] && key !in children; children[key] = true
		assert fields[5].all_after('=').int() == if code == 'T' { 12 } else { 6 }; assert fields[6] == 'failures=0'
	}
	assert !log.contains('LINUX PROCSELF STAT DETAIL:') && !log.contains('LINUX PROCSELF ACCOUNT DETAIL:')
}
fn failure(log string) {
	assert log.contains('LINUX PROCSELF STATE DETAIL:'), 'task-state baseline failure markers required'
	states(log, false); samples(log)
	rows := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF OUTCOMES:')); assert rows.len == 6 && rows.all(it.contains('cases=270 failures=0 status=1'))
	ids := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF TASKIDS:')); assert ids.len == 4 && ids.all(it.trim_space().ends_with('PASS'))
	details := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF STATE DETAIL:')); assert details.len == 48; mut counts := map[string]int{}
	for row in details {
		fields := row.fields(); assert fields.len == 8 && fields[5] == 'actual=R' && fields[6] == 'expected=S'
		path := fields[4].all_after('='); suffix := path.all_after_last('/'); assert suffix in ['stat', 'status']; assert fields[7] == if suffix == 'status' { 'description=0' } else { 'description=1' }
		parts := path.split('/'); mut category := ''
		if parts.len == 2 && parts[0] == 'self' { category = 'self' }
		else if parts.len == 2 { assert parts[0].int() > 1; category = 'process' }
		else { assert parts.len == 4 && parts[1] == 'task' && parts[0].int() > 1 && parts[2].int() > 1; category = if parts[0] == parts[2] { 'leader_task' } else { 'worker_task' } }
		counts[category + '-' + suffix]++
	}
	for category in ['self', 'process', 'leader_task', 'worker_task'] { for suffix in ['stat', 'status'] { assert counts[category + '-' + suffix] == 6 } }
	assert log.contains('LINUX PROCSELF CHROOT: no-/proc relative-self/thread-self-status PASS') && log.contains('LINUX PROCSELF PIDVIEW: outer-and-own leader/worker Pid/Tgid/NSpid PASS')
	assert log.contains('LINUX PROCSELF FAIL:') && !log.split_into_lines().any(it.trim_space() == 'LINUX PROCSELF: PASS')
}
fn partial_receipt(state string, arch string, kernel_hash string, failed string) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel_hash && digest(state + '/kernel/bin/vinix') == kernel_hash
	rows := value['results']!.as_array(); names := ['procself', 'nnpthread', 'seccompthread', 'namespace', 'open', 'runtime']; assert rows.len == names.len
	mut artifacts := {'receipt': digest(state + '/receipt.json'), 'aggregate': digest(state + '.log')}
	assert os.read_file(state + '.log')!.contains('No space left on device') && !os.read_file(state + '.log')!.contains('Linux compatibility guest suite: PASS')
	for index, row in rows {
		entry := row.as_map(); name := entry['name']!.str(); assert name == names[index]
		assert entry['exit_code']!.int() == if name == failed { 1 } else { 0 }; assert entry['detail']!.str() == if name == failed { 'Command failed' } else { '' }
		source := state + '/sources/' + name + 'fixture/core.v'; artifacts[name + '_source'] = digest(source)
		assert artifacts[name + '_source'] == entry['source_sha256']!.str() && artifacts[name + '_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/' + name + 'fixture/core.v')
		for label, path in {'init': state + '/' + name + '/init', 'iso': state + '/' + name + '/test.iso'} {
			wanted := entry[label + '_sha256']!.str()
			if wanted == '' { assert name == failed && !os.exists(path); artifacts[name + '_' + label] = '' }
			else { assert wanted == digest(path); artifacts[name + '_' + label] = wanted }
		}
		for label, path in {'c': state + '/' + name + '/fixture.c', 'serial': state + '/' + name + '/serial.log'} {
			if os.exists(path) { artifacts[name + '_' + label] = digest(path) } else { assert name == failed; artifacts[name + '_' + label] = '' }
		}
		if name != failed { assert os.read_file(state + '/' + name + '/serial.log')!.contains('LINUX ' + name.to_upper() + ': PASS') }
	}
	return artifacts
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/procstate-20261013/'; compiler_source := '/Users/alex/.cache/vinix-linux-compat/compiler-f6358ec/'; compiler := area + 'compiler/'
	out := root + 'tests/linux-compat/results/2026-10-13/'
	if '--kernel-control' in os.args { for suffix in ['arm', 'x86'] { restore_generated(os.read_file(area + 'kernel-' + suffix + '/kernel/obj/blob.c')!, os.read_file(area + 'before-' + suffix + '.c')!) }; println('Selected task-state kernel scope: PASS'); return }
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'after-arm/procself/serial.log'], 'task-state baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == 'd0694ccac90d48f78ddd4d6cafdad0813e314aa9'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	for path in ['kernel/proc/proc.v', 'kernel/proc/state.v'] { assert inputs[path] == digest(root + path) }
	assert git(compiler_source, ['rev-parse', 'HEAD'])! == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c' && git(compiler_source, ['diff', '--name-only', 'HEAD'])! == ''
	assert digest(compiler + 'v') == 'f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39'
	assert os.read_file(area + 'host-tests-pinned.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	assert os.read_file(area + 'verify-kernel-c.log')!.contains('x86: private compiler reproduces complete candidate C') && os.read_file(area + 'verify-baseline-c.log')!.contains('x86: private compiler reproduces complete baseline C')
	drift := os.read_file(area + 'allocs-after-drift.log')!; assert drift.contains('ERROR: x86_64 compiler failed (exit 1); allocation report is incomplete') && !drift.contains('x86_64: 653 source files, 295 allocation sites (V exit 0)')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after-pinned.log')!
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	for arch, row in {'aarch64': '657 source files, 406 allocation sites', 'x86_64': '653 source files, 295 allocation sites'} { assert before_allocs.contains(arch + ': ' + row + ' (V exit 0)') && after_allocs.contains(arch + ': ' + row + ' (V exit 0)') }
	review := root + 'tests/linux-compat/results/2026-10-13/procstate-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent selected task-state lifetime review: PASS')
	for path in [root + 'kernel/proc/proc.v', root + 'kernel/proc/state.v', root + 'tests/linux-compat/procselffixture/core.v', area + 'preview-arm.c', area + 'preview-x86.c'] { assert review_text.contains(digest(path)) }
	original_v := git(root, ['show', base + ':tests/linux-compat/procselffixture/core.v'])! + '\n'; final_v := os.read_file(root + 'tests/linux-compat/procselffixture/core.v')!
	for name in ['probe', 'prepare', 'cleanup', 'status', 'stat_record', 'workload', 'scheduling', 'matrix', 'worker', 'snapshot', 'chroot_test', 'namespace_identity', 'namespace_child', 'namespace_test', 'namespace_worker', 'run'] { assert definition(original_v, name) == definition(final_v, name), name }
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/proc/proc.v\nkernel/proc/state.v'
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		restore_generated(os.read_file(tree + 'kernel/obj/blob.c')!, os.read_file(area + 'before-' + suffix + '.c')!)
		assert review_text.contains(digest(tree + 'kernel/obj/blob.c')) && review_text.contains(digest(area + 'after-' + suffix + '/procself/serial.log'))
		preview := os.read_file(area + 'preview-' + suffix + '.c')!; assert preview.count('alloca(') == 4 && !preview.contains('memdup') && !preview.contains('malloc') && !preview.contains('v_fixed_index') && !preview.contains('new_array')
		fixture_reproduction(preview, os.read_file(area + 'verify-' + suffix + '.c')!)
		for phase in ['kernel', 'baseline'] {
			reproduced := os.read_file(area + 'verify-' + phase + '-' + suffix + '.c')!.replace('call 0(', 'call *(').split('\n').filter(!it.contains('Wimplicit-function-declaration')).join('\n')
			assert reproduced == os.read_file(if phase == 'kernel' { tree + 'kernel/obj/blob.c' } else { area + 'before-' + suffix + '.c' })!
		}
		mut artifacts := {'compiler': digest(compiler + 'v'), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'audit': digest(@FILE),
			'host_tests': digest(area + 'host-tests-pinned.log'), 'allocs_before': digest(area + 'allocs-before.log'), 'allocs_after': digest(area + 'allocs-after-pinned.log'), 'allocs_after_drift': digest(area + 'allocs-after-drift.log'),
			'compiler_pin': digest(area + 'pin-compiler.log'), 'verify_kernel': digest(area + 'verify-kernel-c.log'), 'verify_baseline': digest(area + 'verify-baseline-c.log'), 'reproduced_kernel_c': digest(area + 'verify-kernel-' + suffix + '.c'), 'reproduced_baseline_c': digest(area + 'verify-baseline-' + suffix + '.c'), 'reproduced_fixture_c': digest(area + 'verify-' + suffix + '.c'),
			'coverage_check': digest(area + 'coverage-check.log'), 'review': digest(review), 'baseline_c': digest(area + 'before-' + suffix + '.c'), 'candidate_c': digest(tree + 'kernel/obj/blob.c'), 'preview_c': digest(area + 'preview-' + suffix + '.c')}
		for phase in ['before', 'after'] { build := area + 'build-' + phase + '-' + suffix + '.log'; build_log := os.read_file(build)!; assert build_log.contains('-o bin/vinix') && !build_log.contains('Error ') && !build_log.contains('No space left on device'); artifacts['build_' + phase] = digest(build) }
		before_hash := digest(area + 'before-' + suffix + '.kernel'); after_hash := digest(tree + 'kernel/bin/vinix'); artifacts['before_kernel'] = before_hash; artifacts['after_kernel'] = after_hash
		before := receipt(area + 'before-' + suffix, arch, before_hash, ['procself'], true)!
		missing := if arch == 'aarch64' { 'runtime' } else { 'namespace' }
		after := partial_receipt(area + 'after-' + suffix, arch, after_hash, missing)!
		retry := receipt(area + 'retry-' + suffix, arch, after_hash, [missing], false)!
		for key, value in before { artifacts['before_' + key] = value }; for key, value in after { artifacts['after_' + key] = value }; for key, value in retry { artifacts['retry_' + key] = value }
		for phase in ['before', 'after'] {
			state := area + phase + '-' + suffix; data := if phase == 'before' { before } else { after }
			assert data['procself_source'] == digest(root + 'tests/linux-compat/procselffixture/core.v') && data['procself_c'] == digest(area + 'preview-' + suffix + '.c')
			log := os.read_file(state + '/procself/serial.log')!
			if phase == 'before' { failure(log) } else { success(log, arch); samples(log); states(log, true); assert !log.contains('LINUX PROCSELF STATE DETAIL:') }
			publish(state + '.log', out + 'procstate-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'procstate-' + phase + '-' + arch + '.json')!
		}
		assert retry[missing + '_source'] == after[missing + '_source'] && os.read_file(area + 'retry-' + suffix + '.log')!.contains('Linux compatibility guest suite: PASS')
		publish(area + 'retry-' + suffix + '.log', out + 'procstate-retry-' + arch + '.log')!; publish(area + 'retry-' + suffix + '/receipt.json', out + 'procstate-retry-' + arch + '.json')!
		draft := area + 'promoted-before-' + suffix; draft_receipt := object(draft + '/receipt.json')!
		assert draft_receipt['architecture']!.str() == arch && draft_receipt['kernel_sha256']!.str() == before_hash && digest(draft + '/kernel/bin/vinix') == before_hash
		rows := draft_receipt['results']!.as_array(); assert rows.len == 1; row := rows[0].as_map()
		assert row['name']!.str() == 'procself' && row['exit_code']!.int() == 1 && row['detail']!.str() == 'Command failed' && row['init_sha256']!.str() == '' && row['iso_sha256']!.str() == ''
		assert !os.exists(draft + '/procself/init') && !os.exists(draft + '/procself/test.iso') && !os.exists(draft + '/procself/serial.log')
		assert row['source_sha256']!.str() == digest(draft + '/sources/procselffixture/core.v') && digest(draft + '/procself/fixture.c') == digest(area + 'promoted-preview-' + suffix + '.c')
		assert os.read_file(draft + '/procself/fixture.c')!.contains('memdup(&_t1, sizeof(procselffixture__StateWorker))') && os.read_file(draft + '.log')!.contains("function 'memdup'")
		for label, path in {'source': draft + '/sources/procselffixture/core.v', 'c': draft + '/procself/fixture.c', 'receipt': draft + '/receipt.json', 'aggregate': draft + '.log'} { artifacts['promoted_' + label] = digest(path) }
		publish(draft + '/sources/procselffixture/core.v', out + 'procstate-promoted-fixture.v.txt')!
		publish(draft + '.log', out + 'procstate-promoted-before-' + arch + '.log')!; publish(draft + '/receipt.json', out + 'procstate-promoted-before-' + arch + '.json')!
		context := 'Native musl selected task stat field3 and status State now use table-retained task exit/dead/job-stop/runnable/running_on scalars. Leader/process paths select the leader even while a sibling runs; no list lock/new ownership/allocation. Source aggregate helper stays for other callers and is pruned when unused; SysRq process_state_unlocked unchanged. Root/UID1000 leader and pipe-backed worker alternate actual blocked reads:120 initial R/S records across3 aliases and self/thread-self/numeric process/leader/worker task paths, plus24 stopped process/task and12 zombie process controls. Baselines fail48 R-for-S records (main6+worker18 each cohort), with all existing1620 links,84identity/scheduling/accounting stat records, positive256/32/64faults,200/50/100ms CPU work, namespaces/chroot and T/Z controls passing. Candidates pass all156 initial state records and200cycles of120links+6status+12accountingstat+30state reads per cohort; held StateWorker/two pipe pairs keep every live slab flat and75ARM/198x86bigpages exact. Corrected fixture uses4 explicit allocas, no memdup/malloc/new_array/bounds runtime; join precedes all4FD closes, failures exit, child cleanup reaps. Original promoted StateWorker caused both native CC failures before ELF/ISO/guest; draft source/C/log/failed receipts retained. Primary candidates each pass5cases; disk exhaustion prevents ARM runtime ISO and x86 namespace tool compilation. Failed primary receipts remain code1 with actual errors/artifacts; fresh same-kernel/source targeted recovery receipts supply missing sixth verdict. All six semantic verdicts pass across primary+recovery, no claim primary aggregate passed. Private clean-source f6358ec compiler reproducer has a different executable hash from the earlier build binary but regenerates all4captured kernel C exactly. Its fixture C differs only by an exact unused stderr-print prelude: replacing that whole validated block reproduces original C, with both print helpers referenced only by their definitions. Actual guest C still equals original previews. Original shared executable was observed reportinga27079a; first after-allocation scan is incomplete and retained. Private pinned re-audit restores406ARM/295x86 allowance refusals/NEW rows and eight host tests pass;63input coverage passes. Whole C restores by replacing2formatter bodies, removing task helper and reinserting pruned aggregate helper at original prototype/definition sites, with only unused-loop names normalized. Independent source/C/final capture review approved; compiler/controller/build/kernel/C/source/ELF/ISO/capture/review receipts and inputs bound and negative controls execute. Zombie task directories/leader-only thread exit, stop-transition windows, D/t/X/I states, cgroup holding, scheduler retirement races, full proc mount retention and glibc/translated/ELF32/install/sandbox/portal acceptance remain separate.'
		os.write_file(out + 'procstate-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests-pinned.log', 'allocs-before.log', 'allocs-after-pinned.log', 'allocs-after-drift.log', 'pin-compiler.log', 'verify-kernel-c.log', 'verify-baseline-c.log', 'coverage-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log'] { publish(area + name, out + 'procstate-' + name)! }
	println('Selected task-state qualification audit: PASS')
}
