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
		rows := log.split_into_lines().filter(it.starts_with('LINUX PIPEABI ' + label)); assert rows.len == 8
		mut seen := map[string]bool{}; mut calls := 0; mut failures := 0
		for row in rows {
			fields := row.fields(); assert fields.len == 8
			for i, prefix in {3: 'ordinary=', 4: 'namespace=', 5: 'kind=', 6: 'calls=', 7: 'failures='} { assert fields[i].starts_with(prefix) }
			ordinary := fields[3].all_after('=').int(); namespace := fields[4].all_after('=').int(); kind := fields[5].all_after('=').int()
			assert ordinary in [0, 1] && namespace == 0 && kind in [0, 1, 2, 3]
			key := '${ordinary}-${namespace}-${kind}'; assert key !in seen; seen[key] = true
			n := fields[6].all_after('=').int(); f := fields[7].all_after('=').int()
			expected := if reference { [160, 1600, 0, 13]![kind] } else { [160, 1600, 320, 13]![kind] }
			assert n == expected && f == if passing { 0 } else { [32, 1600, 320, 0]![kind] }
			if label == 'CASES:' { snapshots[key] = '${n}/${f}' } else { assert snapshots[key] == '${n}/${f}' }
			calls += n; failures += f
		}; assert calls == if reference { 3546 } else { 4186 } && failures == if passing { 0 } else { 3904 }
	}
	if passing { assert !log.contains('LINUX PIPEABI DETAIL:') && !log.contains('LINUX PIPEABI FAIL:') }
	else { assert log.contains('LINUX PIPEABI DETAIL:') && log.contains('LINUX PIPEABI FAIL:') && !log.contains('LINUX PIPEABI: PASS') && !log.contains('LINUX PIPEABI STORAGE:') }
	if reference { assert passing && log.contains('LINUX PIPEABI REFERENCE: PASS') && log.contains('Linux version 6.12.51-0-virt') && !log.contains('Kernel panic') && !log.contains('LINUX PIPEABI STORAGE:') }
	else if passing { assert log.split_into_lines().filter(it.trim_space() == 'LINUX PIPEABI: PASS').len == 1 && !log.contains('LINUX PIPEABI REFERENCE: PASS') }
}
fn failure(log string, arch string) { assert log.contains('LINUX PIPEABI DETAIL:'), 'pipeabi baseline failure markers required'; semantics(log, false, false, arch) }
fn storage(log string, arch string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines() {
		if !row.starts_with('LINUX PIPEABI SLAB:') && !row.starts_with('LINUX PIPEABI STORAGE:') { continue }
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
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/pipeabireferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/pipeabi-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/pipeabireferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, true, true, arch); return artifacts
}


