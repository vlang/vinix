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
	assert arch in ['aarch64', 'x86_64']
	rows := log.split_into_lines().filter(it.starts_with('LINUX DUPPUBLISH FLAGS:')); assert rows.len == 12
	mut seen := map[string]bool{}
	mut failed_forks := [2]int{}
	for row in rows {
		f := row.fields(); assert f.len == 13
		group := f[3].all_after('='); method := f[4].all_after('='); key := group + '-' + method
		assert f[3].starts_with('ordinary=') && f[4].starts_with('method=') && group in ['0', '1'] && method in ['0', '1', '2', '3', '4', '5'] && key !in seen; seen[key] = true
		assert f[5] == 'calls=128' && f[6].starts_with('samples=') && f[6].all_after('=').u64() >= 128 && f[8] == 'forks=16' && f[10] == 'post_bad=0' && f[11] == 'producer_bad=0'
		assert f[7].starts_with('bad=') && f[9].starts_with('fork_bad=')
		for index in [6, 7, 9] { digits := f[index].all_after('='); assert digits != '' && digits.bytes().all(it.is_digit()) }
		if passing { assert f[7] == 'bad=0' && f[9] == 'fork_bad=0' && f[12] == 'PASS' }
		else { assert f[7].all_after('=').u64() > 0 && f[9].all_after('=').int() >= 0 && f[12] == 'FAIL'; failed_forks[group.int()] += f[9].all_after('=').int() }
	}
	if !passing {
		assert failed_forks[0] > 0 && failed_forks[1] > 0, 'baseline must expose bad fork snapshots for both credentials'
		assert log.contains('LINUX DUPPUBLISH FAIL:') && !log.contains('LINUX DUPPUBLISH: PASS') && !log.contains('LINUX DUPPUBLISH CLOSE:') && !log.contains('LINUX DUPPUBLISH STORAGE:')
		return
	}
	assert !log.contains('LINUX DUPPUBLISH FAIL:')
	close_rows(log, false)
	if reference { assert log.contains('LINUX DUPPUBLISH REFERENCE: PASS') && log.contains('Linux version 6.12.51-0-virt') && !log.contains('Kernel panic') && !log.contains('LINUX DUPPUBLISH STORAGE:') }
	else { assert log.split_into_lines().filter(it.trim_space() == 'LINUX DUPPUBLISH: PASS').len == 1 && !log.contains('LINUX DUPPUBLISH REFERENCE: PASS') }
}
fn close_rows(log string, window bool) {
	rows := log.split_into_lines().filter(it.starts_with('LINUX DUPPUBLISH CLOSE:')); assert rows.len == 2
	mut seen := map[string]bool{}
	for row in rows {
		f := row.fields(); assert f.len == 8; group := f[3].all_after('=')
		assert f[3].starts_with('ordinary=') && group in ['0', '1'] && group !in seen; seen[group] = true
		assert f[4] == 'calls=200' && f[5].starts_with('during=') && f[5].all_after('=').int() >= 0 && f[5].all_after('=').int() <= 200 && f[6] == 'bad=0' && f[7] == 'PASS'
		digits := f[5].all_after('='); assert digits != '' && digits.bytes().all(it.is_digit())
		if window { assert f[5].all_after('=').int() > 0, 'instrumented close/reuse must observe unfinished producer' }
	}
}
fn failure(log string, arch string) { assert log.contains('LINUX DUPPUBLISH FAIL:'), 'duppublish baseline failure markers required'; semantics(log, false, false, arch) }
fn storage(log string, arch string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines() {
		if !row.starts_with('LINUX DUPPUBLISH SLAB:') && !row.starts_with('LINUX DUPPUBLISH STORAGE:') { continue }
		f := row.fields(); assert f.len == 7; group := f[3].all_after('=').int(); assert group in [0, 1]
		pair := f[5].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		key := f[3] + '-' + f[4]; assert key !in seen; seen[key] = true
		if f[2] == 'SLAB:' { assert f[6] == 'cycles=200'; slabs[group]++ }
		else { assert f[4] == 'cycles=200' && f[6] == 'PASS' && pair[0].int() > 0; pages[group]++ }
	}
	for group in 0 .. 2 { assert slabs[group] == if arch == 'aarch64' { 18 } else { 14 }; assert pages[group] == 1 }
}
fn scope(before string, after string, arch string) {
	assert arch in ['aarch64', 'x86_64']
	old := complete(before, 'file__fdnum_dup'); new := complete(after, 'file__fdnum_dup')
	assert old != new && before.count(old) == 1 && after.count(new) == 1
	assert canonical(after.replace(new, old)) == canonical(before), 'whole kernel C may change only fdnum_dup'
	flags := 'new_fd->flags = flags & resource__file_descriptor_flags_mask;'
	publication := 'file__fdnum_create_from_fd(new_process, new_fd, newfdnum, specific)'
	assert new.all_before(publication).contains(flags) && !new.all_after(publication).contains('new_fd->')
	assert old.all_after(publication).contains(flags)
	assert new.count('malloc(') == old.count('malloc(') && new.count('memcpy(') == old.count('memcpy(') && new.count('file__FD__unref(') == old.count('file__FD__unref(')
}
fn scheduling_scope(production string, instrumented string, arch string) {
	name := 'file__fdnum_dup'; old := complete(production, name); new := complete(instrumented, name)
	assert old != new && new.contains('sched__reschedule();') && !old.contains('sched__reschedule();')
	mut restored := instrumented.replace(new, old); mut plain := production
	if arch == 'x86_64' {
		// The added sched import moves exactly this constant declaration block;
		// every literal definition and all remaining generated C must match.
		rows := production.split_into_lines().filter(it.starts_with('#define mmap__')); assert rows.len == 48
		block := rows.join('\n') + '\n'; assert production.count(block) == 1 && instrumented.count(block) == 1
		assert rows == instrumented.split_into_lines().filter(it.starts_with('#define mmap__'))
		plain = plain.replace(block, ''); restored = restored.replace(block, '')
	}
	matches := canonical(restored) == canonical(plain); assert matches, 'QA C differs only by the scheduling function and identical x86 mmap constant block placement'
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
fn reference_receipt(state string, arch string, init string) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['passed']!.bool() && value['finished']!.bool() && value['forced']!.bool() && value['status']!.int() == 0
	artifacts := value['artifacts']!.as_map_of_strings()
	command := value['command']!.as_array().map(it.str()); assert command.contains('-kernel') && command.contains('-initrd') && command.contains('-no-reboot')
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/duppublishreferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/duppublish-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/duppublishreferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, true, true, arch); return artifacts
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!, os.args[3]); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/duppublish-20261013/'; out := root + 'tests/linux-compat/results/2026-10-13/'; compiler := '/Users/alex/.cache/vinix-linux-compat/procstate-20261013/compiler/v'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'qualified-after-arm/duppublish/serial.log', 'aarch64'], 'duppublish baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == 'd1cf55595f1d395344a9cb5099984b95cb5f8daf'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	assert digest(compiler) == 'f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39'
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	for arch in ['aarch64', 'x86_64'] { count := arch + ': ' + if arch == 'aarch64' { '659 source files, 400 allocation sites (V exit 0)' } else { '655 source files, 292 allocation sites (V exit 0)' }; assert before_allocs.contains(count) && after_allocs.contains(count) }
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	probe_compiler := json2.decode[json2.Any](os.read_file(area + 'probe-compiler.json')!)!.as_map_of_strings(); assert probe_compiler['compiler'] == digest(probe_compiler['compiler_path']) && os.read_file(area + 'qualified-probe-rebuild.log')!.count('selected probe compiler reconstructs exact tested C and ELF: PASS') == 2
	for label, path in {'generator': root + 'tests/linuxkpi/generate_module.v', 'generator_core': root + 'tests/native-generators/generators/core.v', 'build': root + 'tests/native-guest-tools/guesthost/build.v'} { assert probe_compiler[label] == digest(path) }
	window := '\n\t// dup publication qualification window: only scalar state after insertion.\n\tif new_fdnum == 63 {\n\t\tfor _ in 0 .. 32 { sched.reschedule() }\n\t}\n'
	for phase, plain in {'before': area + 'baseline-file.v', 'after': root + 'kernel/file/file.v'} {
		instrumented := os.read_file(area + 'yield-' + phase + '-file.v')!; assert instrumented.count(window) == 1 && instrumented.count('import sched\n') == 1
		matches := instrumented.replace(window, '').replace('import sched\n', '') == os.read_file(plain)!; assert matches, 'private source contains only scheduling instrumentation'
	}
	path := 'kernel/file/file.v'; review := out + 'duppublish-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent duppublish lifetime review: PASS')
	assert inputs[path] == digest(root + path) && review_text.contains(inputs[path]) && review_text.contains(digest(root + 'tests/linux-compat/duppublishfixture/core.v'))
	mut scope_log := ''
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; qa := area + 'yield-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == base && git(qa, ['rev-parse', 'HEAD'])! == base
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == [path] && git(qa, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == [path]
		for source_path, hash in inputs { if source_path.starts_with('kernel/') { assert digest(tree + source_path) == hash; if source_path != path { assert digest(qa + source_path) == hash } } }
		before_c := os.read_file(area + 'before-kernel-' + suffix + '.c')!; after_c := os.read_file(tree + 'kernel/obj/blob.c')!
		before_qa_c := os.read_file(area + 'before-yield-' + suffix + '.c')!; after_qa_c := os.read_file(qa + 'kernel/obj/blob.c')!
		scope(before_c, after_c, arch); scope(before_qa_c, after_qa_c, arch); scheduling_scope(before_c, before_qa_c, arch); scheduling_scope(after_c, after_qa_c, arch)
		for cpath in [tree + 'kernel/obj/blob.c', qa + 'kernel/obj/blob.c'] { assert review_text.contains(digest(cpath)) }
		scope_log += arch + ': whole production and QA C restore by replacing only fdnum_dup; QA/production differ at the scheduling window plus x86 relocation of48 byte-identical mmap literal macros; initialization precedes insertion; no successful post-publication descriptor access; no allocation/free/refcount additions: PASS\n'
	}
	os.write_file(area + 'scope-check.log', scope_log)!
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; qa := area + 'yield-' + suffix + '/'
		before_hash := digest(area + 'before-yield-' + suffix + '.kernel'); after_hash := digest(tree + 'kernel/bin/vinix'); after_qa_hash := digest(qa + 'kernel/bin/vinix')
		baseline := area + 'qualified-yield-before-' + suffix; candidate := area + 'qualified-after-' + suffix; qualified := area + 'qualified-yield-after-' + suffix; reference := area + 'verified-reference-' + suffix
		before := receipt(baseline, arch, before_hash, ['duppublish'], true)!; after := receipt(candidate, arch, after_hash, ['duppublish', 'dupabi', 'open', 'runtime'], false)!; after_qa := receipt(qualified, arch, after_qa_hash, ['duppublish'], false)!
		assert before['duppublish_source'] == after['duppublish_source'] && before['duppublish_init'] == after['duppublish_init'] && before['duppublish_c'] == after['duppublish_c'] && after['duppublish_init'] == after_qa['duppublish_init'] && after['duppublish_c'] == after_qa['duppublish_c']
		preview := os.read_file(area + 'pinned-preview-' + suffix + '.c')!; c_matches := preview == os.read_file(candidate + '/duppublish/fixture.c')!; assert c_matches, 'reconstructed probe C must match the tested fixture'
		assert preview.count('alloca(') == 6 && !preview.contains('memdup(') && !preview.contains('malloc(') && !preview.contains('new_array') && !preview.contains('v_fixed_index')
		failure(os.read_file(baseline + '/duppublish/serial.log')!, arch)
		for state in [candidate, qualified] { log := os.read_file(state + '/duppublish/serial.log')!; semantics(log, true, false, arch); storage(log, arch); assert review_text.contains(digest(state + '/duppublish/serial.log')) }; close_rows(os.read_file(qualified + '/duppublish/serial.log')!, true)
		linux := reference_receipt(reference, arch, after['duppublish_init'])!; assert review_text.contains(linux['serial']) && review_text.contains(linux['wrapper_c']) && review_text.contains(linux['probe'])
		assert linux['kernel'] == digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/vmlinuz-' + arch)
		assert os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: JIT page sizes')
		mut artifacts := {'compiler': digest(compiler), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'reference_controller': digest(area + 'verified-reference'), 'instrumenter': digest(root + 'tests/linux-compat/duppublish-instrument.v'), 'audit': digest(@FILE), 'review': digest(review), 'before_qa_kernel': before_hash, 'after_kernel': after_hash, 'after_qa_kernel': after_qa_hash, 'before_kernel': digest(area + 'before-kernel-' + suffix + '.kernel'), 'before_kernel_c': digest(area + 'before-kernel-' + suffix + '.c'), 'after_kernel_c': digest(tree + 'kernel/obj/blob.c'), 'before_qa_kernel_c': digest(area + 'before-yield-' + suffix + '.c'), 'after_qa_kernel_c': digest(qa + 'kernel/obj/blob.c'), 'before_source': digest(area + 'baseline-file.v'), 'before_qa_source': digest(area + 'yield-before-file.v'), 'after_qa_source': digest(area + 'yield-after-file.v'), 'preview': digest(area + 'pinned-preview-' + suffix + '.c'), 'probe_compiler': probe_compiler['compiler'], 'probe_compiler_manifest': digest(area + 'probe-compiler.json'), 'probe_reconstruction': digest(area + 'rebuild-probe.v'), 'probe_reconstruction_log': digest(area + 'qualified-probe-rebuild.log')}
		assert probe_compiler[arch + '_c'] == after['duppublish_c'] && probe_compiler[arch + '_elf'] == after['duppublish_init']
		for key, hash in before { artifacts['before_qa_' + key] = hash }; for key, hash in after { artifacts['after_' + key] = hash }; for key, hash in after_qa { artifacts['after_qa_' + key] = hash }; for key, hash in linux { artifacts['reference_' + key] = hash }
		artifacts['reference_receipt'] = digest(reference + '/receipt.json'); artifacts['reference_aggregate'] = digest(reference + '.log'); artifacts['reference_url'] = digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/url-' + arch + '.txt')
		for phase, state in {'before-qa': baseline, 'after': candidate, 'after-qa': qualified} { publish(state + '.log', out + 'duppublish-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'duppublish-' + phase + '-' + arch + '.json')!; publish(state + '/duppublish/serial.log', out + 'duppublish-' + phase + '-' + arch + '-native.log')! }
		publish(reference + '.log', out + 'duppublish-reference-' + arch + '.log')!; publish(reference + '/serial.log', out + 'duppublish-reference-' + arch + '-native.log')!; publish(reference + '/receipt.json', out + 'duppublish-reference-' + arch + '.json')!
		for profile in ['kernel', 'yield'] { for phase in ['before', 'after'] { build := area + 'build-' + if profile == 'yield' { 'yield-' } else { '' } + phase + '-' + suffix + '.log'; build_text := os.read_file(build)!; assert build_text.contains('-o bin/vinix') && !build_text.contains('Error ') && !build_text.contains('No space left on device'); artifacts['build_' + profile + '_' + phase] = digest(build); publish(build, out + 'duppublish-build-' + profile + '-' + phase + '-' + suffix + '.log')! } }
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		context := 'Native musl root/UID1000 descriptor publication: six dup/dup2/dup3/F_DUPFD/F_DUPFD_CLOEXEC methods, 128 calls and16 actual fork snapshots per method per credential (1536 calls/192 forks per architecture/run). Source flags oppose the target expectation. Candidate flags are finalized before locked insertion; complete production/QA C changes only fdnum_dup and adds no allocation/free/refcount operations. Private QA copies alone reschedule32 times immediately after insertion for target63; on x86 only, the added import relocates one48-line byte-identical mmap literal macro block, validated separately. Both baseline QA credentials fail all six visibility phases and expose bad fork snapshots while post-return and producer controls pass; baseline intentionally skips close/reuse. Production and QA candidates pass visibility/fork/close controls plus flat sequential200-cycle storage cohorts. QA close rows require observing an unfinished producer immediately before close in both credentials; this is an observed timing count, not a synchronized proof of close-before-return. Close/reuse repeats200 times per credential: detect source inode, close63, seed64 CLOEXEC, and retain exact sentinel metadata/cursor/flags and duplicate return; completed branch rechecks metadata after acquire(done) to avoid stale sampling. Final source/seed bytes/cursors/parent flags remain exact. Both real Linux6.12.51 boots pass the identical native probe ELF (reference skips allocator controls). Dupabi/open/runtime and eight host test files pass. Existing659/655 source-file and400/292 allocation-site inventories and allowance failures unchanged. Independent source/C/native/QA/reference lifetime review approved. All63 inputs and compiler/controller/kernel/C/ELF/ISO/Linux/wrapper/cpio/QEMU/log/build/audit/review hashes bound, with executing assertion and passing-as-baseline negative controls. Initial stale-sample probe failures and interrupted timing captures remain private and are not accepted receipts. Actual exec inheritance, concurrent F_SETFD or source-close races, descriptor limit pressure, GNU wrappers and translated/ELF32 paths remain separate; sequential storage is not whole-concurrency retention.'
		os.write_file(out + 'duppublish-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { publish(area + name, out + 'duppublish-' + name)! }
	for name in ['probe-compiler.json', 'qualified-probe-rebuild.log'] { publish(area + name, out + 'duppublish-' + name)! }
	publish(area + 'rebuild-probe.v', out + 'duppublish-rebuild-probe.v')!
	println('Native duppublish conformance audit: PASS')
}
