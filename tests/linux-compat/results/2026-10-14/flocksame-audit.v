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
	mut p := os.new_process('git'); p.set_args(command); p.set_redirect_stdio_merged(); p.run()
	output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	assert code == 0, output; return output.trim_space()
}
fn control(args []string, marker string) string {
	mut p := os.new_process(os.executable()); p.set_args(args); p.set_redirect_stdio_merged(); p.run()
	output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }; return output
}
fn semantics(log string, passing bool, reference bool, arch string) {
	assert arch in ['aarch64', 'x86_64']
	rows := log.split_into_lines().filter(it.starts_with('LINUX FLOCKSAME CASES:')); assert rows.len == 8
	mut seen := map[string]bool{}
	for row in rows {
		fields := row.fields(); assert fields.len == 7 && fields[3].starts_with('ordinary=') && fields[4].starts_with('kind=') && fields[5].starts_with('calls=') && fields[6].starts_with('failures=')
		group := fields[3].all_after('='); kind := fields[4].all_after('=').int(); key := group + '-' + kind.str()
		assert group in ['0', '1'] && kind in [0, 1, 2, 3] && key !in seen; seen[key] = true
		assert fields[5].all_after('=').int() == if passing { [192, 192, 240, 344]![kind] } else { [192, 192, 240, 344]![kind] }
		assert fields[6].all_after('=').int() == if passing { 0 } else if arch == 'x86_64' && group == '0' { [191, 191, 12, 0]![kind] } else { [192, 192, 12, 0]![kind] }
	}
	if passing { assert !log.contains('LINUX FLOCKSAME DETAIL:') && !log.contains('LINUX FLOCKSAME FAIL:') }
	else { assert log.contains('LINUX FLOCKSAME DETAIL:') && log.contains('LINUX FLOCKSAME FAIL:') && !log.contains('LINUX FLOCKSAME: PASS') }
	if reference { assert passing && log.contains('LINUX FLOCKSAME REFERENCE: PASS') && log.contains('Linux version 6.12.51-0-virt') && !log.contains('Kernel panic') && !log.contains('LINUX FLOCKSAME STORAGE:') }
	else if passing { assert log.split_into_lines().filter(it.trim_space() == 'LINUX FLOCKSAME: PASS').len == 1 && !log.contains('LINUX FLOCKSAME REFERENCE: PASS') }
}
fn failure(log string, arch string) { assert log.contains('LINUX FLOCKSAME DETAIL:'), 'flocksame baseline failure markers required'; semantics(log, false, false, arch) }
fn storage(log string, arch string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines() {
		if !row.starts_with('LINUX FLOCKSAME SLAB:') && !row.starts_with('LINUX FLOCKSAME STORAGE:') { continue }
		fields := row.fields(); assert fields.len == 7; group := fields[3].all_after('=').int(); assert group in [0, 1]
		pair := fields[5].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' { key := fields[3] + '-' + fields[4]; assert key !in seen && fields[6] == 'cycles=200'; seen[key] = true; slabs[group]++ }
		else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS' && pair[0].int() == if arch == 'aarch64' { 63 } else { 160 }; pages[group]++ }
	}
	for group in 0 .. 2 { assert slabs[group] == if arch == 'aarch64' { 18 } else { 14 }; assert pages[group] == 1 }
}

