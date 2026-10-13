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
	mut p := os.new_process('git'); p.set_args(command); p.set_redirect_stdio_merged(); p.run()
	output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	assert code == 0, output; return output.trim_space()
}
fn definition(source string, name string) string {
	lines := source.split_into_lines().filter(!it.starts_with(' ') && !it.starts_with('	') && it.contains(' ' + name + '(') && it.ends_with(' {'))
	assert lines.len == 1; return source.all_after(lines[0]).all_before('\n}\n')
}
fn control(args []string, marker string) string {
	mut p := os.new_process(os.executable()); p.set_args(args); p.set_redirect_stdio_merged(); p.run()
	output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }; return output
}
fn canonical(source string) string {
	mut output := strings.new_builder(source.len); mut names := map[string]string{}; mut position := 0
	for position < source.len {
		start := position
		if source[position].is_letter() || source[position] == `_` {
			position++
			for position < source.len && (source[position].is_alnum() || source[position] == `_`) { position++ }
			token := source[start..position]
			if token.starts_with('__discard_') && token.len > 10 && token[10..].bytes().all(it.is_digit() || it == `_`) {
				if token !in names { names[token] = '_return' + names.len.str() }; output.write_string(names[token])
			} else { output.write_string(token) }
		} else { output.write_u8(source[position]); position++ }
	}
	return output.str()
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
fn exec_observations(log string, arch string, passing bool) {
	rows := log.split_into_lines().filter(it.starts_with('LINUX EXECNAMES OBSERVE:')); assert rows.len == 8
	mut seen := map[string]bool{}; mut reads := [2]u64{}; mut failures := u64(0)
	for row in rows {
		fields := row.fields(); assert fields.len == 8 && fields[7] == 'execs=200'
		group := fields[3].all_after('=').int(); kind := fields[4].all_after('='); key := fields[3] + '-' + kind
		assert group in [0, 1] && kind in ['comm', 'stat', 'status', 'exe'] && key !in seen; seen[key] = true
		n := fields[5].all_after('=').u64(); bad := fields[6].all_after('=').u64(); assert n > 0 && n % 3 == 0 && bad <= n
		if reads[group] == 0 { reads[group] = n } else { assert reads[group] == n }
		if passing { assert bad == 0 }; failures += bad
	}
	mut slabs := [2]int{}; mut pages := [2]int{}; mut slab_keys := map[string]bool{}
	for row in log.split_into_lines() {
		if !row.starts_with('LINUX EXECNAMES SLAB:') && !row.starts_with('LINUX EXECNAMES STORAGE:') { continue }
		fields := row.fields(); assert fields.len == 7; group := fields[3].all_after('=').int(); assert group in [0, 1]
		pair := fields[5].all_after('=').split('/'); assert pair.len == 2 && pair.all(it != '' && it.bytes().all(it.is_digit())) && pair[0] == pair[1]
		if fields[2] == 'SLAB:' { key := fields[3] + '-' + fields[4]; assert key !in slab_keys && fields[6] == 'cycles=200'; slab_keys[key] = true; slabs[group]++ }
		else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS' && pair[0].u64() > 0; pages[group]++ }
	}
	for group in 0 .. 2 { assert slabs[group] == if arch == 'aarch64' { 18 } else { 14 }; assert pages[group] == 1 }
	if passing { assert failures == 0 && !log.contains('LINUX EXECNAMES DETAIL:') && !log.contains('LINUX EXECNAMES FAIL:') && log.split_into_lines().filter(it.trim_space() == 'LINUX EXECNAMES: PASS').len == 1 }
	else { assert failures > 0 && log.contains('LINUX EXECNAMES DETAIL:') && log.contains('LINUX EXECNAMES FAIL:') && !log.split_into_lines().any(it.trim_space() == 'LINUX EXECNAMES: PASS') }
}
fn baseline_failure(log string) {
	assert log.contains('LINUX EXECNAMES DETAIL:'), 'exec baseline failure markers required'
	exec_observations(log, 'x86_64', false)
}
fn receipt(state string, arch string, kernel_hash string, names []string, codes []int) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel_hash && digest(state + '/kernel/bin/vinix') == kernel_hash
	rows := value['results']!.as_array(); assert rows.len == names.len && codes.len == names.len
	mut artifacts := {'receipt': digest(state + '/receipt.json'), 'aggregate': digest(state + '.log')}
	for index, row in rows {
		entry := row.as_map(); name := entry['name']!.str(); assert name == names[index] && entry['exit_code']!.int() == codes[index] && entry['detail']!.str() == ''
		for label, path in {'source': state + '/sources/' + name + 'fixture/core.v', 'init': state + '/' + name + '/init', 'iso': state + '/' + name + '/test.iso'} {
			hash := digest(path); key := if label == 'source' { 'source_sha256' } else if label == 'init' { 'init_sha256' } else { 'iso_sha256' }; assert hash == entry[key]!.str(); artifacts[name + '_' + label] = hash
		}
		assert artifacts[name + '_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/' + name + 'fixture/core.v')
		artifacts[name + '_c'] = digest(state + '/' + name + '/fixture.c'); artifacts[name + '_serial'] = digest(state + '/' + name + '/serial.log')
		log := os.read_file(state + '/' + name + '/serial.log')!
		if codes[index] == 0 { assert log.contains('LINUX ' + name.to_upper() + ': PASS') && !log.contains('LINUX ' + name.to_upper() + ' FAIL') }
		else { assert name == 'execnames' && log.contains('LINUX EXECNAMES FAIL') }
	}
	return artifacts
}
fn kernel_scope(before string, after string, process string) {
	old := definition(before, 'userland__load_program_image'); changed := definition(after, 'userland__load_program_image'); assert old != changed && after.count(changed) == 1
	assert canonical(after.replace(changed, old)) == canonical(before), 'only exec loader body and unused loop source offsets may change entire kernel C'
	metadata := changed.all_after('string new_name = proc__process_name(').all_before('proc__install_command_line(')
	assert metadata.starts_with('path, ' + process + '->pid);') && metadata.count('proc__lock_table();') == 1 && metadata.count('proc__unlock_table();') == 1 && metadata.count('string__free(') == 2
	assert metadata.contains(process + '->name = new_name;') && metadata.contains(process + '->executable_path = program_path;') && !metadata.contains('return ') && !metadata.contains('memdup(') && !metadata.contains('malloc(')
	locked := metadata.index('proc__lock_table();') or { panic('missing metadata lock') }; free_name := metadata.index('string__free(&' + process + '->name);') or { panic('missing old name reclamation') }; free_path := metadata.index('string__free(&' + process + '->executable_path);') or { panic('missing old path reclamation') }
	name := metadata.index(process + '->name = new_name;') or { panic('missing name transfer') }; path := metadata.index(process + '->executable_path = program_path;') or { panic('missing path transfer') }; unlock := metadata.index('proc__unlock_table();') or { panic('missing metadata unlock') }
	assert locked < free_name && free_name < free_path && free_path < name && name < path && path < unlock
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { baseline_failure(os.read_file(os.args[2])!); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/procexec-20261013/'; compiler := '/Users/alex/.cache/vinix-linux-compat/procstate-20261013/compiler/v'
	out := root + 'tests/linux-compat/results/2026-10-13/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'final-after-x86/execnames/serial.log'], 'exec baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '23dbc7b5d02c30bbe549fd5ecf29783c79c308af'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	assert digest(compiler) == 'f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39'
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	for arch in ['aarch64', 'x86_64'] {
		count := arch + ': ' + if arch == 'aarch64' { '657 source files, 403 allocation sites (V exit 0)' } else { '653 source files, 292 allocation sites (V exit 0)' }
		assert before_allocs.contains(count) && after_allocs.contains(count)
	}
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	paths := ['kernel/userland/userland.v', 'kernel/userland/userland_arm64.v']
	review := root + 'tests/linux-compat/results/2026-10-13/procexec-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent exec metadata lifetime review: PASS')
	for path in paths { assert inputs[path] == digest(root + path) && review_text.contains(digest(root + path)) }
	assert review_text.contains(digest(root + 'tests/linux-compat/execnamesfixture/core.v'))
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == paths.join('\n')
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		kernel_c := tree + 'kernel/obj/blob.c'; kernel_scope(os.read_file(area + 'before-' + suffix + '.c')!, os.read_file(kernel_c)!, if suffix == 'arm' { 'curr_process' } else { 'process' }); assert review_text.contains(digest(kernel_c))
		preview := os.read_file(area + 'preview-' + suffix + '.c')!; assert preview.count('alloca(') == 5 && !preview.contains('memdup(') && !preview.contains('malloc(') && !preview.contains('new_array') && !preview.contains('v_fixed_index')
		before_hash := digest(area + 'before-' + suffix + '.kernel'); after_hash := digest(tree + 'kernel/bin/vinix')
		baseline := area + 'final-before-' + suffix; candidate := area + 'final-after-' + suffix
		code := object(baseline + '/receipt.json')!['results']!.as_array()[0].as_map()['exit_code']!.int(); assert code in [0, 1]; if suffix == 'x86' { assert code == 1 }
		before := receipt(baseline, arch, before_hash, ['execnames'], [code])!
		after := receipt(candidate, arch, after_hash, if suffix == 'arm' { ['execnames', 'procself', 'runtime'] } else { ['execnames'] }, if suffix == 'arm' { [0, 0, 0] } else { [0] })!
		assert before['execnames_source'] == after['execnames_source'] && before['execnames_init'] == after['execnames_init'] && before['execnames_c'] == after['execnames_c'] && after['execnames_c'] == digest(area + 'preview-' + suffix + '.c')
		exec_observations(os.read_file(baseline + '/execnames/serial.log')!, arch, code == 0); exec_observations(os.read_file(candidate + '/execnames/serial.log')!, arch, true)
		if suffix == 'x86' { baseline_failure(os.read_file(baseline + '/execnames/serial.log')!) }
		assert review_text.contains(digest(candidate + '/execnames/serial.log'))
		related := if suffix == 'arm' { candidate } else { area + 'completion-x86' }
		proc_log := os.read_file(related + '/procself/serial.log')!; success(proc_log, arch); names(proc_log, true)
		assert os.read_file(related + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && os.read_file(related + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: JIT page sizes')
		mut artifacts := {'compiler': digest(compiler), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'audit': digest(@FILE), 'review': digest(review), 'before_kernel': before_hash, 'after_kernel': after_hash, 'before_kernel_c': digest(area + 'before-' + suffix + '.c'), 'after_kernel_c': digest(kernel_c), 'preview': digest(area + 'preview-' + suffix + '.c')}
		for key, hash in before { artifacts['before_' + key] = hash }; for key, hash in after { artifacts['after_' + key] = hash }
		if suffix == 'x86' {
			completion := receipt(related, arch, after_hash, ['procself', 'runtime'], [0, 0])!
			for key, hash in completion { artifacts['completion_' + key] = hash }
			assert os.read_file(candidate + '.log')!.contains('failed to open file') && !os.read_file(candidate + '.log')!.contains('Linux compatibility guest suite: PASS')
			assert os.read_file(candidate + '.log')!.contains('LINUX PROCSELF: PASS')
			serial := candidate + '/procself/serial.log'
			artifacts['interrupted_procself_serial'] = if os.is_file(serial) { digest(serial) } else { '' }
			if os.is_file(serial) { publish(serial, out + 'procexec-interrupted-x86_64-procself.log')! }
			publish(related + '.log', out + 'procexec-completion-x86_64.log')!; publish(related + '/receipt.json', out + 'procexec-completion-x86_64.json')!
			for fixture in ['procself', 'runtime'] { publish(related + '/' + fixture + '/serial.log', out + 'procexec-completion-x86_64-' + fixture + '.log')! }
		}
		for phase in ['before', 'after'] {
			state := area + 'final-' + phase + '-' + suffix; publish(state + '.log', out + 'procexec-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'procexec-' + phase + '-' + arch + '.json')!
			for fixture in if phase == 'before' || suffix == 'x86' { ['execnames'] } else { ['execnames', 'procself', 'runtime'] } { publish(state + '/' + fixture + '/serial.log', out + 'procexec-' + phase + '-' + arch + '-' + fixture + '.log')! }
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_text := os.read_file(build)!; assert build_text.contains('-o bin/vinix') && !build_text.contains('Error ') && !build_text.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
		}
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		artifacts['draft_after_arm_receipt'] = digest(area + 'after-arm/receipt.json'); artifacts['draft_after_arm_log'] = digest(area + 'after-arm.log')
		assert os.read_file(area + 'after-arm.log')!.contains('No space left on device')
		context := 'Native musl root/UID1000 parents observe a child across 200 actual exec replacements, checking exact comm/stat/status/exe allowlists through three proc mounts. Dumpability is established before the initial gate. Each record snapshots independently; cross-file atomic generations are not promised. The x86 baseline reproduces 27 invalid names; ARM baseline timing passes. Candidates have zero failures, positive concurrent reads and child exit0. Each 200-cycle observer storage cohort reads 12 records after exec completes while the child remains alive: all slabs and large pages stay flat. This does not qualify retention across the entire exec sequence. Procself retains 524 name/API, 156 state, 1620 link and 84 stat/accounting checks; native atomics/SIMD/TLS/JIT/page-size/wide-offset/time64 runtime checks pass. ARM final passes all three cases. X86 final exec passes, then disk exhaustion interrupts procself capture/receipt persistence after its stdout PASS; the valid partial receipt and aggregate error remain. Fresh same-kernel/source completion passes procself/runtime. Same fixture source/C/init ELF before/after. Replacing only the exec loader body restores entire kernel C after unused-loop identifier normalization. Source counts657/653 and allocation sites403/292 remain unchanged, with identical existing allowance refusals. Independent source/C/fixture/capture lifetime review approved. All63 inputs and compiler/controller/kernel/C/source/ELF/ISO/log/build/audit/review hashes are bound. Assertion and passing-log-as-failure controls execute. Early errno-macro compiler and pre-dumpability ARM EACCES fixture drafts remain private; the earlier ARM runtime ENOSPC receipt is separately published. Sibling exec/exit, retirement, full proc ownership, glibc/translated/ELF32 and installation/sandbox/portal acceptance remain separate.'
		os.write_file(out + 'procexec-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log'] { publish(area + name, out + 'procexec-' + name)! }
	// Preserve the real interrupted receipt and errors separately from the
	// fresh final qualification; its earlier fixture is deliberately distinct.
	publish(area + 'after-arm.log', out + 'procexec-draft-after-aarch64.log')!; publish(area + 'after-arm/receipt.json', out + 'procexec-draft-after-aarch64.json')!
	println('Exec metadata qualification audit: PASS')
}
