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
	semantic_rows(log, passing, reference, arch, false)
}
fn semantic_rows(log string, passing bool, reference bool, arch string, diagnostic bool) {
	assert arch in ['aarch64', 'x86_64']
	mut snapshots := map[string]string{}
	for label in ['CASES:', 'FINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX PIPECMD ' + label)); assert rows.len == 8
		mut seen := map[string]bool{}; mut calls := 0; mut failures := 0
		for row in rows {
			fields := row.fields(); assert fields.len == 8
			for i, prefix in {3: 'ordinary=', 4: 'namespace=', 5: 'kind=', 6: 'calls=', 7: 'failures='} { assert fields[i].starts_with(prefix) }
			ordinary := fields[3].all_after('=').int(); namespace := fields[4].all_after('=').int(); kind := fields[5].all_after('=').int()
			assert ordinary in [0, 1] && namespace == 0 && kind in [0, 1, 2, 3]
			key := '${ordinary}-${namespace}-${kind}'; assert key !in seen; seen[key] = true
			n := fields[6].all_after('=').int(); f := fields[7].all_after('=').int()
			expected := [950, 250, 338, 48]![kind]
			assert n == expected && f == if passing { 0 } else { [800, 0, 62, 0]![kind] }
			if label == 'CASES:' { snapshots[key] = '${n}/${f}' } else { assert snapshots[key] == '${n}/${f}' }
			calls += n; failures += f
		}; assert calls == 3172 && failures == if passing { 0 } else { 1724 }
	}
	if passing { assert !log.contains('LINUX PIPECMD DETAIL:') && (diagnostic || !log.contains('LINUX PIPECMD FAIL:')) }
	else { assert log.contains('LINUX PIPECMD DETAIL:') && log.contains('LINUX PIPECMD FAIL:') && !log.contains('LINUX PIPECMD: PASS') && !log.contains('LINUX PIPECMD STORAGE:') }
	if reference { assert passing && log.contains('LINUX PIPECMD REFERENCE: PASS') && log.contains('Linux version 6.12.51-0-virt') && !log.contains('Kernel panic') && !log.contains('LINUX PIPECMD STORAGE:') }
	else if passing && !diagnostic { assert log.split_into_lines().filter(it.trim_space() == 'LINUX PIPECMD: PASS').len == 1 && !log.contains('LINUX PIPECMD REFERENCE: PASS') }
}
fn failure(log string, arch string) { assert log.contains('LINUX PIPECMD DETAIL:'), 'pipecmd baseline failure markers required'; semantics(log, false, false, arch) }
fn storage(log string, arch string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines() {
		if !row.starts_with('LINUX PIPECMD SLAB:') && !row.starts_with('LINUX PIPECMD STORAGE:') { continue }
		fields := row.fields(); assert fields.len == 8 && fields[3].starts_with('ordinary=') && fields[4].starts_with('namespace=')
		ordinary := fields[3].all_after('=').int(); namespace := fields[4].all_after('=').int(); assert ordinary in [0, 1] && namespace == 0; group := ordinary
		pair := fields[6].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' { key := fields[3] + '-' + fields[4] + '-' + fields[5]; assert key !in seen && fields[7] == 'cycles=200'; seen[key] = true; slabs[group]++ }
		else {
			assert fields[5] == 'cycles=200' && fields[7] == 'PASS'
			assert pair[0].u64() > 0
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
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/pipecmdreferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/pipecmd-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/pipecmdreferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, true, true, arch); return artifacts
}

// The errno-only kernel passes semantics but fails the measured storage gate.
// Keep that intermediate failure separate from the original wrong-errno baseline.
fn leak_baseline(area string, out string, arch string, suffix string, init string, source string) !map[string]string {
	state := area + 'states/p2-after-' + suffix; value := object(state + '/receipt.json')!
	assert value['architecture']!.str() == arch
	assert value['kernel_sha256']!.str() == digest(area + 'errno-only-' + suffix + '/kernel/bin/vinix') && value['kernel_sha256']!.str() == digest(state + '/kernel/bin/vinix')
	rows := value['results']!.as_array(); assert rows.len == 5
	mut result := map[string]string{}
	for index, row in rows {
		entry := row.as_map(); name := entry['name']!.str(); assert name == ['pipecmd', 'fcntlabi', 'fcntlpath', 'open', 'runtime'][index]
		assert entry['exit_code']!.int() == if index == 0 { 1 } else { 0 } && entry['detail']!.str() == ''
		for label, path in {'source_sha256': state + '/sources/' + name + 'fixture/core.v', 'init_sha256': state + '/' + name + '/init', 'iso_sha256': state + '/' + name + '/test.iso'} { assert entry[label]!.str() == digest(path); result[name + '_' + label] = digest(path) }
		result[name + '_c'] = digest(state + '/' + name + '/fixture.c'); result[name + '_serial'] = digest(state + '/' + name + '/serial.log')
		if index > 0 { assert os.read_file(state + '/' + name + '/serial.log')!.contains('LINUX ' + name.to_upper() + ': PASS') }
	}
	assert result['pipecmd_init_sha256'] == init && result['pipecmd_source_sha256'] == source
	log := os.read_file(state + '/pipecmd/serial.log')!; semantic_rows(log, true, false, arch, true)
	assert !log.contains('LINUX PIPECMD DETAIL:') && log.contains('LINUX PIPECMD FAIL: pipe commands or retained state') && !log.contains('LINUX PIPECMD: PASS')
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines().filter(it.starts_with('LINUX PIPECMD SLAB:') || it.starts_with('LINUX PIPECMD STORAGE:')) {
		fields := row.fields(); assert fields.len == 8; group := fields[3].all_after('=').int(); assert group in [0,1] && fields[4] == 'namespace=0'
		pair := fields[6].all_after('=').split('/'); assert pair.len == 2
		if fields[2] == 'SLAB:' { key := fields[3] + fields[5]; assert key !in seen; seen[key] = true; slabs[group]++; assert fields[7] == 'cycles=200'; assert pair[1].int() - pair[0].int() == if fields[5] == 'size=16' { 4000 } else { 0 } }
		else { assert fields[5] == 'cycles=200' && fields[7] == 'FAIL' && pair[0] == pair[1] && pair[0].u64() > 0; pages[group]++ }
	}
	for group in 0 .. 2 { assert slabs[group] == if arch == 'aarch64' { 18 } else { 14 }; assert pages[group] == 1 }
	for label, path in {'receipt': state + '/receipt.json', 'aggregate': state + '.log', 'native': state + '/pipecmd/serial.log', 'kernel_c': area + 'errno-only-' + suffix + '.c', 'build': area + 'build-errno-' + suffix + '.log'} {
		result[label] = digest(path)
		if label in ['receipt', 'aggregate', 'native', 'build'] { publish(path, out + 'pipecmd-errno-only-' + arch + '-' + label + if label == 'receipt' { '.json' } else { '.log' })! }
	}
	return result
}
fn tracked_sites(area string, out string) !map[string]string {
	serial := os.read_file(area + 'states/track-arm/serial.log')!
	assert serial.contains('live 4005 dropped 0') && serial.contains('LINUX PIPECMD STORAGE: ordinary=0 namespace=0 cycles=200 big_pages=75/75 FAIL')
	rows := serial.split_into_lines().filter(it.fields().len == 12 && it.fields()[0] == '2000' && it.fields()[1] == '16'); assert rows.len == 2
	assert os.read_file(area + 'track-sites.log')! == rows.map('PERF-SITE pipecmd ' + it.fields().join(' ')).join('\n') + '\n'
	named := os.read_file(area + 'track-named-sites.log')!; assert named.count('2000 x 16 bytes') == 2 && named.contains('file__syscall_fcntl') && named.contains('resource__pipe_capacity') && named.contains('resource__set_pipe_capacity')
	build := os.read_file(area + 'build-track-arm.log')!; assert build.contains('-d alloc_track') && build.contains('-o bin/vinix') && !build.contains('Error ')
	mut result := map[string]string{}
	for name, path in {'serial': area + 'states/track-arm/serial.log', 'sites': area + 'track-sites.log', 'named_sites': area + 'track-named-sites.log', 'build': area + 'build-track-arm.log', 'source': area + 'track-source/pipecmdfixture/core.v', 'probe_c': area + 'states/track-arm/fixture.c', 'probe': area + 'states/track-arm/init', 'kernel': area + 'tracked-arm/kernel/bin/vinix', 'kernel_c': area + 'track-arm.c'} {
		result['tracked_' + name] = digest(path)
		if name in ['serial', 'sites', 'named_sites', 'build'] { publish(path, out + 'pipecmd-tracked-' + name + '.log')! }
	}
	return result
}
fn reference_setup_failure(area string, out string, arch string, suffix string, init string) !map[string]string {
	state := area + 'states/p2-reference-' + suffix; value := object(state + '/receipt.json')!
	assert value['architecture']!.str() == arch && !value['passed']!.bool() && value['finished']!.bool()
	artifacts := value['artifacts']!.as_map_of_strings(); assert artifacts['probe'] == init && artifacts['probe'] == digest(state + '/probe')
	assert artifacts['controller_source'] == digest(area + 'diagnostic-reference-controller.v')
	assert !os.read_file(area + 'diagnostic-reference-controller.v')!.contains("'dev/null'")
	log := os.read_file(state + '/serial.log')!; assert log.contains('Kernel panic') && !log.contains('LINUX PIPECMD CASES:') && !log.contains('LINUX PIPECMD REFERENCE: PASS')
	mut result := map[string]string{}
	for label, path in {'receipt': state + '/receipt.json', 'serial': state + '/serial.log', 'aggregate': state + '.log', 'controller': area + 'diagnostic-reference-controller.v'} {
		result['setup_failure_' + label] = digest(path)
		if label != 'controller' { publish(path, out + 'pipecmd-reference-setup-failure-' + arch + '-' + label + if label == 'receipt' { '.json' } else { '.log' })! }
	}
	return result
}


fn performance(area string, out string) !map[string]string {
	mut result := map[string]string{}
	mut measure := ''; mut desktop := ''; mut source := ''
	for phase in ['after'] { for profile in ['ops', 'desktop'] {
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
		if profile == 'ops' {
			assert counts['PERF-OPS'] == 36 && counts['PERF-CHURN'] == 4 && counts['PERF-CACHE'] == 1 && rows.len == 41; assert !log.contains('PERF-SLAB ')
			operations := log.split_into_lines().filter(it.starts_with('PERF-OPS ')); assert operations.len == 36
			for row in operations { fields := row.fields(); assert fields.len == 8 && fields[1] == 'variant=new' && fields[2] == 'scenario=ops' && fields[3] == 'round=1' && fields[6] == 'count=200' && fields[7] == 'bytes_per_op=0' }
		}
		else { assert rows.len == 3 && seen.len == 3 }
		prefix := 'perf_' + phase + '_' + profile
		for name, path in {'serial': work + '/serial.log', 'result': work + '/result.json', 'aggregate': area + 'perf-' + phase + '-' + profile + '.log', 'stage_pins': work + '/stage-pins.json'} {
			result[prefix + '_' + name] = digest(path); publish(path, out + 'pipecmd-perf-' + phase + '-' + profile + '-' + name + if name in ['result', 'stage_pins'] { '.json' } else { '.log' })!
		}
		for name in ['kernel', 'measure', 'config', 'vinix-desktop-new', 'measure.c'] { result[prefix + '_' + name] = pins[name] }
	} }
	result['perf_image'] = digest(area + 'perf-inputs/image.tar')
	return result
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
fn body(source string, name string) string {
	mut lines := []string{}; mut inside := false
	for line in source.split_into_lines() {
		if !inside && line != '' && line[0] != `\t` && line.contains(' ' + name + '(') && line.ends_with('{') { inside = true }
		if inside { lines << line; if line == '}' { return lines.join('\n') } }
	}
	panic('missing generated body: ' + name)
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!, os.args[3]); return }
	if '--scope-only' in os.args {
		for suffix in ['arm', 'x86'] {
			area := '/Users/alex/.cache/vinix-linux-compat/pipecmd-20261014/'
			before := os.read_file(area + 'before-' + suffix + '.c')!; after := os.read_file(area + 'kernel-' + suffix + '/kernel/obj/blob.c')!
			assert before != after && erase(before, ['file__syscall_fcntl', 'resource__pipe_capacity', 'resource__set_pipe_capacity'], 6) == erase(after, ['file__syscall_fcntl', 'resource__pipe_capacity', 'resource__set_pipe_capacity'], 6)
			assert erase(os.read_file(area + 'errno-only-' + suffix + '.c')!, ['resource__pipe_capacity', 'resource__set_pipe_capacity'], 4) == erase(after, ['resource__pipe_capacity', 'resource__set_pipe_capacity'], 4)
		}
		println('Whole generated C outside fcntl and capacity bodies/prototypes: PASS'); return
	}
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/pipecmd-20261014/'; out := root + 'tests/linux-compat/results/2026-10-14/'; compiler_root := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/'; compiler := compiler_root + 'compiler/v'; states := area + 'states/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', states + 'p3-after-arm/pipecmd/serial.log', 'aarch64'], 'pipecmd baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == 'f6d7c868c15bee486447baea44d0ea04aaa215cf'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 64
	mut qualified_inputs := inputs.clone()
	qualified_inputs['kernel/resource/cache.v'] = digest(root + 'kernel/resource/cache.v')
	final_sources := strings(area + 'candidate-inputs.json')!; assert final_sources.len == 2
	for path, hash in final_sources { assert hash == qualified_inputs[path] }
	assert os.read_file(compiler_root + 'compiler-commit.txt')!.trim_space() == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c'
	pins := strings(compiler_root + 'compiler-inputs.json')!; assert pins.len == 15146 && pins['v'] == digest(compiler)
	for path, hash in pins { assert digest(compiler_root + 'compiler/' + path) == hash, 'compiler input drift: ' + path }
	recovery := object(compiler_root + 'compiler-recovery.json')!; assert recovery['local_binary']!.str() == digest(compiler) && recovery['old_binary']!.str() == digest(compiler_root + 'pre-restore-v') && recovery['old_binary']!.str() == 'f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39' && recovery['inputs_manifest']!.str() == digest(compiler_root + 'compiler-inputs.json')
	assert recovery['rebuild_log']!.str() == digest(compiler_root + 'compiler-rebuild.log')
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	for arch, count in {'aarch64': '400', 'x86_64': '292'} { for log in [before_allocs, after_allocs] { assert log.split_into_lines().filter(it.starts_with(arch + ': ')).len == 1 && log.split_into_lines().filter(it.starts_with(arch + ': '))[0].contains(count + ' allocation sites (V exit 0)') } }
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	paths := ['kernel/file/file.v', 'kernel/resource/cache.v']; review := out + 'pipecmd-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent pipecmd lifetime review: PASS')
	for path in paths { assert review_text.contains(qualified_inputs[path]) && qualified_inputs[path] == digest(root + path) }
	assert review_text.contains(digest(root + 'tests/linux-compat/pipecmdfixture/core.v'))
	perf := performance(area, out)!; tracked := tracked_sites(area, out)!
	drift := strings(area + 'preflight-drift-pins.json')!; assert drift.len == 8
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == paths
		assert object(tree + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings() == inputs
		for path, hash in inputs { if path.starts_with('kernel/') || path == 'tools/linux-compat/coverage.v' { assert digest(tree + path) == hash } }
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'tools'])! == ''
		assert inputs['kernel/file/file.v'] == digest(root + 'kernel/file/file.v')
		assert qualified_inputs['kernel/resource/cache.v'] == digest(tree + 'kernel/resource/cache.v')
		kernel_c := tree + 'kernel/obj/blob.c'; assert erase(os.read_file(area + 'before-' + suffix + '.c')!, ['file__syscall_fcntl', 'resource__pipe_capacity', 'resource__set_pipe_capacity'], 6) == erase(os.read_file(kernel_c)!, ['file__syscall_fcntl', 'resource__pipe_capacity', 'resource__set_pipe_capacity'], 6), 'whole generated C outside fcntl body/prototype'; assert review_text.contains(digest(kernel_c))
		assert erase(os.read_file(area + 'errno-only-' + suffix + '.c')!, ['resource__pipe_capacity', 'resource__set_pipe_capacity'], 4) == erase(os.read_file(kernel_c)!, ['resource__pipe_capacity', 'resource__set_pipe_capacity'], 4)
		for name in ['resource__pipe_capacity', 'resource__set_pipe_capacity'] {
			old := body(os.read_file(area + 'errno-only-' + suffix + '.c')!, name); current := body(os.read_file(kernel_c)!, name)
			assert old.count('memdup(') == 1 && current.contains('PipeCapacityResource backend =') && current.contains('PipeCapacityResource* stack = &backend;')
			for helper in ['memdup(', 'malloc(', 'new_array', 'v_fixed_index'] { assert !current.contains(helper) }
		}

		preview := os.read_file(area + 'preview-' + suffix + '.c')!; assert preview.count('alloca(') == 12; for forbidden in ['memdup(', 'malloc(', 'new_array', 'v_fixed_index'] { assert !preview.contains(forbidden) }
		before_hash := digest(area + 'baseline-' + suffix + '/kernel/bin/vinix'); after_hash := digest(tree + 'kernel/bin/vinix')
		baseline := states + 'p2-before-' + suffix; candidate := states + 'p3-after-' + suffix; reference := states + 'p3-reference-' + suffix
		before := receipt(baseline, arch, before_hash, ['pipecmd'], true)!; after := receipt(candidate, arch, after_hash, ['pipecmd', 'fcntlabi', 'fcntlpath', 'open', 'runtime'], false)!
		assert before['pipecmd_source'] == after['pipecmd_source'] && before['pipecmd_init'] == after['pipecmd_init'] && before['pipecmd_c'] == after['pipecmd_c'] && after['pipecmd_c'] == digest(area + 'preview-' + suffix + '.c')
		failure(os.read_file(baseline + '/pipecmd/serial.log')!, arch); log := os.read_file(candidate + '/pipecmd/serial.log')!; semantics(log, true, false, arch); storage(log, arch); assert review_text.contains(digest(candidate + '/pipecmd/serial.log'))
		leak := leak_baseline(area, out, arch, suffix, after['pipecmd_init'], after['pipecmd_source'])!
		setup := reference_setup_failure(area, out, arch, suffix, after['pipecmd_init'])!
		linux := reference_receipt(reference, arch, after['pipecmd_init'])!; assert review_text.contains(linux['serial']) && review_text.contains(linux['wrapper_c']) && review_text.contains(linux['probe'])
		preflight := states + 'preflight2-pipecmd-' + suffix
		assert digest(preflight + '/init') == after['pipecmd_init'] && drift[arch + '_elf'] == after['pipecmd_init']
		assert drift[arch + '_native_c'] == after['pipecmd_c'] && drift[arch + '_preflight_c'] == after['pipecmd_c'] && drift[arch + '_preflight_c'] == digest(preflight + '/fixture.c') && review_text.contains(drift[arch + '_preflight_c'])
		assert drift[arch + '_drift'] == digest(area + 'preflight-drift-' + arch + '.log') && os.read_file(area + 'preflight-drift-' + arch + '.log')! == ''
		assert linux['kernel'] == digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/vmlinuz-' + arch)
		assert os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: JIT page sizes')
		mut artifacts := {'compiler': digest(compiler), 'compiler_inputs': digest(compiler_root + 'compiler-inputs.json'), 'compiler_recovery': digest(compiler_root + 'compiler-recovery.json'), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'reference_controller': digest(area + 'reference'), 'audit': digest(@FILE), 'audit_executable': digest(os.executable()), 'review': digest(review), 'before_kernel': before_hash, 'after_kernel': after_hash, 'before_kernel_c': digest(area + 'before-' + suffix + '.c'), 'after_kernel_c': digest(kernel_c), 'preview': digest(area + 'preview-' + suffix + '.c')}
		for key, hash in perf { artifacts[key] = hash }; for key, hash in tracked { artifacts[key] = hash }; for key, hash in setup { artifacts[key] = hash }; for key, hash in leak { artifacts['errno_only_' + key] = hash }
		for key, hash in before { artifacts['before_' + key] = hash }; for key, hash in after { artifacts['after_' + key] = hash }; for key, hash in linux { artifacts['reference_' + key] = hash }
		artifacts['reference_receipt'] = digest(reference + '/receipt.json'); artifacts['reference_aggregate'] = digest(reference + '.log')
		for key, hash in drift { artifacts['preflight_' + key] = hash }; artifacts['preflight_drift_pins'] = digest(area + 'preflight-drift-pins.json')
		for phase in ['before', 'after'] {
			state := if phase == 'after' { candidate } else { baseline }; publish(state + '.log', out + 'pipecmd-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'pipecmd-' + phase + '-' + arch + '.json')!; publish(state + '/pipecmd/serial.log', out + 'pipecmd-' + phase + '-' + arch + '-native.log')!
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_text := os.read_file(build)!; assert build_text.contains('-o bin/vinix') && !build_text.contains('Error ') && !build_text.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
		}
		publish(reference + '.log', out + 'pipecmd-reference-' + arch + '.log')!; publish(reference + '/serial.log', out + 'pipecmd-reference-' + arch + '-native.log')!; publish(reference + '/receipt.json', out + 'pipecmd-reference-' + arch + '.json')!
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		context := 'Native pipe-only fcntl type errors. Two non-FIFO guards and missing-capacity getter refusal return EBADF, preserving all existing descriptor unrefs and supported capacity behavior. Measured successful capacity dispatch originally leaks one 16-byte interface box per call; getter/setter now borrow a local capability synchronously without changing underlying buffer allocation or free paths. Root/UID1000 cohorts run [950,250,338,48] checks each. Linked/unlinked regular files, directories, /dev/null, UNIX sockets and O_PATH descriptions refuse both commands; real anonymous read/write ends and named FIFO aliases return their actual capacity and accept same-capacity setters. Original/dup/CLOEXEC and fixed64/65 aliases, full register patterns, ignored getter arguments, libc commands, bad descriptors, reduced limits8/0, closed/reused66, exact real errors and final metadata/flags/regular XYZ/cursor1/queued AB-CD-GH/80-slot vector are checked. Baselines fail [800,0,62,0] per cohort, total1724 of3172 per architecture. Candidates and actual same-ELF Linux6.12.51 pass3172. Two warmed200-cycle alias/query/close cohorts retain all slabs and large pages exactly flat. Six production builds and one allocation-tracked diagnostic build, five fresh guest cases per architecture, eight host test files,64 frozen inventory inputs, identical existing allocation allowance refusals, complete C scope outside fcntl/capacity bodies/prototypes, with errno-only versus final differences confined to capacity helpers, twelve fixture allocas with no hidden heap/index helpers, source/C/ELF identity and empty raw preflight drift, active assertion/passing-baseline controls and independent fixture/FD lifetime review are bound. Resizing requests beyond existing capacity, page-ring occupancy rules, privileged ceilings/budget injection, unsupported FIFO-shaped resource capability fallback, concurrent descriptor close/reuse/resize, GNU/translated/ELF32 and broad section15 gates remain separate. Fresh corrected-kernel AArch64 ops/churn/cache and idle/apps/drag controls are separately bound; the application-specific probe supplies both-architecture capacity retention qualification.'
		os.write_file(out + 'pipecmd-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: qualified_inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log', 'preflight-drift-pins.json', 'preflight-drift-aarch64.log', 'preflight-drift-x86_64.log'] { publish(area + name, out + 'pipecmd-' + name)! }
	println('Native pipecmd conformance audit: PASS')
}