fn receipt(state string, arch string, kernel string, names []string, failing bool) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel && digest(state + '/kernel/bin/vinix') == kernel
	rows := value['results']!.as_array(); assert rows.len == names.len
	mut artifacts := {'receipt': digest(state + '/receipt.json'), 'aggregate': digest(state + '.log')}
	for index, row in rows {
		entry := row.as_map(); name := entry['name']!.str(); assert name == names[index] && entry['exit_code']!.int() == if failing { 1 } else { 0 } && entry['detail']!.str() == ''
		for label, path in {'source': state + '/sources/' + name + 'fixture/core.v', 'init': state + '/' + name + '/init', 'iso': state + '/' + name + '/test.iso'} {
			hash := digest(path); key := if label == 'source' { 'source_sha256' } else if label == 'init' { 'init_sha256' } else { 'iso_sha256' }; assert hash == entry[key]!.str(); artifacts[name + '_' + label] = hash
		}
		maintained := '/Users/alex/code/vinix/tests/linux-compat/' + name + 'fixture/core.v'
		assert artifacts[name + '_source'] == digest(maintained)
		artifacts[name + '_c'] = digest(state + '/' + name + '/fixture.c'); artifacts[name + '_serial'] = digest(state + '/' + name + '/serial.log')
		if !failing { assert os.read_file(state + '/' + name + '/serial.log')!.contains('LINUX ' + name.to_upper() + ': PASS') }
	}
	return artifacts
}
fn reference_receipt(state string, arch string, init string) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['passed']!.bool() && value['finished']!.bool() && value['forced']!.bool() && value['status']!.int() == 0
	artifacts := value['artifacts']!.as_map_of_strings()
	command := value['command']!.as_array().map(it.str()); assert command.contains('-kernel') && command.contains('-initrd') && command.contains('-no-reboot')
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/flocksamereferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/flocksame-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/flocksamereferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, true, true, arch); return artifacts
}
fn erase(source string) string {
	names := ['file__syscall_flock']; mut kept := []string{}; mut inside := false; mut removed := 0
	for line in source.split_into_lines() {
		if inside { if line == '}' { inside = false }; continue }
		if line != '' && line[0] != `\t` && names.any(line.contains(' ' + it + '(')) { assert line.ends_with(';') || line.ends_with('{'), line; inside = line.ends_with('{'); removed++; continue }
		kept << line
	}
	assert !inside && removed == 2
	return kept.join('\n')
}

