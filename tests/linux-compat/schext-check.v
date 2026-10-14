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
	mut p := os.new_process('git'); p.set_args(['-C',tree,...args]); p.set_redirect_stdio_merged(); p.run(); output := p.stdout_slurp(); p.wait(); code := p.code; p.close(); assert code == 0,output; return output.trim_space()
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
fn semantics(log string, phase string, arch string, reference bool) {
	assert phase in ['before', 'after'] && arch in ['aarch64', 'x86_64']
	mut cases := map[string]string{}
	for label in ['CASES:', 'FINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX SCHEXT ' + label)); assert rows.len == 8
		mut seen := map[string]bool{}; mut total := 0; mut failures := 0
		for row in rows {
			fields := row.fields(); assert fields.len == 7
			for index, prefix in {3: 'ordinary=', 4: 'kind=', 5: 'calls=', 6: 'failures='} { assert fields[index].starts_with(prefix) }
			ordinary := fields[3].all_after('=').int(); kind := fields[4].all_after('=').int(); assert ordinary in [0,1] && kind in [0,1,2,3]
			key := fields[3] + fields[4]; assert key !in seen; seen[key] = true
			n := fields[5].all_after('=').int(); f := fields[6].all_after('=').int()
			assert n == [180,14,30,1]![kind]
			expected := if phase == 'after' { 0 } else { [0,14,0,0]![kind] }
			assert f == expected, row
			if label == 'CASES:' { cases[key] = fields[5] + fields[6] } else { assert cases[key] == fields[5] + fields[6] }
			total += n; failures += f
		}; assert total == 450; if phase == 'after' { assert failures == 0 } else { assert failures > 0 }
	}
	assert !log.contains('Kernel panic') && !log.contains('LINUX SCHEXT FAIL: setup')
	if phase == 'after' { assert !log.contains('LINUX SCHEXT DETAIL:') && !log.contains('LINUX SCHEXT FAIL:') }
	else { assert log.contains('LINUX SCHEXT DETAIL:'), 'schext baseline failure markers required'; assert log.contains('LINUX SCHEXT FAIL:') && !log.contains('LINUX SCHEXT: PASS') }
	if reference { assert phase == 'after' && log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX SCHEXT REFERENCE: PASS') && !log.contains('LINUX SCHEXT STORAGE:') }
	else if phase == 'after' { assert log.count('LINUX SCHEXT: PASS') == 1 }
}
fn storage(log string, arch string, phase string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines().filter(it.starts_with('LINUX SCHEXT SLAB:') || it.starts_with('LINUX SCHEXT STORAGE:')) {
		fields := row.fields(); assert fields.len == 7 && fields[3].starts_with('ordinary=')
		ordinary := fields[3].all_after('=').int(); assert ordinary in [0,1]
		pair := fields[5].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' { assert fields[4].starts_with('size=') && fields[6] == 'cycles=200'; key := fields[3] + fields[4]; assert key !in seen; seen[key] = true; slabs[ordinary]++ }
		else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS' && pair[0].u64() > 0; pages[ordinary]++ }
	}
	for ordinary in 0 .. 2 { assert slabs[ordinary] == if phase == 'before' { 0 } else if arch == 'aarch64' { 18 } else { 14 }; assert pages[ordinary] == if phase == 'before' { 0 } else { 1 } }
}
fn failure(log string, arch string) { assert log.contains('LINUX SCHEXT DETAIL:'), 'schext baseline failure markers required'; semantics(log, 'before', arch, false) }
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
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/schextreferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/schext-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/schextreferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, 'after', arch, true); return artifacts
}
fn scope(area string) {
	names := ['table__syscall_linux_sched_get_priority_min','table__syscall_linux_sched_get_priority_max']
	macro := '#define table__linux_sched_ext (((i64)(7)))'
	mut verdict := ''
	for suffix in ['arm','x86'] {
		before := os.read_file(area + 'before-' + suffix + '.c') or { panic(err) }; after := os.read_file(area + 'after-' + suffix + '.c') or { panic(err) }
		assert before != after && !before.contains(macro) && after.split_into_lines().filter(it == macro).len == 1
		assert erase(before,names,4) == erase(after,names,4).split_into_lines().filter(it != macro).join('\n')
		for name in names {
			first := body(before,name); last := body(after,name)
			assert last.count(' || (policy == table__linux_sched_ext)') == 1 && last.replace(' || (policy == table__linux_sched_ext)','') == first
			for token in ['malloc(', 'memdup(', 'free(', 'array_', 'usercopy__', 'proc__set_'] { assert !last.contains(token) }
		}
		verdict += suffix + ': complete C unchanged outside two query bodies and one scalar macro; each body adds only the SCHED_EXT zero-bound predicate\n'
	}
	os.write_file(area + 'scope-check.log',verdict) or { panic(err) }
}
fn preparation(area string, out string, arch string, suffix string) !map[string]string {
	state := area + 'states/preflight1-schext-' + suffix; raw := state + '/fixture.c'
	assert !os.exists(state + '/init') && os.read_file(raw)!.count('v_fixed_index(') == 5
	log := area + 'preparation-replay-' + suffix + '.log'; assert os.read_file(log)!.contains('v_fixed_index') && os.read_file(log)!.contains('implicit')
	publish(log,out + 'schext-preparation-' + arch + '.log')!
	return {'preparation_raw_c':digest(raw),'preparation_replay':digest(log),'preparation_preview_c':digest(area + 'preparation-preview-' + suffix + '.c')}
}
fn main() {
	if '--negative-control' in os.args { assert false,'schext assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!,os.args[3]); return }
	assert os.args.len == 2,'Usage: schext-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'; states := area + 'states/'; root := '/Users/alex/code/vinix/'; out := root + 'tests/linux-compat/results/2026-10-14/'
	os.write_file(area + 'assertion-control.log',control(['--negative-control'],'schext assertions must execute'))!
	os.write_file(area + 'passing-log-control.log',control(['--negative-pass-control',states + 'p1-reference-arm/serial.log','aarch64'],'schext baseline failure markers required'))!
	scope(area)
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '4142e9a49e2a4b317272e73cc98c5b698cad8d4f'
	compiler_root := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/'; compiler := compiler_root + 'compiler/v'
	mut pins := map[string]string{}; for path, value in object(compiler_root + 'compiler-inputs.json')! { pins[path] = value.str() }; assert pins.len == 15146
	assert pins['v'] == '9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b'
	for path, hash in pins { assert digest(compiler_root + 'compiler/' + path) == hash,path }
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.count('Linux dispatch coverage: PASS') == 4
	assert os.read_file(area + 'allocs-before.log')! == os.read_file(area + 'allocs-after.log')!
	for arch, count in {'aarch64':'398','x86_64':'290'} { for name in ['allocs-before.log','allocs-after.log'] { text := os.read_file(area + name)!; assert text.split_into_lines().filter(it.starts_with(arch + ':')).len == 1 && text.contains(count + ' allocation sites (V exit 0)') && text.contains('NEW:') } }
	review := os.read_file(out + 'schext-lifetime-review.md')!; assert review.starts_with('Independent schext lifetime review: PASS') && review.contains(digest(root + 'kernel/syscall/table/gaps.v')) && review.contains(digest(root + 'tests/linux-compat/schextfixture/core.v'))
	for arch, suffix in {'aarch64':'arm','x86_64':'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree,['rev-parse','HEAD'])! == base && git(tree,['diff','--name-only','HEAD','--','kernel'])! == 'kernel/syscall/table/gaps.v'
		assert digest(tree + 'kernel/syscall/table/gaps.v') == digest(root + 'kernel/syscall/table/gaps.v')
		inputs := object(tree + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 64
		for path, hash in inputs { assert digest(tree + path) == hash,path }
		mut artifacts := {'compiler':digest(compiler),'compiler_inputs':digest(compiler_root + 'compiler-inputs.json'),'kernel_source':digest(root + 'kernel/syscall/table/gaps.v'),'kernel_source_before':digest(area + 'before-gaps.v'),'fixture_source':digest(root + 'tests/linux-compat/schextfixture/core.v'),'audit_source':digest(@FILE),'review':digest(out + 'schext-lifetime-review.md')}
		mut identity := map[string]string{}
		for phase in ['before','after'] {
			state := states + 'p1-' + phase + '-' + suffix; kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' { ['schext'] } else { ['schext','runtime','schedabi','open','fcntlabi'] }
			captured := receipt(state,arch,digest(kernel),names,phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['schext_source','schext_init','schext_c'] { if phase == 'before' { identity[key] = captured[key] } else { assert identity[key] == captured[key] } }
			text := os.read_file(state + '/schext/serial.log')!; semantics(text,phase,arch,false); storage(text,arch,phase)
			build := area + 'build-' + phase + '-' + suffix + '.log'; text_build := os.read_file(build)!; assert text_build.contains('-o bin/vinix') && !text_build.contains('Nothing to be done') && !text_build.contains('Error ')
			artifacts[phase + '_kernel'] = digest(kernel); artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
			for label, path in {'receipt':state + '/receipt.json','aggregate':state + '.log','native':state + '/schext/serial.log','build':build} { publish(path,out + 'schext-' + phase + '-' + arch + '-' + label + if label == 'receipt' { '.json' } else { '.log' })! }
		}
		preflight := states + 'preflight2-schext-' + suffix; raw := os.read_file(preflight + '/fixture.c')!
		assert digest(preflight + '/fixture.c') == identity['schext_c'] && digest(preflight + '/init') == identity['schext_init'] && digest(area + 'preview-' + suffix + '.c') == identity['schext_c']
		assert raw.count('alloca(') == 6
		for token in ['malloc(','memdup(','array_push(','array_get(','v_fixed_index('] { assert !raw.contains(token) }
		artifacts['preflight_c'] = digest(preflight + '/fixture.c'); artifacts['preflight_init'] = digest(preflight + '/init')
		reference := states + 'p1-reference-' + suffix; linux := reference_receipt(reference,arch,identity['schext_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {'receipt':reference + '/receipt.json','aggregate':reference + '.log','native':reference + '/serial.log'} { publish(path,out + 'schext-reference-' + arch + '-' + label + if label == 'receipt' { '.json' } else { '.log' })!; artifacts['reference_' + label] = digest(path) }
		for key, value in preparation(area,out,arch,suffix)! { artifacts[key] = value }
		for name in ['host-tests.log','allocs-before.log','allocs-after.log','coverage-check.log','scope-check.log','assertion-control.log','passing-log-control.log'] { artifacts[name] = digest(area + name) }
		os.write_file(out + 'schext-evidence-' + arch + '.json',json2.encode(Evidence{architecture:arch,context:'SCHED_EXT priority metadata queries on native musl ELF64: 450 root/UID1000 checks per architecture, 448 raw/libc bounds queries over 16 policies and six raw word forms plus two final policy/priority controls. Original 28 policy 7 failures, corrected/reference zero; identical probe ELF/C on original/corrected/Linux 6.12.51. Two warmed 200-cycle cohorts keep all slabs/large pages flat. Four fresh production builds, two pure query C changes and one scalar macro, five-case native profiles, eight host test files, unchanged allocation allowance failures, compiler/source/ELF pins and independent lifetime review. First standalone-helper compile failure is retained separately. No class/BPF installation, scheduler mutation, permissions, target races, glibc, translated/ELF32 or broad roadmap completion is claimed.',base_commit:base,artifacts:artifacts,source_inputs:inputs},prettify:true) + '\n')!
	}
	for name in ['host-tests.log','allocs-before.log','allocs-after.log','coverage-check.log','scope-check.log','assertion-control.log','passing-log-control.log'] { publish(area + name,out + 'schext-' + name)! }
	os.write_file(area + 'audit.log','Native schext conformance audit: PASS\n')!; publish(area + 'audit.log',out + 'schext-audit.log')!; println('Native schext conformance audit: PASS')
}
