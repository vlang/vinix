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
	rows := log.split_into_lines().filter(it.starts_with('LINUX FCNTLABI CASES:')); assert rows.len == 10
	mut seen := map[string]bool{}
	for row in rows {
		fields := row.fields(); assert fields.len == 7; group := fields[3].all_after('='); kind := fields[4].all_after('=').int(); key := group + '-' + kind.str()
		assert group in ['0', '1'] && kind in [0, 1, 2, 3, 4] && key !in seen; seen[key] = true
		assert fields[5].all_after('=').int() == [324, 2592, 1350, 36, 162]![kind]
		assert fields[6].all_after('=').int() == if passing { 0 } else { [288, 2136, 1180, 32, 38]![kind] }
	}
	if passing { assert !log.contains('LINUX FCNTLABI DETAIL:') && !log.contains('LINUX FCNTLABI FAIL:') }
	else { assert log.contains('LINUX FCNTLABI DETAIL:') && log.contains('LINUX FCNTLABI FAIL:') && !log.contains('LINUX FCNTLABI: PASS') }
	if reference { assert passing && log.contains('LINUX FCNTLABI REFERENCE: PASS') && log.contains('Linux version 6.12.51-0-virt') && !log.contains('Kernel panic') && !log.contains('LINUX FCNTLABI STORAGE:') }
	else if passing { assert log.split_into_lines().filter(it.trim_space() == 'LINUX FCNTLABI: PASS').len == 1 && !log.contains('LINUX FCNTLABI REFERENCE: PASS') }
}
fn failure(log string, arch string) { assert log.contains('LINUX FCNTLABI DETAIL:'), 'fcntlabi baseline failure markers required'; semantics(log, false, false, arch) }
fn storage(log string, arch string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines() {
		if !row.starts_with('LINUX FCNTLABI SLAB:') && !row.starts_with('LINUX FCNTLABI STORAGE:') { continue }
		fields := row.fields(); assert fields.len == 7; group := fields[3].all_after('=').int(); assert group in [0, 1]
		pair := fields[5].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' { key := fields[3] + '-' + fields[4]; assert key !in seen && fields[6] == 'cycles=200'; seen[key] = true; slabs[group]++ }
		else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS' && pair[0].int() > 0; pages[group]++ }
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
fn scope(before string, after string, arch string) {
	mut restored := after
	name := 'table__init_syscall_table'; new_definition := complete(after, name); old_definition := complete(before, name)
	slot := if arch == 'aarch64' { '[25]' } else { '[72]' }
	assert new_definition.replace('syscall_table' + slot + ' = table__syscall_linux_fcntl;', 'syscall_table' + slot + ' = file__syscall_fcntl;') == old_definition
	restored = restored.replace(new_definition, old_definition)
	helper := complete(after, 'table__syscall_linux_fcntl'); assert !before.contains('table__syscall_linux_fcntl') && restored.count(helper + '\n') == 1
	restored = restored.replace(helper + '\n', '')
	declarations := restored.split_into_lines().filter(!it.starts_with(' ') && !it.starts_with('\t') && it.contains(' table__syscall_linux_fcntl(') && it.ends_with(';')); assert declarations.len == 1
	restored = restored.replace(declarations[0] + '\n', '')
	matches := canonical(restored) == canonical(before); assert matches, 'only native fcntl adapter and dispatch may change whole kernel C'
	assert helper.contains('(u32)(fdnum)') && helper.contains('(u32)(cmd)') && helper.contains('(i32)((u32)(arg))')
	assert helper.contains('u64 value = arg;') && helper.contains('file__syscall_fcntl(') && helper.contains('file__fd_from_fdnum(')
	assert helper.count('file__FD__unref(') == 1 && !helper.contains('memdup(') && !helper.contains('malloc(') && !helper.contains('vinix_stack_alloc(')
	for callee in ['file__syscall_fcntl', 'file__fdnum_dup', 'file__fdnum_create_from_fd', 'file__fd_from_fdnum', 'table__syscall_linux_dup', 'table__syscall_linux_dup3', 'file__fcntl_lock'] { assert definition(after, callee) == definition(before, callee) }
}
fn reference_receipt(state string, arch string, init string) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['passed']!.bool() && value['finished']!.bool() && value['forced']!.bool() && value['status']!.int() == 0
	artifacts := value['artifacts']!.as_map_of_strings()
	command := value['command']!.as_array().map(it.str()); assert command.contains('-kernel') && command.contains('-initrd') && command.contains('-no-reboot')
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/fcntlabireferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/fcntlabi-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/fcntlabireferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, true, true, arch); return artifacts
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!, os.args[3]); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/fcntlabi-20261013/'; out := root + 'tests/linux-compat/results/2026-10-13/'; compiler := '/Users/alex/.cache/vinix-linux-compat/procstate-20261013/compiler/v'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'final-after-arm/fcntlabi/serial.log', 'aarch64'], 'fcntlabi baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == 'e85df8e5f8086a8d048669e420196bae9b206a72'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	assert digest(compiler) == 'f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39'
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	for arch in ['aarch64', 'x86_64'] { count := arch + ': ' + if arch == 'aarch64' { '659 source files, 400 allocation sites (V exit 0)' } else { '655 source files, 292 allocation sites (V exit 0)' }; assert before_allocs.contains(count) && after_allocs.contains(count) }
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	paths := ['kernel/syscall/table/linux_common.v', 'kernel/syscall/table/linux_table_amd64.v', 'kernel/syscall/table/syscall_table_arm64.v']; review := out + 'fcntlabi-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent fcntlabi lifetime review: PASS')
	for path in paths { assert inputs[path] == digest(root + path) && review_text.contains(inputs[path]) }; assert review_text.contains(digest(root + 'tests/linux-compat/fcntlabifixture/core.v'))
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == paths
		for source_path, hash in inputs { if source_path.starts_with('kernel/') { assert digest(tree + source_path) == hash } }
		kernel_c := tree + 'kernel/obj/blob.c'; scope(os.read_file(area + 'before-' + suffix + '.c')!, os.read_file(kernel_c)!, arch); assert review_text.contains(digest(kernel_c))
		preview := os.read_file(area + 'preview-' + suffix + '.c')!; assert preview.count('alloca(') == 16 && !preview.contains('memdup(') && !preview.contains('malloc(') && !preview.contains('new_array') && !preview.contains('v_fixed_index')
		before_hash := digest(area + 'before-' + suffix + '.kernel'); after_hash := digest(tree + 'kernel/bin/vinix')
		baseline := area + 'final-before-' + suffix; candidate := area + 'final-after-' + suffix; reference := area + 'final-reference-' + suffix
		before := receipt(baseline, arch, before_hash, ['fcntlabi'], true)!; after := receipt(candidate, arch, after_hash, ['fcntlabi', 'dupabi', 'duppublish', 'open', 'runtime'], false)!
		assert before['fcntlabi_source'] == after['fcntlabi_source'] && before['fcntlabi_init'] == after['fcntlabi_init'] && before['fcntlabi_c'] == after['fcntlabi_c'] && after['fcntlabi_c'] == digest(area + 'preview-' + suffix + '.c')
		failure(os.read_file(baseline + '/fcntlabi/serial.log')!, arch); log := os.read_file(candidate + '/fcntlabi/serial.log')!; semantics(log, true, false, arch); storage(log, arch); assert review_text.contains(digest(candidate + '/fcntlabi/serial.log'))
		linux := reference_receipt(reference, arch, after['fcntlabi_init'])!; assert review_text.contains(linux['serial']) && review_text.contains(linux['wrapper_c']) && review_text.contains(linux['probe'])
		assert linux['kernel'] == digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/vmlinuz-' + arch)
		assert os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: JIT page sizes')
		mut artifacts := {'compiler': digest(compiler), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'reference_controller': digest(area + 'reference'), 'audit': digest(@FILE), 'review': digest(review), 'before_kernel': before_hash, 'after_kernel': after_hash, 'before_kernel_c': digest(area + 'before-' + suffix + '.c'), 'after_kernel_c': digest(kernel_c), 'preview': digest(area + 'preview-' + suffix + '.c')}
		for key, hash in before { artifacts['before_' + key] = hash }; for key, hash in after { artifacts['after_' + key] = hash }; for key, hash in linux { artifacts['reference_' + key] = hash }
		artifacts['reference_receipt'] = digest(reference + '/receipt.json'); artifacts['reference_aggregate'] = digest(reference + '.log'); artifacts['reference_url'] = digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/url-' + arch + '.txt')
		for phase in ['before', 'after'] {
			state := area + 'final-' + phase + '-' + suffix; publish(state + '.log', out + 'fcntlabi-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'fcntlabi-' + phase + '-' + arch + '.json')!
			publish(state + '/fcntlabi/serial.log', out + 'fcntlabi-' + phase + '-' + arch + '-native.log')!
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_text := os.read_file(build)!; assert build_text.contains('-o bin/vinix') && !build_text.contains('Error ') && !build_text.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
		}
		publish(reference + '.log', out + 'fcntlabi-reference-' + arch + '.log')!; publish(reference + '/serial.log', out + 'fcntlabi-reference-' + arch + '-native.log')!; publish(reference + '/receipt.json', out + 'fcntlabi-reference-' + arch + '.json')!
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		context := 'Native musl root/UID1000 fcntl: 4464 calls percredential, 8928 perarchitecture. Three independent upper-word patterns cover fd/command/scalar arg. Native adapter narrows unsigned32 fd/cmd, signed32 duplicate minima and other supported int scalar arguments; pointer and unknown arguments retain full64. F_DUPFD/CLOEXEC minima0/63/127 succeed below soft128; minima128/129/INT_MAX/INT_MIN/-1 return EINVAL after validating source. Invalid source remains EBADF; fixed-full64 and soft0 cohorts retain EMFILE for native dup and valid full-table duplicate requests, and EINVAL for out-of-range minima. Six held source classes cover regular, O_PATH file/directory, unlinked and both pipe endpoints. Actual metadata, requested descriptor flags, shared cursors and a distinct seed64 remain exact; successful aliases move/restore regular offsets. FD flag setters, selected APPEND/NONBLOCK changes, signal0/1/64 success and65/negative refusal state, and pipe identity-size requests check real result/state without inventing cross-platform absolute capacities. Real high64 stack flock pointers retain user transport/canaries and expected unlocked type; NULL retains EFAULT with no source changes. Ordinary libc invalid-minimum controls agree. Source/seed bytes and queued AB remain exact. Baselines fail7348 calls each; candidates and actual Linux6.12.51 reference boots pass the identical matrix/C/native ELF. Two200-cycle native cohorts issue two high-word aliases plus four invalid-minimum calls percycle and retain all18 ARM/14 x86 slabs and large pages flat. Dupabi/duppublish/open/runtime and eight host test files pass. Whole kernel C restores by replacing one fcntl dispatch assignment, removing the new adapter body/declaration and ignoring only unused-return source offsets; generic fcntl, descriptor lookup/duplication, native dup/dup3 and lock helper unchanged.659/655 source files and400/292 allocation sites and existing allowance failures unchanged. New invalid-minimum lookup has paired release before scalar error, independently reviewed in source/C/native/reference. All63 inputs and controlled compiler/controller/source/C/kernel/ELF/ISO/Linux/wrapper/cpio/QEMU/capture/build/audit/review hashes bound; both negative controls execute. Disk-space failures remain private and are not qualified receipts; completed older ISO/firmware artifacts were losslessly archived with SHA manifests. O_PATH disallowed commands, full status-flag/ownership/sealing semantics, dynamic pipe resizing, full lock semantics/concurrency, concurrent RLIMIT changes, GNU wrappers and translated/ELF32 paths remain separate.'
		os.write_file(out + 'fcntlabi-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log'] { publish(area + name, out + 'fcntlabi-' + name)! }
	println('Native fcntlabi conformance audit: PASS')
}
