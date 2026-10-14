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
		rows := log.split_into_lines().filter(it.starts_with('LINUX ACCESSFLAGS ' + label)); assert rows.len == 6
		mut seen := map[string]bool{}; mut calls := 0; mut failures := 0
		for row in rows {
			fields := row.fields(); assert fields.len == 8
			for i, prefix in {3: 'ordinary=', 4: 'namespace=', 5: 'kind=', 6: 'calls=', 7: 'failures='} { assert fields[i].starts_with(prefix) }
			ordinary := fields[3].all_after('=').int(); namespace := fields[4].all_after('=').int(); kind := fields[5].all_after('=').int()
			assert ordinary in [0, 1] && namespace == 0 && kind in [0, 1, 2]
			key := '${ordinary}-${namespace}-${kind}'; assert key !in seen; seen[key] = true
			n := fields[6].all_after('=').int(); f := fields[7].all_after('=').int()
			assert n == [2800, 400, 15]![kind] && f == if passing { 0 } else { if ordinary == 1 { [1828, 0, 3]![kind] } else { [1792, 0, 0]![kind] } }
			if label == 'CASES:' { snapshots[key] = '${n}/${f}' } else { assert snapshots[key] == '${n}/${f}' }
			calls += n; failures += f
		}; assert calls == 6430 && failures == if passing { 0 } else { 3623 }
	}
	if passing { assert !log.contains('LINUX ACCESSFLAGS DETAIL:') && !log.contains('LINUX ACCESSFLAGS FAIL:') }
	else { assert log.contains('LINUX ACCESSFLAGS DETAIL:') && log.contains('LINUX ACCESSFLAGS FAIL:') && !log.contains('LINUX ACCESSFLAGS: PASS') && !log.contains('LINUX ACCESSFLAGS STORAGE:') }
	if reference { assert passing && log.contains('LINUX ACCESSFLAGS REFERENCE: PASS') && log.contains('Linux version 6.12.51-0-virt') && !log.contains('Kernel panic') && !log.contains('LINUX ACCESSFLAGS STORAGE:') }
	else if passing { assert log.split_into_lines().filter(it.trim_space() == 'LINUX ACCESSFLAGS: PASS').len == 1 && !log.contains('LINUX ACCESSFLAGS REFERENCE: PASS') }
}
fn failure(log string, arch string) { assert log.contains('LINUX ACCESSFLAGS DETAIL:'), 'accessflags baseline failure markers required'; semantics(log, false, false, arch) }
fn storage(log string, arch string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines() {
		if !row.starts_with('LINUX ACCESSFLAGS SLAB:') && !row.starts_with('LINUX ACCESSFLAGS STORAGE:') { continue }
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
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/accessflagsreferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/accessflags-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/accessflagsreferenceinit/core.v')
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
			area := '/Users/alex/.cache/vinix-linux-compat/accessflags-20261014/'
			before := os.read_file(area + 'before-' + suffix + '.c')!; word := os.read_file(area + 'word-' + suffix + '.c')!; after := os.read_file(area + 'kernel-' + suffix + '/kernel/obj/blob.c')!
			assert before != word && word != after
			assert erase(before, ['table__syscall_linux_faccessat2']) == erase(word, ['table__syscall_linux_faccessat2'])
			assert erase(word, ['pipe__create']) == erase(after, ['pipe__create'])
		}
		println('Independent flag-word and pipe-owner generated-C scopes: PASS'); return
	}
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/accessflags-20261014/'; out := root + 'tests/linux-compat/results/2026-10-14/'; compiler_root := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/'; compiler := compiler_root + 'compiler/v'; states := area + 'states/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', states + 'v2-after-arm/accessflags/serial.log', 'aarch64'], 'accessflags baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == 'd00fe874ad9db66c958e35692fbb18c0a18c15bf'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	assert os.read_file(compiler_root + 'compiler-commit.txt')!.trim_space() == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c'
	pins := strings(compiler_root + 'compiler-inputs.json')!; assert pins.len == 15146 && pins['v'] == digest(compiler)
	for path, hash in pins { assert digest(compiler_root + 'compiler/' + path) == hash, 'compiler input drift: ' + path }
	recovery := object(compiler_root + 'compiler-recovery.json')!; assert recovery['local_binary']!.str() == digest(compiler) && recovery['old_binary']!.str() == digest(compiler_root + 'pre-restore-v') && recovery['old_binary']!.str() == 'f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39' && recovery['inputs_manifest']!.str() == digest(compiler_root + 'compiler-inputs.json')
	assert recovery['rebuild_log']!.str() == digest(compiler_root + 'compiler-rebuild.log')
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	for arch, count in {'aarch64': '400', 'x86_64': '292'} { for log in [before_allocs, after_allocs] { assert log.split_into_lines().filter(it.starts_with(arch + ': ')).len == 1 && log.split_into_lines().filter(it.starts_with(arch + ': '))[0].contains(count + ' allocation sites (V exit 0)') } }
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	paths := ['kernel/pipe/pipe.v', 'kernel/syscall/table/linux_compat.v']; review := out + 'accessflags-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent accessflags lifetime review: PASS')
	for path in paths { assert review_text.contains(inputs[path]) && inputs[path] == digest(root + path) }
	assert review_text.contains(digest(root + 'tests/linux-compat/accessflagsfixture/core.v'))
	drift := strings(area + 'preflight-drift-pins.json')!; assert drift.len == 8
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == paths
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		kernel_c := tree + 'kernel/obj/blob.c'; assert erase(os.read_file(area + 'before-' + suffix + '.c')!, ['pipe__create', 'table__syscall_linux_faccessat2']) == erase(os.read_file(kernel_c)!, ['pipe__create', 'table__syscall_linux_faccessat2']), 'whole generated C outside two scalar initialization bodies/prototypes'; assert review_text.contains(digest(kernel_c))
		word_c := os.read_file(area + 'word-' + suffix + '.c')!
		assert erase(os.read_file(area + 'before-' + suffix + '.c')!, ['table__syscall_linux_faccessat2']) == erase(word_c, ['table__syscall_linux_faccessat2'])
		assert erase(word_c, ['pipe__create']) == erase(os.read_file(kernel_c)!, ['pipe__create'])
		preview := os.read_file(area + 'preview-' + suffix + '.c')!; assert preview.count('alloca(') == 9; for forbidden in ['memdup(', 'malloc(', 'new_array', 'v_fixed_index'] { assert !preview.contains(forbidden) }
		before_hash := digest(area + 'baseline-' + suffix + '/kernel/bin/vinix'); after_hash := digest(tree + 'kernel/bin/vinix')
		baseline := states + 'v2-before-' + suffix; candidate := states + 'v2-after-' + suffix; reference := states + 'v2-reference-' + suffix
		before := receipt(baseline, arch, before_hash, ['accessflags'], true)!; after := receipt(candidate, arch, after_hash, ['accessflags', 'access', 'procpid', 'open', 'runtime'], false)!
		assert before['accessflags_source'] == after['accessflags_source'] && before['accessflags_init'] == after['accessflags_init'] && before['accessflags_c'] == after['accessflags_c'] && after['accessflags_c'] == digest(area + 'preview-' + suffix + '.c')
		failure(os.read_file(baseline + '/accessflags/serial.log')!, arch); log := os.read_file(candidate + '/accessflags/serial.log')!; semantics(log, true, false, arch); storage(log, arch); assert review_text.contains(digest(candidate + '/accessflags/serial.log'))
		linux := reference_receipt(reference, arch, after['accessflags_init'])!; assert review_text.contains(linux['serial']) && review_text.contains(linux['wrapper_c']) && review_text.contains(linux['probe'])
		preflight := states + 'preflight-accessflags-' + suffix
		assert digest(preflight + '/init') == after['accessflags_init'] && drift[arch + '_elf'] == after['accessflags_init']
		assert drift[arch + '_native_c'] == after['accessflags_c'] && drift[arch + '_preflight_c'] == after['accessflags_c'] && drift[arch + '_preflight_c'] == digest(preflight + '/fixture.c') && review_text.contains(drift[arch + '_preflight_c'])
		assert drift[arch + '_drift'] == digest(area + 'preflight-drift-' + arch + '.log') && os.read_file(area + 'preflight-drift-' + arch + '.log')! == ''
		assert linux['kernel'] == digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/vmlinuz-' + arch)
		assert os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: JIT page sizes')
		mut artifacts := {'compiler': digest(compiler), 'compiler_inputs': digest(compiler_root + 'compiler-inputs.json'), 'compiler_recovery': digest(compiler_root + 'compiler-recovery.json'), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'reference_controller': digest(area + 'reference'), 'audit': digest(@FILE), 'audit_executable': digest(os.executable()), 'review': digest(review), 'before_kernel': before_hash, 'after_kernel': after_hash, 'before_kernel_c': digest(area + 'before-' + suffix + '.c'), 'after_kernel_c': digest(kernel_c), 'preview': digest(area + 'preview-' + suffix + '.c')}
		for label, path in {'word_kernel_c': area + 'word-' + suffix + '.c', 'word_kernel': area + 'word-' + suffix + '.vinix', 'word_build': area + 'word-build-' + suffix + '.log'} { artifacts[label] = digest(path) }
		assert os.read_file(candidate + '/access/serial.log')!.contains('LINUX ACCESS PASS: pipe inode ownership and real/effective permissions')
		for phase, state in {'qmp': area + 'diagnostic-qmp-before-' + suffix, 'original_baseline': states + 'af-before-' + suffix, 'word_only': states + 'af-after-' + suffix} {
			capture := os.read_file(state + '/accessflags/serial.log')!
			if phase == 'qmp' { assert capture.contains('Path must be less than 104 bytes') && !capture.contains('LINUX ACCESSFLAGS CASES:') }
			else { assert capture.contains('LINUX ACCESSFLAGS FAIL:') && capture.split_into_lines().filter(it.starts_with('LINUX ACCESSFLAGS CASES:')).len == 6 }
			for label, path in {'receipt': state + '/receipt.json', 'serial': state + '/accessflags/serial.log', 'aggregate': state + '.log', 'source': state + '/sources/accessflagsfixture/core.v', 'probe': state + '/accessflags/init', 'c': state + '/accessflags/fixture.c'} { artifacts['diagnostic_' + phase + '_' + label] = digest(path) }
			publish(state + '/receipt.json', out + 'accessflags-diagnostic-' + phase + '-' + arch + '.json')!; publish(state + '/accessflags/serial.log', out + 'accessflags-diagnostic-' + phase + '-' + arch + '-native.log')!
		}
		artifacts['diagnostic_preview'] = digest(area + 'diagnostic-preview-arm.log'); artifacts['diagnostic_preview_source'] = digest(area + 'diagnostic-source.v')
		for key, hash in before { artifacts['before_' + key] = hash }; for key, hash in after { artifacts['after_' + key] = hash }; for key, hash in linux { artifacts['reference_' + key] = hash }
		artifacts['reference_receipt'] = digest(reference + '/receipt.json'); artifacts['reference_aggregate'] = digest(reference + '.log')
		for key, hash in drift { artifacts['preflight_' + key] = hash }; artifacts['preflight_drift_pins'] = digest(area + 'preflight-drift-pins.json')
		for phase in ['before', 'after'] {
			state := if phase == 'after' { candidate } else { baseline }; publish(state + '.log', out + 'accessflags-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'accessflags-' + phase + '-' + arch + '.json')!; publish(state + '/accessflags/serial.log', out + 'accessflags-' + phase + '-' + arch + '-native.log')!
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_text := os.read_file(build)!; assert build_text.contains('-o bin/vinix') && !build_text.contains('Error ') && !build_text.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
		}
		publish(reference + '.log', out + 'accessflags-reference-' + arch + '.log')!; publish(reference + '/serial.log', out + 'accessflags-reference-' + arch + '-native.log')!; publish(reference + '/receipt.json', out + 'accessflags-reference-' + arch + '.json')!
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		context := 'Native faccessat2 flags and anonymous pipe ownership. Root/UID1000 run [2800,400,15] controls each across known/unknown low flags, five upper-register patterns, full-width bad pointers, absolute/relative/empty paths, three aliases for regular/directory/unlinked O_PATH/pipe resources and real EACCES/ENOENT/ENOTDIR/EBADF/EFAULT/EINVAL behavior. Total6430 per architecture. Baselines fail3623: root1792 and UID1828 permission/flag controls plus three incorrect pipe-owner metadata checks. Same musl ELF and exact C pass both native candidates and actual Linux6.12.51. Additional low-word access fixture checks equal UID/GID1000 and real1000/effective0 pipe ownership and permissions. Existing scalar VFS/descriptor ownership and cleanup stay unchanged. Pipe UID/GID initialize before resource boxing/publication; flags narrow before validation and dispatch. Whole generated C changes only the two existing bodies/prototypes; intermediate word-only C separately proves each stage. Nine explicit probe allocas, no hidden heap/index helpers. Two warmed/settled200-cycle stable-inode/alias cohorts retain every slab and observed large pages flat; process/pipe churn and physical exhaustion are separate. Six production builds (including intermediate), five final guest cases per architecture, eight host files,63 frozen kernel inputs, allocation-site comparisons, exact preflight/native/Linux bytes, deliberately failing audit controls and independent review are bound. Initial QMP path-length failures, probe type-check failure and semantic word-only profiles remain diagnostic artifacts; only fresh v2 profiles qualify the final source. Prior self-contained f635 compiler and its15146 pins/recovery record are reused. Concurrent credentials, fsuid/fsgid extensions, named FIFOs, GNU/translated/ELF32 and three broad roadmap gates remain separate.'
		os.write_file(out + 'accessflags-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log', 'preflight-drift-pins.json', 'preflight-drift-aarch64.log', 'preflight-drift-x86_64.log'] { publish(area + name, out + 'accessflags-' + name)! }
	publish(area + 'diagnostic-preview-arm.log', out + 'accessflags-diagnostic-preview-arm.log')!
	println('Native accessflags conformance audit: PASS')
}
