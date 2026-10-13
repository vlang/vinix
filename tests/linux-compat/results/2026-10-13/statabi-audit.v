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
fn complete(source string, name string) string {
	lines := source.split_into_lines().filter(!it.starts_with(' ') && !it.starts_with('\t') && it.contains(' ' + name + '(') && it.ends_with(' {')); assert lines.len == 1; return lines[0] + definition(source, name) + '\n}\n'
}
fn semantics(log string, passing bool, reference bool, arch string) {
	rows := log.split_into_lines().filter(it.starts_with('LINUX STATABI CASES:')); assert rows.len == 10
	mut seen := map[string]bool{}
	for row in rows {
		fields := row.fields(); assert fields.len == 7; group := fields[3].all_after('='); kind := fields[4].all_after('=').int(); key := group + '-' + kind.str()
		assert group in ['0', '1'] && kind in [0, 1, 2, 3, 4] && key !in seen; seen[key] = true
		assert fields[5].all_after('=').int() == [54, 348, 1152, if arch == 'aarch64' { 96 } else { 132 }, 12]![kind]
		assert fields[6].all_after('=').int() == if passing { 0 } else { [24, 140, 972, 9, 1]![kind] }
	}
	if passing { assert !log.contains('LINUX STATABI DETAIL:') && !log.contains('LINUX STATABI FAIL:') }
	else { assert log.contains('LINUX STATABI DETAIL:') && log.contains('LINUX STATABI FAIL:') && !log.contains('LINUX STATABI: PASS') }
	if reference { assert passing && log.contains('LINUX STATABI REFERENCE: PASS') && log.contains('Linux version 6.12.51-0-virt') && !log.contains('Kernel panic') && !log.contains('LINUX STATABI STORAGE:') }
	else if passing { assert log.split_into_lines().filter(it.trim_space() == 'LINUX STATABI: PASS').len == 1 && !log.contains('LINUX STATABI REFERENCE: PASS') }
}
fn failure(log string, arch string) { assert log.contains('LINUX STATABI DETAIL:'), 'statabi baseline failure markers required'; semantics(log, false, false, arch) }
fn storage(log string, arch string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines() {
		if !row.starts_with('LINUX STATABI SLAB:') && !row.starts_with('LINUX STATABI STORAGE:') { continue }
		fields := row.fields(); assert fields.len == 7; group := fields[3].all_after('=').int(); assert group in [0, 1]
		pair := fields[5].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' { key := fields[3] + '-' + fields[4]; assert key !in seen && fields[6] == 'cycles=200'; seen[key] = true; slabs[group]++ }
		else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS' && pair[0] == if arch == 'aarch64' { '63' } else { '160' }; pages[group]++ }
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
		assert artifacts[name + '_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/' + name + 'fixture/core.v')
		artifacts[name + '_c'] = digest(state + '/' + name + '/fixture.c'); artifacts[name + '_serial'] = digest(state + '/' + name + '/serial.log')
		if !failing { assert os.read_file(state + '/' + name + '/serial.log')!.contains('LINUX ' + name.to_upper() + ': PASS') }
	}
	return artifacts
}
fn scope(before string, after string) {
	mut restored := after
	for name in ['table__syscall_linux_fstat', 'table__syscall_linux_fstatat'] {
		new_definition := complete(after, name); old_definition := complete(before, name)
		assert new_definition != old_definition && after.count(new_definition) == 1
		restored = restored.replace(new_definition, old_definition)
	}
	helper := complete(after, 'table__linux_fstatat_lookup')
	assert !before.contains('table__linux_fstatat_lookup') && restored.count(helper + '\n') == 1
	restored = restored.replace(helper + '\n', '')
	declarations := restored.split_into_lines().filter(!it.starts_with(' ') && !it.starts_with('\t') && it.contains(' table__linux_fstatat_lookup(') && it.ends_with(';'))
	assert declarations.len == 1; restored = restored.replace(declarations[0] + '\n', '')
	old_c := canonical(before); restored_c := canonical(restored)
	matches := restored_c == old_c
	assert matches, 'only two native stat adapters and one helper declaration/body may change whole kernel C'
	assert helper.contains('u32 query_flags = (u32)(flags);') && helper.contains('(i32)((u32)(dirfd)) >= 0')
	assert helper.contains('fs__syscall_fstat(') && helper.contains('fs__syscall_fstatat(')
	assert !helper.contains('memdup(') && !helper.contains('malloc(') && !helper.contains('vinix_stack_alloc(')
	assert definition(after, 'table__syscall_linux_statx') == definition(before, 'table__syscall_linux_statx')
	for name in ['table__convert_stat_to_statx', 'fs__syscall_fstat', 'fs__syscall_fstatat'] { assert definition(after, name) == definition(before, name) }
	if after.contains('bool table__convert_stat_to_linux(') { assert definition(after, 'table__convert_stat_to_linux') == definition(before, 'table__convert_stat_to_linux') }
	else { assert definition(after, 'table__copy_stat_to_user') == definition(before, 'table__copy_stat_to_user') }
}
fn reference_receipt(state string, arch string, init string) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['passed']!.bool() && value['finished']!.bool() && value['forced']!.bool() && value['status']!.int() == 0
	artifacts := value['artifacts']!.as_map_of_strings()
	command := value['command']!.as_array().map(it.str()); assert command.contains('-kernel') && command.contains('-initrd') && command.contains('-no-reboot')
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/statabireferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/statabi-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/statabireferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, true, true, arch); return artifacts
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!, os.args[3]); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/statabi-20261013/'; out := root + 'tests/linux-compat/results/2026-10-13/'; compiler := '/Users/alex/.cache/vinix-linux-compat/procstate-20261013/compiler/v'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'final-after-arm/statabi/serial.log', 'aarch64'], 'statabi baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '8fc078a86a6cd540c80ef667d9335afaf7c0230e'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	assert digest(compiler) == 'f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39'
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	for arch in ['aarch64', 'x86_64'] { count := arch + ': ' + if arch == 'aarch64' { '658 source files, 403 allocation sites (V exit 0)' } else { '654 source files, 292 allocation sites (V exit 0)' }; assert before_allocs.contains(count) && after_allocs.contains(count) }
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	paths := ['kernel/syscall/table/linux_common.v', 'kernel/syscall/table/linux_table_amd64.v', 'kernel/syscall/table/syscall_table_arm64.v']; review := out + 'statabi-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent statabi lifetime review: PASS')
	for path in paths { assert inputs[path] == digest(root + path) && review_text.contains(inputs[path]) }; assert review_text.contains(digest(root + 'tests/linux-compat/statabifixture/core.v'))
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == paths
		for source_path, hash in inputs { if source_path.starts_with('kernel/') { assert digest(tree + source_path) == hash } }
		kernel_c := tree + 'kernel/obj/blob.c'; scope(os.read_file(area + 'before-' + suffix + '.c')!, os.read_file(kernel_c)!); assert review_text.contains(digest(kernel_c))
		preview := os.read_file(area + 'final-preview-' + suffix + '.c')!; assert preview.count('alloca(') == 8 && !preview.contains('memdup(') && !preview.contains('malloc(') && !preview.contains('new_array') && !preview.contains('v_fixed_index')
		before_hash := digest(area + 'before-' + suffix + '.kernel'); after_hash := digest(tree + 'kernel/bin/vinix')
		baseline := area + 'final-before-' + suffix; candidate := area + 'final-after-' + suffix; reference := area + 'final-reference-' + suffix
		before := receipt(baseline, arch, before_hash, ['statabi'], true)!; after := receipt(candidate, arch, after_hash, ['statabi', 'statx', 'open', 'runtime'], false)!
		assert before['statabi_source'] == after['statabi_source'] && before['statabi_init'] == after['statabi_init'] && before['statabi_c'] == after['statabi_c'] && after['statabi_c'] == digest(area + 'final-preview-' + suffix + '.c')
		failure(os.read_file(baseline + '/statabi/serial.log')!, arch); log := os.read_file(candidate + '/statabi/serial.log')!; semantics(log, true, false, arch); storage(log, arch); assert review_text.contains(digest(candidate + '/statabi/serial.log'))
		linux := reference_receipt(reference, arch, after['statabi_init'])!; assert review_text.contains(linux['serial']) && review_text.contains(linux['wrapper_c']) && review_text.contains(linux['probe'])
		assert linux['kernel'] == digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/vmlinuz-' + arch)
		assert os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: JIT page sizes')
		mut artifacts := {'compiler': digest(compiler), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'reference_controller': digest(area + 'final-reference'), 'audit': digest(@FILE), 'review': digest(review), 'before_kernel': before_hash, 'after_kernel': after_hash, 'before_kernel_c': digest(area + 'before-' + suffix + '.c'), 'after_kernel_c': digest(kernel_c), 'preview': digest(area + 'final-preview-' + suffix + '.c')}
		for key, hash in before { artifacts['before_' + key] = hash }; for key, hash in after { artifacts['after_' + key] = hash }; for key, hash in linux { artifacts['reference_' + key] = hash }
		artifacts['reference_receipt'] = digest(reference + '/receipt.json'); artifacts['reference_aggregate'] = digest(reference + '.log'); artifacts['reference_url'] = digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/url-' + arch + '.txt')
		for phase in ['before', 'after'] {
			state := area + 'final-' + phase + '-' + suffix; publish(state + '.log', out + 'statabi-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'statabi-' + phase + '-' + arch + '.json')!
			publish(state + '/statabi/serial.log', out + 'statabi-' + phase + '-' + arch + '-native.log')!
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_text := os.read_file(build)!; assert build_text.contains('-o bin/vinix') && !build_text.contains('Error ') && !build_text.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
		}
		publish(reference + '.log', out + 'statabi-reference-' + arch + '.log')!; publish(reference + '/serial.log', out + 'statabi-reference-' + arch + '-native.log')!; publish(reference + '/receipt.json', out + 'statabi-reference-' + arch + '.json')!
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		context := 'Native musl root/UID1000 fstat/newfstatat conformance: 3324 ARM and 3396 x86 calls, including x86 legacy stat/lstat controls. C-int descriptor/flag words narrow to 32 bits; pointers and metadata retain native width. Unknown flags return EINVAL before pathname/FD/output access. Local sync bits, including the pair accepted by Linux fstatat, preserve real regular/link/unlinked/pipe metadata. Only exact AT_EMPTY_PATH with a nonnegative signed FD word enables NULL descriptor queries; other NULL forms retain Linux 6.12 EFAULT. Every probe checks surrounding canaries and writable sentinel output on errors; file bytes/cursor unchanged. Baselines fail 2292 calls on each architecture; candidates and actual Linux 6.12.51 reference boots pass the identical semantic matrix and native ELF. Native 200-cycle cohorts execute 21 calls/cycle and require exact live slabs/large pages. Statx/open/runtime and eight host test files pass. Whole C restores by replacing two native adapter bodies and removing one shared helper declaration/body, ignoring only unused-loop source-offset identifiers; stat layouts, statx and VFS bodies unchanged. Allocation site counts and existing allowance refusals unchanged. Independent source/C/native/reference lifetime review approved. Compiler/controller/source/kernel/C/ELF/ISO/Linux kernel/wrapper/cpio/QEMU/serial/build/audit/review hashes bound; both negative controls execute. Initial musl NULL-wrapper misuse and failed native/Linux draft captures remain private. Remote synchronization/automount, concurrent close/disk metadata, GNU wrappers/translated/ELF32 and installation/sandbox/portal acceptance remain separate.'
		os.write_file(out + 'statabi-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log'] { publish(area + name, out + 'statabi-' + name)! }
	println('Native statabi conformance audit: PASS')
}
