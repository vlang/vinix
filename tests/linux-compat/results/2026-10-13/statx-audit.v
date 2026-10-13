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
fn prototype(source string) string {
	lines := source.split_into_lines().filter(!it.starts_with(' ') && !it.starts_with('\t') && it.contains(' table__syscall_linux_statx(') && it.ends_with(';')); assert lines.len == 1; return lines[0]
}
fn semantics(log string, passing bool, reference bool) {
	rows := log.split_into_lines().filter(it.starts_with('LINUX STATX CASES:')); assert rows.len == 8
	mut seen := map[string]bool{}
	for row in rows {
		fields := row.fields(); assert fields.len == 7; group := fields[3].all_after('='); kind := fields[4].all_after('=').int(); key := group + '-' + kind.str()
		assert group in ['0', '1'] && kind in [0, 1, 2, 3] && key !in seen; seen[key] = true
		assert fields[5].all_after('=').int() == [1620, 1440, 32, 15]![kind]
		assert fields[6].all_after('=').int() == if passing { 0 } else { [840, 1440, 7, 9]![kind] }
	}
	if passing { assert !log.contains('LINUX STATX DETAIL:') && !log.contains('LINUX STATX FAIL:') }
	else { assert log.contains('LINUX STATX DETAIL:') && log.contains('LINUX STATX FAIL:') && !log.contains('LINUX STATX: PASS') }
	if reference { assert passing && log.contains('LINUX STATX REFERENCE: PASS') && log.contains('Linux version 6.12.51-0-virt') && !log.contains('Kernel panic') && !log.contains('LINUX STATX STORAGE:') }
	else if passing { assert log.split_into_lines().filter(it.trim_space() == 'LINUX STATX: PASS').len == 1 && !log.contains('LINUX STATX REFERENCE: PASS') }
}
fn failure(log string) { assert log.contains('LINUX STATX DETAIL:'), 'statx baseline failure markers required'; semantics(log, false, false) }
fn storage(log string, arch string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines() {
		if !row.starts_with('LINUX STATX SLAB:') && !row.starts_with('LINUX STATX STORAGE:') { continue }
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
	new_definition := complete(after, 'table__syscall_linux_statx'); old_definition := complete(before, 'table__syscall_linux_statx'); assert new_definition != old_definition && after.count(new_definition) == 1
	mut restored := after.replace(new_definition, old_definition)
	new_prototype := prototype(after); old_prototype := prototype(before); assert new_prototype != old_prototype; restored = restored.replace(new_prototype, old_prototype)
	for name in ['reserved', 'no_automount', 'sync_type'] { lines := restored.split_into_lines().filter(it.starts_with('#define table__statx_' + name + ' ')); assert lines.len == 1 && restored.count(lines[0]) == 1; restored = restored.replace(lines[0] + '\n', '') }
	assert canonical(restored) == canonical(before), 'only statx definition/prototype and three constants may change whole kernel C'
	assert new_definition.contains('u32 query_flags = (u32)(flags);') && new_definition.contains('(i32)((u32)(dirfd)) >= 0') && new_definition.contains('fs__syscall_fstat(') && new_definition.contains('fs__syscall_fstatat(')
	assert !new_definition.contains('memdup(') && !new_definition.contains('malloc(') && !new_definition.contains('buf == 0') && new_definition.contains('vinix_stack_alloc(sizeof(stat__Stat))')
	assert definition(after, 'table__convert_stat_to_statx') == definition(before, 'table__convert_stat_to_statx') && definition(after, 'fs__syscall_fstat') == definition(before, 'fs__syscall_fstat') && definition(after, 'fs__syscall_fstatat') == definition(before, 'fs__syscall_fstatat')
}
fn reference_receipt(state string, arch string, init string) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['passed']!.bool() && value['finished']!.bool() && value['forced']!.bool() && value['status']!.int() == 0
	artifacts := value['artifacts']!.as_map_of_strings()
	command := value['command']!.as_array().map(it.str()); assert command.contains('-kernel') && command.contains('-initrd') && command.contains('-no-reboot')
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/statxreferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/statx-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/statxreferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, true, true); return artifacts
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/statx-20261013/'; out := root + 'tests/linux-compat/results/2026-10-13/'; compiler := '/Users/alex/.cache/vinix-linux-compat/procstate-20261013/compiler/v'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'final-after-arm/statx/serial.log'], 'statx baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '1940edfc04b77f7937ac03e54f4fe3870c23d787'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	assert digest(compiler) == 'f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39'
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	for arch in ['aarch64', 'x86_64'] { count := arch + ': ' + if arch == 'aarch64' { '658 source files, 403 allocation sites (V exit 0)' } else { '654 source files, 292 allocation sites (V exit 0)' }; assert before_allocs.contains(count) && after_allocs.contains(count) }
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	path := 'kernel/syscall/table/linux_common.v'; review := out + 'statx-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent statx lifetime review: PASS')
	assert inputs[path] == digest(root + path) && review_text.contains(inputs[path]) && review_text.contains(digest(root + 'tests/linux-compat/statxfixture/core.v'))
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == path
		for source_path, hash in inputs { if source_path.starts_with('kernel/') { assert digest(tree + source_path) == hash } }
		kernel_c := tree + 'kernel/obj/blob.c'; scope(os.read_file(area + 'before-' + suffix + '.c')!, os.read_file(kernel_c)!); assert review_text.contains(digest(kernel_c))
		preview := os.read_file(area + 'preview-' + suffix + '.c')!; assert preview.count('alloca(') == 8 && !preview.contains('memdup(') && !preview.contains('malloc(') && !preview.contains('new_array') && !preview.contains('v_fixed_index')
		before_hash := digest(area + 'before-' + suffix + '.kernel'); after_hash := digest(tree + 'kernel/bin/vinix')
		baseline := area + 'final-before-' + suffix; candidate := area + 'final-after-' + suffix; reference := area + 'final-reference-' + suffix
		before := receipt(baseline, arch, before_hash, ['statx'], true)!; after := receipt(candidate, arch, after_hash, ['statx', 'open', 'runtime'], false)!
		assert before['statx_source'] == after['statx_source'] && before['statx_init'] == after['statx_init'] && before['statx_c'] == after['statx_c'] && after['statx_c'] == digest(area + 'preview-' + suffix + '.c')
		failure(os.read_file(baseline + '/statx/serial.log')!); log := os.read_file(candidate + '/statx/serial.log')!; semantics(log, true, false); storage(log, arch); assert review_text.contains(digest(candidate + '/statx/serial.log'))
		linux := reference_receipt(reference, arch, after['statx_init'])!; assert review_text.contains(linux['serial']) && review_text.contains(linux['wrapper_c']) && review_text.contains(linux['probe'])
		assert linux['kernel'] == digest(area + 'linux-inputs/vmlinuz-' + arch)
		assert os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: JIT page sizes')
		mut artifacts := {'compiler': digest(compiler), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'reference_controller': digest(area + 'reference'), 'audit': digest(@FILE), 'review': digest(review), 'before_kernel': before_hash, 'after_kernel': after_hash, 'before_kernel_c': digest(area + 'before-' + suffix + '.c'), 'after_kernel_c': digest(kernel_c), 'preview': digest(area + 'preview-' + suffix + '.c')}
		for key, hash in before { artifacts['before_' + key] = hash }; for key, hash in after { artifacts['after_' + key] = hash }; for key, hash in linux { artifacts['reference_' + key] = hash }
		artifacts['reference_receipt'] = digest(reference + '/receipt.json'); artifacts['reference_aggregate'] = digest(reference + '.log'); artifacts['reference_url'] = digest(area + 'linux-inputs/url-' + arch + '.txt')
		for phase in ['before', 'after'] {
			state := area + 'final-' + phase + '-' + suffix; publish(state + '.log', out + 'statx-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'statx-' + phase + '-' + arch + '.json')!
			publish(state + '/statx/serial.log', out + 'statx-' + phase + '-' + arch + '-native.log')!
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_text := os.read_file(build)!; assert build_text.contains('-o bin/vinix') && !build_text.contains('Error ') && !build_text.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
		}
		publish(reference + '.log', out + 'statx-reference-' + arch + '.log')!; publish(reference + '/serial.log', out + 'statx-reference-' + arch + '-native.log')!; publish(reference + '/receipt.json', out + 'statx-reference-' + arch + '.json')!
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		context := 'Native musl root/UID1000 statx conformance: 6214 calls per architecture (3240 metadata/word cases, 2880 argument refusals, 64 lookup/output errors, 30 libc controls). Reserved mask, invalid sync pair and unknown flag bits return EINVAL before path/FD/output access, leaving valid output untouched. FD/flags/mask words narrow to32bits; metadata remains full width. Valid local sync/NO_AUTOMOUNT/NOFOLLOW modes preserve actual file/link/unlinked/pipe metadata, file bytes and cursor. Descriptor-only NULL uses existing held fstat for nonnegative signed FD words; negative NULL and NULL+NOFOLLOW retain EFAULT. Baseline fails4592 calls per architecture. Exact same source/C/init ELF before/after and actual unchanged native ELF on pinned Alpine3.22.2 Linux6.12.51 reference boots: all6214 semantics pass on both kernels/architectures. Reference uses explicit --reference only to skip Vinix-specific allocator reporting. Native200cyclecohorts cover18 successful/refused queries percycle; all18ARM/14x86 slab classes and63/160largepages stay flat. Open/runtime and eight host test files pass. Whole kernel C restores by replacing one statx definition/prototype parameter and removing three constants, ignoring only unused-loop source offsets; converter/fstat/fstatat bodies unchanged. Source658/654 and allocation403/292 counts plus existing allowance refusals unchanged. Independent source/C/native/reference lifetime review approved. All63inputs plus compiler/controller/source/kernel/C/ELF/ISO/referencekernel/wrapper/cpio/QEMU/capture/build/audit/review hashes bound; bothnegativecontrols execute. Initial alias-conditional build failures and kernel-string/negative-NULL-expectation fixture drafts and reference failures remain private. Remote synchronization/automount triggers, extended statx fields, concurrent close/disk metadata, GNU wrappers/translated/ELF32 and installation/sandbox/portal acceptance remain separate.'
		os.write_file(out + 'statx-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log'] { publish(area + name, out + 'statx-' + name)! }
	println('Native statx conformance audit: PASS')
}
