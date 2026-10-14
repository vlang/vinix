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
fn strings(path string) !map[string]string {
	mut result := map[string]string{}
	for key, value in object(path)! { result[key] = value.str() }
	return result
}
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
	mut snapshots := map[string]string{}
	for label in ['CASES:', 'FINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX PIPEPAIR ' + label)); assert rows.len == 8
		mut seen := map[string]bool{}; mut calls := 0; mut failures := 0
		for row in rows {
			fields := row.fields(); assert fields.len == 8
			for i, prefix in {3: 'ordinary=', 4: 'namespace=', 5: 'kind=', 6: 'calls=', 7: 'failures='} { assert fields[i].starts_with(prefix) }
			ordinary := fields[3].all_after('=').int(); namespace := fields[4].all_after('=').int(); kind := fields[5].all_after('=').int()
			assert ordinary in [0, 1] && namespace == 0 && kind in [0, 1, 2, 3]
			key := '${ordinary}-${namespace}-${kind}'; assert key !in seen; seen[key] = true
			n := fields[6].all_after('=').int(); f := fields[7].all_after('=').int()
			expected := [1120, 1120, 2240, 13]![kind]
			assert n == expected && f == if passing { 0 } else { [0, 280, 0, 0]![kind] }
			if label == 'CASES:' { snapshots[key] = '${n}/${f}' } else { assert snapshots[key] == '${n}/${f}' }
			calls += n; failures += f
		}; assert calls == 8986 && failures == if passing { 0 } else { 560 }
	}
	if passing { assert !log.contains('LINUX PIPEPAIR DETAIL:') && !log.contains('LINUX PIPEPAIR FAIL:') }
	else { assert log.contains('LINUX PIPEPAIR DETAIL:') && log.contains('LINUX PIPEPAIR FAIL:') && !log.contains('LINUX PIPEPAIR: PASS') && !log.contains('LINUX PIPEPAIR STORAGE:') }
	if reference { assert passing && log.contains('LINUX PIPEPAIR REFERENCE: PASS') && log.contains('Linux version 6.12.51-0-virt') && !log.contains('Kernel panic') && !log.contains('LINUX PIPEPAIR STORAGE:') }
	else if passing { assert log.split_into_lines().filter(it.trim_space() == 'LINUX PIPEPAIR: PASS').len == 1 && !log.contains('LINUX PIPEPAIR REFERENCE: PASS') }
}
fn failure(log string, arch string) { assert log.contains('LINUX PIPEPAIR DETAIL:'), 'pipepair baseline failure markers required'; semantics(log, false, false, arch) }
fn storage(log string, arch string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines() {
		if !row.starts_with('LINUX PIPEPAIR SLAB:') && !row.starts_with('LINUX PIPEPAIR STORAGE:') { continue }
		fields := row.fields(); assert fields.len == 8 && fields[3].starts_with('ordinary=') && fields[4].starts_with('namespace=')
		ordinary := fields[3].all_after('=').int(); namespace := fields[4].all_after('=').int(); assert ordinary in [0, 1] && namespace == 0; group := ordinary
		pair := fields[6].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' { key := fields[3] + '-' + fields[4] + '-' + fields[5]; assert key !in seen && fields[7] == 'cycles=200'; seen[key] = true; slabs[group]++ }
		else {
			assert fields[5] == 'cycles=200' && fields[7] == 'PASS'
			assert pair[0] == if arch == 'aarch64' { '68' } else { '177' }
			pages[group]++
		}
	}; for group in 0 .. 2 { assert slabs[group] == if arch == 'aarch64' { 18 } else { 14 }; assert pages[group] == 1 }
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
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/pipepairreferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/pipepair-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/pipepairreferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, true, true, arch); return artifacts
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
fn performance(area string, out string) !map[string]string {
	mut result := map[string]string{}
	mut measure := ''; mut desktop := ''; mut source := ''
	for phase in ['before', 'after'] { for profile in ['ops', 'desktop'] {
		work := area + 'pf-' + phase + '-' + profile; artifacts := work + '/artifacts/'
		log := os.read_file(work + '/serial.log')!; aggregate := os.read_file(area + 'perf-' + phase + '-' + profile + '.log')!
		assert aggregate.contains('Completed ' + phase + ' ' + profile + ' qualification') && log.contains('VINIX DESKTOP PERF: DONE')
		for marker in ['PERF-ERROR', 'KERNEL PANIC', 'FATAL EXCEPTION'] { assert !log.contains(marker) }
		pins := strings(work + '/stage-pins.json')!
		for name in ['kernel', 'measure', 'config', 'vinix-desktop-new', 'measure.c'] { assert pins[name] == digest(artifacts + name) }
		kernel := area + if phase == 'before' { 'baseline-arm' } else { 'kernel-arm' } + '/kernel/bin/vinix'
		assert pins['kernel'] == digest(kernel) && pins['vinix-desktop-new'] == digest(area + 'perf-inputs/desktop')
		if measure == '' { measure = pins['measure']; desktop = pins['vinix-desktop-new']; source = pins['measure.c'] }
		else { assert measure == pins['measure'] && desktop == pins['vinix-desktop-new'] && source == pins['measure.c'] }
		rows := json2.decode[json2.Any](os.read_file(work + '/result.json')!)!.as_array()
		mut seen := map[string]bool{}; mut counts := map[string]int{}
		for row in rows { value := row.as_map(); assert value['variant']!.str() == 'new' && value['round']!.int() == 1
			if profile == 'ops' {
				report := value['report']!.str(); counts[report]++
				if report == 'PERF-OPS' { key := value['op']!.str() + '-' + value['dir']!.str(); assert key !in seen; seen[key] = true; assert value['count']!.str() == '200' && value['bytes_per_op']!.str() == '0' }
				else if report == 'PERF-CHURN' { key := value['program']!.str(); assert key !in seen; seen[key] = true; assert value['runs']!.str() == '300' && value['retained_kb']!.str() == '0' && value['per_run_bytes']!.str() == '0' }
				else { assert report == 'PERF-CACHE' && value['written_mb']!.str() == '32' }
			} else { scenario := value['scenario']!.str(); assert scenario in ['idle', 'apps', 'drag'] && scenario !in seen; seen[scenario] = true
				assert value['seconds']!.str() == '5.0' && value['processes']!.str().int() >= if scenario == 'apps' { 4 } else { 1 }
			}
		}
		if profile == 'ops' { assert counts['PERF-OPS'] == 36 && counts['PERF-CHURN'] == 4 && counts['PERF-CACHE'] == 1 && rows.len == 41; assert !log.contains('PERF-SLAB ') }
		else { assert rows.len == 3 && seen.len == 3 }
		prefix := 'perf_' + phase + '_' + profile
		for name, path in {'serial': work + '/serial.log', 'result': work + '/result.json', 'aggregate': area + 'perf-' + phase + '-' + profile + '.log', 'stage_pins': work + '/stage-pins.json'} {
			result[prefix + '_' + name] = digest(path); publish(path, out + 'pipepair-perf-' + phase + '-' + profile + '-' + name + if name in ['result', 'stage_pins'] { '.json' } else { '.log' })!
		}
		for name in ['kernel', 'measure', 'config', 'vinix-desktop-new', 'measure.c'] { result[prefix + '_' + name] = pins[name] }
	} }
	result['perf_image'] = digest(area + 'perf-inputs/image.tar')
	return result
}
fn diagnostics(area string, out string, arch string, suffix string) !map[string]string {
	mut result := map[string]string{}
	for phase in ['p2-before', 'p2-after', 'p3-before', 'p3-after'] {
		state := area + 'states/' + phase + '-' + suffix; value := object(state + '/receipt.json')!
		first := value['results']!.as_array()[0].as_map()
		assert first['name']!.str() == 'pipepair' && first['exit_code']!.int() == 1 && first['detail']!.str() != '' && first['init_sha256']!.str() == '' && first['iso_sha256']!.str() == ''
		log := os.read_file(state + '.log')!; assert !log.contains('LINUX PIPEPAIR CASES:')
		assert log.contains(if phase.starts_with('p2') { 'mktemp:' } else { 'v_fixed_index' })
		for label, path in {'receipt': state + '/receipt.json', 'aggregate': state + '.log'} { result[phase + '_' + label] = digest(path); publish(path, out + 'pipepair-diagnostic-' + phase + '-' + arch + if label == 'receipt' { '.json' } else { '.log' })! }
	}
	for name in ['diagnostic-cycle-source.v', 'diagnostic-cycle-preview-' + suffix + '.c', 'diagnostic-vfixed-' + suffix + '.log', 'diagnostic-temp-host-tests.log', 'diagnostic-temp-allocs-before.log', 'diagnostic-temp-allocs-after.log'] { result[name] = digest(area + name) }
	assert os.read_file(area + 'diagnostic-vfixed-' + suffix + '.log')!.contains('v_fixed_index')
	return result
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!, os.args[3]); return }
	if '--scope-only' in os.args {
		for suffix in ['arm', 'x86'] {
			area := '/Users/alex/.cache/vinix-linux-compat/pipepair-20261014/'
			before := os.read_file(area + 'before-' + suffix + '.c')!; after := os.read_file(area + 'kernel-' + suffix + '/kernel/obj/blob.c')!
			assert before != after && erase(before, ['pipe__syscall_pipe', 'file__fdnum_create_pair'], 2) == erase(after, ['pipe__syscall_pipe', 'file__fdnum_create_pair'], 4)
		}
		println('Whole generated C outside private pipe constructor and new pair helper: PASS'); return
	}
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/pipepair-20261014/'; out := root + 'tests/linux-compat/results/2026-10-14/'; compiler_root := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/'; compiler := compiler_root + 'compiler/v'; states := area + 'states/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', states + 'p4-after-arm/pipepair/serial.log', 'aarch64'], 'pipepair baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == 'd6a33ce248887d5dd8e400eb6d3b78d315a6567d'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 64
	assert os.read_file(compiler_root + 'compiler-commit.txt')!.trim_space() == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c'
	pins := strings(compiler_root + 'compiler-inputs.json')!; assert pins.len == 15146 && pins['v'] == digest(compiler)
	for path, hash in pins { assert digest(compiler_root + 'compiler/' + path) == hash, 'compiler input drift: ' + path }
	recovery := object(compiler_root + 'compiler-recovery.json')!; assert recovery['local_binary']!.str() == digest(compiler) && recovery['old_binary']!.str() == digest(compiler_root + 'pre-restore-v') && recovery['old_binary']!.str() == 'f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39' && recovery['inputs_manifest']!.str() == digest(compiler_root + 'compiler-inputs.json')
	assert recovery['rebuild_log']!.str() == digest(compiler_root + 'compiler-rebuild.log')
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	for arch, count in {'aarch64': '400', 'x86_64': '292'} { for log in [before_allocs, after_allocs] { assert log.split_into_lines().filter(it.starts_with(arch + ': ')).len == 1 && log.split_into_lines().filter(it.starts_with(arch + ': '))[0].contains(count + ' allocation sites (V exit 0)') } }
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	paths := ['kernel/file/file.v', 'kernel/pipe/pipe.v']; review := out + 'pipepair-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent pipepair lifetime review: PASS')
	for path in paths { assert review_text.contains(inputs[path]) && inputs[path] == digest(root + path) }
	assert review_text.contains(digest(root + 'tests/linux-compat/pipepairfixture/core.v'))
	perf := performance(area, out)!
	drift := strings(area + 'preflight-drift-pins.json')!; assert drift.len == 8
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == paths
		assert object(tree + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings() == inputs
		for path, hash in inputs { if path.starts_with('kernel/') || path == 'tools/linux-compat/coverage.v' { assert digest(tree + path) == hash } }
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'tools'])! == ''
		assert inputs['kernel/file/file.v'] == digest(root + 'kernel/file/file.v') && inputs['kernel/pipe/pipe.v'] == digest(root + 'kernel/pipe/pipe.v')
		kernel_c := tree + 'kernel/obj/blob.c'; assert erase(os.read_file(area + 'before-' + suffix + '.c')!, ['pipe__syscall_pipe', 'file__fdnum_create_pair'], 2) == erase(os.read_file(kernel_c)!, ['pipe__syscall_pipe', 'file__fdnum_create_pair'], 4), 'whole generated C outside private constructor and pair helper'; assert review_text.contains(digest(kernel_c))

		preview := os.read_file(area + 'preview-' + suffix + '.c')!; assert preview.count('alloca(') == 16; for forbidden in ['memdup(', 'malloc(', 'new_array', 'v_fixed_index'] { assert !preview.contains(forbidden) }
		before_hash := digest(area + 'baseline-' + suffix + '/kernel/bin/vinix'); after_hash := digest(tree + 'kernel/bin/vinix')
		baseline := states + 'p4-before-' + suffix; candidate := states + 'p4-after-' + suffix; reference := states + 'p4-reference-' + suffix
		before := receipt(baseline, arch, before_hash, ['pipepair'], true)!; after := receipt(candidate, arch, after_hash, ['pipepair', 'pipeabi', 'access', 'open', 'runtime'], false)!
		assert before['pipepair_source'] == after['pipepair_source'] && before['pipepair_init'] == after['pipepair_init'] && before['pipepair_c'] == after['pipepair_c'] && after['pipepair_c'] == digest(area + 'preview-' + suffix + '.c')
		failure(os.read_file(baseline + '/pipepair/serial.log')!, arch); log := os.read_file(candidate + '/pipepair/serial.log')!; semantics(log, true, false, arch); storage(log, arch); assert review_text.contains(digest(candidate + '/pipepair/serial.log'))
		linux := reference_receipt(reference, arch, after['pipepair_init'])!; assert review_text.contains(linux['serial']) && review_text.contains(linux['wrapper_c']) && review_text.contains(linux['probe'])
		preflight := states + 'preflight4-pipepair-' + suffix
		assert digest(preflight + '/init') == after['pipepair_init'] && drift[arch + '_elf'] == after['pipepair_init']
		assert drift[arch + '_native_c'] == after['pipepair_c'] && drift[arch + '_preflight_c'] == after['pipepair_c'] && drift[arch + '_preflight_c'] == digest(preflight + '/fixture.c') && review_text.contains(drift[arch + '_preflight_c'])
		assert drift[arch + '_drift'] == digest(area + 'preflight-drift-' + arch + '.log') && os.read_file(area + 'preflight-drift-' + arch + '.log')! == ''
		assert linux['kernel'] == digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/vmlinuz-' + arch)
		assert os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: JIT page sizes')
		mut artifacts := {'compiler': digest(compiler), 'compiler_inputs': digest(compiler_root + 'compiler-inputs.json'), 'compiler_recovery': digest(compiler_root + 'compiler-recovery.json'), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'reference_controller': digest(area + 'reference'), 'audit': digest(@FILE), 'audit_executable': digest(os.executable()), 'review': digest(review), 'before_kernel': before_hash, 'after_kernel': after_hash, 'before_kernel_c': digest(area + 'before-' + suffix + '.c'), 'after_kernel_c': digest(kernel_c), 'preview': digest(area + 'preview-' + suffix + '.c')}
		for key, hash in perf { artifacts[key] = hash }
		for key, hash in diagnostics(area, out, arch, suffix)! { artifacts['diagnostic_' + key] = hash }

		artifacts['diagnostic_preview'] = digest(area + 'diagnostic-preview-arm.log'); artifacts['diagnostic_preview_source'] = digest(area + 'diagnostic-source.v')
		diagnostic := os.read_file(area + 'diagnostic-preview-arm.log')!
		assert diagnostic.contains('cannot dereference a function call on the left side of an assignment')
		for key, hash in before { artifacts['before_' + key] = hash }; for key, hash in after { artifacts['after_' + key] = hash }; for key, hash in linux { artifacts['reference_' + key] = hash }
		artifacts['reference_receipt'] = digest(reference + '/receipt.json'); artifacts['reference_aggregate'] = digest(reference + '.log')
		for key, hash in drift { artifacts['preflight_' + key] = hash }; artifacts['preflight_drift_pins'] = digest(area + 'preflight-drift-pins.json')
		for phase in ['before', 'after'] {
			state := if phase == 'after' { candidate } else { baseline }; publish(state + '.log', out + 'pipepair-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'pipepair-' + phase + '-' + arch + '.json')!; publish(state + '/pipepair/serial.log', out + 'pipepair-' + phase + '-' + arch + '-native.log')!
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_text := os.read_file(build)!; assert build_text.contains('-o bin/vinix') && !build_text.contains('Error ') && !build_text.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
		}
		publish(reference + '.log', out + 'pipepair-reference-' + arch + '.log')!; publish(reference + '/serial.log', out + 'pipepair-reference-' + arch + '-native.log')!; publish(reference + '/receipt.json', out + 'pipepair-reference-' + arch + '.json')!
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		context := 'Native pipe construction under descriptor pressure. Root/UID1000 cohorts run [1120,1120,2240,13] controls each across48/64softlimits, zero/one/two/three nonadjacent free slots, four ordinary flag combinations, five upper-register patterns and seven aligned/unaligned/fault destinations. Exact return/error, immediate FDtable slots, output canaries and restored filler aliases plus real pair metadata/FD flags/64bitstatus/EAGAIN/ABC/EOF and retained bank data/cursor/queuedAB are checked. Baselines fail560 of8986nativecontrols; candidates and same-ELF actualLinux6.12.51 pass8986. Firstreader remains private whilewriterconstructs; writerfailure releasesreader; pairrefusal releasesbothprivateowners withsavederrno. New lock-scoped helper selects2lowestslots beforegrowth/publication, adoptingbothrefs onlysuccess andleavingtable/scratchunchangedonrefusal. Existingresource/FDconstructor/unref/growth/usercopybodies unchanged; entireCscope isconstructorplusnewhelper, nohiddenheapallocation. Sixteenexplicitfixtureallocas, zero bounds/heaphelpers. Two warmed200cycle pressure/copyfault/success/alias cohorts stayflat. Fourproductionbuilds, fivefreshguestcases/arch, host8,64frozeninputs, unchangedallocationsiteallowancefailures, exactpreview/native/preflight/Linuxbytes andrawCdrift, activemalformedauditcontrols andindependentlifetimereview bound. Initialerrnoassignmentpreviewerror, missingmountedTMPDIR andunlinkablefixed-indexpreview failures remain diagnostics only; finalp4profiles useprivateData TMPDIR. AGENTS desktopops/churn/cache andidle/apps/drag evidence is recorded separately with actualstagedkernel/measurement inputs. Descriptor-tablegrowth/budgetexhaustion is not exercisedby48/64limits belowinitial1024; concurrentprlimit/close, copy-before-publication/output-fault rollbackraces, nil-versus-limitprecedence, packet/watch semantics, GNU/foreignpaths andthreebroadroadmapgates remainunqualified.'
		os.write_file(out + 'pipepair-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log', 'preflight-drift-pins.json', 'preflight-drift-aarch64.log', 'preflight-drift-x86_64.log'] { publish(area + name, out + 'pipepair-' + name)! }
	publish(area + 'diagnostic-preview-arm.log', out + 'pipepair-diagnostic-preview-arm.log')!
	for name in ['diagnostic-vfixed-arm.log', 'diagnostic-vfixed-x86.log', 'diagnostic-temp-host-tests.log', 'diagnostic-temp-allocs-before.log', 'diagnostic-temp-allocs-after.log'] { publish(area + name, out + 'pipepair-' + name)! }
	println('Native pipepair conformance audit: PASS')
}
