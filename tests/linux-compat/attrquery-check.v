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
		rows := log.split_into_lines().filter(it.starts_with('LINUX ATTRQUERY ' + label)); assert rows.len == 8
		mut seen := map[string]bool{}; mut total := 0; mut failures := 0
		for row in rows {
			fields := row.fields(); assert fields.len == 7
			for index, prefix in {3: 'ordinary=', 4: 'kind=', 5: 'calls=', 6: 'failures='} { assert fields[index].starts_with(prefix) }
			ordinary := fields[3].all_after('=').int(); kind := fields[4].all_after('=').int(); assert ordinary in [0,1] && kind in [0,1,2,3]
			key := fields[3] + fields[4]; assert key !in seen; seen[key] = true
			n := fields[5].all_after('=').int(); f := fields[6].all_after('=').int()
			assert n == [1920,3840,1920,23]![kind]
			expected := if phase == 'after' { 0 } else { [210,1092,210,8]![kind] }
			assert f == expected, row
			if label == 'CASES:' { cases[key] = fields[5] + fields[6] } else { assert cases[key] == fields[5] + fields[6] }
			total += n; failures += f
		}; assert total == 15406; if phase == 'after' { assert failures == 0 } else { assert failures > 0 }
	}
	assert !log.contains('Kernel panic') && !log.contains('LINUX ATTRQUERY FAIL: setup')
	if phase == 'after' { assert !log.contains('LINUX ATTRQUERY DETAIL:') && !log.contains('LINUX ATTRQUERY FAIL:') }
	else { assert log.contains('LINUX ATTRQUERY DETAIL:'), 'attrquery baseline failure markers required'; assert log.contains('LINUX ATTRQUERY FAIL:') && !log.contains('LINUX ATTRQUERY: PASS') }
	if reference { assert phase == 'after' && log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX ATTRQUERY REFERENCE: PASS') && !log.contains('LINUX ATTRQUERY STORAGE:') }
	else if phase == 'after' { assert log.count('LINUX ATTRQUERY: PASS') == 1 }
}
fn storage(log string, arch string, phase string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines().filter(it.starts_with('LINUX ATTRQUERY SLAB:') || it.starts_with('LINUX ATTRQUERY STORAGE:')) {
		fields := row.fields(); assert fields.len == 7 && fields[3].starts_with('ordinary=')
		ordinary := fields[3].all_after('=').int(); assert ordinary in [0,1]
		pair := fields[5].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' { assert fields[4].starts_with('size=') && fields[6] == 'cycles=200'; key := fields[3] + fields[4]; assert key !in seen; seen[key] = true; slabs[ordinary]++ }
		else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS' && pair[0].u64() > 0; pages[ordinary]++ }
	}
	for ordinary in 0 .. 2 { assert slabs[ordinary] == if phase == 'before' { 0 } else if arch == 'aarch64' { 18 } else { 14 }; assert pages[ordinary] == if phase == 'before' { 0 } else { 1 } }
}
fn failure(log string, arch string) { assert log.contains('LINUX ATTRQUERY DETAIL:'), 'attrquery baseline failure markers required'; semantics(log, 'before', arch, false) }
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
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/attrqueryreferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/attrquery-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/attrqueryreferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, 'after', arch, true); return artifacts
}
fn scope(area string) {
	names := ['table__syscall_linux_sched_getattr']; mut verdict := ''
	for suffix in ['arm','x86'] {
		before := os.read_file(area + 'before-' + suffix + '.c') or { panic(err) }; after := os.read_file(area + 'after-' + suffix + '.c') or { panic(err) }
		assert before != after && erase(before,names,2) == erase(after,names,2)
		first := body(before,names[0]); last := body(after,names[0])
		assert first.contains('i64 pid, u64 attr_ptr, u32 size, u32 flags') && last.contains('i64 raw_pid, u64 attr_ptr, u32 size, u32 flags')
		marker := '__v_option_i64 __or_opt_0'; prefix := last.all_before(marker)
		assert prefix == 'multi_return_u64_u64 table__syscall_linux_sched_getattr(void* _0, i64 raw_pid, u64 attr_ptr, u32 size, u32 flags) {\n\ti64 pid = (i64)((i32)((u32)(raw_pid)));\n\tif ((attr_ptr == 0) || (pid < 0) || (flags != 0) || (size < table__sched_attr_v0_size) || ((u64)(size) > memory__page_size)) {\n\t\treturn (multi_return_u64_u64){errno__err, errno__einval};\n\t}\n\t'
		assert first.count(marker) == 1 && last.count(marker) == 1
		expected := first.replace(first.all_before(marker),prefix).replace('__if_val_4 = table__sched_attr_v0_size;','__if_val_4 = size;').replace('if (!usercopy__copy_to_user(attr_ptr, (void*)(&attr), attr.size)) {','if (!usercopy__user_range(attr_ptr, (u64)(size)) || !usercopy__copy_to_user(attr_ptr, (void*)(&attr), attr.size)) {')
		assert expected == last
		assert last.count('usercopy__copy_to_user(') == 1 && last.count('usercopy__user_range(') == 1
		for token in ['malloc(', 'memdup(', 'free(', 'array_', 'proc__set_'] { assert !last.contains(token) }
		verdict += suffix + ': complete C differs only in getter prototype/body; signed32/input guards, exact prefix and full range check; all lookup/lock/value-copy/allocation code unchanged\n'
	}
	os.write_file(area + 'scope-check.log',verdict) or { panic(err) }
}
fn ranges(log string, arch string, reference bool) {
	rows := log.split_into_lines().filter(it.starts_with('LINUX ATTRQUERY RANGE:')); assert rows.len == 2
	mut seen := map[string]bool{}
	for row in rows {
		fields := row.fields(); assert fields.len == 6 && fields[3] in ['ordinary=0','ordinary=1'] && fields[3] !in seen; seen[fields[3]] = true
		limit := fields[4].all_after('='); page := fields[5].all_after('=').int()
		assert fields[4].starts_with('limit=') && fields[5].starts_with('page=')
		if arch == 'aarch64' { assert page == if reference { 4096 } else { 16384 }; assert limit == if reference { '1000000000000' } else { '800000000000' } }
		else { assert page == 4096; assert limit in if reference { ['7ffffffff000','fffffffffff000'] } else { ['800000000000','100000000000000'] } }
	}
}
fn preparation(area string, out string, arch string, suffix string) !map[string]string {
	mut artifacts := map[string]string{}
	for stage in ['mapcheck','reserved-page'] {
		state := area + 'states/preparation-' + stage + '-' + suffix
		for label, path in {'c':state + '/fixture.c','elf':state + '/init'} { artifacts['preparation_' + stage + '_' + label] = digest(path) }
	}
	state := area + 'states/p1-reference-' + suffix; value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch
	artifacts['preparation_reference_receipt'] = digest(state + '/receipt.json'); artifacts['preparation_reference_serial'] = digest(state + '/serial.log')
	assert value['artifacts']!.as_map_of_strings()['probe'] == artifacts['preparation_reserved-page_elf']
	log := os.read_file(state + '/serial.log')!
	if suffix == 'arm' { assert value['passed']!.bool(); semantics(log,'after',arch,true); ranges(log,arch,true) }
	else { assert !value['passed']!.bool() && log.contains('LINUX ATTRQUERY FAIL: setup or child protocol stage=12 errno=12') && !log.contains('LINUX ATTRQUERY REFERENCE: PASS') && !log.contains('LINUX ATTRQUERY CASES:') }
	for label, path in {'receipt':state + '/receipt.json','serial':state + '/serial.log','aggregate':state + '.log'} { publish(path,out + 'attrquery-preparation-' + arch + '-' + label + if label == 'receipt' { '.json' } else { '.log' })!; artifacts['preparation_' + label] = digest(path) }
	return artifacts
}
fn main() {
	if '--negative-control' in os.args { assert false,'attrquery assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!,os.args[3]); return }
	assert os.args.len == 2,'Usage: attrquery-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'; states := area + 'states/'; root := '/Users/alex/code/vinix/'; out := root + 'tests/linux-compat/results/2026-10-14/'
	os.write_file(area + 'assertion-control.log',control(['--negative-control'],'attrquery assertions must execute'))!
	os.write_file(area + 'passing-log-control.log',control(['--negative-pass-control',states + 'p2-reference-arm/serial.log','aarch64'],'attrquery baseline failure markers required'))!
	scope(area)
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '8175c29c1559cad97f58820770d6e88c5befaa38'
	compiler_root := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/'; compiler := compiler_root + 'compiler/v'
	mut pins := map[string]string{}; for path, value in object(compiler_root + 'compiler-inputs.json')! { pins[path] = value.str() }; assert pins.len == 15146
	assert pins['v'] == '9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b'
	for path, hash in pins { assert digest(compiler_root + 'compiler/' + path) == hash,path }
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.count('Linux dispatch coverage: PASS') == 4
	assert os.read_file(area + 'allocs-before.log')! == os.read_file(area + 'allocs-after.log')!
	for arch, count in {'aarch64':'398','x86_64':'290'} { for name in ['allocs-before.log','allocs-after.log'] { text := os.read_file(area + name)!; assert text.split_into_lines().filter(it.starts_with(arch + ':')).len == 1 && text.contains(count + ' allocation sites (V exit 0)') && text.contains('NEW:') } }
	review := os.read_file(out + 'attrquery-lifetime-review.md')!; assert review.starts_with('Independent attrquery lifetime review: PASS') && review.contains(digest(root + 'kernel/syscall/table/gaps.v')) && review.contains(digest(root + 'tests/linux-compat/attrqueryfixture/core.v'))
	for arch, suffix in {'aarch64':'arm','x86_64':'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree,['rev-parse','HEAD'])! == base && git(tree,['diff','--name-only','HEAD','--','kernel'])! == 'kernel/syscall/table/gaps.v'
		assert digest(tree + 'kernel/syscall/table/gaps.v') == digest(root + 'kernel/syscall/table/gaps.v')
		inputs := object(tree + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 64
		for path, hash in inputs { assert digest(tree + path) == hash,path }
		mut artifacts := {'compiler':digest(compiler),'compiler_inputs':digest(compiler_root + 'compiler-inputs.json'),'kernel_source':digest(root + 'kernel/syscall/table/gaps.v'),'kernel_source_before':digest(area + 'before-gaps.v'),'fixture_source':digest(root + 'tests/linux-compat/attrqueryfixture/core.v'),'audit_source':digest(@FILE),'review':digest(out + 'attrquery-lifetime-review.md'),'native_controller':digest(area + 'run'),'native_controller_source':digest(root + 'tests/linux-compat/run.v'),'reference_controller':digest(area + 'reference')}
		for key, hash in preparation(area,out,arch,suffix)! { artifacts[key] = hash }
		mut identity := map[string]string{}
		for phase in ['before','after'] {
			state := states + 'p2-' + phase + '-' + suffix; kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' { ['attrquery'] } else { ['attrquery','runtime','schedabi','rrabi','open','fcntlabi'] }
			captured := receipt(state,arch,digest(kernel),names,phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['attrquery_source','attrquery_init','attrquery_c'] { if phase == 'before' { identity[key] = captured[key] } else { assert identity[key] == captured[key] } }
			text := os.read_file(state + '/attrquery/serial.log')!; semantics(text,phase,arch,false); storage(text,arch,phase)
			ranges(text,arch,false)
			build := area + 'build-' + phase + '-' + suffix + '.log'; text_build := os.read_file(build)!; assert text_build.contains('-o bin/vinix') && !text_build.contains('Nothing to be done') && !text_build.contains('Error ')
			artifacts[phase + '_kernel'] = digest(kernel); artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
			for label, path in {'receipt':state + '/receipt.json','aggregate':state + '.log','native':state + '/attrquery/serial.log','build':build} { publish(path,out + 'attrquery-' + phase + '-' + arch + '-' + label + if label == 'receipt' { '.json' } else { '.log' })! }
		}
		preflight := states + 'preflight1-attrquery-' + suffix; raw := os.read_file(preflight + '/fixture.c')!
		assert digest(preflight + '/fixture.c') == identity['attrquery_c'] && digest(preflight + '/init') == identity['attrquery_init'] && digest(area + 'preview-' + suffix + '.c') == identity['attrquery_c']
		assert raw.count('alloca(') == 11
		for token in ['malloc(','memdup(','array_push(','array_get(','v_fixed_index('] { assert !raw.contains(token) }
		artifacts['preflight_c'] = digest(preflight + '/fixture.c'); artifacts['preflight_init'] = digest(preflight + '/init')
		reference := states + 'p2-reference-' + suffix; linux := reference_receipt(reference,arch,identity['attrquery_init'])!
		ranges(os.read_file(reference + '/serial.log')!,arch,true)
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {'receipt':reference + '/receipt.json','aggregate':reference + '.log','native':reference + '/serial.log'} { publish(path,out + 'attrquery-reference-' + arch + '-' + label + if label == 'receipt' { '.json' } else { '.log' })!; artifacts['reference_' + label] = digest(path) }
		for name in ['host-tests.log','allocs-before.log','allocs-after.log','coverage-check.log','scope-check.log','assertion-control.log','passing-log-control.log'] { artifacts[name] = digest(area + name) }
		os.write_file(out + 'attrquery-evidence-' + arch + '.json',json2.encode(Evidence{architecture:arch,context:'Native sched_getattr query arguments and exact prefixes: 15406 root/UID1000 checks per architecture, including six PID targets, 16 sizes, 10 buffer forms,flags 0/1,ordinary/two upper PID words and upper size/flag controls. Real RR/BATCH queries and four full user-range boundary controls per cohort; native page caps 16KiB ARM/4 KiB x86. Original 3040 failures, corrected and same-ELF Linux 6.12.51 zero. Eleven probe allocas, no heap/index helpers. Two warmed 200-cycle cohorts retain flat storage. Four production captures,sole getter C scope, six-case native profiles, eight host files, unchanged allocation allowance refusals, pinned compiler/source/C/ELF inputs, executing negatives and independent lifetime review. Prior x86 reference reserved-top-page setup and earlier preflights remain separate. Setter semantics,policy/permission/races,  glibc, foreign/ELF32 and broad roadmap gates remain open',base_commit:base,artifacts:artifacts,source_inputs:inputs},prettify:true) + '\n')!
	}
	for name in ['host-tests.log','allocs-before.log','allocs-after.log','coverage-check.log','scope-check.log','assertion-control.log','passing-log-control.log'] { publish(area + name,out + 'attrquery-' + name)! }
	os.write_file(area + 'audit.log','Native attrquery conformance audit: PASS\n')!; publish(area + 'audit.log',out + 'attrquery-audit.log')!; println('Native attrquery conformance audit: PASS')
}
