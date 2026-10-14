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
			result[prefix + '_' + name] = digest(path); publish(path, out + 'pipesize-perf-' + phase + '-' + profile + '-' + name + if name in ['result', 'stage_pins'] { '.json' } else { '.log' })!
		}
		for name in ['kernel', 'measure', 'config', 'vinix-desktop-new', 'measure.c'] { result[prefix + '_' + name] = pins[name] }
	} }
	result['perf_image'] = digest(area + 'perf-inputs/image.tar')
	return result
}
fn diagnostics(area string, out string) !map[string]string {
	mut pins := map[string]string{}
	for suffix, arch in {'arm':'aarch64','x86':'x86_64'} {
		old_probe := area + 'states/preflight2-pipesize-' + suffix + '/init'; final_probe := area + 'states/preflight3-pipesize-' + suffix + '/init'; assert digest(old_probe) != digest(final_probe)
		pins['diagnostic_prezero_' + arch + '_elf'] = digest(old_probe); pins['diagnostic_prezero_' + arch + '_c'] = digest(area + 'states/preflight2-pipesize-' + suffix + '/fixture.c')
		for phase in ['before','reference'] {
			state := area + 'states/p2-' + phase + '-' + suffix; receipt_path := state + '/receipt.json'; value := object(receipt_path)!
			assert value['architecture']!.str() == arch
			probe := if phase == 'reference' { state + '/probe' } else { state + '/pipesize/init' }; assert digest(probe) == digest(old_probe)
			log := state + if phase == 'reference' { '/serial.log' } else { '/pipesize/serial.log' }
			for label, path in {'receipt':receipt_path, 'serial':log, 'aggregate':state + '.log'} { pins['diagnostic_prezero_' + phase + '_' + arch + '_' + label] = digest(path); publish(path, out + 'pipesize-diagnostic-prezero-' + phase + '-' + arch + '-' + label + if label == 'receipt' { '.json' } else { '.log' })! }
		}
	}
	for label, path in {'unstaged_arm_c':area + 'middle-arm-unstaged-diagnostic.c', 'unstaged_arm_elf':area + 'middle-arm-unstaged-diagnostic.elf', 'unstaged_arm_build':area + 'middle-arm-unstaged-diagnostic.log', 'map_pointer_preparation':area + 'preview-arm-map-pointer-preparation.log', 'bounds_helper_c':area + 'states/preflight1-pipesize-arm/fixture.c'} { pins['diagnostic_' + label] = digest(path); if path.ends_with('.log') { publish(path, out + 'pipesize-diagnostic-' + label + '.log')! } }
	assert digest(area + 'middle-arm-unstaged-diagnostic.elf') == digest(area + 'baseline-arm/kernel/bin/vinix')
	assert os.read_file(area + 'middle-arm-unstaged-diagnostic.log')!.contains('Nothing to be done') && os.read_file(area + 'states/preflight1-pipesize-arm/fixture.c')!.contains('v_fixed_index')
	for name in ['normalization-check.log','normalization-assertion-control.log','normalization-passing-control.log'] { pins[name] = digest(area + name); publish(area + name, out + 'pipesize-' + name)! }
	return pins
}
fn preflight_drift(area string, out string, arch string, suffix string, native_c string, native_elf string) !map[string]string {
	preflight := area + 'states/preflight3-pipesize-' + suffix; current := os.read_file(native_c)!; old := os.read_file(preflight + '/fixture.c')!
	old_block := 'static FILE* v3_eprint_begin(void) {\n\tfflush(stdout);\n\tfflush(stderr);\n\treturn stderr;\n}\nstatic void v3_eprint_end(void) {\n\tfflush(stderr);\n}\n#define v3_eprintf(...) do { fprintf(v3_eprint_begin(), __VA_ARGS__); v3_eprint_end(); } while (0)\nstatic void v3_eprint_lit(const char* s) {\n\tv3_eprintf("%s", s);\n}\nstatic void v3_eprintln_string(string s) {\n\tv3_eprintf("%.*s\\n", s.len, (char*)s.str);\n}\n'
	new_block := 'static void v3_eprint_lit(const char* s) {\n\tfprintf(stderr, "%s", s);\n}\nstatic void v3_eprintln_string(string s) {\n\tfprintf(stderr, "%.*s\\n", s.len, (char*)s.str);\n}\n'
	assert old.count(old_block) == 1 && current.count(new_block) == 1 && old.count('v3_eprintf(') == 3 && old.replace(old_block,new_block) == current
	assert digest(preflight + '/init') == digest(native_elf)
	mut p := os.new_process('git'); p.set_args(['diff','--no-index','--',preflight + '/fixture.c',native_c]); p.set_redirect_stdio_merged(); p.run(); drift := p.stdout_slurp(); p.wait(); code := p.code; p.close(); assert code == 1 && drift.contains('v3_eprint_begin') && drift.contains('v3_eprint_end')
	path := area + 'preflight3-drift-' + arch + '.log'; os.write_file(path,drift)!; publish(path,out + 'pipesize-preflight3-drift-' + arch + '.log')!
	return {'preflight3_raw_c':digest(preflight + '/fixture.c'), 'preflight3_elf':digest(preflight + '/init'), 'preflight3_drift':digest(path)}
}
fn semantics(log string, phase string, arch string, reference bool) {
	assert phase in ['before', 'middle', 'after'] && arch in ['aarch64', 'x86_64']
	mut cases := map[string]string{}
	for label in ['CASES:', 'FINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX PIPESIZE ' + label)); assert rows.len == 20
		mut seen := map[string]bool{}; mut total := 0; mut failures := 0
		for row in rows {
			fields := row.fields(); assert fields.len == 8
			for index, prefix in {3: 'ordinary=', 4: 'capability=', 5: 'kind=', 6: 'calls=', 7: 'failures='} { assert fields[index].starts_with(prefix) }
			ordinary := fields[3].all_after('=').int(); capability := fields[4].all_after('=').int(); kind := fields[5].all_after('=').int(); assert ordinary in [0,1] && capability in [0,1] && kind in [0,1,2,3,4]
			key := fields[3] + fields[4] + fields[5]; assert key !in seen; seen[key] = true
			n := fields[6].all_after('=').int(); f := fields[7].all_after('=').int()
			assert n == if kind == 2 { if capability == 1 { 194 } else { 240 } } else { [1000,722,0,28,48]![kind] }
			expected := if phase == 'after' { 0 } else if kind == 2 && capability == 1 { 188 } else if phase == 'before' && kind == 1 { 257 } else if phase == 'before' && kind == 0 && arch == 'aarch64' { 435 } else { 0 }
			assert f == expected, row
			if label == 'CASES:' { cases[key] = fields[6] + fields[7] } else { assert cases[key] == fields[6] + fields[7] }
			total += n; failures += f
		}; assert total == 8060 && failures == if phase == 'after' { 0 } else if phase == 'middle' { 376 } else if arch == 'aarch64' { 3144 } else { 1404 }
	}
	assert !log.contains('Kernel panic') && !log.contains('LINUX PIPESIZE FAIL: setup')
	if phase == 'after' { assert !log.contains('LINUX PIPESIZE DETAIL:') && !log.contains('LINUX PIPESIZE FAIL:') }
	else { assert log.contains('LINUX PIPESIZE DETAIL:'), 'pipesize baseline failure markers required'; assert log.contains('LINUX PIPESIZE FAIL:') && !log.contains('LINUX PIPESIZE: PASS') }
	if reference { assert phase == 'after' && log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX PIPESIZE REFERENCE: PASS') && !log.contains('LINUX PIPESIZE STORAGE:') }
	else if phase == 'after' { assert log.count('LINUX PIPESIZE: PASS') == 1 }
	pages := log.split_into_lines().filter(it.starts_with('LINUX PIPESIZE PAGE:')); assert pages.len == 4
	for row in pages { fields := row.fields(); assert fields.len == 7 && fields[5] == 'bytes=' + if arch == 'aarch64' && !reference { '16384' } else { '4096' } && fields[6] == 'reference=' + if reference { '1' } else { '0' } }
}
fn storage(log string, arch string, phase string) {
	mut slabs := [4]int{}; mut pages := [4]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines().filter(it.starts_with('LINUX PIPESIZE SLAB:') || it.starts_with('LINUX PIPESIZE STORAGE:')) {
		fields := row.fields(); assert fields.len == 8 && fields[3].starts_with('ordinary=') && fields[4].starts_with('capability=')
		ordinary := fields[3].all_after('=').int(); capability := fields[4].all_after('=').int(); assert ordinary in [0,1] && capability in [0,1]; group := ordinary * 2 + capability
		pair := fields[6].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' { assert fields[5].starts_with('size=') && fields[7] == 'cycles=200'; key := fields[3] + fields[4] + fields[5]; assert key !in seen; seen[key] = true; slabs[group]++ }
		else { assert fields[5] == 'cycles=200' && fields[7] == 'PASS' && pair[0].u64() > 0; pages[group]++ }
	}
	for group in 0 .. 4 { expected := phase == 'after' || (phase == 'middle' && group % 2 == 0); assert slabs[group] == if expected { if arch == 'aarch64' { 18 } else { 14 } } else { 0 }; assert pages[group] == if expected { 1 } else { 0 } }
}
fn failure(log string, arch string) { assert log.contains('LINUX PIPESIZE DETAIL:'), 'pipesize baseline failure markers required'; semantics(log, 'before', arch, false) }
fn receipt(state string, arch string, kernel string, names []string, failing bool) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel && digest(state + '/kernel/bin/vinix') == kernel
	rows := value['results']!.as_array(); assert rows.len == names.len
	mut artifacts := {'receipt': digest(state + '/receipt.json'), 'aggregate': digest(state + '.log')}
	for index, row in rows {
		entry := row.as_map(); name := entry['name']!.str(); assert name == names[index] && entry['exit_code']!.int() == if failing && index == 0 { 1 } else { 0 } && entry['detail']!.str() == ''
		for label, path in {'source': state + '/sources/' + name + 'fixture/core.v', 'init': state + '/' + name + '/init', 'iso': state + '/' + name + '/test.iso'} { hash := digest(path); key := if label == 'source' { 'source_sha256' } else if label == 'init' { 'init_sha256' } else { 'iso_sha256' }; assert hash == entry[key]!.str(); artifacts[name + '_' + label] = hash }
		assert artifacts[name + '_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/' + name + 'fixture/core.v')
		artifacts[name + '_c'] = digest(state + '/' + name + '/fixture.c'); artifacts[name + '_serial'] = digest(state + '/' + name + '/serial.log')
		if !failing || index > 0 { assert os.read_file(state + '/' + name + '/serial.log')!.contains('LINUX ' + name.to_upper() + ': PASS') }
	}; return artifacts
}
fn reference_receipt(state string, arch string, init string) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['passed']!.bool() && value['finished']!.bool() && value['forced']!.bool() && value['status']!.int() == 0
	artifacts := value['artifacts']!.as_map_of_strings(); command := value['command']!.as_array().map(it.str()); assert command.contains('-kernel') && command.contains('-initrd') && command.contains('-no-reboot')
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/pipesizereferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/pipesize-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/pipesizereferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, 'after', arch, true); return artifacts
}
fn scope(area string) {
	mut verdict := ''
	for suffix in ['arm', 'x86'] {
		before := os.read_file(area + 'before-' + suffix + '.c') or { panic(err) }; middle := os.read_file(area + 'middle-' + suffix + '.c') or { panic(err) }; after := os.read_file(area + 'after-' + suffix + '.c') or { panic(err) }
		assert before != middle && middle != after
		assert erase(before, ['pipe__normalized_capacity'], 2) == erase(middle, ['pipe__normalized_capacity'], 2)
		assert erase(before, ['pipe__normalized_capacity', 'pipe__Pipe__set_pipe_capacity'], 4) == erase(after, ['pipe__normalized_capacity', 'pipe__Pipe__set_pipe_capacity'], 4)
		current := body(after, 'pipe__normalized_capacity'); assert current.contains('memory__page_size') && current.contains('errno__einval') && !current.contains('errno__eperm')
		setter := body(after, 'pipe__Pipe__set_pipe_capacity'); assert setter.contains('proc__current_has_capability(')
		verdict += suffix + ': full generated C unchanged outside normalization and capacity setter bodies/prototypes\n'
	}; os.write_file(area + 'scope-check.log', verdict) or { panic(err) }
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!, os.args[3]); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/pipesize-20261014/'; out := root + 'tests/linux-compat/results/2026-10-14/'; states := area + 'states/'
	if '--scope-only' in os.args { scope(area); println('Pipe resizing C scope: PASS'); return }
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', states + 'p3-after-arm/pipesize/serial.log', 'aarch64'], 'pipesize baseline failure markers required'))!
	scope(area)
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == 'faec863268ebe028ee9c20df03ff31c720bdff2b'
	compiler_root := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/'; compiler := compiler_root + 'compiler/v'; pins := strings(compiler_root + 'compiler-inputs.json')!; assert pins.len == 15146 && pins['v'] == digest(compiler)
	for path, hash in pins { assert digest(compiler_root + 'compiler/' + path) == hash, path }
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 64
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	for arch, count in {'aarch64':'398', 'x86_64':'290'} { for log in [before_allocs, after_allocs] { assert log.split_into_lines().filter(it.starts_with(arch + ': ')).len == 1 && log.split_into_lines().filter(it.starts_with(arch + ': '))[0].contains(count + ' allocation sites (V exit 0)') } }
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	review := os.read_file(out + 'pipesize-lifetime-review.md')!; assert review.starts_with('Independent pipesize lifetime review: PASS') && review.contains(digest(root + 'kernel/pipe/pipe.v')) && review.contains(digest(root + 'tests/linux-compat/pipesizefixture/core.v'))
	perf := performance(area, out)!; diagnostic := diagnostics(area, out)!
	for arch, suffix in {'aarch64':'arm', 'x86_64':'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/pipe/pipe.v'
		assert object(tree + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings() == inputs
		for path, hash in inputs { if path.starts_with('kernel/') || path == 'tools/linux-compat/coverage.v' { assert digest(tree + path) == hash } }
		assert digest(tree + 'kernel/pipe/pipe.v') == digest(root + 'kernel/pipe/pipe.v') && review.contains(digest(tree + 'kernel/obj/blob.c'))
		mut artifacts := {'compiler':digest(compiler), 'compiler_inputs':digest(compiler_root + 'compiler-inputs.json'), 'review':digest(out + 'pipesize-lifetime-review.md'), 'kernel_source':digest(root + 'kernel/pipe/pipe.v'), 'fixture_source':digest(root + 'tests/linux-compat/pipesizefixture/core.v'), 'kernel_final':digest(tree + 'kernel/bin/vinix'), 'kernel_c_final':digest(tree + 'kernel/obj/blob.c'), 'normalization_commit_record':digest(area + 'normalization-commit.txt')}
		for key, value in perf { artifacts[key] = value }
		for key, value in diagnostic { artifacts[key] = value }
		mut identity := map[string]string{}
		for phase in ['before','middle','after'] {
			state := states + 'p3-' + phase + '-' + suffix; kernel := if phase == 'before' { area + 'baseline-' + suffix + '/kernel/bin/vinix' } else if phase == 'middle' { area + 'middle-' + suffix + '/kernel/bin/vinix' } else { tree + 'kernel/bin/vinix' }
			names := if phase == 'after' { ['pipesize','pipecmd','fcntlabi','keepcaps','capset','open','runtime'] } else { ['pipesize'] }; captured := receipt(state, arch, digest(kernel), names, phase != 'after')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['pipesize_source','pipesize_c','pipesize_init'] { if phase == 'before' { identity[key] = captured[key] } else { assert identity[key] == captured[key] } }
			log := os.read_file(state + '/pipesize/serial.log')!; semantics(log, phase, arch, false); storage(log, arch, phase)
			for label, path in {'receipt':state + '/receipt.json', 'aggregate':state + '.log', 'native':state + '/pipesize/serial.log', 'build':area + 'build-' + phase + '-' + suffix + '.log'} { publish(path, out + 'pipesize-' + phase + '-' + arch + '-' + label + if label == 'receipt' { '.json' } else { '.log' })!; artifacts[phase + '_' + label] = digest(path) }
			artifacts[phase + '_kernel'] = digest(kernel); artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
		}
		preview := area + 'preview-' + suffix + '.c'; preview_text := os.read_file(preview)!; assert preview_text.count('alloca(') == 16; for helper in ['memdup(', 'malloc(', 'new_array', 'v_fixed_index'] { assert !preview_text.contains(helper), helper }
		assert digest(preview) == identity['pipesize_c']; artifacts['preview_c'] = digest(preview)
		drift := preflight_drift(area,out,arch,suffix,states + 'p3-after-' + suffix + '/pipesize/fixture.c',states + 'p3-after-' + suffix + '/pipesize/init')!; for key, value in drift { artifacts[key] = value }
		preflight := states + 'preflight4-pipesize-' + suffix; assert digest(preflight + '/init') == identity['pipesize_init'] && digest(preflight + '/fixture.c') == identity['pipesize_c']
		artifacts['preflight_c'] = digest(preflight + '/fixture.c'); artifacts['preflight_elf'] = digest(preflight + '/init')
		reference := states + 'p3-reference-' + suffix; linux := reference_receipt(reference, arch, identity['pipesize_init'])!; for key, value in linux { artifacts['reference_' + key] = value }; artifacts['reference_receipt'] = digest(reference + '/receipt.json')
		for label, path in {'receipt':reference + '/receipt.json', 'aggregate':reference + '.log', 'native':reference + '/serial.log'} { publish(path, out + 'pipesize-reference-' + arch + '-' + label + if label == 'receipt' { '.json' } else { '.log' })! }
		for name in ['host-tests.log','allocs-before.log','allocs-after.log','coverage-check.log','scope-check.log','assertion-control.log','passing-log-control.log'] { artifacts[name] = digest(area + name) }
		artifacts['audit_source'] = digest(@FILE)
		os.write_file(out + 'pipesize-evidence-' + arch + '.json', json2.encode(Evidence{architecture:arch, context:'Native musl pipe capacity normalization and effective CAP_SYS_RESOURCE resizing. Four root/UID1000 capability cohorts; 8060 exact error, capacity alias, metadata/flags/cursor/descriptor and real queued-byte checks per architecture; original failures3144ARM/1404x86, normalization-only failures376, final and same-ELF Linux6.12.51 zero. Warmed200-cycle resizing cohorts preserve every slab class and large-page count. Valid exact2^31 is tested without capability; no privileged2GiB allocation is attempted. Page-slot fragmented occupancy, user-page quotas, mutable sysctl ceiling, concurrent resize, budget-failure injection, glibc/translation/ELF32 and broad roadmap gates remain separate. Six production builds, full generated C scope, unchanged existing allocation allowances, pinned compiler/source/ELF inputs, seven-case native profiles, independent lifetime review, fresh ARM general memory/desktop controls and executing audit negatives are bound.', base_commit:base, artifacts:artifacts, source_inputs:inputs}, prettify:true) + '\n')!
	}
	for name in ['host-tests.log','allocs-before.log','allocs-after.log','coverage-check.log','scope-check.log','assertion-control.log','passing-log-control.log'] { publish(area + name, out + 'pipesize-' + name)! }
	println('Native pipesize conformance audit: PASS')
}