fn normalized_macros(source string) string {
	rows := source.split_into_lines().filter(it.starts_with('#define mmap__')); assert rows.len == 48; block := rows.join('\n') + '\n'; assert source.count(block) == 1; return source.replace(block, '')
}
fn window_scope(plain string, window string, suffix string) {
	if erase(plain) == erase(window) { return }
	assert suffix == 'x86'; assert plain.split_into_lines().filter(it.starts_with('#define mmap__')) == window.split_into_lines().filter(it.starts_with('#define mmap__'))
	assert erase(normalized_macros(plain)) == erase(normalized_macros(window)), 'QA differs outside sole function and byte-identical mmap literal block placement'
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!, os.args[3]); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/flocksame-20261014/'; out := root + 'tests/linux-compat/results/2026-10-14/'; compiler := '/Users/alex/.cache/vinix-linux-compat/procstate-20261013/compiler/v'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'verified-after-kernel-arm/flocksame/serial.log', 'aarch64'], 'flocksame baseline failure markers required'))!
	window := '\t// flock conversion qualification window: no table lock is held here.\n\tif operation & lock_nb != 0 {\n\t\tfor _ in 0 .. 32 { sched.reschedule() }\n\t}\n'
	for phase, plain in {'before': area + 'baseline-locks.v', 'after': root + 'kernel/file/locks.v'} { qa_source := os.read_file(area + 'window-' + phase + '-locks.v')!; assert qa_source.count(window) == 1 && qa_source.count('import sched\n') == 1 && qa_source.replace(window, '').replace('import sched\n', '') == os.read_file(plain)! }
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '84e6321ed2e61682b3a98ca3e6f9665f1f8e2380'
	mut inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	inputs['kernel/file/locks.v'] = digest(area + 'kernel-arm/kernel/file/locks.v')
	assert digest(compiler) == 'f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39'
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	for arch in ['aarch64', 'x86_64'] { count := arch + ': ' + if arch == 'aarch64' { '659 source files, 400 allocation sites (V exit 0)' } else { '655 source files, 292 allocation sites (V exit 0)' }; assert before_allocs.contains(count) && after_allocs.contains(count) }
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	paths := ['kernel/file/locks.v']; review := out + 'flocksame-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent flocksame lifetime review: PASS')
	for path in paths { assert review_text.contains(inputs[path]) && inputs[path] == digest(root + path) }
	assert review_text.contains(digest(root + 'tests/linux-compat/flocksamefixture/core.v'))
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == paths
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		kernel_c := tree + 'kernel/obj/blob.c'; assert erase(os.read_file(area + 'before-kernel-' + suffix + '.c')!) == erase(os.read_file(kernel_c)!), 'complete C outside sole reviewed syscall_flock definition/prototype'; assert review_text.contains(digest(kernel_c))
		preview := os.read_file(area + 'preview-' + suffix + '.c')!; assert preview.count('alloca(') == 11 && !preview.contains('memdup(') && !preview.contains('malloc(') && !preview.contains('new_array') && !preview.contains('v_fixed_index')
		qa_tree := area + 'window-' + suffix + '/'; assert git(qa_tree, ['rev-parse', 'HEAD'])! == base && git(qa_tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == paths
		for path, hash in inputs { if path.starts_with('kernel/') && path != 'kernel/file/locks.v' { assert digest(qa_tree + path) == hash } }
		qa_c := qa_tree + 'kernel/obj/blob.c'; old_qa_c := area + 'before-window-' + suffix + '.c'; assert erase(os.read_file(old_qa_c)!) == erase(os.read_file(qa_c)!)
		window_scope(os.read_file(area + 'before-kernel-' + suffix + '.c')!, os.read_file(old_qa_c)!, suffix); window_scope(os.read_file(kernel_c)!, os.read_file(qa_c)!, suffix); assert review_text.contains(digest(qa_c))
		before_hash := digest(area + 'baseline-window-' + suffix + '/kernel/bin/vinix'); after_hash := digest(tree + 'kernel/bin/vinix')
		baseline := area + 'verified-before-window-' + suffix; candidate := area + 'verified-after-kernel-' + suffix; reference := area + 'verified-reference-' + suffix
		before := receipt(baseline, arch, before_hash, ['flocksame'], true)!; after := receipt(candidate, arch, after_hash, ['flocksame', 'lockaccess', 'ofdlocks', 'open', 'runtime'], false)!
		assert before['flocksame_source'] == after['flocksame_source'] && before['flocksame_init'] == after['flocksame_init'] && before['flocksame_c'] == after['flocksame_c'] && after['flocksame_c'] == digest(area + 'preview-' + suffix + '.c')
		failure(os.read_file(baseline + '/flocksame/serial.log')!, arch); log := os.read_file(candidate + '/flocksame/serial.log')!; semantics(log, true, false, arch); storage(log, arch); assert review_text.contains(digest(candidate + '/flocksame/serial.log'))
		qualified := area + 'verified-after-window-' + suffix; qa := receipt(qualified, arch, digest(qa_tree + 'kernel/bin/vinix'), ['flocksame'], false)!
		assert qa['flocksame_source'] == after['flocksame_source'] && qa['flocksame_c'] == after['flocksame_c'] && qa['flocksame_init'] == after['flocksame_init']
		qa_log := os.read_file(qualified + '/flocksame/serial.log')!; semantics(qa_log, true, false, arch); storage(qa_log, arch); assert review_text.contains(digest(qualified + '/flocksame/serial.log'))
		publish(qualified + '.log', out + 'flocksame-after-window-' + arch + '.log')!; publish(qualified + '/receipt.json', out + 'flocksame-after-window-' + arch + '.json')!; publish(qualified + '/flocksame/serial.log', out + 'flocksame-after-window-' + arch + '-native.log')!
		linux := reference_receipt(reference, arch, after['flocksame_init'])!; assert review_text.contains(linux['serial']) && review_text.contains(linux['wrapper_c']) && review_text.contains(linux['probe'])
		assert linux['kernel'] == digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/vmlinuz-' + arch)
		assert os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: JIT page sizes')
		mut artifacts := {'compiler': digest(compiler), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'reference_controller': digest(area + 'reference'), 'audit': digest(@FILE), 'audit_executable': digest(os.executable()), 'review': digest(review), 'before_qa_kernel': before_hash, 'after_kernel': after_hash, 'before_ordinary_kernel_c': digest(area + 'before-kernel-' + suffix + '.c'), 'after_kernel_c': digest(kernel_c), 'preview': digest(area + 'preview-' + suffix + '.c')}
		artifacts['before_source'] = digest(area + 'baseline-locks.v'); artifacts['before_qa_source'] = digest(area + 'window-before-locks.v'); artifacts['after_qa_source'] = digest(area + 'window-after-locks.v'); artifacts['before_ordinary_kernel'] = digest(area + 'baseline-' + suffix + '/kernel/bin/vinix'); artifacts['before_qa_kernel_c'] = digest(old_qa_c); artifacts['after_qa_kernel_c'] = digest(qa_c); artifacts['after_qa_kernel'] = digest(qa_tree + 'kernel/bin/vinix'); artifacts['instrumenter'] = digest(root + 'tests/linux-compat/flocksame-instrument.v'); for key, hash in qa { artifacts['after_qa_' + key] = hash }
		for key, hash in before { artifacts['before_qa_' + key] = hash }; for key, hash in after { artifacts['after_' + key] = hash }; for key, hash in linux { artifacts['reference_' + key] = hash }
		artifacts['reference_receipt'] = digest(reference + '/receipt.json'); artifacts['reference_aggregate'] = digest(reference + '.log')
		for phase in ['before', 'after'] {
			state := if phase == 'after' { candidate } else { baseline }; publish(state + '.log', out + 'flocksame-' + if phase == 'before' { 'before-window' } else { 'after' } + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'flocksame-' + if phase == 'before' { 'before-window' } else { 'after' } + '-' + arch + '.json')!; publish(state + '/flocksame/serial.log', out + 'flocksame-' + if phase == 'before' { 'before-window' } else { 'after' } + '-' + arch + '-native.log')!
			build := area + 'build-' + if phase == 'before' { 'window-' } else { 'kernel-' } + phase + '-' + suffix + '.log'; build_text := os.read_file(build)!; assert build_text.contains('-o bin/vinix') && !build_text.contains('Error ') && !build_text.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
		}
		publish(reference + '.log', out + 'flocksame-reference-' + arch + '.log')!; publish(reference + '/serial.log', out + 'flocksame-reference-' + arch + '-native.log')!; publish(reference + '/receipt.json', out + 'flocksame-reference-' + arch + '.json')!
		for profile in ['kernel', 'window'] { for phase in ['before', 'after'] { name := 'build-' + profile + '-' + phase + '-' + suffix + '.log'; artifacts[name] = digest(area + name); publish(area + name, out + 'flocksame-' + name)! } }
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		context := 'Native musl ELF64 same-kind flock preservation: 1936 counted controls per architecture/run, root/UID1000. Regular files and directories; SH/EX, original/dup/CLOEXEC aliases and libc/raw high fd/operation words. Twenty-four real queued independent contenders per credential, eight same-kind nonblocking requests each; waiter remains blocked until explicit unlock, peer SH/EX and file metadata/bytes/status/flags/shared offsets verify original kind. Positive controls exercise blocking/NB alias repetitions, both real conversions, nonfinal/final alias close. Unchanged private scheduling-window baselines expose 792 ARM/790 x86 failures in their recorded runs while 688 sequential conversion/close controls remain correct; no claim that uninstrumented baselines deterministically fail. QA copies alone add sched import and32 reschedules after actual description-lock release for NB calls, with restored source equality; the new same-kind branch precedes that window. Ordinary and window candidates pass identical source/C/ELF and paired200-cycle mixed regular/directory storage cohorts, with all18/14 slab classes and63/160 pages flat. Linux6.12.51 passes the same native ELF. Complete ordinary/window C changes only syscall_flock definition/prototype; scheduling comparison permits only that function and, if x86 requires it, one48-line relocated block of byte-identical mmap macros. No ownership/allocation/reclamation change; table read is under existing lock with retained FD and copied scalar owner/resource/kind. Eleven explicit probe allocas, no hidden heap/index helpers; allocation inventories/allowance refusals unchanged. Four before/after ordinary/window production builds per architecture, five ordinary guest cases plus window probe, eight host tests, 64 inputs, independent lifetime review and executing assertion/passing-as-baseline controls bound. MAC/policy races, arbitrary shared-description concurrent mutation, fairness/deadlocks, other filesystems/nonregular types, deprecated mandatory locks and GNU/translated/ELF32 paths remain separate; three broad roadmap gates stay open.'
		os.write_file(out + 'flocksame-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { publish(area + name, out + 'flocksame-' + name)! }
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		for prefix in ['final', 'new', 'retry'] { path := area + prefix + '-after-' + suffix; if os.is_file(path + '/receipt.json') { publish(path + '/receipt.json', out + 'flocksame-diagnostic-' + prefix + '-' + arch + '.json')! }; if os.is_file(path + '.log') { publish(path + '.log', out + 'flocksame-diagnostic-' + prefix + '-' + arch + '.log')! } }
	}
	println('Native flocksame conformance audit: PASS')
}
