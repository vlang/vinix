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
fn complete(source string, name string) string {
	lines := source.split_into_lines().filter(!it.starts_with(' ') && !it.starts_with('\t') && it.contains(' ' + name + '(') && it.ends_with(' {')); assert lines.len == 1; return lines[0] + definition(source, name) + '\n}\n'
}
fn semantics(log string, passing bool, reference bool, arch string) {
	rows := log.split_into_lines().filter(it.starts_with('LINUX FCNTLQUERY CASES:')); assert rows.len == 6
	mut seen := map[string]bool{}
	for row in rows {
		fields := row.fields(); assert fields.len == 7; group := fields[3].all_after('='); kind := fields[4].all_after('=').int(); key := group + '-' + kind.str()
		assert group in ['0', '1'] && kind in [0, 1, 2] && key !in seen; seen[key] = true
		assert fields[5].all_after('=').int() == [3072, 512, 956]![kind]
		assert fields[6].all_after('=').int() == if passing { 0 } else { [3072, 424, 952]![kind] }
	}
	if passing { assert !log.contains('LINUX FCNTLQUERY DETAIL:') && !log.contains('LINUX FCNTLQUERY FAIL:') }
	else { assert log.contains('LINUX FCNTLQUERY DETAIL:') && log.contains('LINUX FCNTLQUERY FAIL:') && !log.contains('LINUX FCNTLQUERY: PASS') }
	if reference { assert passing && log.contains('LINUX FCNTLQUERY REFERENCE: PASS') && log.contains('Linux version 6.12.51-0-virt') && !log.contains('Kernel panic') && !log.contains('LINUX FCNTLQUERY STORAGE:') }
	else if passing { assert log.split_into_lines().filter(it.trim_space() == 'LINUX FCNTLQUERY: PASS').len == 1 && !log.contains('LINUX FCNTLQUERY REFERENCE: PASS') }
}
fn failure(log string, arch string) { assert log.contains('LINUX FCNTLQUERY DETAIL:'), 'fcntlquery baseline failure markers required'; semantics(log, false, false, arch) }
fn storage(log string, arch string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines() {
		if !row.starts_with('LINUX FCNTLQUERY SLAB:') && !row.starts_with('LINUX FCNTLQUERY STORAGE:') { continue }
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
		maintained := '/Users/alex/code/vinix/tests/linux-compat/' + name + 'fixture/core.v'
		if name == 'fcntlquery' {
			frozen := os.read_file(state + '/sources/' + name + 'fixture/core.v')!; current := os.read_file(maintained)!
			assert frozen == current + '\n', 'only the tested trailing blank line may be removed'
			artifacts[name + '_maintained_source'] = digest(maintained)
		} else { assert artifacts[name + '_source'] == digest(maintained) }
		artifacts[name + '_c'] = digest(state + '/' + name + '/fixture.c'); artifacts[name + '_serial'] = digest(state + '/' + name + '/serial.log')
		if !failing { assert os.read_file(state + '/' + name + '/serial.log')!.contains('LINUX ' + name.to_upper() + ': PASS') }
	}
	return artifacts
}
fn canonical_returns(source string, temporaries bool) string {
	mut output := strings.new_builder(source.len); mut names := map[string]string{}; mut position := 0
	for position < source.len {
		start := position
		if source[position].is_letter() || source[position] == `_` {
			position++
			for position < source.len && (source[position].is_alnum() || source[position] == `_`) { position++ }
			token := source[start..position]; mut temporary := false
			if temporaries {
				for prefix in ['_t', '__or_opt_', '__or_val_', '__if_val_', '__match_val_', '__multi_ret_'] { if token.starts_with(prefix) && token.len > prefix.len && token[prefix.len..].bytes().all(it.is_digit()) { temporary = true } }
			}
			if (token.starts_with('__discard_') && token.len > 10 && token[10..].bytes().all(it.is_digit() || it == `_`)) || temporary {
				if token !in names { names[token] = '_return' + names.len.str() }; output.write_string(names[token])
			} else { output.write_string(token) }
		} else { output.write_u8(source[position]); position++ }
	}
	return output.str()
}
fn scope(before string, after string, arch string) {
	old := complete(before, 'file__syscall_fcntl'); new := complete(after, 'file__syscall_fcntl')
		start := '\tif (cmd == file__f_dupfd_query) {'
		branch := start + new.all_after(start).all_before('\t} else if (cmd == file__f_dupfd) {') + '\t} else '
		assert branch.count('file__FD__unref(') == 3 && branch.contains('errno__ebadf') && branch.contains('file__fd_from_fdnum(NULL, (i64)((u32)(arg)))')
		assert branch.contains('if ((void*)(other->handle) == (void*)(handle))') && !branch.contains('__ptr_eq_') && !branch.contains('__eq_lhs_') && !branch.contains('array_get(') && !branch.contains('v_fixed_index(') && !branch.contains('memdup(')
		matches := canonical_returns(new.replace(branch, '\t'), true) == canonical_returns(old, true); assert matches, 'fcntl rest must remain identical'
		mut restored := after.replace(new, old)
		old_adapter := complete(before, 'table__syscall_linux_fcntl'); new_adapter := complete(after, 'table__syscall_linux_fcntl')
		assert new_adapter.replace(' || (command == file__f_dupfd_query)', '') == old_adapter
		restored = restored.replace(new_adapter, old_adapter)
		assert canonical_returns(restored, false) == canonical_returns(before, false), 'whole C outside query and adapter word must remain identical'

}
fn reference_receipt(state string, arch string, init string) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['passed']!.bool() && value['finished']!.bool() && value['forced']!.bool() && value['status']!.int() == 0
	artifacts := value['artifacts']!.as_map_of_strings()
	command := value['command']!.as_array().map(it.str()); assert command.contains('-kernel') && command.contains('-initrd') && command.contains('-no-reboot')
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/fcntlqueryreferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/fcntlquery-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/fcntlqueryreferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, true, true, arch); return artifacts
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!, os.args[3]); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/fcntlquery-20261013/'; out := root + 'tests/linux-compat/results/2026-10-13/'; compiler := '/Users/alex/.cache/vinix-linux-compat/procstate-20261013/compiler/v'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'final-after-arm/fcntlquery/serial.log', 'aarch64'], 'fcntlquery baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == 'd3ed59c6e285d6cd90202fd373e6ed8b5f6562be'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	assert digest(compiler) == 'f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39'
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	for arch in ['aarch64', 'x86_64'] { count := arch + ': ' + if arch == 'aarch64' { '659 source files, 400 allocation sites (V exit 0)' } else { '655 source files, 292 allocation sites (V exit 0)' }; assert before_allocs.contains(count) && after_allocs.contains(count) }
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	paths := ['kernel/file/file.v', 'kernel/syscall/table/linux_common.v']; review := out + 'fcntlquery-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent fcntlquery lifetime review: PASS')
	for path in paths { assert inputs[path] == digest(root + path) && review_text.contains(inputs[path]) }; assert review_text.contains(digest(root + 'tests/linux-compat/fcntlqueryfixture/core.v'))
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == paths
		for source_path, hash in inputs { if source_path.starts_with('kernel/') { assert digest(tree + source_path) == hash } }
		kernel_c := tree + 'kernel/obj/blob.c'; scope(os.read_file(area + 'before-' + suffix + '.c')!, os.read_file(kernel_c)!, arch); assert review_text.contains(digest(kernel_c))
		preview := os.read_file(area + 'preview-' + suffix + '.c')!; assert preview.count('alloca(') == 8 && !preview.contains('memdup(') && !preview.contains('malloc(') && !preview.contains('new_array') && !preview.contains('v_fixed_index')
		before_hash := digest(area + 'baseline-' + suffix + '/kernel/bin/vinix'); after_hash := digest(tree + 'kernel/bin/vinix')
		baseline := area + 'final-before-' + suffix; candidate := area + 'final-after-' + suffix; reference := area + 'final-reference-' + suffix
		before := receipt(baseline, arch, before_hash, ['fcntlquery'], true)!; after := receipt(candidate, arch, after_hash, ['fcntlquery', 'fcntlpath', 'open', 'runtime'], false)!
		assert before['fcntlquery_source'] == after['fcntlquery_source'] && before['fcntlquery_init'] == after['fcntlquery_init'] && before['fcntlquery_c'] == after['fcntlquery_c'] && after['fcntlquery_c'] == digest(area + 'preview-' + suffix + '.c')
		failure(os.read_file(baseline + '/fcntlquery/serial.log')!, arch); log := os.read_file(candidate + '/fcntlquery/serial.log')!; semantics(log, true, false, arch); storage(log, arch); assert review_text.contains(digest(candidate + '/fcntlquery/serial.log'))
		linux := reference_receipt(reference, arch, after['fcntlquery_init'])!; assert review_text.contains(linux['serial']) && review_text.contains(linux['wrapper_c']) && review_text.contains(linux['probe'])
		assert linux['kernel'] == digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/vmlinuz-' + arch)
		assert os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: JIT page sizes')
		mut artifacts := {'compiler': digest(compiler), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'reference_controller': digest(area + 'reference'), 'audit': digest(@FILE), 'review': digest(review), 'before_kernel': before_hash, 'after_kernel': after_hash, 'before_kernel_c': digest(area + 'before-' + suffix + '.c'), 'after_kernel_c': digest(kernel_c), 'preview': digest(area + 'preview-' + suffix + '.c')}
		for key, hash in before { artifacts['before_' + key] = hash }; for key, hash in after { artifacts['after_' + key] = hash }; for key, hash in linux { artifacts['reference_' + key] = hash }
		artifacts['reference_receipt'] = digest(reference + '/receipt.json'); artifacts['reference_aggregate'] = digest(reference + '.log'); artifacts['reference_url'] = digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/url-' + arch + '.txt')
		for phase in ['before', 'after'] {
			state := area + 'final-' + phase + '-' + suffix; publish(state + '.log', out + 'fcntlquery-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'fcntlquery-' + phase + '-' + arch + '.json')!
			publish(state + '/fcntlquery/serial.log', out + 'fcntlquery-' + phase + '-' + arch + '-native.log')!
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_text := os.read_file(build)!; assert build_text.contains('-o bin/vinix') && !build_text.contains('Error ') && !build_text.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
		}
		publish(reference + '.log', out + 'fcntlquery-reference-' + arch + '.log')!; publish(reference + '/serial.log', out + 'fcntlquery-reference-' + arch + '-native.log')!; publish(reference + '/receipt.json', out + 'fcntlquery-reference-' + arch + '.json')!
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		context := 'Native musl ELF64 F_DUPFD_QUERY. Eight source classes with original/dup/CLOEXEC aliases and eight independent descriptions; root/UID1000: 4540 controls per credential, 9080 per architecture. Four independent native source/command/target word controls compare real Handle identity, including six separately opened same-inode descriptions, private/directory/FIFO/unfollowed-link/unlinked objects and nonblocking pipe endpoints. Either invalid descriptor returns EBADF, not EINVAL or success. Existing held64/65 descriptors work above zero/eight soft limits. Musl queries, balanced-reference/flag directory controls and real close/replace/reuse66 transitions agree; all held metadata/flags/status/cursors, original/reopened bytes and AB/CD queues remain exact. Fork-inherited aliases share a cursor, independent opens do not. Baselines reproduce8896 failures each; candidates and actual Linux6.12.51 references pass the same C/native ELF. Two200-cycle native query cohorts retain all18 ARM/14 x86 slabs and73/194 pages flat. Four cases fcntlquery,fcntlpath,open,runtime and eight host test files pass. Whole C changes only the query branch and native comparison-word classification; exact direct void-pointer equality, paired primary/secondary releases and absence of structural copying/array traversal are independently checked. Allocation sites/allowance failures remain unchanged. Baseline kernel/C/build outputs reuse the prior fcntlpath candidate. All63 isolated inputs and compiler/controller/source/C/kernel/ELF/ISO/Linux/wrapper/archive/QEMU/serial/build/audit/review hashes bound; both negative controls execute. Initial structural-comparison builds and fixed-index setup failures are private diagnostics, never qualified evidence. Completed older ISO/firmware artifacts are losslessly archived with hash manifests. F_CREATED_QUERY, full ordinary fcntl semantics, concurrent close/table sharing, GNU wrappers and foreign ABIs remain separate.'
		os.write_file(out + 'fcntlquery-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log'] { publish(area + name, out + 'fcntlquery-' + name)! }
	println('Native fcntlquery conformance audit: PASS')
}
