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
		rows := log.split_into_lines().filter(it.starts_with('LINUX PROCPID ' + label)); assert rows.len == 24
		mut seen := map[string]bool{}; mut calls := 0; mut failures := 0
		for row in rows {
			fields := row.fields(); assert fields.len == 8
			for i, prefix in {3: 'ordinary=', 4: 'namespace=', 5: 'kind=', 6: 'calls=', 7: 'failures='} { assert fields[i].starts_with(prefix) }
			ordinary := fields[3].all_after('=').int(); namespace := fields[4].all_after('=').int(); kind := fields[5].all_after('=').int()
			assert ordinary in [0, 1] && namespace in [0, 1] && kind in [0, 1, 2, 3, 4, 5]
			key := '${ordinary}-${namespace}-${kind}'; assert key !in seen; seen[key] = true
			n := fields[6].all_after('=').int(); f := fields[7].all_after('=').int()
			assert n == [135, 45, 90, 180, 90, 108]![kind] && f == if passing { 0 } else { [0, 0, 90, 0, 0, 0]![kind] }
			if label == 'CASES:' { snapshots[key] = '${n}/${f}' } else { assert snapshots[key] == '${n}/${f}' }
			calls += n; failures += f
		}; assert calls == 2592 && failures == if passing { 0 } else { 360 }
	}
	if passing { assert !log.contains('LINUX PROCPID DETAIL:') && !log.contains('LINUX PROCPID FAIL:') }
	else { assert log.contains('LINUX PROCPID DETAIL:') && log.contains('LINUX PROCPID FAIL:') && !log.contains('LINUX PROCPID: PASS') && !log.contains('LINUX PROCPID STORAGE:') }
	if reference { assert passing && log.contains('LINUX PROCPID REFERENCE: PASS') && log.contains('Linux version 6.12.51-0-virt') && !log.contains('Kernel panic') && !log.contains('LINUX PROCPID STORAGE:') }
	else if passing { assert log.split_into_lines().filter(it.trim_space() == 'LINUX PROCPID: PASS').len == 1 && !log.contains('LINUX PROCPID REFERENCE: PASS') }
}
fn failure(log string, arch string) { assert log.contains('LINUX PROCPID DETAIL:'), 'procpid baseline failure markers required'; semantics(log, false, false, arch) }
fn storage(log string, arch string) {
	mut slabs := [4]int{}; mut pages := [4]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines() {
		if !row.starts_with('LINUX PROCPID SLAB:') && !row.starts_with('LINUX PROCPID STORAGE:') { continue }
		fields := row.fields(); assert fields.len == 8 && fields[3].starts_with('ordinary=') && fields[4].starts_with('namespace=')
		ordinary := fields[3].all_after('=').int(); namespace := fields[4].all_after('=').int(); assert ordinary in [0, 1] && namespace in [0, 1]; group := namespace * 2 + ordinary
		pair := fields[6].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' { key := fields[3] + '-' + fields[4] + '-' + fields[5]; assert key !in seen && fields[7] == 'cycles=200'; seen[key] = true; slabs[group]++ }
		else {
			assert fields[5] == 'cycles=200' && fields[7] == 'PASS'
			expected := if arch == 'aarch64' { if namespace == 0 { '74' } else { '80' } } else { if namespace == 0 { '188' } else { '199' } }
			assert pair[0] == expected; pages[group]++
		}
	}; for group in 0 .. 4 { assert slabs[group] == if arch == 'aarch64' { 18 } else { 14 }; assert pages[group] == 1 }
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
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/procpidreferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/procpid-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/procpidreferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, true, true, arch); return artifacts
}

