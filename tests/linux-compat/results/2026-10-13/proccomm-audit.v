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
		else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS'; assert pair[0].int() > 0; pages[group]++ }
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
fn names(log string, passing bool) {
	api := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF NAMEAPI:')); assert api.len == 20
	mut api_seen := map[string]bool{}
	for row in api {
		fields := row.fields(); assert fields.len == 6; ordinary := fields[3].all_after('='); name := fields[4].all_after('='); key := ordinary + '-' + name
		assert ordinary in ['0', '1'] && name in ['short', 'fifteen', 'empty', 'unterminated', 'null', 'wrap', 'protected', 'get-null', 'get-readonly', 'truncated'] && key !in api_seen; api_seen[key] = true
		assert fields[5].all_after('=').int() == if !passing && name in ['short', 'fifteen', 'empty'] { 0 } else { 1 }
	}
	rows := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF NAMES:')); assert rows.len == 8
	mut seen := map[string]bool{}
	for row in rows {
		fields := row.fields(); assert fields.len == 8; ordinary := fields[3].all_after('='); phase := fields[4].all_after('=').int(); key := ordinary + '-' + phase.str()
		assert ordinary in ['0', '1'] && phase in [0, 1, 2, 3] && key !in seen; seen[key] = true
		assert fields[5] == 'records=45' && fields[6].all_after('=').int() == if passing { 0 } else if phase == 2 { 42 } else if phase == 3 { 39 } else { 36 }
		assert fields[7].all_after('=').int() == if !passing && phase == 2 { 0 } else { 1 }
	}
	for kind in ['NAMEINHERIT', 'NAMEEXEC'] {
		controls := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF ' + kind + ':')); assert controls.len == 2
		mut seen_controls := map[string]bool{}
		for row in controls {
			fields := row.fields(); assert fields.len == 7; key := fields[3].all_after('=')
			assert key in if kind == 'NAMEEXEC' { ['0', '1000'] } else { ['0', '1'] }; assert key !in seen_controls; seen_controls[key] = true
			assert fields[4] == 'records=36' && fields[5].all_after('=').int() == if !passing && kind == 'NAMEINHERIT' { 36 } else { 0 }
			assert fields[6].all_after('=').int() == if passing { 1 } else { 0 }
		}
	}
	details := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF NAME DETAIL:'))
	assert details.len == if passing { 0 } else { 306 }
	if !passing {
		mut phases := [4]int{}; mut formats := [3]int{}
		for row in details {
			fields := row.fields(); assert fields.len == 8 && fields[4].starts_with('path=')
			phase := fields[5].all_after('=').int(); format := fields[6].all_after('=').int(); assert phase in [0, 1, 2, 3] && format in [0, 1, 2]
			assert fields[7] == if phase >= 2 { 'empty=1' } else { 'empty=0' }; phases[phase]++; formats[format]++
			assert fields[4].ends_with(if format == 0 { '/stat' } else if format == 1 { '/status' } else { '/comm' })
		}
		assert phases == [72, 72, 84, 78]! && formats == [120, 120, 66]!
	}
	samples(log); states(log, true)
}
fn failure(log string) {
	assert log.contains('LINUX PROCSELF NAME DETAIL:'), 'task-name baseline failure markers required'
	names(log, false)
	rows := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF OUTCOMES:')); assert rows.len == 6 && rows.all(it.contains('cases=270 failures=0 status=1'))
	ids := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF TASKIDS:')); assert ids.len == 4 && ids.all(it.trim_space().ends_with('PASS'))
	assert log.contains('LINUX PROCSELF CHROOT: no-/proc relative-self/thread-self-status PASS') && log.contains('LINUX PROCSELF PIDVIEW: outer-and-own leader/worker Pid/Tgid/NSpid PASS')
	assert log.contains('LINUX PROCSELF FAIL:') && !log.split_into_lines().any(it.trim_space() == 'LINUX PROCSELF: PASS')
}
fn kernel_check(source string) {
	prctl := definition(source, 'table__syscall_linux_prctl')
	assert !prctl.contains('memdup(') && prctl.count('vinix_stack_alloc(table__task_comm_len)') == 2
	assert prctl.contains('current->comm_named = true;') && prctl.contains('proc__copy_current_command') && prctl.contains('proc__lock_table()') && prctl.contains('proc__unlock_table()')
	for name in ['proc__selected_command_bounds', 'proc__add_task_command', 'proc__copy_current_command'] {
		body := definition(source, name); assert !body.contains('memdup(') && !body.contains('malloc(') && !body.contains('new_array')
	}
	assert source.count('bool comm_named;') == 1 && definition(source, 'sched__new_cloned_thread').contains('.comm_named = source->comm_named')
}
fn partial_receipt(state string, arch string, kernel_hash string) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel_hash && digest(state + '/kernel/bin/vinix') == kernel_hash
	rows := value['results']!.as_array(); names := ['procself', 'nnpthread', 'seccompthread', 'namespace', 'open', 'runtime']; assert rows.len == names.len
	mut artifacts := {'receipt': digest(state + '/receipt.json'), 'aggregate': digest(state + '.log')}
	assert os.read_file(state + '.log')!.contains('No space left on device') && !os.read_file(state + '.log')!.contains('Linux compatibility guest suite: PASS')
	for index, row in rows {
		entry := row.as_map(); name := entry['name']!.str(); assert name == names[index]; failed := index >= 3
		assert entry['exit_code']!.int() == if failed { 1 } else { 0 }; assert entry['detail']!.str() == if failed { 'Command failed' } else { '' }
		artifacts[name + '_source'] = digest(state + '/sources/' + name + 'fixture/core.v')
		assert artifacts[name + '_source'] == entry['source_sha256']!.str() && artifacts[name + '_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/' + name + 'fixture/core.v')
		for label, path in {'init': state + '/' + name + '/init', 'iso': state + '/' + name + '/test.iso'} {
			wanted := entry[label + '_sha256']!.str()
			if wanted == '' { assert failed && !os.exists(path); artifacts[name + '_' + label] = '' }
			else { assert wanted == digest(path); artifacts[name + '_' + label] = wanted }
		}
		for label, path in {'c': state + '/' + name + '/fixture.c', 'serial': state + '/' + name + '/serial.log'} {
			if os.exists(path) { artifacts[name + '_' + label] = digest(path) } else { assert failed; artifacts[name + '_' + label] = '' }
		}
		if !failed { assert os.read_file(state + '/' + name + '/serial.log')!.contains('LINUX ' + name.to_upper() + ': PASS') }
	}
	return artifacts
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/proccomm-20261013/'; compiler := '/Users/alex/.cache/vinix-linux-compat/procstate-20261013/compiler/v'
	out := root + 'tests/linux-compat/results/2026-10-13/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'after-arm/procself/serial.log'], 'task-name baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '708f21f5fe7d79027ad70db692cbc3c77e43a205'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	assert digest(compiler) == 'f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39'
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	for arch in ['aarch64', 'x86_64'] {
		assert before_allocs.contains(arch + ': ' + if arch == 'aarch64' { '657 source files, 406 allocation sites (V exit 0)' } else { '653 source files, 295 allocation sites (V exit 0)' })
		assert after_allocs.contains(arch + ': ' + if arch == 'aarch64' { '657 source files, 403 allocation sites (V exit 0)' } else { '653 source files, 292 allocation sites (V exit 0)' })
	}
	old_new := before_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	wanted_new := old_new.filter(!it.starts_with('NEW: syscall/table/linux_common.v local moved to the heap:')).map(it.replace('NEW: proc/proc.v local moved to the heap: its address escapes: 2, allowed 0', 'NEW: proc/proc.v local moved to the heap: its address escapes: 1, allowed 0'))
	assert after_allocs.split_into_lines().filter(it.starts_with('NEW:')) == wanted_new
	paths := ['kernel/proc/proc.v', 'kernel/proc/proc_amd64.v', 'kernel/proc/proc_arm64.v', 'kernel/sched/sched_amd64.v', 'kernel/sched/sched_arm64.v', 'kernel/syscall/table/linux_common.v']
	review := root + 'tests/linux-compat/results/2026-10-13/proccomm-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent selected task-name lifetime review: PASS')
	for path in paths { assert inputs[path] == digest(root + path) && review_text.contains(digest(root + path)) }
	assert review_text.contains(digest(root + 'tests/linux-compat/procselffixture/core.v'))
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == paths.join('\n')
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		c := os.read_file(tree + 'kernel/obj/blob.c')!; kernel_check(c); assert review_text.contains(digest(tree + 'kernel/obj/blob.c'))
		for body_name in ['proc__process_stat_line', 'proc__process_status_text', 'proc__process_command', 'proc__thread_command'] { assert definition(c, body_name).contains('proc__add_task_command(') }
		baseline_prctl := definition(os.read_file(area + 'before-' + suffix + '.c')!, 'table__syscall_linux_prctl'); assert baseline_prctl.count('memdup(') == 2
		preview := os.read_file(area + 'preview-' + suffix + '.c')!; assert preview.count('alloca(') == 4 && !preview.contains('memdup(') && !preview.contains('malloc(') && !preview.contains('new_array') && !preview.contains('v_fixed_index')
		before_hash := digest(area + 'before-' + suffix + '.kernel'); after_hash := digest(tree + 'kernel/bin/vinix')
		before := receipt(area + 'before-' + suffix, arch, before_hash, ['procself'], true)!
		after := if arch == 'aarch64' { receipt(area + 'after-' + suffix, arch, after_hash, ['procself', 'nnpthread', 'seccompthread', 'namespace', 'open', 'runtime'], false)! } else { partial_receipt(area + 'after-' + suffix, arch, after_hash)! }
		assert before['procself_source'] == after['procself_source'] && before['procself_init'] == after['procself_init'] && before['procself_c'] == after['procself_c'] && after['procself_c'] == digest(area + 'preview-' + suffix + '.c')
		failure(os.read_file(area + 'before-' + suffix + '/procself/serial.log')!)
		log := os.read_file(area + 'after-' + suffix + '/procself/serial.log')!; success(log, arch); names(log, true); assert review_text.contains(digest(area + 'after-' + suffix + '/procself/serial.log'))
		mut artifacts := {'compiler': digest(compiler), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'audit': digest(@FILE), 'review': digest(review), 'before_kernel': before_hash, 'after_kernel': after_hash, 'before_kernel_c': digest(area + 'before-' + suffix + '.c'), 'after_kernel_c': digest(tree + 'kernel/obj/blob.c'), 'preview': digest(area + 'preview-' + suffix + '.c')}
		for key, value in before { artifacts['before_' + key] = value }; for key, value in after { artifacts['after_' + key] = value }
		if arch == 'x86_64' {
			retry := receipt(area + 'retry-x86', arch, after_hash, ['namespace', 'open', 'runtime'], false)!
			for name in ['namespace', 'open', 'runtime'] { assert retry[name + '_source'] == after[name + '_source'] }
			for key, value in retry { artifacts['retry_' + key] = value }
			assert os.read_file(area + 'retry-x86.log')!.contains('Linux compatibility guest suite: PASS')
			publish(area + 'retry-x86.log', out + 'proccomm-retry-x86_64.log')!; publish(area + 'retry-x86/receipt.json', out + 'proccomm-retry-x86_64.json')!
		}
		for phase in ['before', 'after'] {
			publish(area + phase + '-' + suffix + '.log', out + 'proccomm-' + phase + '-' + arch + '.log')!
			publish(area + phase + '-' + suffix + '/receipt.json', out + 'proccomm-' + phase + '-' + arch + '.json')!
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_log := os.read_file(build)!; assert build_log.contains('-o bin/vinix') && !build_log.contains('Error ') && !build_log.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
		}
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		context := 'Native musl selected task comm/stat/status names now use table-retained explicit comm, preserving empty and slash/bracket/parenthesis/backslash/newline bytes; status escapes newline/backslash and raw formats remain exact. Explicit empty flag inherits in both clone implementations. PR_SET_NAME reads at most15 bytes, stops at NUL, uses real EFAULT without mutation; PR_GET_NAME snapshots basename/explicit name and writes all16zero-padded bytes. All524initial record/API checks pass:360phase name records+72empty-fork+72exec-reset records+20prctl boundary/error/truncation controls; inherited and exec GET_NAME controls also pass. Baseline has306phase failures+72inherited failures, six short/fifteen/empty boundary failures, and empty-worker/inherited/exec GET_NAME failures; old156state/1620link/84stat/PID-view/chroot/accounting controls pass. Same frozen source, generated C and native init ELF used before/after. Both legacy prctl scratch arrays were promoted and never freed; pointer annotations still promoted them. Final uses explicit kernel stack buffers with no memdup; original/promoted/address C remain private controls. Old thread-command heap Text becomes explicit stack. Each200-cyclecohort includes120link+6status+12accountingstat+30state+90name reads and two SET/GET roundtrips; all slab classes and large-page counts stay exact. All six native guest verdicts pass across primary/recovery captures. ARM primary passes all6; x86 primary passes3 and host disk exhaustion prevents namespace ISO and open/runtime tool compilation. Failed x86 primary receipt, missing-artifact fields and errors remain; fresh same-kernel/source recovery passes those3. Eight host files pass. Source files657/653, allocation sites406/295before versus403/292after; only known2table escapes removed and knownproc2escapes reducedto1, other NEW rows unchanged and no allowances changed. Independent source/C/capture review approves new lifetime; all63isolatedinputs plus compiler/controller/kernel/C/source/ELF/ISO/capture/build/audit/review hashes bound, bothnegativecontrols execute. Concurrent rename observer timing, exec/retirement races, named zombie/leader-only exit, writable proc comm, glibc/foreign ABIs and application installation/sandbox/portal acceptance remain separate.'
		os.write_file(out + 'proccomm-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log'] { publish(area + name, out + 'proccomm-' + name)! }
	println('Selected task-name qualification audit: PASS')
}