fn erase(source string, names []string) string {
 mut kept := []string{}; mut inside := false; mut separator := false; mut removed := 0
 for line in source.split_into_lines() {
 if inside { if line == '}' { inside = false; separator = true }; continue }
 if separator { assert line == ''; separator = false; continue }
 if line != '' && line[0] != `\t` && names.any(line.contains(' ' + it + '(')) { assert line.ends_with(';') || line.ends_with('{'); inside = line.ends_with('{'); removed++; continue }
 kept << line
 }; assert !inside && removed == names.len * 2; return kept.join('\n')
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!, os.args[3]); return }
	if '--scope-only' in os.args {
		for suffix in ['arm', 'x86'] {
			area := '/Users/alex/.cache/vinix-linux-compat/pipeabi-20261014/'
			before := os.read_file(area + 'before-' + suffix + '.c')!; after := os.read_file(area + 'kernel-' + suffix + '/kernel/obj/blob.c')!
			assert before != after && erase(before, ['pipe__syscall_pipe_checked']) == erase(after, ['pipe__syscall_pipe_checked'])
		}
		println('Whole generated C outside pipe2 checked wrapper body/prototype: PASS'); return
	}
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/pipeabi-20261014/'; out := root + 'tests/linux-compat/results/2026-10-14/'; compiler_root := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/'; compiler := compiler_root + 'compiler/v'; states := area + 'states/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', states + 'p-after-arm/pipeabi/serial.log', 'aarch64'], 'pipeabi baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '09d9bbd210cb89f082a6019d69e508199d9501b7'
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
	paths := ['kernel/pipe/usercopy.v']; review := out + 'pipeabi-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent pipeabi lifetime review: PASS')
	for path in paths { assert review_text.contains(inputs[path]) && inputs[path] == digest(root + path) }
	assert review_text.contains(digest(root + 'tests/linux-compat/pipeabifixture/core.v'))
	drift := strings(area + 'preflight-drift-pins.json')!; assert drift.len == 8
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == paths
		assert object(tree + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings() == inputs
		for path, hash in inputs { if path.starts_with('kernel/') || path == 'tools/linux-compat/coverage.v' { assert digest(tree + path) == hash } }
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'tools'])!.split_into_lines() == ['tools/linux-compat/coverage.v']
		assert inputs['kernel/pipe/usercopy.v'] == digest(root + 'kernel/pipe/usercopy.v') && inputs['tools/linux-compat/coverage.v'] == digest(root + 'tools/linux-compat/coverage.v')
		kernel_c := tree + 'kernel/obj/blob.c'; assert erase(os.read_file(area + 'before-' + suffix + '.c')!, ['pipe__syscall_pipe_checked']) == erase(os.read_file(kernel_c)!, ['pipe__syscall_pipe_checked']), 'whole generated C outside checked pipe2 wrapper body/prototype'; assert review_text.contains(digest(kernel_c))

		preview := os.read_file(area + 'preview-' + suffix + '.c')!; assert preview.count('alloca(') == 12; for forbidden in ['memdup(', 'malloc(', 'new_array', 'v_fixed_index'] { assert !preview.contains(forbidden) }
		before_hash := digest(area + 'baseline-' + suffix + '/kernel/bin/vinix'); after_hash := digest(tree + 'kernel/bin/vinix')
		baseline := states + 'p-before-' + suffix; candidate := states + 'p-after-' + suffix; reference := states + 'p-reference-' + suffix
		before := receipt(baseline, arch, before_hash, ['pipeabi'], true)!; after := receipt(candidate, arch, after_hash, ['pipeabi', 'accessflags', 'access', 'open', 'runtime'], false)!
		assert before['pipeabi_source'] == after['pipeabi_source'] && before['pipeabi_init'] == after['pipeabi_init'] && before['pipeabi_c'] == after['pipeabi_c'] && after['pipeabi_c'] == digest(area + 'preview-' + suffix + '.c')
		failure(os.read_file(baseline + '/pipeabi/serial.log')!, arch); log := os.read_file(candidate + '/pipeabi/serial.log')!; semantics(log, true, false, arch); storage(log, arch); assert review_text.contains(digest(candidate + '/pipeabi/serial.log'))
		linux := reference_receipt(reference, arch, after['pipeabi_init'])!; assert review_text.contains(linux['serial']) && review_text.contains(linux['wrapper_c']) && review_text.contains(linux['probe'])
		preflight := states + 'preflight-pipeabi-' + suffix
		assert digest(preflight + '/init') == after['pipeabi_init'] && drift[arch + '_elf'] == after['pipeabi_init']
		assert drift[arch + '_native_c'] == after['pipeabi_c'] && drift[arch + '_preflight_c'] == after['pipeabi_c'] && drift[arch + '_preflight_c'] == digest(preflight + '/fixture.c') && review_text.contains(drift[arch + '_preflight_c'])
		assert drift[arch + '_drift'] == digest(area + 'preflight-drift-' + arch + '.log') && os.read_file(area + 'preflight-drift-' + arch + '.log')! == ''
		assert linux['kernel'] == digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/vmlinuz-' + arch)
		assert os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: JIT page sizes')
		mut artifacts := {'compiler': digest(compiler), 'compiler_inputs': digest(compiler_root + 'compiler-inputs.json'), 'compiler_recovery': digest(compiler_root + 'compiler-recovery.json'), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'reference_controller': digest(area + 'reference'), 'audit': digest(@FILE), 'audit_executable': digest(os.executable()), 'review': digest(review), 'before_kernel': before_hash, 'after_kernel': after_hash, 'before_kernel_c': digest(area + 'before-' + suffix + '.c'), 'after_kernel_c': digest(kernel_c), 'preview': digest(area + 'preview-' + suffix + '.c')}

		artifacts['diagnostic_preview'] = digest(area + 'diagnostic-preview-arm.log'); artifacts['diagnostic_preview_source'] = digest(area + 'diagnostic-source.v')
		diagnostic := os.read_file(area + 'diagnostic-preview-arm.log')!
		assert diagnostic.contains('cannot use `int` (right expression) as `voidptr`') && diagnostic.contains('C.MAP_FAILED')
		for key, hash in before { artifacts['before_' + key] = hash }; for key, hash in after { artifacts['after_' + key] = hash }; for key, hash in linux { artifacts['reference_' + key] = hash }
		artifacts['reference_receipt'] = digest(reference + '/receipt.json'); artifacts['reference_aggregate'] = digest(reference + '.log')
		for key, hash in drift { artifacts['preflight_' + key] = hash }; artifacts['preflight_drift_pins'] = digest(area + 'preflight-drift-pins.json')
		for phase in ['before', 'after'] {
			state := if phase == 'after' { candidate } else { baseline }; publish(state + '.log', out + 'pipeabi-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'pipeabi-' + phase + '-' + arch + '.json')!; publish(state + '/pipeabi/serial.log', out + 'pipeabi-' + phase + '-' + arch + '-native.log')!
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_text := os.read_file(build)!; assert build_text.contains('-o bin/vinix') && !build_text.contains('Error ') && !build_text.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
		}
		publish(reference + '.log', out + 'pipeabi-reference-' + arch + '.log')!; publish(reference + '/serial.log', out + 'pipeabi-reference-' + arch + '-native.log')!; publish(reference + '/receipt.json', out + 'pipeabi-reference-' + arch + '.json')!
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		context := 'Native pipe2 int flag decoding and errors. Root/UID-GID1000 cohorts run [160,1600,320,13] controls each: four ordinary flag combinations, ten invalid low words, five upper register patterns, eight aligned/unaligned/nil/inaccessible/readonly/cross-page outputs, original/dup/CLOEXEC aliases, exact 64-bit F_GETFL, owner/inode/FD flags, nonblocking EAGAIN, byte transfers and EOF. Native total4186; both baselines fail3904. Same musl ELF and exact fixture C pass candidate kernels and actual Linux6.12.51, whose deliberately separate native-refusal row has zero controls (Linux total3546). Unknown flags return EINVAL before pointers/allocation; low32 decoding ignores upper register words. Unimplemented packet O_DIRECT returns EOPNOTSUPP; notification O_EXCL returns ENOPKG; this records honest native refusals, not Linux packet/watch support. Retained regular cursor/data, queued AB, nine aliases and original64FD slot vector stay unchanged. Twelve explicit probe allocas, no hidden heap/index helpers. Two warmed/settled200-cycle cohorts cover finite pipe create/alias/transfer/close and scalar refusals, keeping all18ARM/14x86 slabs and observed large pages flat. No allocation/release/descriptor ownership changes: entire production C differs only in the existing checked wrapper body/prototype. Four production builds, five final guest cases perarchitecture, eight host files,64 frozen inputs including dispatched pipe usercopy helper, identical baseline/candidate/preflight/Linux ELFs and raw C drift, unchanged allocation-site allowance failures, active negative audit controls and independent lifetime review are bound. Initial MAP_FAILED V type-check failure is diagnostic-only. Prior self-contained f635 compiler and15146 pins/recovery are reused. Packet/watch semantics, F_SETFL packet mode, partial descriptor exhaustion cleanup/publication races, limit-vs-pointer precedence, concurrent closes/credentials, physical exhaustion, FIFO/GNU/translated/ELF32 paths and three broad roadmap gates remain unqualified.'
		os.write_file(out + 'pipeabi-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log', 'preflight-drift-pins.json', 'preflight-drift-aarch64.log', 'preflight-drift-x86_64.log'] { publish(area + name, out + 'pipeabi-' + name)! }
	publish(area + 'diagnostic-preview-arm.log', out + 'pipeabi-diagnostic-preview-arm.log')!
	println('Native pipeabi conformance audit: PASS')
}