fn diagnostic(area string, out string, arch string, suffix string) !map[string]string {
	state := area + 'diagnostic-final-procpid-before-' + suffix
	value := object(state + '/receipt.json')!
	assert value['architecture']!.str() == arch
	rows := value['results']!.as_array(); assert rows.len == 1
	entry := rows[0].as_map()
	assert entry['name']!.str() == 'procpid' && entry['exit_code']!.int() == 1 && entry['detail']!.str() == 'Command failed'
	assert entry['init_sha256']!.str() == '' && entry['iso_sha256']!.str() == ''
	assert !os.exists(state + '/procpid/init') && !os.exists(state + '/procpid/test.iso') && !os.exists(state + '/procpid/serial.log')
	mut artifacts := map[string]string{}
	for label, path in {'receipt': state + '/receipt.json', 'aggregate': state + '.log', 'source': state + '/sources/procpidfixture/core.v', 'c': state + '/procpid/fixture.c', 'serial_c': state + '/procpid/serial.c', 'preflight_c': area + 'diagnostic-preflight-' + suffix + '/fixture.c'} { artifacts[label] = digest(path) }
	assert artifacts['source'] == entry['source_sha256']!.str() && artifacts['source'] == 'b268c704f2a5d2e268137a121d359014cf68e1dbcc4909578549dde8954f5d0a'
	log := os.read_file(state + '.log')!; assert log.contains('error:') && log.contains('LINUX PROCPID SLAB:') && !log.contains('LINUX PROCPID: PASS')
	assert artifacts['c'] == artifacts['preflight_c']
	publish(state + '.log', out + 'procpid-diagnostic-before-' + arch + '.log')!
	publish(state + '/receipt.json', out + 'procpid-diagnostic-before-' + arch + '.json')!
	os.write_file(out + 'procpid-diagnostic-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: 'Superseded host compilation failure: slab logging omitted a printf argument. No probe ELF, ISO or guest execution existed. Exit 1 and empty init/ISO hashes are build diagnostics, not the semantic baseline. The corrected fresh probes and semantic baselines are published separately.', base_commit: os.read_file(area + 'base.txt')!.trim_space(), artifacts: artifacts}, prettify: true) + '\n')!
	return artifacts
}

fn erase(source string) string {
 names := ['fs__procfs_lookup_refresh_locked']; mut kept := []string{}; mut inside := false; mut separator := false; mut removed := 0
 for line in source.split_into_lines() {
 if inside { if line == '}' { inside = false; separator = true }; continue }
 if separator { assert line == ''; separator = false; continue }
 if line != '' && line[0] != `\t` && names.any(line.contains(' ' + it + '(')) { assert line.ends_with(';') || line.ends_with('{'); inside = line.ends_with('{'); removed++; continue }
 kept << line
 }; assert !inside && removed == 2; return kept.join('\n')
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!, os.args[3]); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/procpid-20261014/'; out := root + 'tests/linux-compat/results/2026-10-14/'; compiler_root := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/'; compiler := compiler_root + 'compiler/v'; states := area + 'states/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', states + 'final-procpid-after-arm/procpid/serial.log', 'aarch64'], 'procpid baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == 'a51d6a215d91fe47b84e1d544487f7e62ec1e759'
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
	paths := ['kernel/fs/procfs.v']; review := out + 'procpid-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent procpid lifetime review: PASS')
	for path in paths { assert review_text.contains(inputs[path]) && inputs[path] == digest(root + path) }
	assert review_text.contains(digest(root + 'tests/linux-compat/procpidfixture/core.v'))
	drift := strings(area + 'preflight-drift-pins.json')!; assert drift.len == 8
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == paths
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		kernel_c := tree + 'kernel/obj/blob.c'; assert erase(os.read_file(area + 'before-' + suffix + '.c')!) == erase(os.read_file(kernel_c)!), 'whole generated C outside one lookup body/prototype'; assert review_text.contains(digest(kernel_c))
		preview := os.read_file(area + 'preview-' + suffix + '.c')!; assert preview.count('alloca(') == 19; for forbidden in ['memdup(', 'malloc(', 'new_array', 'v_fixed_index'] { assert !preview.contains(forbidden) }
		before_hash := digest(area + 'baseline-' + suffix + '/kernel/bin/vinix'); after_hash := digest(tree + 'kernel/bin/vinix')
		baseline := states + 'final-procpid-before-' + suffix; candidate := states + 'final-procpid-after-' + suffix; reference := states + 'final-procpid-reference-' + suffix
		before := receipt(baseline, arch, before_hash, ['procpid'], true)!; after := receipt(candidate, arch, after_hash, ['procpid', 'proctask', 'procself', 'open', 'runtime'], false)!
		assert before['procpid_source'] == after['procpid_source'] && before['procpid_init'] == after['procpid_init'] && before['procpid_c'] == after['procpid_c'] && after['procpid_c'] == digest(area + 'preview-' + suffix + '.c')
		failure(os.read_file(baseline + '/procpid/serial.log')!, arch); log := os.read_file(candidate + '/procpid/serial.log')!; semantics(log, true, false, arch); storage(log, arch); assert review_text.contains(digest(candidate + '/procpid/serial.log'))
		linux := reference_receipt(reference, arch, after['procpid_init'])!; assert review_text.contains(linux['serial']) && review_text.contains(linux['wrapper_c']) && review_text.contains(linux['probe'])
		preflight := states + 'preflight-procpid-' + suffix
		assert digest(preflight + '/init') == after['procpid_init'] && drift[arch + '_elf'] == after['procpid_init']
		assert drift[arch + '_native_c'] == after['procpid_c'] && drift[arch + '_preflight_c'] == after['procpid_c'] && drift[arch + '_preflight_c'] == digest(preflight + '/fixture.c') && review_text.contains(drift[arch + '_preflight_c'])
		assert drift[arch + '_drift'] == digest(area + 'preflight-drift-' + arch + '.log') && os.read_file(area + 'preflight-drift-' + arch + '.log')! == ''
		assert linux['kernel'] == digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/vmlinuz-' + arch)
		assert os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: JIT page sizes')
		mut artifacts := {'compiler': digest(compiler), 'compiler_inputs': digest(compiler_root + 'compiler-inputs.json'), 'compiler_recovery': digest(compiler_root + 'compiler-recovery.json'), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'reference_controller': digest(area + 'reference'), 'audit': digest(@FILE), 'audit_executable': digest(os.executable()), 'review': digest(review), 'before_kernel': before_hash, 'after_kernel': after_hash, 'before_kernel_c': digest(area + 'before-' + suffix + '.c'), 'after_kernel_c': digest(kernel_c), 'preview': digest(area + 'preview-' + suffix + '.c')}
		for key, hash in diagnostic(area, out, arch, suffix)! { artifacts['diagnostic_' + key] = hash }
		for key, hash in before { artifacts['before_' + key] = hash }; for key, hash in after { artifacts['after_' + key] = hash }; for key, hash in linux { artifacts['reference_' + key] = hash }
		artifacts['reference_receipt'] = digest(reference + '/receipt.json'); artifacts['reference_aggregate'] = digest(reference + '.log')
		for key, hash in drift { artifacts['preflight_' + key] = hash }; artifacts['preflight_drift_pins'] = digest(area + 'preflight-drift-pins.json')
		for phase in ['before', 'after'] {
			state := if phase == 'after' { candidate } else { baseline }; publish(state + '.log', out + 'procpid-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'procpid-' + phase + '-' + arch + '.json')!; publish(state + '/procpid/serial.log', out + 'procpid-' + phase + '-' + arch + '-native.log')!
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_text := os.read_file(build)!; assert build_text.contains('-o bin/vinix') && !build_text.contains('Error ') && !build_text.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
		}
		publish(reference + '.log', out + 'procpid-reference-' + arch + '.log')!; publish(reference + '/serial.log', out + 'procpid-reference-' + arch + '-native.log')!; publish(reference + '/receipt.json', out + 'procpid-reference-' + arch + '.json')!
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		context := 'Cached numeric procfs process-root invalidation. Root/UID1000 in initial/one-level PID namespaces run [135,45,90,180,90,108] controls across three mounts, stat/status/directory leaves and five libc/raw open/openat forms with native high words and original/dup/CLOEXEC root handles. Total2592 controls per architecture; observed baselines fail360 in reaped-process opens. Live self/two children and WNOWAIT zombie controls succeed; after waitpid and independent kill0 ESRCH, repeated cached PID paths require ENOENT without procfs polling/listing. Live sibling/self and dot/dotdot/self/thread-self/sys/version controls plus missing PID0/maxpositive errors preserve ordinary reachability. Nine root aliases and eighteen retained child stat/directory aliases preserve dev/ino/mode/FD flags after unlink; no detached nlink/content/relative lookup claim. Existing scalar task_attached(pid,pid) checks registration under pid_lock, keeps zombies visible and returns no borrowed pointer; the lock releases before the existing namespace drop helper under procfs_lock. Only the procfs lookup body changes; dot/static/other process directories are excluded by root/view/numeric/resource-kind guards. No new helper, field, allocation or reclamation is added. Four warm/settled200-cycle cohorts measure repeated live/missing process paths and temporary root aliases with all slabs/large pages flat, not creation/mount churn. Four completed production builds, five candidate cases, eight host files,63 frozen kernel inputs, unchanged allocation sites/refusals, exact generated-C scope, same native C/ELF Linux6.12.51 references and independent lifetime review are bound. Assertion and passing-as-baseline controls execute. Reuses the prior self-contained f635 compiler with frozen tracked source/GC/TCC pins and its published recovery record; no new compiler recovery is claimed. Exact PID reuse/generation retention, concurrent reap-after-positive-check races, relative lookup/read through inherited reaped-process handles, namespace/mount teardown, tree reclamation/churn, GNU/translated/ELF32 and three broad roadmap gates remain separate.'
		os.write_file(out + 'procpid-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log', 'preflight-drift-pins.json', 'preflight-drift-aarch64.log', 'preflight-drift-x86_64.log'] { publish(area + name, out + 'procpid-' + name)! }
	println('Native procpid conformance audit: PASS')
}
